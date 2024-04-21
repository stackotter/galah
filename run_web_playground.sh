# You can use alternative swift-build and swift-run binaries (e.g. one's you've built yourself)
# by providing a path to the swift-build binary followed by a path to the swift-run binary.

SWIFT_BUILD=${1:-"swift build"}
SWIFT_RUN=${2:-"swift run"}

bash -c "$SWIFT_BUILD \
             --experimental-swift-sdk 5.10-SNAPSHOT-2024-04-09-a-wasm \
             --product GalahWeb \
             --scratch-path .build/wasm" \
&& bash -c "$SWIFT_RUN CartonFrontend dev \
    --main-wasm-path .build/wasm/debug/GalahWeb.wasm \
    --build-request /dev/null \
    --build-response /dev/null \
    --resources .build/wasm/debug/ \
    --skip-auto-open"
