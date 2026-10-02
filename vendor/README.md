# Vendored snapshots

Each directory here is an exact copy of selected files from a sibling
repository at one commit, so Helix evaluates, builds and runs CI without
credentials for those private repositories. They are integration inputs, not
forks: application changes belong upstream, and Helix must not add policy here.

`sources.json` is the single provenance record: for each snapshot, the
upstream repository, the commit, and the copied paths. Files are copied
byte-for-byte; nothing in this directory is edited by hand.

To update a snapshot after the change has merged upstream:

```bash
./scripts/vendor-sync.sh hamcade <commit>   # or hamllm, modern-bash
git diff vendor/
./scripts/dev-shell.sh --run './scripts/check.sh'
```

`vendor-sync.sh` clones the upstream repository with your GitHub credentials,
replaces the listed paths with that commit's versions, and records the commit.
