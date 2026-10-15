#!/bin/sh
# Makes sure this Mac can build ScreenInk: Apple Silicon, macOS 14+, and a Swift 6 toolchain
# from the Command Line Tools or Xcode (which also provide codesign and lipo). There are no
# package dependencies. Safe to run again; it only installs what's missing.
set -eu

fail() { echo "✗ $*" >&2; exit 1; }

[ "$(uname -m)" = arm64 ] || fail "ScreenInk builds for Apple Silicon only (this Mac is $(uname -m))."
MACOS=$(sw_vers -productVersion)
[ "${MACOS%%.*}" -ge 14 ] || fail "macOS 14 or later is required (this Mac has $MACOS)."
echo "✓ macOS $MACOS on arm64"

# Check before calling swift: without developer tools, /usr/bin/swift is only an installer stub.
if ! DEV=$(xcode-select -p 2>/dev/null) || [ ! -x "$DEV/usr/bin/swift" ]; then
  echo "Installing the Command Line Tools. Finish the dialog that opens, then run 'make install' again."
  xcode-select --install || true
  exit 1
fi
echo "✓ Developer tools at $DEV"

SWIFT=$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p' | head -1)
[ -n "$SWIFT" ] || fail "Couldn't read the Swift version from 'swift --version'."
[ "${SWIFT%%.*}" -ge 6 ] || fail "Swift 6 or later is required (found $SWIFT).
  Update the Command Line Tools in System Settings › General › Software Update, or install a current Xcode."
echo "✓ Swift $SWIFT"

for tool in codesign lipo; do
  command -v "$tool" >/dev/null || fail "$tool is missing; reinstall the Command Line Tools."
done
echo "✓ codesign and lipo"

echo "Ready to build: run 'make run'."
