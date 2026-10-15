#!/bin/sh
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), Swift Testing
# lives in a framework folder that SwiftPM doesn't search by default, so add it explicitly.
set -eu
cd "$(dirname "$0")/.."
DEV=$(xcode-select -p)
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"
if [ -d "$FW/Testing.framework" ] && [ ! -d "$DEV/Platforms" ]; then
  exec swift test \
    -Xswiftc -F"$FW" -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" "$@"
fi
exec swift test "$@"
