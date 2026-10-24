# SPI scoped formal checks

Run from the repository root with Python 3 and `sby`, `yosys`, `boolector` on PATH:

```text
python WHK_APB3_SPI_Master_Controller/formal/run_formal.py
```

On Windows first dot-source the installed OSS CAD Suite `environment.ps1`, then invoke a real Python executable (the Windows Store `python.exe` alias is insufficient). No private user path is embedded in the runner. Windows SBY receives a relative output path to avoid its bundled Python launcher mishandling non-ASCII absolute command-line paths.

The runner uses only the Python standard library. It runs baseline BMC (expected FAIL), then four fixed-RTL prove tasks and one cover task (expected PASS). A baseline ERROR, missing trace, unrelated failure, UNKNOWN, timeout, missing cover, changed source hash, or unexpected process exit fails the overall gate. Each task is limited to 120 seconds in SBY. Normal completion writes a manifest including tool versions, source SHA256, commands, exit codes and statuses. `results/formal/latest.json` points to the last runner's manifest. Raw output stays in a unique UTC directory; it is never reused as a new result.

Manual commands from this directory:

```text
sby -f baseline.sby
sby -f spi.sby reset config timing rx cover
```

The first manual command MUST fail with `count_bound` and `edge_due` and emit a counterexample. Its nonzero exit is not an infrastructure failure if and only if those expected checks fail. The Python runner enforces this distinction. The second command must pass all tasks. Run the Python runner for the complete evidence gate.

The baseline snapshot `baseline_apb3_spi_master.sv` is intentionally self-contained. It came from initial repository commit `64a7ed6114ef7a479e88319fa7207e1f09b20e0e`, RTL blob `4f2dbb8445870e66cf5626b788174d433d8cc91d`, with only an in-module FORMAL include added. No git command is needed at runtime. Snapshot SHA256: `190e7d7d6ab2f21408a76a6528fe50440385fc045bf5d95584e1ef9b7045a7d6`.

See `../docs/20261024_formal.md` for property names, assumptions, boundaries and recorded results. Frozen compact evidence is in `evidence/20261024/`; raw build models can be regenerated.
