#!/bin/bash
# Builds the Rust engine as a static library for the platform Xcode is
# building for and drops it where the app target links it from.
# Release builds enable the `hardened` feature (debugger detection).
set -euo pipefail

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

ROOT="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
RUST_DIR="$ROOT/rust"
PLATFORM="${PLATFORM_NAME:-iphonesimulator}"
CONFIG="${CONFIGURATION:-Debug}"
ARCHS_LIST="${ARCHS:-arm64}"
OUT_DIR="$RUST_DIR/target/xcode/$PLATFORM"
export CARGO_TARGET_DIR="$RUST_DIR/target"

# Keep local paths (home directory, project folder) out of the shipped binary.
# The encoded form is used because the project path contains spaces.
SEP=$'\x1f'
# rustc applies the LAST matching remap, so the most specific prefixes go last.
CARGO_HOME_DIR="${CARGO_HOME:-$HOME/.cargo}"
FLAGS="--remap-path-prefix=$HOME=/h${SEP}--remap-path-prefix=$CARGO_HOME_DIR=/c${SEP}--remap-path-prefix=$HOME/.rustup=/t${SEP}--remap-path-prefix=$RUST_DIR=/s"
# Git dependencies (the VM) would otherwise leak their crate names through panic locations.
n=0
for d in "$CARGO_HOME_DIR"/git/checkouts/*/* "$CARGO_HOME_DIR"/git/checkouts/*/*/crates/*; do
    [ -d "$d" ] || continue
    n=$((n + 1))
    FLAGS="$FLAGS${SEP}--remap-path-prefix=$d=/d$n"
done
for d in "$CARGO_HOME_DIR"/registry/src/*; do
    [ -d "$d" ] && FLAGS="$FLAGS${SEP}--remap-path-prefix=$d=/r"
done
export CARGO_ENCODED_RUSTFLAGS="$FLAGS"
unset RUSTFLAGS

FEATURES=()
if [ "$CONFIG" = "Release" ]; then
  FEATURES=(--features hardened)
fi

# Xcode exports variables that confuse cargo when building for another target.
unset SDKROOT LLVM_TARGET_TRIPLE_SUFFIX

LIBS=()
for ARCH in $ARCHS_LIST; do
  case "$PLATFORM:$ARCH" in
    iphoneos:arm64) TRIPLE=aarch64-apple-ios ;;
    iphonesimulator:arm64) TRIPLE=aarch64-apple-ios-sim ;;
    iphonesimulator:x86_64) TRIPLE=x86_64-apple-ios ;;
    *) echo "error: unsupported $PLATFORM/$ARCH"; exit 1 ;;
  esac
  (cd "$RUST_DIR" && cargo build --release --locked --target "$TRIPLE" -p taycoon_engine ${FEATURES[@]+"${FEATURES[@]}"})
  LIBS+=("$RUST_DIR/target/$TRIPLE/release/libtaycoon_engine.a")
done

mkdir -p "$OUT_DIR"
if [ "${#LIBS[@]}" -gt 1 ]; then
  lipo -create "${LIBS[@]}" -output "$OUT_DIR/libtaycoon_engine.a"
else
  cp -f "${LIBS[0]}" "$OUT_DIR/libtaycoon_engine.a"
fi
echo "Rust engine ready: $OUT_DIR/libtaycoon_engine.a"
