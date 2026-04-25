# erlang

Adding Erlang to the build takes only a few easy steps:

+ In `petalinux-config` > Image Packaging Configuration > Root filesystem type, switch to an EXT4 root filesystem.
+ Add the Erlang yocto layer.
    + Add the layer to the build system by `mkdir -p project-spec/layers ; cd project-spec/layers ; git clone -b scarthgap https://github.com/meta-erlang/meta-erlang.git` . (NOTE: `kirkstone` is another branch name for other versions of Petalinux, but mine seems to want `scarthgap`.)
    + Tell the build system to build it by going to `petalinux-config` > Yocto settings > User layers and entering `${PROOT}/project-spec/layers/meta-erlang` in the first field.
    + Tell the build system to package it by creating the file `project-spec/meta-user/recipes-core/images` with the contents `IMAGE_INSTALL:append = " erlang erlang-modules"`.
+ Rebuild with `petalinux-build`.
+ Copy `image.ub` and `boot.scr` to the boot partition.  Then, image the root partition with `dd if=path/to/rootfs.ext4 of=/dev/rdisk4s2 bs=4m`.

If you haven't set up an SD card with separate boot and root partitions, you can do that in macOS like so:
```sh
diskutil partitionDisk /dev/disk4 \
  MBR \
  FAT32 BOOT 256M \
  ExFAT ROOT 0  # this will get overwritten with ext4 in a moment

# detach second partition, which got auto-mounted after formatted completed
diskutil unmount /dev/disk4s2
```

When you next boot, you should see `/dev/mmcblk0p2` listed in `mount`, and `erl` should bring you to an Erlang shell.

## Example

Follow the instructions in `async/README.md` to load the bitstream and kernel module.  Then:

```erl
bridge:start_link().     % {ok, PID}  % start erlang server
bridge:ping(1234).       % 1234       % SYN - ACK
bridge:set(1, 2, 16#f).  % ok         % store 2 into reg 1's bottom 4 bits
bridge:bulk_get(0, 2).   % [0, 2]     % reports values in registers 0 and 1
```

## Notes

+ It might be nice to include `rebar3` and so on.
+ `erlang` provides `erl`, `erlang-modules` provides `erlc`.
+ Plenty of repeated boilerplate in `bridge.erl` that could be reduced.
