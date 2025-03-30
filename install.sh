#!/bin/bash

set -Eeou pipefail
SETUP_DIR=$(dirname "$(readlink -f "$0")")
BIN_DIR="$HOME/.local/bin"
source "${SETUP_DIR}/scripts/logger.sh"

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
    _notice "Installing chezmoi to '${chezmoi}'"
    if command -v curl > /dev/null; then
      chezmoi_install_script="$(curl -fsSL https://get.chezmoi.io)"
    elif command -v wget > /dev/null; then
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
    _notice "Installing age to '${age}'"
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
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR:$PATH"
  _install_chezmoi
  _install_age

  _notice "Initialize chezmoi"
  echo "sourceDir: \"$(readlink -f "$SETUP_DIR")\"" > "$SETUP_DIR"/home/.chezmoi.yaml.tmpl
  cat "$SETUP_DIR"/.chezmoi.yaml.tmpl >> "$SETUP_DIR"/home/.chezmoi.yaml.tmpl

  ${chezmoi} init -S "$SETUP_DIR"

  _notice "Apply ssh"
  if [ -n "${DOTFILES_DEBUG-}" ]; then
    ${chezmoi} apply --debug --verbose --dry-run "$HOME/.ssh"
  else
    ${chezmoi} apply "$HOME/.ssh"
  fi

  _notice "Apply rootmoi"
  if [ -n "${DOTFILES_DEBUG-}" ]; then
    ${chezmoi} apply --debug --verbose --dry-run "$HOME/.config/rootmoi"
    ${chezmoi} apply --debug --verbose --dry-run "$HOME/.local/bin/rootmoi"
  else
    ${chezmoi} apply "$HOME/.config/rootmoi"
    ${chezmoi} apply "$HOME/.local/bin/rootmoi"
  fi

  _notice "Initialize system configurations"
  rootmoi init -S "$SETUP_DIR"/root

  _notice "Apply system configurations"
  if [ -n "${DOTFILES_DEBUG-}" ]; then
    rootmoi apply --debug --verbose --dry-run
  else
    rootmoi apply
  fi

  _notice "Apply dotfiles"
  if [ -n "${DOTFILES_DEBUG-}" ]; then
    ${chezmoi} apply --debug --verbose --dry-run
  else
    ${chezmoi} apply
  fi

  # Modify remote url of dotfiles
  _notice "Modify remote url of dotfiles"
  cd "$SETUP_DIR"
  git remote set-url origin git@github.com:tuandzung/dotfiles.git
  git config --local include.path .gitconfig

  _success "Install complete"
}

_main
