# TE0715 SD boot-payload maintenance

Use one of these checked paths to replace a role-specific FAT payload. Both verify the source hash and the bytes written to the card. Neither path repartitions the card or changes its ext4 root.

## Update a card attached to macOS

Identify the mounted FAT partition with `diskutil list`; pass the partition identifier, such as `disk4s1`, not the whole disk or a `/Volumes` path. The updater accepts a flat archive containing exactly `BOOT.bin`, `boot.scr` and `image.ub`, validates every file against the role manifest, resolves the partition's parent, refuses the current macOS system disk, copies the files to the FAT root, synchronizes them, verifies the on-media hashes and only then ejects the parent disk.

```sh
python3 platforms/xc7/update_fat_macos.py \
  --archive role-a-fat.zip \
  --manifest role-a-manifest.json \
  --partition disk4s1
```

USB SD readers do not report `Internal` consistently. The safety check therefore accepts an explicit external location, removable/ejectable media, or an external bus such as USB, while independently rejecting the root filesystem's parent disk. The typed partition confirmation remains required unless `--yes` is supplied.

Use `--verify-only` without `--partition` to validate an archive before inserting a card:

```sh
python3 platforms/xc7/update_fat_macos.py \
  --archive role-a-fat.zip \
  --manifest role-a-manifest.json \
  --verify-only
```

Do not treat a successful source check as evidence that the card changed. The final `PASS` line includes the verified on-media `BOOT.bin` digest and confirms that the parent disk was ejected.

## Update `BOOT.bin` from a running board

When only the bitstream-bearing `BOOT.bin` changes, transfer it without relying on an SFTP server, then invoke the guarded board-side writer. Replace the example host and digest with the role's values:

```sh
ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes \
  -i ~/.ssh/id_ed25519 root@192.168.77.31 \
  'cat > /tmp/write_boot && chmod 755 /tmp/write_boot' \
  < platforms/xc7/write_boot.sh

ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes \
  -i ~/.ssh/id_ed25519 root@192.168.77.31 \
  'cat > /tmp/BOOT.bin' < BOOT.bin

ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes \
  -i ~/.ssh/id_ed25519 root@192.168.77.31 \
  "/tmp/write_boot /tmp/BOOT.bin EXPECTED_SHA256"
```

`write_boot` checks the source digest, selects `/dev/mmcblk0p1` unless another block device is supplied, mounts it only if necessary, replaces `BOOT.bin` through a temporary file, synchronizes the filesystem and checks the on-media digest. A successful write changes the next cold boot; it does not reload the running PL image.
