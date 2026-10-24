#!/usr/bin/env bash
# Run from any Linux directory. Example:
#   bash scripts/run_smoke_vcs.sh
#
# Prefer the vendor launcher because it orchestrates compilation, elaboration
# and linking.  The direct vcs1 fallback is retained for parser diagnostics
# only; it cannot replace the full launcher on every legacy VCS release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT}/build/smoke"

if [[ -n "${VCS_BIN:-}" ]]; then
  VCS_CMD="${VCS_BIN}"
  VCS_MODE="user-specified"
elif [[ -n "${VCS_HOME:-}" && -x "${VCS_HOME}/bin/vcs" ]]; then
  VCS_CMD="${VCS_HOME}/bin/vcs"
  VCS_MODE="standard-launcher"
elif [[ -n "${VCS_HOME:-}" && -x "${VCS_HOME}/linux64/bin/vcs1" ]]; then
  VCS_CMD="${VCS_HOME}/linux64/bin/vcs1"
  VCS_INSTALL_ROOT="${VCS_HOME}"
  VCS_RUNTIME_HOME="${VCS_HOME}/linux64"
  VCS_MODE="direct-64-bit-compiler"
else
  VCS_CMD="vcs"
  VCS_MODE="standard-launcher"
fi

if [[ "${VCS_CMD}" == */* ]]; then
  [[ -x "${VCS_CMD}" ]] || {
    echo "ERROR: VCS executable is not runnable: ${VCS_CMD}" >&2
    exit 127
  }
else
  command -v "${VCS_CMD}" >/dev/null 2>&1 || {
    echo "ERROR: VCS not found. Set VCS_BIN or VCS_HOME." >&2
    exit 127
  }
fi

mkdir -p "${BUILD_DIR}"
cd "${ROOT}"
echo "INFO: using ${VCS_MODE}: ${VCS_CMD}"

VCS_ARGS=(-sverilog -timescale=1ns/1ps \
  -debug_access+all -kdb -assert svaext -l "${BUILD_DIR}/compile.log" \
  -f scripts/smoke.f -top tb_top_smoke -o "${BUILD_DIR}/simv")

# vcs1 is already the 64-bit executable.  The vendor launcher still needs
# -full64 to choose that executable on installations where it is supported.
if [[ "${VCS_MODE}" != "direct-64-bit-compiler" ]]; then
  VCS_ARGS=(-full64 "${VCS_ARGS[@]}")
fi

if [[ "${VCS_MODE}" == "direct-64-bit-compiler" ]]; then
  # The vendor launcher normally sets this library path before it starts
  # vcs1.  Preserve the top-level VCS_HOME and mirror its Linux-64 setup.
  echo "INFO: VCS runtime library root: ${VCS_RUNTIME_HOME}"
  env VCS_HOME="${VCS_INSTALL_ROOT}" \
    VCS_ARCH="linux64" \
    TOOL_HOME="${VCS_RUNTIME_HOME}" \
    LD_LIBRARY_PATH="${VCS_INSTALL_ROOT}/lib:${VCS_RUNTIME_HOME}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    "${VCS_CMD}" "${VCS_ARGS[@]}"
else
  "${VCS_CMD}" "${VCS_ARGS[@]}"
fi

cd "${BUILD_DIR}"
if [[ ! -x ./simv ]]; then
  echo "ERROR: VCS did not create simv. The direct vcs1 fallback is parser-only on this installation." >&2
  echo "       Run this project with a VCS-supported Linux release and the standard vcs launcher." >&2
  exit 2
fi

./simv -l simulate.log
echo "PASS: smoke logs are in ${BUILD_DIR}"
