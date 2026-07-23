#!/bin/sh
# Builds the buzzerd CLI and the Buzzctl menu bar app.
set -e
cd "$(dirname "$0")"

swiftc -O -parse-as-library Engine.swift buzzerd.swift -o buzzerd
./buzzerd selftest

swiftc -O -parse-as-library Engine.swift BuzzctlApp.swift -o Buzzctl
rm -rf Buzzctl.app
mkdir -p Buzzctl.app/Contents/MacOS
cp Buzzctl Buzzctl.app/Contents/MacOS/
cp Info.plist Buzzctl.app/Contents/
# Use a real signing identity if one exists — keeps the code signature stable
# across rebuilds, so the macOS Accessibility grant survives. Ad-hoc otherwise.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p' | head -1)
codesign --force -s "${IDENTITY:--}" Buzzctl.app
echo "signed as: ${IDENTITY:-ad-hoc}"
echo "built: ./buzzerd and ./Buzzctl.app"
