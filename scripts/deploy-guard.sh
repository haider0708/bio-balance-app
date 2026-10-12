#!/usr/bin/env bash
# Safety shared by the deploy scripts, so the Linux PC and the Mac behave the same:
#  - deploy only from the main branch, with everything committed;
#  - deploy only what is already on GitHub and equals GitHub's main (so the other machine can
#    always get what the server runs, and a machine that forgot to pull cannot send old code);
#  - never replace a newer version on the server with an older one;
#  - never two deploys at once.
# Used with:  source scripts/deploy-guard.sh;  guard_start api|web "$host";  ...;  guard_done
# `FORCE_DEPLOY=1` skips only the "older than the server" check (for a deliberate rollback).

guard_die() { echo "Deploy refused: $*" >&2; exit 1; }

guard_start() {
  guard_what=$1
  guard_host=$2
  local branch head remote deployed
  branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$branch" = main ] || guard_die "deploy from the main branch (this is $branch)."
  git diff --quiet && git diff --cached --quiet \
    || guard_die "commit your changes first (what is deployed must be what is in Git)."
  git fetch -q origin main || guard_die "cannot reach GitHub to compare with its main."
  head=$(git rev-parse HEAD)
  remote=$(git rev-parse origin/main)
  if [ "$head" != "$remote" ]; then
    if git merge-base --is-ancestor "$head" "$remote"; then
      guard_die "this copy is behind GitHub: run 'git pull' first."
    elif git merge-base --is-ancestor "$remote" "$head"; then
      guard_die "this copy has commits GitHub does not have: run 'git push' first."
    else
      guard_die "this copy and GitHub have both changed: run 'git pull --rebase', test, then 'git push'."
    fi
  fi
  deployed=$(ssh "$guard_host" "cat /opt/biobalance-deployed-$guard_what 2>/dev/null" || true)
  if [ -n "$deployed" ] && [ "$deployed" != "$head" ] && [ -z "${FORCE_DEPLOY:-}" ]; then
    git cat-file -e "$deployed^{commit}" 2>/dev/null \
      || guard_die "the server runs $deployed, which this copy does not know: run 'git pull'."
    git merge-base --is-ancestor "$deployed" "$head" \
      || guard_die "the server runs $deployed, which is not an ancestor of this version: pull first (FORCE_DEPLOY=1 only for a deliberate rollback)."
  fi
  ssh "$guard_host" "sudo mkdir /opt/biobalance-deploy.lock && echo \"$(hostname) $(date -u +%FT%TZ) $guard_what\" | sudo tee /opt/biobalance-deploy.lock/owner >/dev/null" 2>/dev/null \
    || guard_die "another deploy is running ($(ssh "$guard_host" 'cat /opt/biobalance-deploy.lock/owner' 2>/dev/null || echo unknown)). If it crashed: ssh $guard_host 'sudo rm -rf /opt/biobalance-deploy.lock'."
  guard_head=$head
  trap guard_release EXIT
  echo "== Deploying $guard_what from $(hostname): ${head:0:8}${deployed:+ (server had ${deployed:0:8})}"
}

guard_release() {
  ssh "$guard_host" 'sudo rm -rf /opt/biobalance-deploy.lock' >/dev/null 2>&1 || true
}

# Remember what the server now runs (called only after the deploy was checked healthy).
guard_done() {
  ssh "$guard_host" "echo $guard_head | sudo tee /opt/biobalance-deployed-$guard_what >/dev/null"
}
