#!/usr/bin/env bash
# Launch Verdi after a successful VCS smoke run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERDI_BIN="${VERDI_BIN:-verdi}"
BUILD_DIR="${ROOT}/build/smoke"

command -v "${VERDI_BIN}" >/dev/null 2>&1 || {
  echo "ERROR: Verdi not found. Set VERDI_BIN to the verdi executable path." >&2
  exit 127
}

test -f "${BUILD_DIR}/smoke.vcd" || {
  echo "ERROR: no smoke.vcd waveform. Run scripts/run_smoke_vcs.sh first." >&2
  exit 1
}

cd "${ROOT}"
"${VERDI_BIN}" -sv -f scripts/smoke.f -top tb_top_smoke -vcd "${BUILD_DIR}/smoke.vcd" &
