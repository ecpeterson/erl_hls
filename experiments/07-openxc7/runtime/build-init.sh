#!/bin/sh
# Assemble the offline package set in RAM, then copy it to the disposable SD image.
set -eu
export ERL_LIBS=/opt/erl-hls/lib
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /tmp
# These signed packages are copied onto persistent ext4 below, rather than kept in RAM.
apk --no-progress --force-non-repository --no-network --repositories-file /dev/null add /packages/*.apk
rm -rf /packages
chown root:shadow /etc/shadow
cp /runtime-world /etc/apk/world
printf 'erl-hls\n' > /etc/hostname
printf '127.0.0.1 localhost erl-hls\n::1 localhost\n' > /etc/hosts
printf 'auto lo\niface lo inet loopback\nauto eth0\niface eth0 inet dhcp\n' > /etc/network/interfaces
# Serial is the recovery console. SSH accepts keys only and starts on explicit request.
printf '\nttyPS0::respawn:/sbin/getty -n -l /bin/sh 115200 ttyPS0 vt100\n' >> /etc/inittab
sed -i '/^tty[1-6]::/d' /etc/inittab
mkdir -p /etc/modprobe.d
printf 'options uio_pdrv_genirq of_id=generic-uio\n' > /etc/modprobe.d/erl-hls-probe.conf
printf 'DROPBEAR_OPTS="-s"\n' > /etc/conf.d/dropbear
for service in devfs dmesg procfs sysfs mdev; do rc-update add "$service" sysinit; done
for service in bootmisc hostname hwclock modules hwdrivers sysctl seedrng networking; do rc-update add "$service" boot; done
rc-update add local default
rc-update add killprocs shutdown
rc-update add mount-ro shutdown
printf '/dev/mmcblk0p2 / ext4 defaults,noatime 0 1\n' > /etc/fstab
printf 'https://dl-cdn.alpinelinux.org/alpine/v3.23/main\nhttps://dl-cdn.alpinelinux.org/alpine/v3.23/community\n' > /etc/apk/repositories
mkdir -p /opt/erl-hls/test-ebin
ERL_FLAGS='+S 1:1 +A 2' erlc -W0 -o /opt/erl-hls/test-ebin /opt/erl-hls/tests/*.erl
/opt/erl-hls/bin/runtime-check
# QEMU exposes only the generated image as this SD device. No host block device is passed.
mke2fs -q -t ext4 -F -L hls-root -U 2bfa8b35-7f96-4a71-81d8-b66899130300 /dev/mmcblk0
mkdir -p /target
mount /dev/mmcblk0 /target
for item in bin etc lib media mnt opt root run sbin srv usr var; do
    [ ! -e "/$item" ] || cp -a "/$item" /target/
done
mkdir -p /target/dev /target/proc /target/sys /target/tmp
chmod 1777 /target/tmp
# No machine identity or SSH host key is baked into the reusable image.
rm -f /target/etc/machine-id /target/etc/dropbear/dropbear_*_host_key /target/var/lib/seedrng/*
df -m /target
sync
umount /target
echo 'PASS: ARM runtime image assembled'
reboot -f
