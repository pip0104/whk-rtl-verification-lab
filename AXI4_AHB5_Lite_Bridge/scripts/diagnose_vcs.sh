#!/usr/bin/env bash
# Read-only VCS installation diagnosis.  It never prints license values.
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${PROJECT_ROOT}/results"
OUT_FILE="${OUT_DIR}/vcs_diagnose.txt"
mkdir -p "${OUT_DIR}"

report() {
  if [ "$#" -eq 0 ]; then
    # Do not invoke bare tee here: it would wait forever for terminal input.
    printf '\n' | tee -a "${OUT_FILE}"
  else
    printf '%s\n' "$*" | tee -a "${OUT_FILE}"
  fi
}

: > "${OUT_FILE}"
report "VCS installation diagnosis"
report "$(date -Is)"
report
report "VCS_HOME=${VCS_HOME:-UNSET}"
report "SNPSLMD_LICENSE_FILE=$([ -n "${SNPSLMD_LICENSE_FILE:-}" ] && printf SET || printf UNSET)"
report

VCS_CMD="$(command -v vcs 2>/dev/null || true)"
if [ -n "${VCS_CMD}" ]; then
  report "PATH vcs=${VCS_CMD}"
  report "resolved vcs=$(readlink -f "${VCS_CMD}" 2>/dev/null || printf '%s' "${VCS_CMD}")"
  report "vcs command file type:"
  file "${VCS_CMD}" 2>&1 | tee -a "${OUT_FILE}"
else
  report "PATH vcs=NOT_FOUND"
fi
report

if [ -n "${VCS_HOME:-}" ]; then
  report "VCS_HOME directory status:"
  ls -ld "${VCS_HOME}" "${VCS_HOME}/bin" 2>&1 | tee -a "${OUT_FILE}"
  report
  report "VCS executables below VCS_HOME (depth <= 5):"
  find "${VCS_HOME}" -maxdepth 5 -type f \( -name vcs -o -name vcs1 -o -name vcs2 \) -printf '%p\n' 2>/dev/null | sort | tee -a "${OUT_FILE}"
else
  report "VCS_HOME is unset, so its installation tree cannot be inspected."
fi
report

if [ -d /home/synopsys/vcs ]; then
  report "Candidate VCS launchers below /home/synopsys/vcs (depth <= 5):"
  find /home/synopsys/vcs -maxdepth 5 -type f \( -name vcs -o -name vcs1 -o -name vcs2 \) -printf '%p\n' 2>/dev/null | sort | tee -a "${OUT_FILE}"
else
  report "/home/synopsys/vcs does not exist or is not readable."
fi

report
report "Report saved to ${OUT_FILE}"
