# Artifact storage

Source repositories contain generators, tests, frozen test inputs and small parser fixtures. Build caches live in disposable `_build/`. Retained simulation traces, profiles, synthesized netlists and measurement reports live outside the repositories.

The default archive is `hls_artifacts/` beside the primary `hls_fabric` checkout, including when a command runs from a linked worktree. Set `HLS_ARTIFACT_ROOT` to use another external directory. `tools/hls_fabric/artifacts.py` prints its location. New measurements go under `runs/`; use a fresh named or timestamped directory for each experiment.

A retained run should include its selected configuration, source/tool hashes, input vectors, reports and required raw evidence. A filesystem location alone is not a backup. Copy valuable runs to durable storage before reclaiming them locally. Moving files out of a checkout does not remove them from Git history or reclaim the repository's existing object storage.

## Historical reports

The October 1 migration preserved the previous repository-relative paths under:

```text
hls_artifacts/repositories/hls_fabric/pre-packaging-2026-10-01/
```

`index.json` identifies the source commit and checksums every archived file. Historical filenames in documentation are lookup keys into that directory. For example:

```sh
python3 tools/hls_fabric/artifacts.py experiments/snowflake/actors/transfer-collection/measurements.md
```

Earlier untracked retained builds live in `hls_artifacts/local/`, including `collector-ownership-2026-10-01/`. Test and build commands must not require this historical archive. Comparison tools may require explicitly selected prior measurements. Board reference manifests and parser fixtures remain in source control because they are actual inputs.
