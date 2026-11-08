#!/bin/zsh
set -eu
cd "${0:A:h}"
export SCREENY_ARCHS='arm64 x86_64'
./build.sh
xcrun lipo build/screeny.app/Contents/MacOS/screeny -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent build/screeny.app build/screeny-macos-universal.zip
(cd build && shasum -a 256 screeny-macos-universal.zip > screeny-macos-universal.zip.sha256)
