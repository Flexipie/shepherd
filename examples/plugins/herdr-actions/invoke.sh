#!/bin/sh
# Invokes a herdr plugin action. herdr runs workspace actions on its focused workspace, so for a
# project action this focuses the project's workspace first.
set -eu
herdr="${HERDR_BIN_PATH:-herdr}"
case "${SHEPHERD_PROJECT_ID:-}" in
  herdr:*) "$herdr" workspace focus "${SHEPHERD_PROJECT_ID#herdr:}" >/dev/null ;;
esac
"$herdr" plugin action invoke --plugin "$1" "$2" >/dev/null
