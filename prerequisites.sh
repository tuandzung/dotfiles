#!/bin/sh
set -Eeuo pipefail

if command -v sw_vers &> /dev/null; then
  UNAME_MACHINE="$(/usr/bin/uname -m)"
  if [[ "${UNAME_MACHINE}" == "arm64" ]]
  then
    # On ARM macOS, this script installs to /opt/homebrew only
    HOMEBREW_PREFIX="/opt/homebrew"
  else
    # On Intel macOS, this script installs to /usr/local only
    HOMEBREW_PREFIX="/usr/local"
  fi
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash - || :
  (echo; echo "eval \"\$(${HOMEBREW_PREFIX}/bin/brew shellenv)\"") >> ~/.zprofile
  eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
  brew update && brew install bash coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent gnu-getopt grep chezmoi age yq
  echo "export PATH=\"$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin:$HOMEBREW_PREFIX/opt/gnu-tar/libexec/gnubin:$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$HOMEBREW_PREFIX/opt/gawk/libexec/gnubin:$HOMEBREW_PREFIX/opt/gnu-indent/libexec/gnubin:$HOMEBREW_PREFIX/opt/gnu-getopt/bin:$HOMEBREW_PREFIX/opt/grep/libexec/gnubin:$PATH\"" >> ~/.zprofile
elif command -v apt &> /dev/null; then
  sudo apt update && sudo apt install -y git curl gnupg openssh-client
elif command -v pacman &> /dev/null; then
  sudo pacman -Sy && sudo pacman -Sy --noconfirm git curl openssh
  if ! command -v yay > /dev/null; then
    sudo pacman -S --noconfirm --needed git base-devel go
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay || exit
    makepkg -si --noconfirm
    rm -rf /tmp/yay
    sudo pacman -Rscn --noconfirm go
  fi
  yay -Syu --noconfirm
elif command -v emerge &> /dev/null; then
  sudo emerge --sync && sudo emerge \
    dev-vcs/git \
    net-misc/curl \
    net-misc/openssh \
    app-portage/gentoolkit \
    app-portage/portage-utils \
    app-eselect/eselect-repository \
    app-portage/cpuid2cpuflags
  sudo eselect repository add tep git https://github.com/tuandzung/gentoo-overlay.git
  sudo emerge --sync tep
fi

git clone https://github.com/tuandzung/dotfiles.git ~/Dotfiles
