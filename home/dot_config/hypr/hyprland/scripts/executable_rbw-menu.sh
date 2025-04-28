#!/bin/bash
set -eu
IFS='

'
# Creator: Robert Buchberger <robert@buchberger.cc>
#                            @robert@spacey.space
#
# Select an item from bitwarden with wofi, return value for passed query
# Dependencies: rbw installed and configured
#
# Usage: rbw-menu [query]
#   query: "code" or anything on the login object; username, password, totp, etc
#     - code will return a TOTP code
#     - anything else will return the value of the query
#   default: username

# Check if rbw is locked, redirect stderr and stdout to /dev/null. Unlock if
# necessary.
rbw unlocked > /dev/null 2>&1 || rbw unlock

query=${1:-username}

chosen_item=$(
  # If RBW_MENU_COMMAND is unset, use wofi
  if [ "${RBW_MENU_COMMAND:-}" = "" ]; then
    rbw list | wofi --dmenu --matching fuzzy --insensitive --prompt "$query"
  else
    eval "rbw list | $RBW_MENU_COMMAND"
  fi
)

# Exit if user didn't select anything
[ "$chosen_item" = "" ] && exit 1

case "$query" in
  code)
    rbw code "$chosen_item"
    ;;
  *)
    # Select chosen item from vault, return login.query
    rbw get "$chosen_item" --raw | jq --join-output ".data.$query"
    ;;
esac
