#!/usr/bin/env bash
# Safe, read-only diagnostic for the IC_EDA Linux guest.
# Run from the shared project directory:
#   bash scripts/check_eda_tools.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/results/eda_tool_report.txt"
mkdir -p "${ROOT}/results"

{
  echo "EDA tool diagnostic"
  date -Is
  echo "kernel: $(uname -srmo)"
  echo

  for variable in SYNOPSYS VCS_HOME VERDI_HOME SNPSLMD_LICENSE_FILE LM_LICENSE_FILE; do
    if [[ -n "${!variable:-}" ]]; then
      echo "${variable}=SET (value intentionally redacted)"
    else
      echo "${variable}=UNSET"
    fi
  done
  echo

  for tool in vcs verdi urg; do
    if command -v "${tool}" >/dev/null 2>&1; then
      echo "${tool}: $(command -v "${tool}")"
      case "${tool}" in
        vcs) vcs -ID 2>&1 | head -n 3 ;;
        verdi) verdi -version 2>&1 | head -n 3 ;;
        urg) urg -version 2>&1 | head -n 3 ;;
      esac
    else
      echo "${tool}: NOT_FOUND_IN_PATH"
    fi
    echo
  done
} | tee "${OUT}"

echo "Report written to ${OUT}"
