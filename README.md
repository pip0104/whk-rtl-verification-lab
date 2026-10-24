# RTL Verification Portfolio

Two educational RTL projects with executable verification: an APB3 SPI master and an AXI4-to-AHB-Lite bridge. The focus of the 2026-10-24 work is reproducible bug discovery, correction, regression and scoped formal verification.

Repository: [pip0104/rtl-verification-portfolio](https://github.com/pip0104/rtl-verification-portfolio). See [GitHub Actions](https://github.com/pip0104/rtl-verification-portfolio/actions) for actual hosted verification results.

## Start here

- [Current evidence and interview wording](docs/面试证据与口径.md)
- [SPI divider defect and directed regression](APB3_SPI_Master_Controller/docs/20261024_spi_fix.md)
- [SPI formal scope, assumptions and results](APB3_SPI_Master_Controller/docs/20261024_formal.md)
- [Bridge phase, boundary and regression corrections](AXI4_AHB5_Lite_Bridge/docs/20261024_bridge_fix.md)
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

GitHub Actions uses the same entrypoint. The workflow is prepared locally; a green GitHub badge requires a real hosted run and is not claimed by a local run.

## Evidence boundaries

- `23/23` (SPI) and `36/36` (legacy bridge) refer to defined transaction-level functional bins, not code coverage or complete input spaces. New coverage points are reported separately or explicitly versioned.
- SPI formal claims cover only the named properties/configurations and listed assumptions. A bounded counterexample search, a successful unbounded proof and a reachable cover are different results.
- SPI UVM sources are an incomplete migration scaffold; these projects are not claimed to have completed UVM regressions.
- This repository does not claim CPU core validation, ISS differential checking, FPGA board operation, chip signoff or contributions merged into an upstream CPU project.
- Inherited documents, coverage percentages and implementation/timing estimates predate this change. They are historical background, not fresh evidence. Start with the dated reports above and current run summaries.
- The bridge's current AHB mapping and supported restrictions are defined in its updated specification. Do not infer full AXI/AHB feature compliance from the project title.

## Repository contents

Generated executables, virtual environments, full build directories, large waveforms and local result directories are ignored. Selected compact evidence is retained under `evidence/`; regenerate full reports using the commands above. Original project directories and supplied ZIPs were preserved outside this independent repository.

This public repository starts from the verified source snapshot. Baseline commit identifiers in frozen evidence refer to the preserved local development history. The baseline RTL is included as a file, so reproducing its failure does not require those local commits. Commits here use a GitHub noreply address.
