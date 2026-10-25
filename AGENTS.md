# Repository maintenance

This repository is the current source of truth for the two WHK RTL projects. Older project copies and the CPU-DV package are historical baselines; compare source and evidence before importing changes.

The owner requested that completed, verified project progress be updated in this same GitHub repository. When a development task is complete and its changes are authorized for publication, include the matching documentation, commit, non-force push and hosted-check verification in that task. Do not configure periodic synchronization or overwrite uncommitted user work.

- Run `python scripts/verify.py --project all --formal` using the documented cocotb and OSS CAD Suite environment before claiming the full suite passes.
- Preserve the distinction between positive tests and the deliberately failing baseline/formal counterexample. Record exact test counts and exit codes.
- SPI 23/23 and bridge 36/36 are defined transaction-level functional bins. Never reinterpret them as complete protocol, code or safety coverage.
- Add dated evidence for changed RTL. Refresh FPGA results if the source hash changes before describing prior timing/resource results as current.
- Board operation, external IO timing, CPU validation and complete UVM regression are not established by existing evidence.
- Keep credentials, private contact information, local environments, large waveforms and proprietary tools out of commits. Use the account's GitHub noreply author identity.
- Fetch the remote first; never force-push or discard remote work. If histories diverge, reconcile without overwriting either side.
- Report the actual hosted workflow result. A successful push alone does not establish CI success.
