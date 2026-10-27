#!/bin/bash
# Runs the test suite with whichever toolchain is selected (Xcode or the Command Line Tools).
# Under the Command Line Tools, `swift test` doesn't find their Swift Testing framework on its
# own, so point the compiler, linker, and runtime search path at it. Extra args pass through,
# e.g. ./run_tests.sh --filter OCRLayoutTests
DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
FRAMEWORKS="$DEV_DIR/Library/Developer/Frameworks"
ARGS=()
if [ -d "$FRAMEWORKS/Testing.framework" ]; then
  ARGS+=(-Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -F -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS")
fi
exec swift test "${ARGS[@]}" "$@"
