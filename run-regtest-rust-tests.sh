#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT_DIR/.regtest"
LOG_FILE="$LOG_DIR/regtest-rust-tests.log"

usage() {
  cat <<'EOF'
Usage: ./run-regtest-rust-tests.sh

Resets the local zcashd/lightwalletd regtest state, starts a fresh regtest stack,
runs the Rust regtest integration tests, streams the full output to the terminal,
and saves a copy to:

  .regtest/regtest-rust-tests.log
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -gt 0 ]]; then
  echo "Unknown argument: $1" >&2
  usage >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

echo "==> Resetting regtest services and state"
"$ROOT_DIR/scripts/regtest/down.sh" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/regtest/reset.sh"

echo "==> Starting fresh regtest services"
"$ROOT_DIR/scripts/regtest/up.sh"

echo "==> Running Rust regtest integration tests"
echo "==> Log file: $LOG_FILE"

(
  cd "$ROOT_DIR/rust"
  if [[ -n "${RUSTFLAGS:-}" ]]; then
    export RUSTFLAGS="$RUSTFLAGS -Awarnings"
  else
    export RUSTFLAGS="-Awarnings"
  fi
  cargo test --test regtest_wallet_flow -- --ignored --nocapture
) 2>&1 | tee "$LOG_FILE"
test_status=${PIPESTATUS[0]}

echo
if [[ "$test_status" -eq 0 ]]; then
  echo "==> Regtest Rust integration tests passed"
else
  echo "==> Regtest Rust integration tests failed (exit $test_status)" >&2
fi
echo "==> Full log saved to $LOG_FILE"

exit "$test_status"
