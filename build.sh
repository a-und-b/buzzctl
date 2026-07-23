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
codesign --force -s - Buzzctl.app   # ad-hoc signature
echo "built: ./buzzerd and ./Buzzctl.app"
