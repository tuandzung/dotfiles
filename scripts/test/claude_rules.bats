#!/usr/bin/env bats
# @file claude_rules.bats
# @brief Keep Claude's instruction files in step with the agent partials
# @description
#   Other agents read every partial of `home/.chezmoitemplates/ai/` through
#   `ai/all.md.tmpl`. Claude reads the same partials split up: the absolute
#   rules in each config dir's `CLAUDE.md.tmpl`, one rule file per partial in
#   its `rules/`. A partial missing from either place is an instruction Claude
#   never sees, and nothing else would notice.

setup_file() {
  REPO_ROOT="$(realpath "${BATS_TEST_DIRNAME}/../..")"
  AI="${REPO_ROOT}/home/.chezmoitemplates/ai"
  CONFIG_DIRS=(
    "${REPO_ROOT}/home/private_dot_claude"
    "${REPO_ROOT}/home/Working/Enterprise/TCV/private_dot_claude"
  )
  ABSOLUTE=(credentials destructive-commands)
  export REPO_ROOT AI ABSOLUTE_LIST="${ABSOLUTE[*]}" CONFIG_DIR_LIST="${CONFIG_DIRS[*]}"
}

# @description Print the partials `all.md.tmpl` includes, one name per line
# @stdout Partial names without the `ai/` prefix or `.md.tmpl` suffix
partials() {
  local line
  while IFS= read -r line; do
    [[ "${line}" =~ template\ \"ai/([a-z-]+)\.md\.tmpl\" ]] && printf '%s\n' "${BASH_REMATCH[1]}"
  done < "${AI}/all.md.tmpl"
}

@test "all.md.tmpl includes every partial and both absolute rules" {
  run partials
  [ "${status}" -eq 0 ]
  [ "${#lines[@]}" -gt 2 ]
  local name
  for name in ${ABSOLUTE_LIST}; do
    [[ " ${lines[*]} " == *" ${name} "* ]]
  done
}

@test "every working-convention partial has a rule file that includes it" {
  local name dir missing=()
  while IFS= read -r name; do
    [[ " ${ABSOLUTE_LIST} " == *" ${name} "* ]] && continue
    for dir in ${CONFIG_DIR_LIST}; do
      grep -q "template \"ai/${name}.md.tmpl\"" "${dir}/rules/${name}.md.tmpl" 2> /dev/null \
        || missing+=("${dir#"${REPO_ROOT}/"}/rules/${name}.md.tmpl")
    done
  done < <(partials)
  printf 'missing or not including its partial: %s\n' "${missing[*]-}"
  [ "${#missing[@]}" -eq 0 ]
}

@test "no rule file is left over from a removed partial" {
  local dir file name extra=()
  for dir in ${CONFIG_DIR_LIST}; do
    for file in "${dir}"/rules/*.md.tmpl; do
      name="$(basename "${file}" .md.tmpl)"
      [ -f "${AI}/${name}.md.tmpl" ] || extra+=("${file#"${REPO_ROOT}/"}")
    done
  done
  printf 'no partial behind: %s\n' "${extra[*]-}"
  [ "${#extra[@]}" -eq 0 ]
}

@test "each CLAUDE.md.tmpl includes the absolute rules" {
  local dir name missing=()
  for dir in ${CONFIG_DIR_LIST}; do
    for name in ${ABSOLUTE_LIST}; do
      grep -q "template \"ai/${name}.md.tmpl\"" "${dir}/CLAUDE.md.tmpl" \
        || missing+=("${dir#"${REPO_ROOT}/"}: ${name}")
    done
  done
  printf 'missing: %s\n' "${missing[*]-}"
  [ "${#missing[@]}" -eq 0 ]
}

@test "both config dirs carry the same rule files" {
  local -a dirs
  read -r -a dirs <<< "${CONFIG_DIR_LIST}"
  local file name differ=()
  # Only the templates: claude-mem drops untracked notes next to them.
  for file in "${dirs[0]}"/rules/*.md.tmpl "${dirs[1]}"/rules/*.md.tmpl; do
    name="$(basename "${file}")"
    cmp -s "${dirs[0]}/rules/${name}" "${dirs[1]}/rules/${name}" || differ+=("${name}")
  done
  printf 'differ or missing in one dir: %s\n' "${differ[*]-}"
  [ "${#differ[@]}" -eq 0 ]
}
