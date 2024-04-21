#!/bin/bash
set -e

# You can use an alternative swift-build binary (e.g. one's you've built yourself)
# by providing a path to the swift-build binary as the first argument to this script.

# Set the WASM_OPTIMIZE environment variable to any value to create an optimized build.

SWIFT_BUILD=${1:-"swift build"}

bash -c "$SWIFT_BUILD \
             --experimental-swift-sdk 5.10-SNAPSHOT-2024-04-09-a-wasm \
             --product GalahWeb \
             --scratch-path .build/wasm"
cp .build/wasm/debug/GalahWeb.wasm static
mv static/GalahWeb.wasm static/main.wasm

if [[ -v WASM_OPTIMIZE ]]; then
  wasm-strip static/main.wasm
  wasm-opt -Oz static/main.wasm -o static/main.wasm
fi

cd static
rm main.wasm.gz || true
gzip -9 main.wasm
