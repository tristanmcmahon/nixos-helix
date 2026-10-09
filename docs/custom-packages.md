# Custom package pins

Custom packages use immutable upstream revisions and fixed hashes. Update one
package at a time, build it against the maintained NixOS release, run
`./scripts/check.sh`, and retain the old pin if the candidate does not pass.

## Current audit

- GridPlayer is pinned to tested `0.5.4` because later candidates change its
  Python build backend and dependency constraints; retain the tested pin until
  a replacement is packaged and fully built.
- modern-bash is pinned to commit
  `55b1c4de6bc47e14285d55f6a1dfdf9fb494e806`. Its small runtime snapshot
  deliberately remains vendored so Helix builds do not depend on sibling-repo
  visibility, GitHub availability, or credentials; lifecycle-command blocking
  remains intentional.
- nix-openclaw is pinned to commit
  `d3760a6f103642f11e24bc01ee9aec80a0153774` / OpenClaw `2026.7.1-2`.
  Helix carries a narrow local definition of the upstream npm gateway package
  so the wrapper lock is read as a path during non-flake evaluation. The
  gateway runs on Node 22 built with Node's bundled SQLite rather than the
  nixpkgs shared SQLite 3.51.2, which OpenClaw rejects because of the WAL-reset
  corruption bug. The override applies only while nixpkgs shares a SQLite older
  than 3.51.3, so it retires itself and the cached Node returns automatically.
  That Node build skips Node's own test suite, and the gateway build fails if
  its Node links a SQLite older than 3.51.3 (one `minimumSqlite` value in
  `packages/openclaw-node.nix` drives both, and the weekly Nixpkgs bump uses
  the same file to say whether the source build happens). ACPX, extended tools, the batteries bundle, source/version pins and
  dependency hashes still come from that immutable upstream revision.

## Manual update procedure

1. Confirm the upstream release or commit from its official repository.
2. Update only the version/revision and fixed source hash in the owning Nix file.
3. Build the package with the NixOS 26.05 package set.
4. Run its focused closure/import checks and `./scripts/check.sh`.
5. Commit the pin and its evidence together; never replace a fixed hash with an
   impure fetch.
