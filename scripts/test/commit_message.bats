#!/usr/bin/env bats
# @file commit_message.bats
# @brief Tests for home/dot_config/git/scripts/executable_commit_message.sh.tmpl
# @description
#   Runs the rendered hook by hand on a message file, the way git's `commit-msg`
#   event calls it, and checks what it lets through. The last tests commit for
#   real through the `hook.*` entries of the rendered git config.tmpl, after
#   strip_agent_credit.sh, to pin down the order the two hooks run in.

setup_file() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  command -v chezmoi > /dev/null || skip "chezmoi is not installed"
  local root
  root="$(realpath "${BATS_TEST_DIRNAME}/../..")"
  HOOK="${BATS_FILE_TMPDIR}/commit_message.sh"
  chezmoi execute-template --source "${root}" \
    --file "${root}/home/dot_config/git/scripts/executable_commit_message.sh.tmpl" > "${HOOK}"
  STRIP="${BATS_FILE_TMPDIR}/strip_agent_credit.sh"
  chezmoi execute-template --source "${root}" \
    --file "${root}/home/dot_config/git/scripts/executable_strip_agent_credit.sh.tmpl" > "${STRIP}"
  # Only the hook entries leave the rendered config: the test never prints it.
  HOOKS="${BATS_FILE_TMPDIR}/hooks"
  chezmoi execute-template --source "${root}" \
    --file "${root}/home/dot_config/git/config.tmpl" > "${BATS_FILE_TMPDIR}/config"
  git config --file "${BATS_FILE_TMPDIR}/config" --get-regexp '^hook\.' > "${HOOKS}" || true
  export HOOK STRIP HOOKS
}

# @description Commit for real in a throwaway repository, with only the hook
# entries of the rendered git config and their scripts under a throwaway HOME.
setup_repo() {
  local version
  version="$(git version | cut -d' ' -f3)"
  [[ "$(printf '%s\n' 2.54 "${version}" | sort -V | head -n1)" == 2.54 ]] \
    || skip "git ${version} predates hooks from config"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export GIT_CONFIG_GLOBAL="${HOME}/.gitconfig" GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  mkdir -p "${HOME}/.config/git/scripts"
  install -m 755 "${HOOK}" "${HOME}/.config/git/scripts/commit_message.sh"
  install -m 755 "${STRIP}" "${HOME}/.config/git/scripts/strip_agent_credit.sh"
  local key value
  while read -r key value; do
    git config --global --add "${key}" "${value}"
  done < "${HOOKS}"
  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q -b main "${REPO}"
  git -C "${REPO}" commit -q --allow-empty --no-verify -m init
}

setup() {
  # The hook reads commit.cleanup: keep the user's own config out of it.
  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig" GIT_CONFIG_NOSYSTEM=1
  cd "${BATS_TEST_TMPDIR}" || return 1
  MSG="${BATS_TEST_TMPDIR}/COMMIT_EDITMSG"
}

@test "an empty message is rejected" {
  printf '\n\n' > "${MSG}"
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"empty"* ]]
}

@test "a subject of 73 characters is rejected" {
  # 73 characters: the 72 character limit plus one.
  printf 'feat(git): %s\n' "$(printf 'x%.0s' {1..62})" > "${MSG}"
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"72"* ]]
}

@test "a subject of exactly 72 characters is accepted" {
  printf 'feat(git): %s\n' "$(printf 'x%.0s' {1..61})" > "${MSG}"
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
}

@test "a subject of 51 characters is accepted with a warning" {
  printf 'feat(git): %s\n' "$(printf 'x%.0s' {1..40})" > "${MSG}"
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"50"* ]]
}

@test "a subject of exactly 50 characters is accepted silently" {
  printf 'feat(git): %s\n' "$(printf 'x%.0s' {1..39})" > "${MSG}"
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "comment lines and everything below the scissors line are ignored" {
  local long
  long="$(printf 'x%.0s' {1..80})"
  cat > "${MSG}" << MSG
# ${long}

fix(git): short subject

# ------------------------ >8 ------------------------
# Do not modify or remove the line above.
${long}
MSG
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "a message of only comments and a scissors section is rejected as empty" {
  cat > "${MSG}" << 'MSG'

# Please enter the commit message for your changes.
# ------------------------ >8 ------------------------
diff --git a/file b/file
MSG
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"empty"* ]]
}

@test "length is counted in characters, not bytes, whatever the locale" {
  # 50 characters, but 95 bytes in UTF-8.
  printf 'docs: %s\n' "$(printf 'ơ%.0s' {1..44})" > "${MSG}"
  LC_ALL=C run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "a subject git wrote itself over 72 characters is accepted with a warning" {
  # git commit --fixup/--squash prefixes a subject that was already up to 72
  # characters, and git merge or pull names a branch or a URL of any length.
  local subject long
  long="$(printf 'x%.0s' {1..61})"
  for subject in "fixup! feat(git): ${long}" "squash! feat(git): ${long}" \
    "amend! feat(git): ${long}" "Merge branch 'feature/${long}' of https://example.com/r"; do
    printf '%s\n' "${subject}" > "${MSG}"
    run bash "${HOOK}" "${MSG}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"72"* ]]
  done
}

@test "a subject that only starts like one git writes is still rejected" {
  printf 'Merged feat(git): %s\n' "$(printf 'x%.0s' {1..61})" > "${MSG}"
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -ne 0 ]
}

@test "a real commit lands without its agent credit" {
  setup_repo
  run git -C "${REPO}" commit -q --allow-empty -m "feat: add a thing" \
    -m "Co-Authored-By: Claude <noreply@anthropic.com>"
  [ "${status}" -eq 0 ]
  run git -C "${REPO}" log -1 --format=%B
  [ "${output}" = "feat: add a thing" ]
}

@test "a real commit of nothing but agent credit is rejected as empty" {
  setup_repo
  # Checked before the credit is stripped, this 46 character subject would pass.
  run git -C "${REPO}" commit -q --allow-empty --allow-empty-message \
    -m "Co-Authored-By: Claude <noreply@anthropic.com>"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"empty"* ]]
  run git -C "${REPO}" log -1 --format=%s
  [ "${output}" = "init" ]
}

@test "when commit.cleanup keeps # lines, a # line is the subject git commits" {
  local mode
  for mode in scissors whitespace verbatim; do
    git config --global commit.cleanup "${mode}"
    printf '#42 fix login\n' > "${MSG}"
    run bash "${HOOK}" "${MSG}"
    [ "${status}" -eq 0 ]
    printf '# %s\n\nfix: short\n' "$(printf 'x%.0s' {1..80})" > "${MSG}"
    run bash "${HOOK}" "${MSG}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"82 characters"* ]]
  done
}

@test "a project's own LOG_LEVEL and LOG_FILE never reach the hook" {
  # Python-style values from a project's .env, picked up by direnv.
  printf 'feat(git): %s\n' "$(printf 'x%.0s' {1..40})" > "${MSG}"
  LOG_LEVEL=WARNING LOG_FILE=app.log run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"50"* ]]
  [ ! -e app.log ]
}

@test "without a working dybatpho the commit goes through unchecked, with a warning" {
  # A moved, half checked out or broken library must not block every commit.
  mkdir -p lib/bare lib/empty
  cp "${BATS_TEST_DIRNAME}/../lib/dybatpho/init.sh" lib/bare/init.sh
  touch lib/empty/init.sh
  printf 'feat(git): %s\n' "$(printf 'x%.0s' {1..62})" > "${MSG}"
  local lib
  for lib in gone bare empty; do
    sed "s|\"[^\"]*/scripts/lib/dybatpho/init.sh\"|\"${PWD}/lib/${lib}/init.sh\"|" "${HOOK}" > nolib.sh
    run bash nolib.sh "${MSG}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"could not load dybatpho"*"skipped"* ]]
    [[ "${output}" != *"command not found"* ]]
  done
}
