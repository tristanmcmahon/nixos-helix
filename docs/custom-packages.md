# Custom package pins

Custom packages use immutable upstream revisions and fixed hashes. Update one
package at a time, build it against the maintained NixOS release, run
`./scripts/check.sh`, and retain the old pin if the candidate does not pass.

## Current audit

- ChatGPT `26.818.61809` packages OpenAI's official x86_64 Debian build with a
  fixed content hash because OpenAI does not currently publish a NixOS package.
- Zen Browser `1.21.10b` uses the official x86_64 AppImage because the selected
  NixOS package set does not provide the required browser package.
- GridPlayer is pinned to tested `0.5.4` because later candidates change its
  Python build backend and dependency constraints; retain the tested pin until
  a replacement is packaged and fully built.
- modern-bash is pinned to commit
  `55b1c4de6bc47e14285d55f6a1dfdf9fb494e806`; its immutable runtime and
  lifecycle-command blocking remain intentional.

## Manual update procedure

1. Confirm the upstream release or commit from its official repository.
2. Update only the version/revision and fixed source hash in the owning Nix file.
3. Build the package with the NixOS 26.05 package set.
4. Run its focused closure/import checks and `./scripts/check.sh`.
5. Commit the pin and its evidence together; never replace a fixed hash with an
   impure fetch.
