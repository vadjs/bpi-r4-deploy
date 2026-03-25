#!/bin/sh
# install-emmc.sh — Install OpenWrt to eMMC from USB flash drive
# Must be run from NAND rescue system only!

set -e

EMMC_IMG="emmc-img.bin"
EMMC_DEV="/dev/mmcblk0"
EMMC_BOOT="/dev/mmcblk0boot0"

# 1. Check boot media
echo ">>> Checking boot media..."
if grep -q "fitrw" /proc/mounts; then
    echo "ERROR: Running from SD card — must be run from NAND rescue!"
    exit 1
fi
if ! grep -q "ubi.block" /proc/cmdline; then
    if grep -q "fit0" /proc/cmdline && ! grep -q "ubi" /proc/cmdline; then
        echo "ERROR: Running from eMMC — must be run from NAND rescue!"
        exit 1
    fi
fi
echo "    OK — running from NAND rescue"

# 2. Check eMMC
echo ">>> Checking eMMC..."
if [ ! -b "$EMMC_DEV" ]; then
    echo "ERROR: eMMC ($EMMC_DEV) not found!"
    exit 1
fi
echo "    OK — $EMMC_DEV found"

# 3. Detect USB — find mount point
echo ">>> Looking for USB flash drive..."
USB_MOUNT=""
for dev in /dev/sd*1; do
    [ -b "$dev" ] || continue
    MP=$(mount | grep "^$dev " | awk '{print $3}')
    if [ -n "$MP" ]; then
        USB_MOUNT="$MP"
        echo "    OK — $dev mounted at $USB_MOUNT"
        break
    fi
done

if [ -z "$USB_MOUNT" ]; then
    # Try manual mount
    for dev in /dev/sd*1; do
        [ -b "$dev" ] || continue
        mkdir -p /mnt/usb
        if mount "$dev" /mnt/usb 2>/dev/null; then
            USB_MOUNT="/mnt/usb"
            echo "    OK — $dev mounted at $USB_MOUNT"
            break
        fi
    done
fi

if [ -z "$USB_MOUNT" ]; then
    echo "ERROR: No USB flash drive found!"
    exit 1
fi

# 4. Check image file
echo ">>> Checking $EMMC_IMG..."
if [ ! -f "$USB_MOUNT/$EMMC_IMG" ]; then
    echo "ERROR: $EMMC_IMG not found on $USB_MOUNT!"
    exit 1
fi
IMG_SIZE=$(ls -lh "$USB_MOUNT/$EMMC_IMG" | awk '{print $5}')
echo "    OK — $EMMC_IMG found ($IMG_SIZE)"

# 5. Final warning
echo ""
echo "!!! WARNING !!!"
echo "About to overwrite eMMC ($EMMC_DEV)."
echo "All data on eMMC will be lost!"
echo ""
printf "Continue? [yes/no]: "
read CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# 6. Write image to eMMC
echo ">>> Writing $EMMC_IMG to $EMMC_DEV..."
dd if="$USB_MOUNT/$EMMC_IMG" of="$EMMC_DEV" bs=1M
sync
echo "    OK — image written"

# 7. Write BL2 to boot partition
echo ">>> Writing BL2 to boot partition..."
echo 0 > /sys/block/mmcblk0boot0/force_ro
dd if="$USB_MOUNT/$EMMC_IMG" of="$EMMC_BOOT" bs=512 skip=34 count=512
sync
echo "    OK — BL2 written"

# 8. Set eMMC boot partition
echo ">>> Setting eMMC boot partition..."
mmc bootpart enable 1 1 "$EMMC_DEV"
echo "    OK"

# 9. Done
echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Power off the device"
echo "  2. Set DIP switch: SW3-A=1, SW3-B=0 (eMMC boot)"
echo "  3. Power on the device"
echo ""