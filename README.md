# Revolute-Taycoon

A casino business management simulator for iOS. You run the company — equipment, staff, taxes,
licenses, loans and branches — from a small gaming club to a casino chain. The player never places bets.

## Layout

- `RevoluteTycoon/` — SwiftUI app (UI, vector art, bridge to the engine)
- `rust/engine/` — `taycoon_engine` static library: simulation, economy, anti-tamper, save sealing
- `scripts/build_rust.sh` — Xcode pre-build step that compiles the Rust library for the current platform
- `project.yml` — XcodeGen spec; `codemagic.yaml` — CI / App Store pipeline

## Build locally

Requirements: Xcode 16+, [rustup](https://rustup.rs), XcodeGen (`brew install xcodegen`).

```sh
(cd rust && rustup toolchain install)   # pinned by rust/rust-toolchain.toml
xcodegen generate
open RevoluteTycoon.xcodeproj
```

Engine tests: `cd rust && cargo test --release`.

## Release

Pushing to `main` triggers the `ios-app-store` workflow on Codemagic, which builds a signed IPA and
uploads it to TestFlight (bundle id `com.taycoon.revolute`, Apple ID `6824470855`).
