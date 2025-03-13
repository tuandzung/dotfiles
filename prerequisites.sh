#!/bin/sh
set -Eeuo pipefail

if command -v sw_vers &> /dev/null; then
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash - || :
  (echo; echo 'eval "$(/usr/local/bin/brew shellenv)"') >> ~/.zprofile
  eval "$(/usr/local/bin/brew shellenv)"
  brew update && brew install bash coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent gnu-getopt grep chezmoi age yq
  echo "export PATH=\"/usr/local/bin:/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/findutils/libexec/gnubin:/usr/local/opt/gnu-tar/libexec/gnubin:/usr/local/opt/gnu-sed/libexec/gnubin:/usr/local/opt/gawk/libexec/gnubin:/usr/local/opt/gnu-indent/libexec/gnubin:/usr/local/opt/gnu-getopt/bin:/usr/local/opt/grep/libexec/gnubin:$PATH\"" >> ~/.zprofile
elif command -v apt &> /dev/null; then
  sudo apt update && sudo apt install -y git curl gnupg openssh
elif command -v pacman &> /dev/null; then
  sudo pacman -Sy && sudo pacman -Sy git curl openssh
  if ! command -v yay > /dev/null; then
    sudo pacman -Sy --needed git base-devel go
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay || exit
    makepkg -si --noconfirm
    rm -rf /tmp/yay
    sudo pacman -Sy -Rscn --noconfirm go
  fi
elif command -v emerge &> /dev/null; then
  sudo emerge --sync && sudo emerge -uDN dev-vcs/git net-misc/curl net-misc/openssh app-portage/gentookit app-portage/portage-utils app-eselect/eselect-repository
fi

git clone https://github.com/tuandzung/dotfiles.git ~/Dotfiles
