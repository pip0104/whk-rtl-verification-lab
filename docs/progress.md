# Execution record

- 2026-10-24: User requested immediate execution using the installed open-source toolchain. Proceeding with SPI defect/FPV, bridge corrections and a reproducible local GitHub-ready repository.
- Original directories are not Git repositories. Created this independent source copy on branch `develop` with a baseline commit; originals and ZIPs are preserved.
- Parallel ownership: SPI simulation/RTL, SPI formal instrumentation/harness, bridge corrections. Root owns portable entrypoint, evidence gate, CI, delivery and independent verification.
- Evidence gate RED: 4 tests exposed missing failure/empty/skip rejection. GREEN: 4/4 tests passed.
- Root independently ran `python scripts/verify.py --project spi`: reference model, smoke, original cocotb and 24 new directed cases PASS.
- Git Credential Manager's GitHub account listing returned no registered account. Public hosting is not yet confirmed.
- Final independent review: no Critical/Important findings; no blocking minors. Read-only reviewer inspected RTL, models, tests, formal properties and evidence.
- Final unified command: python scripts/verify.py --project all --formal; exit 0, summary PASS (2026-10-24 17:45 Asia/Shanghai).
- Scoped results: SPI 12 model unit tests + 1 original cocotb + 24 new directed; bridge 16 model unit tests + 5 cocotb; smoke and parameter elaboration passed. Transaction-level required bins remain 23/23 and 36/36.
- SPI formal: baseline expected FAIL; reset/config/timing/rx prove PASS (18 assert including auxiliaries); 3 cover goals reached. No full-module liveness/signoff claim.
- Deliberate bridge tradeoff: independent AHB SINGLE/NONSEQ for every AXI beat, retaining AXI address semantics; throughput and AHB burst output are not claimed.
- Hosted GitHub Actions and public repository remain pending authenticated account access. No GitHub success is inferred from local tests.
