# The second SD partition holds rootfs.ext4; the first retains the boot artifacts.
echo "TE0715 Linux/OTP candidate: SD image.ub and root partition 2"
if fatload mmc 0:1 0x10000000 image.ub; then
    setenv bootargs 'console=ttyPS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw'
    bootm 0x10000000
fi
echo "Candidate boot failed; inspect the UART log."
