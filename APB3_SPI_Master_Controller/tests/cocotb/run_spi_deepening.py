"""Run the 24 directed cases with separate fresh XML and waveform evidence."""

import argparse
import os
from pathlib import Path
import xml.etree.ElementTree as ET

from cocotb_tools.runner import get_runner


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=["red", "green"], required=True)
    parser.add_argument("--rtl", type=Path, help="Explicit RTL source (e.g. a baseline copy)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    rtl = args.rtl.resolve() if args.rtl else root / "rtl" / "apb3_spi_master.sv"
    if args.phase == "red" and args.rtl is None:
        parser.error("--phase red requires --rtl pointing to the preserved baseline")
    output = root / "results" / "deepening" / args.phase
    output.mkdir(parents=True, exist_ok=True)
    junit = output / "results.xml"
    junit.unlink(missing_ok=True)
    # External selection must not silently skip directed cases.
    for key in ("COCOTB_TEST_FILTER", "COCOTB_TESTCASE", "TESTCASE"):
        os.environ.pop(key, None)
    os.environ["WAVES"] = "1"
    runner = get_runner("icarus")
    runner.build(
        sources=[rtl,
                 root / "tb" / "tb_cocotb_spi.sv"],
        hdl_toplevel="tb_cocotb_spi", build_dir=root / "build" / "spi_deepening",
        waves=True, clean=True,
        timescale=("1ns", "1ps"), always=True)
    runner.test(
        hdl_toplevel="tb_cocotb_spi", test_module="test_spi_deepening",
        test_dir=output, test_args=[],
        waves=True, plusargs=["+dumpfile_path=deepening.fst"],
        extra_env={"PYTHONPATH": str(Path(__file__).resolve().parent)},
        build_dir=root / "build" / "spi_deepening", results_xml=str(junit))
    cases = ET.parse(junit).getroot().findall(".//testcase")
    failures = sum(case.find("failure") is not None or case.find("error") is not None
                   for case in cases)
    skipped = sum(case.find("skipped") is not None for case in cases)
    print(f"DEEPENING: tests={len(cases)} failures={failures} skipped={skipped}")
    if len(cases) != 24 or failures or skipped:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
