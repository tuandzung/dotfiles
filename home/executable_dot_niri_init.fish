#!/bin/env fish

mkdir -p $XDG_RUNTIME_DIR
dbus-run-session niri --session
