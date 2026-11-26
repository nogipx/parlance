#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
fvm flutter build macos --release
exec fvm dart run bin/console.dart "$PWD/build/macos/Build/Products/Release/parlance_console.app/Contents/MacOS/parlance_console"
