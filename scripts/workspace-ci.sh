#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
windows_script="$(cygpath -w "$script_dir/workspace-ci.ps1")"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$windows_script" "$@"
