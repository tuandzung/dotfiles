#!/usr/bin/env bats
# @file pkgs_schema.bats
# @brief Validate the tool list pkg_installer reads
# @description
#   Renders `home/dot_config/pkg_installer/tools.yaml.tmpl`, the list built from
#   every file in `home/.chezmoitemplates/pkgs/tools/`, and checks each entry
#   against the shape the Python installers expect. chezmoi renders for the
#   machine it runs on, so an entry for another OS is checked only there.
#   Each check prints the names of the offending entries, `[]` when none.

setup_file() {
  # Run from a git hook, these would point git at the repository committed to.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  REPO_ROOT="$(realpath "${BATS_TEST_DIRNAME}/../..")"
  export REPO_ROOT
  command -v chezmoi > /dev/null || skip "chezmoi is not installed"
  # The Python yq takes jq syntax and reads these queries differently.
  [[ "$(yq --version 2>&1)" == *mikefarah* ]] || skip "mikefarah yq v4 is not installed"
  TOOLS="${BATS_FILE_TMPDIR}/tools.yaml"
  export TOOLS
  chezmoi execute-template --source "${REPO_ROOT}" \
    --file "${REPO_ROOT}/home/dot_config/pkg_installer/tools.yaml.tmpl" > "${TOOLS}"
}

# @description Run a yq query on the entries this OS renders: a file that
#   renders nothing for it leaves a null in the list, which `main.py` skips.
# @arg $1 string Query reading the list of non-null entries as `.`
# @stdout The query's result, as one line of JSON
# yq binds `and`/`or` looser than `|`: wrap them in parentheses after a pipe.
check() {
  yq -o json -I0 "[.[] | select(. != null)] | $1" "${TOOLS}"
}

@test "every tracked file under pkgs/ is YAML or a YAML template" {
  run git -C "${REPO_ROOT}" ls-files home/.chezmoitemplates/pkgs
  [ "${status}" -eq 0 ]
  local file
  for file in ${lines[@]+"${lines[@]}"}; do
    [[ "${file}" =~ \.yaml(\.tmpl)?$ ]] || {
      echo "not YAML: ${file}"
      return 1
    }
  done
}

@test "the rendered list is a YAML sequence" {
  run yq 'tag' "${TOOLS}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "!!seq" ]
}

@test "every entry has a name" {
  run check '[.[] | select((.name | tag) != "!!str" or .name == "")]'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "no two entries share a name" {
  run check '[.[].name] | group_by(.) | map(select(length > 1) | .[0])'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "method is os, binary or shell" {
  # main.py drops an entry with any other method without a word.
  run check '[.[] | select(.method != "os" and .method != "binary"
    and .method != "shell") | .name]'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "is_essential is a boolean when set" {
  run check '[.[] | select(has("is_essential")
    and (.is_essential | tag) != "!!bool") | .name]'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "a binary entry has exactly one of github or gitlab" {
  run check '[.[] | select(.method == "binary")
    | select(has("github") == has("gitlab")) | .name]'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "a binary entry names its repo as owner/name, gitlab with subgroups" {
  run check '[.[] | select(.method == "binary")
    | select((has("github")
        and ((.github.repo // "") | test("^[^/ ]+/[^/ ]+$") | not))
      or (has("gitlab")
        and ((.gitlab.repo // "") | test("^[^/ ]+(/[^/ ]+)+$") | not)))
    | .name]'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "a binary archive lists items with a path, or maps paths" {
  # binary_installer.py reads a list of `{path, strip, location}` items, or
  # the older `{paths: [...]}` mapping.
  run check '[.[] | select(.method == "binary" and has("archive"))
    | select(
        ((.archive | tag) == "!!seq"
          and ([.archive[] | (.path // "") == ""] | any))
        or ((.archive | tag) == "!!map"
          and ((.archive.paths | tag) != "!!seq" or (.archive.paths | length) == 0))
        or ((.archive | tag) != "!!seq" and (.archive | tag) != "!!map"))
    | .name]'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "a shell entry has content" {
  run check '[.[] | select(.method == "shell")
    | select((.content // "") == "") | .name]'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "a shell entry depends only on entries of this list" {
  # shell_installer.py looks each dependency up by name and skips, without a
  # word, one it does not find.
  # dyshellint disable=SC2016 $names and $dep are yq variables, not shell ones
  run check '[.[].name] as $names | [.[]
    | select(.method == "shell") | .dependencies[]?
    | select(. as $dep | $names | any_c(. == $dep) | not)] | unique'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "an os entry has a block for at least one OS" {
  run check '[.[] | select(.method == "os")
    | select([has("gentoo"), has("arch"), has("ubuntu"), has("macos"),
      has("termux")] | any | not)
    | .name]'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "an os block's packages is a list" {
  run check '[.[] | select(.method == "os")
    | select([.gentoo, .arch, .ubuntu, .macos, .termux][] | select(. != null)
      | (has("packages") and (.packages | tag) != "!!seq")) | .name] | unique'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "every package of an os entry has a name" {
  run check '[.[] | select(.method == "os")
    | select([.gentoo, .arch, .ubuntu, .macos, .termux][] | select(. != null)
      | .packages[]? | ((.name | tag) != "!!str" or .name == "")) | .name] | unique'
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}
