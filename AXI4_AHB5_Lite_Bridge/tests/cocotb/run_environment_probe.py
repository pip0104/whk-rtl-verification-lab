"""Launch the cocotb/Icarus integration probe without requiring GNU make."""

from pathlib import Path
import xml.etree.ElementTree as ET

from cocotb_tools.runner import get_runner


PROJECT_ROOT = Path(__file__).resolve().parents[2]
TEST_DIR = Path(__file__).resolve().parent
BUILD_DIR = PROJECT_ROOT / "build" / "cocotb_environment_probe"
RESULTS_XML = PROJECT_ROOT / "results" / "environment_probe.xml"
RESULTS_XML.parent.mkdir(parents=True, exist_ok=True)
RESULTS_XML.unlink(missing_ok=True)

runner = get_runner("icarus")
runner.build(
    sources=[PROJECT_ROOT / "tb" / "tb_cocotb_probe.sv"],
    hdl_toplevel="tb_cocotb_probe",
    build_dir=BUILD_DIR,
    clean=True,
    timescale=("1ns", "1ps"),
)
runner.test(
    hdl_toplevel="tb_cocotb_probe",
    test_module="test_environment_probe",
    test_dir=TEST_DIR,
    build_dir=BUILD_DIR,
    results_xml=str(RESULTS_XML),
)
cases = ET.parse(RESULTS_XML).getroot().findall(".//testcase")
if len(cases) != 1 or any(case.find("failure") is not None or case.find("error") is not None for case in cases):
    raise SystemExit("Environment probe failed")
