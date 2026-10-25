# WHK RTL Verification Lab

Two educational RTL projects with executable verification: an APB3 SPI master and an AXI4-to-AHB-Lite bridge. The 2026-10-24 work includes reproducible bug discovery, correction, regression, scoped formal verification and device-level FPGA synthesis/place-and-route.

Repository: [pip0104/whk-rtl-verification-lab](https://github.com/pip0104/whk-rtl-verification-lab). See [GitHub Actions](https://github.com/pip0104/whk-rtl-verification-lab/actions) for actual hosted verification results.

[![RTL verification](https://github.com/pip0104/whk-rtl-verification-lab/actions/workflows/verify.yml/badge.svg)](https://github.com/pip0104/whk-rtl-verification-lab/actions/workflows/verify.yml)

## Latest verified status

The latest completed RTL remains the corrected 2026-10-24 baseline. A fresh Windows simulation and scoped-formal run on **2026-10-26 passed**; see the [dated verification report](docs/20261026_verification_status.md) for commands, source hashes and scope. No RTL change was needed for this refresh.

| Project | Fresh local verification on 2026-10-26 | Existing implementation evidence |
|---|---|---|
| APB3 SPI Master | 12 reference-model tests, original cocotb regression, 24 directed/boundary tests; transaction bins 23/23; 4 scoped proof groups / 18 assertions and 3 reachable covers | 2026-10-24 corrected-RTL iCE40 HX8K implementation, 804 LC, internal 50 MHz target passed |
| AXI4 to AHB5-Lite Bridge | 16 reference-model tests, 5 cocotb tests; transaction bins 36/36; smoke and parameter elaboration checks | 2026-10-24 corrected-RTL ECP5 implementation, internal 25 MHz target passed |

The FPGA source hashes still match the current RTL; synthesis/place-and-route was **not** rerun on 2026-10-26. These are device-level implementation reports, with no board operation or external-IO timing closure claim. The 24 new SPI cases include the 8 cases that fail on the old divider implementation; they are not 32 separate cases.

## Start here

- [Current evidence and interview wording](docs/面试证据与口径.md)
- [2026-10-26 full local verification refresh](docs/20261026_verification_status.md)
- [SPI divider defect and directed regression](WHK_APB3_SPI_Master_Controller/docs/20261024_spi_fix.md)
- [SPI formal scope, assumptions and results](WHK_APB3_SPI_Master_Controller/docs/20261024_formal.md)
- [Bridge phase, boundary and regression corrections](WHK_AXI4_AHB5_Lite_Bridge/docs/20261024_bridge_fix.md)
- [Current-RTL FPGA implementation and timing scope](docs/20261024_fpga_implementation.md): iCE40 HX8K at 50 MHz and ECP5-85F at 25 MHz; internal clock targets passed, no board testing.
- [GitHub publication status](docs/GitHub发布说明.md)
- Fresh machine-readable results: `results/verification_summary.json` after a run.

## Reproduce

Requirements: Python 3.12, `cocotb==2.1.0`, Icarus (`iverilog` and `vvp`). Formal checks additionally need OSS CAD Suite's Yosys, SBY and supported SMT engines. The locally tested OSS CAD Suite version is `20260727`; formal reports record individual executable versions.

```sh
python -m pip install -r requirements.txt
python scripts/verify.py --project all
python scripts/verify.py --project all --formal
```

Windows, with the installed toolchain activated by the wrapper:

```powershell
.\run_checks.ps1 -OssCadRoot 'F:\EDA\oss-cad-suite' -Python 'path\to\python.exe' -Formal
```

The entrypoint runs reference-model unit tests, RTL smoke tests, bridge parameter **elaboration** checks, original cocotb regressions and new SPI directed tests. It rejects failed, empty or entirely skipped JUnit suites even if a subprocess returns zero. Each run replaces its expected report files before checking them.

GitHub Actions uses the same entrypoint. The complete simulation and scoped formal workflow passed on Ubuntu 22.04: [verified hosted run](https://github.com/pip0104/whk-rtl-verification-lab/actions/runs/40084460034). Windows local verification is recorded separately in the frozen evidence.

## Evidence boundaries

- `23/23` (SPI) and `36/36` (legacy bridge) refer to defined transaction-level functional bins, not code coverage or complete input spaces. New coverage points are reported separately or explicitly versioned.
- SPI formal claims cover only the named properties/configurations and listed assumptions. A bounded counterexample search, a successful unbounded proof and a reachable cover are different results.
- SPI UVM sources are an incomplete migration scaffold; these projects are not claimed to have completed UVM regressions.
- This repository does not claim CPU core validation, ISS differential checking, FPGA board operation, chip signoff or contributions merged into an upstream CPU project.
- Inherited documents and older coverage/implementation estimates are historical background. The dated FPGA report and `evidence/fpga/20261024/` contain fresh implementation results for the corrected RTL. Neither IP met the attempted 100 MHz target. External IO timing is not constrained and pins are automatically allocated; this is not board-level timing closure.
- The bridge's current AHB mapping and supported restrictions are defined in its updated specification. Do not infer full AXI/AHB feature compliance from the project title.

## Repository contents

Generated executables, virtual environments, full build directories, large waveforms and local result directories are ignored. Selected compact evidence is retained under `evidence/`; regenerate full reports using the commands above. Original project directories and supplied ZIPs were preserved outside this independent repository.

This public repository starts from the verified source snapshot. Baseline commit identifiers in frozen evidence refer to the preserved local development history. The baseline RTL is included as a file, so reproducing its failure does not require those local commits. Commits here use a GitHub noreply address.

## Future updates

Develop and verify changes in this repository, keep older dated evidence intact, then commit and push the completed change to the same remote. Refresh requirement/test links and interview wording when behavior or measured results change. Follow [AGENTS.md](AGENTS.md) for verification and publication rules; no timed or background synchronization is configured.
