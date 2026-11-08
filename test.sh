#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
xcrun swiftc -O -whole-module-optimization -D SCREENY_TEST -module-cache-path build/ModuleCache -target "$(uname -m)-apple-macosx14.0" Sources/*.swift Tests/SelfTests.swift -o build/screenyTests
build/screenyTests --self-test
