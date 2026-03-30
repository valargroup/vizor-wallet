# CLAUDE.md

## Commands

```bash
# Always use fvm, never bare flutter
fvm flutter run
fvm flutter test
fvm flutter analyze

# Rust tests (run from project root or rust/)
cd rust && cargo test

# After changing Rust API files (rust/src/api/*.rs):
# MUST run from project root, not rust/
flutter_rust_bridge_codegen generate

# Clear app from iOS simulator (keychain + state + uninstall)
./clear-app.sh
```

### clear-app.sh

Removes the app from the booted iOS simulator including Keychain data. This is necessary when testing wallet creation/import because the mnemonic is stored in iOS Keychain via `flutter_secure_storage`, which persists even after a normal app uninstall.

## Architecture

Flutter + Rust FFI via `flutter_rust_bridge` v2. All Zcash cryptography runs in Rust (`librustzcash` crates). Dart handles UI, state management (Riverpod), and secure storage only.

### Rust API Design Constraint

FRB codegen works best with simple types. Keep the `rust/src/api/` surface limited to primitives, `String`, and flat structs. Do all complex Zcash type manipulation inside `rust/src/wallet/` and return simple results through `rust/src/api/`.

### Key Security Model

`zcash_client_sqlite` intentionally does NOT store spending keys in the DB — only viewing keys (UFVK). The mnemonic/seed lives in Flutter's `flutter_secure_storage` (iOS Keychain / Android Keystore) and is passed to Rust only when needed for transaction signing.

### WalletDb Initialization

`WalletDb::for_path()` requires 4 params: `(path, Network, SystemClock, OsRng)`. `init_wallet_db()` must be called before `create_account()` — it runs schema migrations.

## Testing

- Rust unit tests: `cd rust && cargo test` (7 tests: key derivation, address encoding, determinism)
- Dart unit tests: `fvm flutter test`
- Integration tests: `fvm flutter test integration_test/` (requires device/simulator)

## Crate Versions

Pinned in `rust/Cargo.toml`. Key crates: `zcash_client_backend` 0.21.2, `zcash_client_sqlite` 0.19.5, `orchard` 0.12.0, `sapling-crypto` 0.6.1. These must stay compatible — check librustzcash releases before bumping.
