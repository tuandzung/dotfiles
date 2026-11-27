#!/usr/bin/env bats
# @file strip_agent_credit.bats
# @brief Tests for home/dot_config/git/scripts/executable_strip_agent_credit.sh.tmpl
# @description
#   Runs the rendered hook by hand on a message file, the way git's `commit-msg`
#   event calls it, and checks what is left in the file. The lines to drop are
#   the ones the git-conventions rule forbids an agent to add.

setup_file() {
  command -v chezmoi > /dev/null || skip "chezmoi is not installed"
  local root
  root="$(realpath "${BATS_TEST_DIRNAME}/../..")"
  HOOK="${BATS_FILE_TMPDIR}/strip_agent_credit.sh"
  chezmoi execute-template --source "${root}" \
    --file "${root}/home/dot_config/git/scripts/executable_strip_agent_credit.sh.tmpl" > "${HOOK}"
  export HOOK
}

setup() {
  MSG="${BATS_TEST_TMPDIR}/COMMIT_EDITMSG"
}

@test "a Co-Authored-By trailer naming an agent is dropped, the message kept" {
  cat > "${MSG}" << 'MSG'
feat(git): add a hook

Why it matters.

Co-Authored-By: Claude Opus <noreply@anthropic.com>
MSG
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  run cat "${MSG}"
  [[ "${output}" == $'feat(git): add a hook\n\nWhy it matters.'* ]]
  [[ "${output}" != *"Co-Authored-By"* ]]
}

@test "a human co-author stays, any agent goes, whatever the key's case" {
  cat > "${MSG}" << 'MSG'
fix: something

Co-authored-by: Jane Doe <jane@example.com>
Co-authored-by: Claude Monet <claude@example.com>
co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>
CO-AUTHORED-BY: Codex <codex@openai.com>
MSG
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  run cat "${MSG}"
  [ "${output}" = "fix: something

Co-authored-by: Jane Doe <jane@example.com>
Co-authored-by: Claude Monet <claude@example.com>" ]
}

@test "session, assistance and generated-with credit goes, a human line stays" {
  cat > "${MSG}" << 'MSG'
build: regenerate the client

Generated with protoc from the new schema.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
https://claude.ai/code/session_01AbCdEf
Assisted-by: Claude:claude-opus-5-5
Claude-Session: https://claude.ai/code/session_01AbCdEf
MSG
  run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  run cat "${MSG}"
  [[ "${output}" == "build: regenerate the client

Generated with protoc from the new schema."* ]]
  [[ "${output}" != *"laude"* ]]
}

@test "a message that is not UTF-8 is kept byte for byte" {
  # i18n.commitEncoding = latin1: grep in a UTF-8 locale takes it for binary.
  printf 'fix: caf\xe9 menu\n\nExplain the caf\xe9 change.\nSecond line.\n' > "${MSG}"
  cp "${MSG}" "${MSG}.orig"
  LC_ALL=C.UTF-8 run bash "${HOOK}" "${MSG}"
  [ "${status}" -eq 0 ]
  cmp "${MSG}" "${MSG}.orig"
}

@test "a message file it cannot read is rejected, never rewritten" {
  printf 'fix: x\n\nbody\n' > "${MSG}"
  chmod 200 "${MSG}"
  run bash "${HOOK}" "${MSG}"
  chmod 600 "${MSG}"
  [ "${status}" -ne 0 ]
  [ "$(cat "${MSG}")" = $'fix: x\n\nbody' ]
}
