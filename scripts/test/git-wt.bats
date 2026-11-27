#!/usr/bin/env bats
# @file git-wt.bats
# @brief Tests for home/dot_local/bin/executable_git-wt.tmpl
# @description
#   Renders the script once, then runs it as `git wt` against a throwaway
#   repository with the user's git config shut out.

setup_file() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  command -v chezmoi > /dev/null || skip "chezmoi is not installed"
  local root
  root="$(realpath "${BATS_TEST_DIRNAME}/../..")"
  BIN="${BATS_FILE_TMPDIR}/bin"
  mkdir -p "${BIN}"
  chezmoi execute-template --source "${root}" \
    --file "${root}/home/dot_local/bin/executable_git-wt.tmpl" > "${BIN}/git-wt"
  chmod +x "${BIN}/git-wt"
  export BIN
}

setup() {
  export PATH="${BIN}:${PATH}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    HOME="${BATS_TEST_TMPDIR}" XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/.config"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q -b main "${REPO}"
  git -C "${REPO}" commit -q --allow-empty -m init
}

@test "creates the branch's worktree under .worktrees/" {
  cd "${REPO}"
  run git wt feat
  [ "${status}" -eq 0 ]
  [ "$(git -C "${REPO}/.worktrees/feat" branch --show-current)" = "feat" ]
}

@test "a slash in the branch becomes a dash in the directory" {
  cd "${REPO}"
  run git wt feat/x
  [ "${status}" -eq 0 ]
  [ "$(git -C "${REPO}/.worktrees/feat-x" branch --show-current)" = "feat/x" ]
}

@test "from inside a worktree, the new one still lands in the main checkout" {
  cd "${REPO}"
  git wt one
  cd "${REPO}/.worktrees/one"
  run git wt two
  [ "${status}" -eq 0 ]
  [ -d "${REPO}/.worktrees/two" ]
  [ ! -e "${REPO}/.worktrees/one/.worktrees" ]
}

@test "a name that would leave .worktrees/ is refused" {
  cd "${REPO}"
  run git wt ..
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Not a valid branch name"* ]]
}

@test "an option is not taken for a branch name" {
  cd "${REPO}"
  run git wt --force
  [ "${status}" -ne 0 ]
  [ ! -e "${REPO}/.worktrees" ]
}

@test "a repository's alias.wt cannot take over" {
  cd "${REPO}"
  git config alias.wt '!echo hijacked'
  run git wt feat
  [ "${status}" -eq 0 ]
  [[ "${output}" != *hijacked* ]]
  [ -d "${REPO}/.worktrees/feat" ]
}

@test "more than one argument is refused" {
  cd "${REPO}"
  run git wt feat --detach
  [ "${status}" -ne 0 ]
  [ ! -e "${REPO}/.worktrees" ]
}

@test "the branch starts at the current worktree's HEAD" {
  cd "${REPO}"
  git wt one
  git -C "${REPO}/.worktrees/one" commit -q --allow-empty -m ahead
  cd "${REPO}/.worktrees/one"
  git wt two
  [ "$(git -C "${REPO}/.worktrees/two" rev-parse HEAD)" = "$(git rev-parse HEAD)" ]
}

# @description Plant a git dir whose post-checkout hook marks the attack as run
# @arg $1 string Directory to create
plant_gitdir() {
  local dir="$1"
  git init -q --bare -b main "${dir}"
  printf '#!/bin/sh\ntouch "%s"\n' "${BATS_TEST_TMPDIR}/pwned" > "${dir}/hooks/post-checkout"
  chmod +x "${dir}/hooks/post-checkout"
  git -C "${dir}" fetch -q "${REPO}" 'refs/heads/*:refs/heads/*'
}

@test "a .git file pointing elsewhere is refused" {
  plant_gitdir "${BATS_TEST_TMPDIR}/evil"
  mkdir "${BATS_TEST_TMPDIR}/decoy"
  printf 'gitdir: %s\n' "${BATS_TEST_TMPDIR}/evil" > "${BATS_TEST_TMPDIR}/decoy/.git"
  git --git-dir="${BATS_TEST_TMPDIR}/evil" config core.bare false
  git --git-dir="${BATS_TEST_TMPDIR}/evil" config core.worktree "${BATS_TEST_TMPDIR}/decoy"
  cd "${BATS_TEST_TMPDIR}/decoy"
  run git wt feat
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Refusing"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
}

@test "a repository reading per-worktree config is refused" {
  cd "${REPO}"
  git config extensions.worktreeConfig true
  run git wt feat
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"worktreeConfig"* ]]
}

@test "a worktree whose commondir points elsewhere is refused" {
  cd "${REPO}"
  git wt one
  plant_gitdir "${BATS_TEST_TMPDIR}/evil"
  # Its work tree is a decoy whose `.git` file leads straight back to it.
  mkdir "${BATS_TEST_TMPDIR}/decoy"
  printf 'gitdir: %s\n' "${BATS_TEST_TMPDIR}/evil" > "${BATS_TEST_TMPDIR}/decoy/.git"
  git --git-dir="${BATS_TEST_TMPDIR}/evil" config core.bare false
  git --git-dir="${BATS_TEST_TMPDIR}/evil" config core.worktree "${BATS_TEST_TMPDIR}/decoy"
  printf '%s\n' "${BATS_TEST_TMPDIR}/evil" > "${REPO}/.git/worktrees/one/commondir"
  cd "${REPO}/.worktrees/one"
  run git wt two
  [ "${status}" -ne 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
}
