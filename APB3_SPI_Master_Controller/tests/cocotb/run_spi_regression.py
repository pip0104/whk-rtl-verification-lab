"""Build and run the portable APB3 SPI cocotb regression with Icarus."""

from pathlib import Path
import os
import xml.etree.ElementTree as ET

from cocotb_tools.runner import get_runner


PROJECT_ROOT = Path(__file__).resolve().parents[2]
TEST_DIR = Path(__file__).resolve().parent
BUILD_DIR = PROJECT_ROOT / "build" / "cocotb_spi_regression"
JUNIT = PROJECT_ROOT / "results" / "spi_regression.xml"
COVERAGE = PROJECT_ROOT / "results" / "functional_coverage.json"

JUNIT.parent.mkdir(parents=True, exist_ok=True)
for output in (JUNIT, COVERAGE):
    output.unlink(missing_ok=True)
for key in ("COCOTB_TEST_FILTER", "COCOTB_TESTCASE", "TESTCASE"):
    os.environ.pop(key, None)

runner = get_runner("icarus")
runner.build(
    sources=[
        PROJECT_ROOT / "rtl" / "apb3_spi_master.sv",
        PROJECT_ROOT / "tb" / "tb_cocotb_spi.sv",
    ],
    hdl_toplevel="tb_cocotb_spi",
    build_dir=BUILD_DIR,
    clean=True,
    timescale=("1ns", "1ps"),
    always=True,
)
runner.test(
    hdl_toplevel="tb_cocotb_spi",
    test_module="test_apb3_spi",
    test_dir=TEST_DIR,
    build_dir=BUILD_DIR,
    results_xml=str(JUNIT),
)
cases = ET.parse(JUNIT).getroot().findall(".//testcase")
if len(cases) != 1 or any(
    case.find(tag) is not None for case in cases for tag in ("failure", "error", "skipped")
):
    raise SystemExit("SPI regression requires exactly one passing, non-skipped test")
if not COVERAGE.is_file():
    raise SystemExit("SPI regression did not generate fresh functional coverage")
