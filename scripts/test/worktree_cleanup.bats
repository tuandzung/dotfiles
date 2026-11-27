#!/usr/bin/env bats
# @file worktree_cleanup.bats
# @brief Tests for home/dot_config/git/scripts/executable_worktree_cleanup.sh.tmpl
# @description
#   Runs the rendered hook by hand after a merge in a throwaway repository: the
#   git on this machine may predate the config hooks that would run it.

setup_file() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  command -v chezmoi > /dev/null || skip "chezmoi is not installed"
  local root
  root="$(realpath "${BATS_TEST_DIRNAME}/../..")"
  HOOK="${BATS_FILE_TMPDIR}/worktree_cleanup.sh"
  chezmoi execute-template --source "${root}" \
    --file "${root}/home/dot_config/git/scripts/executable_worktree_cleanup.sh.tmpl" > "${HOOK}"
  export HOOK
}

setup() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q -b main "${REPO}"
  git -C "${REPO}" commit -q --allow-empty -m init
  git -C "${REPO}" worktree add -q -b feat "${REPO}/.worktrees/feat"
  git -C "${REPO}/.worktrees/feat" commit -q --allow-empty -m work
}

@test "a merged, clean worktree goes and its branch stays" {
  git -C "${REPO}" merge -q --ff-only feat
  cd "${REPO}"
  run bash "${HOOK}"
  [ "${status}" -eq 0 ]
  [ ! -e "${REPO}/.worktrees/feat" ]
  git -C "${REPO}" rev-parse --verify -q refs/heads/feat
}

@test "a merged worktree holding an untracked file stays" {
  touch "${REPO}/.worktrees/feat/notes.txt"
  git -C "${REPO}" merge -q --ff-only feat
  cd "${REPO}"
  run bash "${HOOK}"
  [ "${status}" -eq 0 ]
  [ -e "${REPO}/.worktrees/feat/notes.txt" ]
  [[ "${output}" == *"Kept"* ]]
}

@test "a fresh worktree on the old tip stays" {
  git -C "${REPO}" worktree add -q -b fresh "${REPO}/.worktrees/fresh"
  git -C "${REPO}" merge -q --ff-only feat
  cd "${REPO}"
  run bash "${HOOK}"
  [ "${status}" -eq 0 ]
  [ -d "${REPO}/.worktrees/fresh" ]
}

@test "a forged worktree entry outside .worktrees/ is never removed" {
  # Empty, like the branch's tree, so the status check finds nothing to keep.
  mkdir "${REPO}/protected"
  printf 'gitdir: %s\n' "${REPO}/.git/worktrees/feat" > "${REPO}/protected/.git"
  printf '%s\n' "${REPO}/protected/.git" > "${REPO}/.git/worktrees/feat/gitdir"
  git -C "${REPO}" merge -q --ff-only feat
  cd "${REPO}"
  run bash "${HOOK}"
  [ "${status}" -eq 0 ]
  [ -e "${REPO}/protected/.git" ]
}

@test "a submodule commit no remote has keeps its worktree, ignore = all or not" {
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
  git init -q -b main "${BATS_TEST_TMPDIR}/lib"
  git -C "${BATS_TEST_TMPDIR}/lib" commit -q --allow-empty -m init
  cd "${REPO}"
  git submodule add -q "${BATS_TEST_TMPDIR}/lib" lib
  git config -f .gitmodules submodule.lib.ignore all
  git add .gitmodules
  git commit -q -m lib
  git worktree add -q -b sm "${REPO}/.worktrees/sm"
  git -C "${REPO}/.worktrees/sm" submodule update -q --init
  git -C "${REPO}/.worktrees/sm/lib" commit -q --allow-empty -m unpushed
  git -C "${REPO}/.worktrees/sm" add lib
  git -C "${REPO}/.worktrees/sm" commit -q -m bump
  git merge -q --ff-only sm
  run bash "${HOOK}"
  [ "${status}" -eq 0 ]
  [ -d "${REPO}/.worktrees/sm/lib" ]
}

@test "an unmerged worktree stays" {
  cd "${REPO}"
  git commit -q --allow-empty -m other
  git merge -q --ff-only HEAD
  run bash "${HOOK}"
  [ "${status}" -eq 0 ]
  [ -d "${REPO}/.worktrees/feat" ]
}
