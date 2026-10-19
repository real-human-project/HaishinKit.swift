#!/bin/bash
set -euo pipefail

fixtures=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$fixtures/../.." && pwd)
source=${1:-"$repo/HaishinKit/Sources/Stream/StreamRecorder.swift"}
build_dir=$(mktemp -d /tmp/agent.haishinkit.recorder-finish.XXXXXX)
trap 'rm -r -- "$build_dir"' EXIT

# This controlled SDK boundary never enters the package's real SDK build.
xcrun swiftc -swift-version 6 -module-cache-path "$build_dir/module-cache" \
    -emit-library -emit-module -module-name AVFoundation \
    -emit-module-path "$build_dir/AVFoundation.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libAVFoundation.dylib \
    "$fixtures/AVFoundation.swift" -o "$build_dir/libAVFoundation.dylib"
xcrun swiftc -swift-version 6 -module-cache-path "$build_dir/module-cache" \
    -I "$build_dir" -L "$build_dir" -lAVFoundation \
    -Xlinker -rpath -Xlinker "$build_dir" -parse-as-library \
    "$source" "$fixtures/RecorderFinishTests.swift" -o "$build_dir/recorder-finish-tests"
"$build_dir/recorder-finish-tests" "$build_dir"
