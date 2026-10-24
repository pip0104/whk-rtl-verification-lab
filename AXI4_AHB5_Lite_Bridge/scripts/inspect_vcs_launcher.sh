#!/usr/bin/env bash
# Extract only the non-sensitive environment setup logic from the vendor VCS
# launcher.  This is read-only and does not execute the launcher.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/results/vcs_launcher_excerpt.txt"

if [[ -z "${VCS_HOME:-}" || ! -r "${VCS_HOME}/bin/vcs" ]]; then
  echo "ERROR: VCS_HOME/bin/vcs is not readable." >&2
  exit 1
fi

{
  echo "VCS launcher environment excerpt"
  echo "source: ${VCS_HOME}/bin/vcs"
  echo
  grep -n -E 'VCS_(HOME|ARCH|PLATFORM)|LD_LIBRARY_PATH|libnz4w|vcs1|uname' \
    "${VCS_HOME}/bin/vcs" || true
} | tee "${OUT}"

echo "Excerpt saved to ${OUT}"
