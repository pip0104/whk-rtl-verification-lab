"""Build and run the portable AXI4-to-AHB5-Lite cocotb regression."""

from pathlib import Path
import os
import xml.etree.ElementTree as ET

from cocotb_tools.runner import get_runner


PROJECT_ROOT = Path(__file__).resolve().parents[2]
TEST_DIR = Path(__file__).resolve().parent
BUILD_DIR = PROJECT_ROOT / "build" / "cocotb_bridge_regression"

RESULTS_XML = PROJECT_ROOT / "results" / "bridge_regression.xml"
RESULTS_XML.parent.mkdir(parents=True, exist_ok=True)
RESULTS_XML.unlink(missing_ok=True)
(PROJECT_ROOT / "results" / "functional_coverage.json").unlink(missing_ok=True)
runner = get_runner("icarus")
runner.build(
    sources=[
        PROJECT_ROOT / "rtl" / "axi4_ahb5_lite_bridge_pkg.sv",
        PROJECT_ROOT / "rtl" / "axi4_ahb5_lite_bridge.sv",
        PROJECT_ROOT / "tb" / "tb_cocotb_bridge.sv",
    ],
    hdl_toplevel="tb_cocotb_bridge",
    build_dir=BUILD_DIR,
    clean=True,
    timescale=("1ns", "1ps"),
    always=True,
)
runner.test(
    hdl_toplevel="tb_cocotb_bridge",
    test_module=os.environ.get("BRIDGE_TEST_MODULE", "test_bridge_regression,test_bridge_deepening"),
    test_dir=TEST_DIR,
    build_dir=BUILD_DIR,
    results_xml=str(RESULTS_XML),
)
root = ET.parse(RESULTS_XML).getroot()
cases = root.findall(".//testcase")
if not cases or any(case.find("failure") is not None or case.find("error") is not None or case.find("skipped") is not None for case in cases):
    raise SystemExit("Bridge regression failed; inspect " + str(RESULTS_XML))
if "BRIDGE_TEST_MODULE" not in os.environ:
    required_names = {
        "full_protocol_regression", "separate_address_and_data_phase",
        "late_illegal_write_has_zero_side_effects", "page_boundary_and_two_cycle_error",
        "required_coverage_bins_fail_closed",
    }
    if {case.attrib.get("name") for case in cases} != required_names:
        raise SystemExit("Wrong or incomplete bridge test selection")
