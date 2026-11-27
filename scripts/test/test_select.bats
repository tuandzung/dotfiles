#!/usr/bin/env bats
# @file test_select.bats
# @brief Tests for scripts/lib/test_select.sh
# @description
#   Each test builds a small repository of its own, with a few bats files under
#   `scripts/test`, and checks which of them `test_select::files` picks for a
#   set of changed paths.

setup() {
  local scripts
  scripts="$(realpath "${BATS_TEST_DIRNAME}/..")"
  # shellcheck source-path=SCRIPTDIR
  # shellcheck source=../lib/dybatpho/init.sh
  . "${scripts}/lib/dybatpho/init.sh"
  # shellcheck source-path=SCRIPTDIR
  # shellcheck source=../lib/test_select.sh
  . "${scripts}/lib/test_select.sh"
  ROOT="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${ROOT}/scripts/test" "${ROOT}/scripts/lib" "${ROOT}/home"
  printf '# nothing else\n' > "${ROOT}/scripts/test/foo.bats"
  printf '# nothing else\n' > "${ROOT}/scripts/test/bar.bats"
  printf 'reads pkgs/tools/claude.yaml\n' > "${ROOT}/scripts/test/pkgs.bats"
}

@test "a change to the runner selects the whole suite" {
  run test_select::files "${ROOT}" scripts/test.sh
  [ "${status}" -eq 0 ]
  [ "${output}" = "--all" ]
}

@test "a change to the selector itself selects the whole suite" {
  run test_select::files "${ROOT}" scripts/lib/test_select.sh
  [ "${status}" -eq 0 ]
  [ "${output}" = "--all" ]
}

@test "a file selects the bats file named after it" {
  touch "${ROOT}/scripts/lib/foo.sh"
  run test_select::files "${ROOT}" scripts/lib/foo.sh
  [ "${status}" -eq 0 ]
  [ "${output}" = "${ROOT}/scripts/test/foo.bats" ]
}

@test "a changed bats file selects itself" {
  run test_select::files "${ROOT}" scripts/test/bar.bats
  [ "${status}" -eq 0 ]
  [ "${output}" = "${ROOT}/scripts/test/bar.bats" ]
}

@test "a file selects every bats file that mentions its name" {
  mkdir -p "${ROOT}/home/pkgs/tools"
  touch "${ROOT}/home/pkgs/tools/claude.yaml"
  run test_select::files "${ROOT}" home/pkgs/tools/claude.yaml
  [ "${status}" -eq 0 ]
  [ "${output}" = "${ROOT}/scripts/test/pkgs.bats" ]
}

@test "chezmoi attribute prefixes and .tmpl are stripped from the name" {
  touch "${ROOT}/home/executable_dot_foo.sh.tmpl"
  run test_select::files "${ROOT}" home/executable_dot_foo.sh.tmpl
  [ "${status}" -eq 0 ]
  [ "${output}" = "${ROOT}/scripts/test/foo.bats" ]
}

@test "a file no test names selects the whole suite" {
  touch "${ROOT}/home/lonely.txt"
  run test_select::files "${ROOT}" home/lonely.txt
  [ "${status}" -eq 0 ]
  [ "${output}" = "--all" ]
}

@test "prose no test names selects nothing" {
  touch "${ROOT}/README.md"
  run test_select::files "${ROOT}" README.md
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "a deleted file no test names selects nothing" {
  run test_select::files "${ROOT}" home/gone.txt
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "a path the sandbox masks is no change" {
  # A FIFO stands in for the device a sandbox puts over a hidden file: it
  # exists and is neither a file nor a directory.
  mkfifo "${ROOT}/home/masked"
  run test_select::files "${ROOT}" home/masked
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "several paths give each bats file once, sorted" {
  touch "${ROOT}/scripts/lib/foo.sh" "${ROOT}/home/dot_foo.tmpl"
  run test_select::files "${ROOT}" scripts/test/pkgs.bats scripts/lib/foo.sh \
    home/dot_foo.tmpl scripts/test/bar.bats
  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf '%s\n' "${ROOT}/scripts/test/"{bar,foo,pkgs}.bats)" ]
}
