#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build-tests
sources=(Sources/*.swift)
sources=(${sources:#Sources/main.swift})
swiftc -g -swift-version 5 -target arm64-apple-macos14.0 "${sources[@]}" Tests/main.swift -o build-tests/FormulensTests
if [[ -n "${FORMULENS_TEST_SNAPSHOT:-}" ]]; then
  cp -R Resources/. build-tests/
fi
build-tests/FormulensTests
