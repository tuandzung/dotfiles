#!/bin/sh

# -e: exit on error
# -u: exit on unset variables
set -eu

_log_color() {
  color_code="$1"
  shift

  printf "\033[${color_code}m%s\033[0m\n" "$*" >&2
}

_log_red() {
  _log_color "0;31" "$@"
}

_log_blue() {
  _log_color "0;34" "$@"
}

_log_task() {
  _log_blue "🔃" "$@"
}

_log_error() {
  _log_red "❌" "$@"
}

_error() {
  _log_error "$@"
  exit 1
}

_install_chezmoi() {
  if ! chezmoi="$(command -v chezmoi)"; then
    bin_dir="${HOME}/.local/bin"
    chezmoi="${bin_dir}/chezmoi"
    _log_task "Installing chezmoi to '${chezmoi}'"
    if command -v curl >/dev/null; then
      chezmoi_install_script="$(curl -fsSL https://get.chezmoi.io)"
    elif command -v wget >/dev/null; then
      chezmoi_install_script="$(wget -qO- https://get.chezmoi.io)"
    else
      _error "To install chezmoi, you must have curl or wget."
    fi
    sh -c "${chezmoi_install_script}" -- -b "${bin_dir}"
    unset chezmoi_install_script bin_dir
  fi
}

_install_age() {
  if ! age="$(command -v age)"; then
    bin_dir="${HOME}/.local/bin"
    age="${bin_dir}/age"
    _log_task "Installing age to '${age}'"
    temp=$(mktemp)
    if command -v curl > /dev/null; then
      curl -sSL -o "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    elif command -v wget > /dev/null; then
      wget -qO "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    else
      _error "To install age, you must have curl or wget."
    fi

    if command -v tar > /dev/null; then
      tar -C "$bin_dir" -xzf "$temp" --strip=1 age/age
    else
      _error "To install age, you must have tar and gzip installed."
    fi

    rm -rf "$temp"
    unset bin_dir
  fi
}

_main() {
  mkdir -p "${HOME}/.local/bin"
  export PATH="${HOME}/.local/bin:${PATH}"
  _install_chezmoi
  _install_age
  # POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
  # shellcheck disable=SC2312
  script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

  set -- init "$@"

  if [ -n "${DOTFILES_ONE_SHOT-}" ]; then
    set -- "$@" --one-shot
  else
    set -- "$@" --apply
  fi

  if [ -n "${DOTFILES_DEBUG-}" ]; then
    set -- "$@" --debug --verbose --dry-run
  fi

  _log_task "Running 'chezmoi $*'"
  # replace current process with chezmoi
  exec "${chezmoi}" "$@"
}

_main
