#!/usr/bin/env bats
# @file worktree_submodules.bats
# @brief Tests for home/dot_config/git/scripts/executable_worktree_submodules.sh.tmpl
# @description
#   Runs the rendered hook by hand in a new linked worktree of a throwaway
#   repository with two submodules: the git on this machine may predate the
#   config hooks that would run it.

readonly NULL_REF="0000000000000000000000000000000000000000"

setup_file() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  command -v chezmoi > /dev/null || skip "chezmoi is not installed"
  local root
  root="$(realpath "${BATS_TEST_DIRNAME}/../..")"
  HOOK="${BATS_FILE_TMPDIR}/worktree_submodules.sh"
  chezmoi execute-template --source "${root}" \
    --file "${root}/home/dot_config/git/scripts/executable_worktree_submodules.sh.tmpl" > "${HOOK}"
  export HOOK
}

setup() {
  # protocol.file.allow: the submodules are local paths, which git refuses by default.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  local name
  for name in lib secret; do
    git init -q -b main "${BATS_TEST_TMPDIR}/${name}"
    git -C "${BATS_TEST_TMPDIR}/${name}" commit -q --allow-empty -m init
  done
  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q -b main "${REPO}"
  git -C "${REPO}" submodule add -q "${BATS_TEST_TMPDIR}/lib" lib
  git -C "${REPO}" submodule add -q "${BATS_TEST_TMPDIR}/secret" secret
  git -C "${REPO}" config -f .gitmodules submodule.secret.worktreeInit false
  git -C "${REPO}" add .gitmodules
  git -C "${REPO}" commit -q -m submodules
  WT="${REPO}/.worktrees/feat"
  git -C "${REPO}" worktree add -q -b feat "${WT}"
}

@test "a new worktree gets the submodules, minus worktreeInit = false" {
  cd "${WT}"
  run bash "${HOOK}" "${NULL_REF}"
  [ "${status}" -eq 0 ]
  [ -e "${WT}/lib/.git" ]
  [ ! -e "${WT}/secret/.git" ]
}

@test "a checkout of an existing branch is left alone" {
  cd "${WT}"
  run bash "${HOOK}" "$(git rev-parse HEAD)"
  [ "${status}" -eq 0 ]
  [ ! -e "${WT}/lib/.git" ]
}

@test "the main checkout is left alone" {
  cd "${REPO}"
  git submodule deinit -q lib
  run bash "${HOOK}" "${NULL_REF}"
  [ "${status}" -eq 0 ]
  [ ! -e "${REPO}/lib/.git" ]
}
