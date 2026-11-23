# Boot only the SD candidate. A failed load leaves the U-Boot prompt available.
echo "TE0715 register-probe candidate: SD image.ub"
if fatload mmc 0:1 0x10000000 image.ub; then
    bootm 0x10000000
fi
echo "Candidate boot failed; inspect the UART log."
