#!/usr/bin/env bash

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
BIN_DIR="$HOME/.local/bin"

# shellcheck source=scripts/lib/dybatpho/init.sh
. "$SCRIPT_DIR/scripts/lib/dybatpho/init.sh"
SETUP_DIR=$(dirname "$(readlink -f "$0")")

_install_chezmoi() {
  if ! chezmoi="$(command -v chezmoi)"; then
    bin_dir="${HOME}/.local/bin"
    chezmoi="${bin_dir}/chezmoi"
    dybatpho::progress "Installing chezmoi to '${chezmoi}'"
    if command -v curl > /dev/null; then
      chezmoi_install_script="$(curl -fsSL https://get.chezmoi.io)"
    elif command -v wget > /dev/null; then
      chezmoi_install_script="$(wget -qO- https://get.chezmoi.io)"
    else
      dybatpho::error "To install chezmoi, you must have curl or wget."
    fi
    sh -c "${chezmoi_install_script}" -- -b "${bin_dir}"
    unset chezmoi_install_script bin_dir
  fi
}

_install_age() {
  if ! age="$(command -v age)"; then
    bin_dir="${HOME}/.local/bin"
    age="${bin_dir}/age"
    dybatpho::progress "Installing age to '${age}'"
    temp=$(mktemp)
    if command -v curl > /dev/null; then
      curl -sSL -o "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    elif command -v wget > /dev/null; then
      wget -qO "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    else
      dybatpho::error "To install age, you must have curl or wget."
    fi

    if command -v tar > /dev/null; then
      tar -C "$bin_dir" -xzf "$temp" --strip=1 age/age
    else
      dybatpho::error "To install age, you must have tar and gzip installed."
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

  dybatpho::header "Initialize chezmoi"
  echo "sourceDir: \"$(readlink -f "$SETUP_DIR")\"" > "$SETUP_DIR"/home/.chezmoi.yaml.tmpl
  cat "$SETUP_DIR"/.chezmoi.yaml.tmpl >> "$SETUP_DIR"/home/.chezmoi.yaml.tmpl

  ${chezmoi} init -S "$SETUP_DIR"

  dybatpho::header "Apply ssh"
  if [ -n "${DOTFILES_DEBUG-}" ]; then
    ${chezmoi} apply --debug --verbose --dry-run "$HOME/.ssh"
  else
    ${chezmoi} apply "$HOME/.ssh"
  fi

  dybatpho::header "Apply rootmoi"
  if [ -n "${DOTFILES_DEBUG-}" ]; then
    ${chezmoi} apply --debug --verbose --dry-run "$HOME/.config/rootmoi"
    ${chezmoi} apply --debug --verbose --dry-run "$HOME/.local/bin/rootmoi"
  else
    ${chezmoi} apply "$HOME/.config/rootmoi"
    ${chezmoi} apply "$HOME/.local/bin/rootmoi"
  fi

  dybatpho::header "Initialize system configurations"
  rootmoi init -S "$SETUP_DIR"/root

  dybatpho::header "Apply dotfiles"
  if [ -n "${DOTFILES_DEBUG-}" ]; then
    ${chezmoi} apply --debug --verbose --dry-run
  else
    ${chezmoi} apply
  fi

  if [ -n "${DOTFILES_DEBUG-}" ]; then
    rootmoi apply --debug --verbose --dry-run
  else
    # Apply OS specific configuration if not Termux
    if sudo -n true 2> /dev/null || sudo true &> /dev/null; then
      case "$(dybatpho::goos)" in
        darwin)
          dybatpho::header "Apply system configurations"
          "$(dybatpho::path_join "$BIN_DIR" "rootmoi")" apply /Applications
          "$(dybatpho::path_join "$BIN_DIR" "rootmoi")" apply /private
          ;;
        linux)
          dybatpho::header "Apply system configurations"
          "$(dybatpho::path_join "$BIN_DIR" "rootmoi")" apply
          ;;
      esac
    fi
  fi

  # Modify remote url of dotfiles
  dybatpho::header "Modify remote url of dotfiles"
  cd "$SETUP_DIR" || exit
  git remote set-url origin git@github.com:tuandzung/dotfiles.git
  git config --local include.path .gitconfig

  dybatpho::success "Install complete"
}

_main
