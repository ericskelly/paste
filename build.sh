#!/bin/sh
set -e

ZIG_VERSION="0.16.0"
ZIG_TAR="zig-linux-x86_64-${ZIG_VERSION}.tar.xz"

curl -L "https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TAR}" -o zig.tar.xz
tar -xf zig.tar.xz
export PATH="$PWD/zig-linux-x86_64-${ZIG_VERSION}:$PATH"

npm run build