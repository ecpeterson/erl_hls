# Repository history

This repository is the canonical source for the compiler, runtime, communication synthesis, physical-target and Spacetime applications. It retains the selected histories of the former repositories through reproducible filtered commits and one mechanical landing.

## Ref map

| History | Selected source commit | Retained commit | Umbrella merge | Final-path landing |
| --- | --- | --- | --- | --- |
| Compiler base | `b86502cc0149731409d878f9aec6c5264ae3f2eb` | unchanged | — | `0ed0d679985149fbc757ce420c2803aced2ca38d` |
| Fabric | `4481afbde5a4ab1594141d698c74e0859ef8c72c` | `878b44269266d6f2c33f844c4aa5eff4d6dd3936` | `4f84e4ddde927a76056956f4832b4a14b8227573` | `0ed0d679985149fbc757ce420c2803aced2ca38d` |
| Spacetime | `3597ecf93ea789c745bc3014ea2c4de8cd5fb243` | `83f19aa922623a5b5bea46176fb0baee1d28c5a4` | `b8e713710cf744ee1d7ccddd4d5f4bee4d0b4bca` | `0ed0d679985149fbc757ce420c2803aced2ca38d` |

The filtered commits use temporary staging prefixes. The landing commit moves their retained trees into the current application, documentation, tool and platform paths. Later ownership changes move modules between OTP applications without replacing this ancestry.

## Imported tag

The Fabric tag `xls-ram-9f360fc89-05a16983` originally selected `d2b611297ffbddb5d7e4a106a57a1ed4457ccb40`. Its content-preserving filtered target is `4e3f1dd15c403d5d0b9f7087ae6dc039579437be`; the tag in this repository resolves to that retained target.

Use the retained commit or tag when correlating an old artifact with the umbrella. The unfiltered Fabric and Spacetime source object IDs are provenance labels, not objects expected to exist in this object database.

## Local verification

From a complete clone:

```sh
git merge-base --is-ancestor 878b44269266d6f2c33f844c4aa5eff4d6dd3936 HEAD
git merge-base --is-ancestor 83f19aa922623a5b5bea46176fb0baee1d28c5a4 HEAD
git merge-base --is-ancestor 4e3f1dd15c403d5d0b9f7087ae6dc039579437be HEAD
test "$(git rev-parse xls-ram-9f360fc89-05a16983^{commit})" = 4e3f1dd15c403d5d0b9f7087ae6dc039579437be
git fsck --strict
```

The detailed filter, path and collision evidence remains in `yap/umbrella-otp-audit.md`; this page is the stable maintainer-facing ref map.
