# Local build storage

Keep reusable toolchains, chip databases, rebar profiles and Dialyzer PLTs. Large historical netlists, RTL, logs and Icarus executables can instead use macOS filesystem compression: their paths, readable contents and modification times remain unchanged, so existing tools can still consume them.

Report eligible artifacts first:

```sh
python3 tools/compact_build.py
```

Stop local builds before applying the plan:

```sh
python3 tools/compact_build.py --apply --report _build/compaction.json
```

The default selects owned generated-text files of at least 1 MiB, older than 24 hours, beneath `_build`. It skips symlinks, hard links, hidden paths, `default`/`test`/`prod` profiles, and binary/tool caches. Pass another `_build` directory as the positional argument; `--min-mib` and `--older-than-hours` adjust the thresholds. Already-compressed files are skipped.

Applying requires macOS and a filesystem supporting native compression. The command compresses a temporary copy beside each source, verifies its SHA-256, size, mode, owner and modification time, checks that the source has not changed, then atomically replaces it only if allocated space decreases. Failure leaves that source intact; an optional receipt records earlier completed files. This uses temporary space up to the size of one candidate file. Run outside sandboxes that prohibit the filesystem compression flag.

This is an explicit maintenance command, not an EUnit or pre-commit hook. The file-revision checks detect concurrent changes but do not lock arbitrary build processes; builds must remain idle. Successful reads are transparent, while later rewrites may remove compression. Allocated-block savings can differ from immediate volume free-space gains because of filesystem clones and snapshots. No artifacts are deleted; remove obsolete experiments separately when their evidence is no longer needed.
