#!/usr/bin/env bash
# Runs the unit tests. With only Command Line Tools installed, Swift Testing lives
# outside the default search paths, so point the compiler and linker at it.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$DEV/Frameworks/Testing.framework" ]; then
  swift test -Xswiftc -F"$DEV/Frameworks" -Xlinker -F"$DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/Frameworks" -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
else
  swift test "$@"
fi
