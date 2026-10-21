#!/bin/zsh
# Builds SidecarSide and installs it to /Applications, replacing any running copy.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

pkill -x SidecarSide 2>/dev/null && while pgrep -x SidecarSide >/dev/null; do sleep 0.2; done || true
rm -rf /Applications/SidecarSide.app
ditto build/SidecarSide.app /Applications/SidecarSide.app

# -F: fresh launch, so no arguments from an earlier `open --args` are reused
open -F /Applications/SidecarSide.app
echo "Installed to /Applications/SidecarSide.app"
