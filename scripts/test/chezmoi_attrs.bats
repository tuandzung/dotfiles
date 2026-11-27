#!/usr/bin/env bats
# @file chezmoi_attrs.bats
# @brief Tests for scripts/lib/chezmoi_attrs.sh

setup() {
  local scripts
  scripts="$(realpath "${BATS_TEST_DIRNAME}/..")"
  # shellcheck source-path=SCRIPTDIR
  # shellcheck source=../lib/dybatpho/init.sh
  . "${scripts}/lib/dybatpho/init.sh"
  # shellcheck source-path=SCRIPTDIR
  # shellcheck source=../lib/chezmoi_attrs.sh
  . "${scripts}/lib/chezmoi_attrs.sh"
}

@test "validate accepts known attributes" {
  run chezmoi_attrs::validate "create,encrypted,executable"
  [ "${status}" -eq 0 ]
}

@test "validate accepts an empty list" {
  run chezmoi_attrs::validate ""
  [ "${status}" -eq 0 ]
}

@test "validate rejects an unknown attribute and names it" {
  run chezmoi_attrs::validate "create,bogus"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"'bogus'"* ]]
}

@test "a path under HOME maps into home/, dotted parts private" {
  local out
  chezmoi_attrs::source_path out "${HOME}/.config/.foo" "create,encrypted"
  [ "${out}" = "home/private_dot_config/create_encrypted_private_dot_foo" ]
}

@test "a literal ~/ path maps into home/" {
  local out
  # dyshellint disable=SC2088 the literal `~/` a caller types is the input under test
  chezmoi_attrs::source_path out '~/notes/todo.md' ""
  [ "${out}" = "home/notes/todo.md" ]
}

@test "an absolute path outside HOME maps into root/" {
  local out
  chezmoi_attrs::source_path out "/etc/hosts" "readonly"
  [ "${out}" = "root/etc/readonly_hosts" ]
}

@test "prefixes follow chezmoi's order, not the caller's" {
  local out
  chezmoi_attrs::source_path out "${HOME}/bin/tool" "executable,create"
  [ "${out}" = "home/bin/create_executable_tool" ]
}

@test "private on a dotted name is written once" {
  local out
  chezmoi_attrs::source_path out "${HOME}/.foo" "private"
  [ "${out}" = "home/private_dot_foo" ]
}

@test "a name chezmoi would read as attributes is marked literal_" {
  local out
  chezmoi_attrs::source_path out "/opt/run_me" ""
  [ "${out}" = "root/opt/literal_run_me" ]
}

@test "a .tmpl suffix is kept with .literal" {
  local out
  chezmoi_attrs::source_path out "${HOME}/page.tmpl" ""
  [ "${out}" = "home/page.tmpl.literal" ]
}

@test "the result reaches a caller variable named like a local" {
  local fields
  chezmoi_attrs::source_path fields "${HOME}/.foo" ""
  [ "${fields}" = "home/private_dot_foo" ]
}

@test "a relative target fails" {
  run chezmoi_attrs::source_path out "relative/path" ""
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"must start with"* ]]
}

@test "a target with no file name fails" {
  run chezmoi_attrs::source_path out "${HOME}/" ""
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"has no file name"* ]]
}

@test "an unknown attribute fails" {
  run chezmoi_attrs::source_path out "${HOME}/.foo" "bogus"
  [ "${status}" -eq 1 ]
}
