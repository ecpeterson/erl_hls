# Boot the shared ext4 root while binding the BRAM register page to generic UIO.
echo "TE0715 BRAM diagnostic: SD image.ub and root partition 2"
if fatload mmc 0:1 0x10000000 image.ub; then
    setenv bootargs 'console=ttyPS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw uio_pdrv_genirq.of_id=generic-uio'
    bootm 0x10000000
fi
echo "BRAM diagnostic boot failed; inspect the UART log."
