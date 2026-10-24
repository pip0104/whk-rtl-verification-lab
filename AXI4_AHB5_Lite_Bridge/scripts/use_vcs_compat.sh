#!/usr/bin/env bash
# Source this file in an interactive shell when the legacy `vcs` launcher
# rejects the Linux kernel but the installed 64-bit compiler is usable:
#   source scripts/use_vcs_compat.sh
# This affects only the current terminal session.

if [[ -z "${VCS_HOME:-}" || ! -x "${VCS_HOME}/linux64/bin/vcs1" ]]; then
  echo "ERROR: expected compiler not found at \${VCS_HOME}/linux64/bin/vcs1" >&2
  return 1 2>/dev/null || exit 1
fi

VCS_COMPAT_ROOT="${VCS_HOME}"

vcs() {
  env VCS_HOME="${VCS_COMPAT_ROOT}" \
    VCS_ARCH="linux64" \
    TOOL_HOME="${VCS_COMPAT_ROOT}/linux64" \
    LD_LIBRARY_PATH="${VCS_COMPAT_ROOT}/lib:${VCS_COMPAT_ROOT}/linux64/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    "${VCS_COMPAT_ROOT}/linux64/bin/vcs1" "$@"
}

echo "INFO: current shell maps vcs -> ${VCS_COMPAT_ROOT}/linux64/bin/vcs1"
