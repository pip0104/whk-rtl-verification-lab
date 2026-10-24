# Verification Portfolio Implementation Plan

> **For agentic workers:** Execute tasks in this session, with independent SPI, formal, and bridge work and a final fresh review. Steps use checkbox syntax.

**Goal:** Produce reproducible RTL bug fixes, simulation evidence, and scoped SPI formal proofs suitable for a CPU DV application.

**Architecture:** Work in an independent source copy; preserve the original projects. SPI and bridge are independent. Formal checks target the same SPI RTL used in simulation, with verification-only instrumentation excluded from synthesis.

**Tech Stack:** Existing OSS CAD Suite (Yosys/SBY/SMT/Icarus), Python 3.12 and cocotb 2.1, Git.

**Spec:** Existing project specifications plus the user's request to execute the proposed three-day work immediately.

## Global Constraints
- Preserve original directories and ZIPs; modify this independent repository only.
- Observe real failing tests before fixes; retain red/green evidence.
- Do not claim CPU core, UVM, FPGA board, upstream contribution, or full-module formal closure without actual evidence.
- Formal claims name the properties, assumptions, configuration and proof mode.
- Prepare a GitHub-ready repository locally; public hosting needs an actual available authenticated destination.

## Review Focus
- Mid-frame divider writes both above and below the running counter.
- Reset/abort must terminate applicable frame obligations, without masking normal traffic.
- AHB address/data phases and two-cycle ERROR responses.
- Illegal late write beats and AXI boundary requests must match the documented contract.
- Stale/misattributed JUnit and coverage output must not create a false PASS.

### Task 1: SPI divider regression and fix
- [x] Add public-interface tests for mid-frame divider writes, frame widths 1/32 and divider zero.
- [x] Run baseline and preserve expected failing logs/waveforms.
- [x] Latch the active divider at START; run directed tests and original full regression.
- [x] Document actual defect and scope.

### Task 2: Scoped SPI formal verification
- [x] Add formal harness, legal APB assumptions and scoped safety/cover properties.
- [x] Demonstrate a failed property with the baseline divider implementation.
- [x] Prove selected safety properties on fixed RTL; generate non-vacuous cover witnesses.
- [x] Save commands, tool versions, source hash and individual statuses.

### Task 3: Bridge protocol corrections
- [x] Reproduce genuine AHB phase mismatch with a compliant responder.
- [x] Correct address/data phases and responder/error handling; retain original regressions.
- [x] Add boundary/late-illegal-beat tests and fix implementation or precisely document valid behavior.
- [x] Isolate regression XML from environment probe and enforce required functional bins.

### Task 4: Reproduction and delivery
- [x] Provide portable Python entrypoint plus Windows wrapper, separate results and failure gates.
- [x] Add GitHub Actions for supported simulation checks, requirements and ignores.
- [x] Independently run simulation/formal, review changes, fix material findings.
- [x] Commit verified work, produce source/evidence archive and concise Chinese interview evidence sheet.
