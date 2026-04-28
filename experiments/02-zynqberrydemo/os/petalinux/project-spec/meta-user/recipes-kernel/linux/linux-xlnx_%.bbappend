FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://bsp.cfg \
                   file://0001-fix-for-s25fl127s.patch "
KERNEL_FEATURES:append = " bsp.cfg"
SRC_URI += "file://user_2026-03-26-01-04-00.cfg"

