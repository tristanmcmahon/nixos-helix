# Custom package pins

Custom packages use immutable upstream revisions and fixed hashes. Update one
package at a time, build it against the maintained NixOS release, run
`./scripts/check.sh`, and retain the old pin if the candidate does not pass.

## Current audit

- Zen Browser `1.21.10b` matches the current stable upstream release. Its
  official x86_64 AppImage remains necessary because NixOS 26.05 has no
  maintained `zen-browser` package providing this browser.
- GridPlayer is pinned to tested `0.5.4`; upstream stable is `0.5.5`. The newer
  release changes its Python build backend and dependency constraints, so it is
  intentionally retained until that candidate is packaged and fully built.
- modern-bash commit `55b1c4de6bc47e14285d55f6a1dfdf9fb494e806`
  matches upstream `main`. Its immutable runtime and lifecycle-command blocking
  remain intentional.

## Manual update procedure

1. Confirm the upstream release or commit from its official repository.
2. Update only the version/revision and fixed source hash in the owning Nix file.
3. Build the package with the NixOS 26.05 package set.
4. Run its focused closure/import checks and `./scripts/check.sh`.
5. Commit the pin and its evidence together; never replace a fixed hash with an
   impure fetch.
