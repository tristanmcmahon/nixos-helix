#!/usr/bin/env bash

set -euo pipefail

delete=0
case ${1:-} in
"")
  ;;
--delete)
  delete=1
  shift
  ;;
-h | --help)
  cat <<'EOF'
Usage: prune-merged-branches.sh [--delete]

Without --delete, list remote branches that are fully merged into origin/main.

With --delete, delete those branches from origin after confirming that no open
pull request uses them.

Always preserved:
  main
  release/*
  rollback/*
EOF
  exit 0
  ;;
*)
  printf 'Usage: %s [--delete]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if [[ $# -ne 0 ]]; then
  printf 'Usage: %s [--delete]\n' "${0##*/}" >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'Not inside a Git repository.\n' >&2
  exit 1
}
cd "$repo_root"

git remote get-url origin >/dev/null
printf 'Refreshing origin...\n'
git fetch origin --prune

git show-ref --verify --quiet refs/remotes/origin/main || {
  printf 'origin/main is unavailable.\n' >&2
  exit 1
}

declare -A open_pr_heads=()
if command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
  while IFS= read -r branch; do
    [[ -n "$branch" ]] && open_pr_heads["$branch"]=1
  done < <(gh pr list --state open --json headRefName --jq '.[].headRefName')
elif ((delete)); then
  printf 'GitHub CLI authentication is required before deleting branches.\n' >&2
  exit 1
fi

mapfile -t merged_branches < <(
  git for-each-ref     --format='%(refname:strip=3)'     --merged=refs/remotes/origin/main     refs/remotes/origin/ |
    sort -u
)

candidates=()
for branch in "${merged_branches[@]}"; do
  case "$branch" in
  HEAD | main | release/* | rollback/*)
    continue
    ;;
  esac

  if [[ -n ${open_pr_heads[$branch]:-} ]]; then
    printf 'KEEP %-48s open pull request\n' "$branch"
    continue
  fi

  git merge-base --is-ancestor "refs/remotes/origin/$branch" refs/remotes/origin/main
  candidates+=("$branch")
done

if (("${#candidates[@]}" == 0)); then
  printf 'No merged remote branches are eligible for pruning.\n'
  exit 0
fi

printf '\nMerged remote branches eligible for pruning:\n'
printf '  %s\n' "${candidates[@]}"

if ((!delete)); then
  printf '\nDry run only. Re-run with --delete to remove these remote branches.\n'
  exit 0
fi

printf '\nDeleting %d merged remote branch(es)...\n' "${#candidates[@]}"
for branch in "${candidates[@]}"; do
  git push origin --delete "$branch"
done

git fetch origin --prune
printf 'Remote branch cleanup complete.\n'
