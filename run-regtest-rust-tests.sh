#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT_DIR/.regtest"
LOG_FILE="$LOG_DIR/regtest-rust-tests.log"
AUTO_DOWN=0

usage() {
  cat <<'EOF'
Usage: ./run-regtest-rust-tests.sh [--down]

Starts the local zcashd/lightwalletd regtest stack, runs the Rust regtest
integration tests, streams the full output to the terminal, and saves a copy to:

  .regtest/regtest-rust-tests.log

Options:
  --down    Stop the regtest docker compose stack after the test run finishes.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --down)
      AUTO_DOWN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$LOG_DIR"

cleanup() {
  if [[ "$AUTO_DOWN" -eq 1 ]]; then
    "$ROOT_DIR/scripts/regtest/down.sh"
  fi
}
trap cleanup EXIT

echo "==> Starting regtest services"
"$ROOT_DIR/scripts/regtest/up.sh"

echo "==> Running Rust regtest integration tests"
echo "==> Log file: $LOG_FILE"

(
  cd "$ROOT_DIR/rust"
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
