"""Portable regression entrypoint; reports are accepted only after a fresh run."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timezone
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECTS = {"spi": "WHK_APB3_SPI_Master_Controller", "bridge": "WHK_AXI4_AHB5_Lite_Bridge"}


def check_junit(path: Path) -> dict:
    tree = ET.parse(path).getroot()
    cases = list(tree.iter("testcase"))
    result = {"tests": len(cases), "failures": sum(len(list(c.iter("failure"))) for c in cases),
              "errors": sum(len(list(c.iter("error"))) for c in cases),
              "skipped": sum(c.find("skipped") is not None for c in cases)}
    suite_failed = any(int(s.get("failures", "0")) or int(s.get("errors", "0"))
                       for s in tree.iter() if s.tag in ("testsuite", "testsuites"))
    if not cases or result["skipped"] == result["tests"] or result["failures"] or result["errors"] or suite_failed:
        raise RuntimeError(f"JUnit did not contain a passing executed suite: {path}: {result}")
    return result


def check_coverage(report: dict) -> None:
    required = report.get("required_bins")
    covered = report.get("hit_bins", report.get("covered_required_bins"))
    if not isinstance(required, int) or required <= 0 or covered != required or report.get("missing_required_bins"):
        raise RuntimeError(f"Incomplete or missing required functional coverage: required={required}, covered={covered}")


def run(command: list, cwd: Path, log: Path, marker: str | None = None) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    print(f"RUN {log.stem}", flush=True)
    environment = dict(os.environ, PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    # A complete verification run must not inherit an interactive test filter.
    for name in ("COCOTB_TEST_FILTER", "COCOTB_TESTCASE", "TESTCASE", "BRIDGE_TEST_MODULE"):
        environment.pop(name, None)
    with log.open("w", encoding="utf-8") as output:
        output.write("COMMAND: " + json.dumps([str(c) for c in command], ensure_ascii=False) + "\n")
        output.flush()
        completed = subprocess.run([str(c) for c in command], cwd=cwd, env=environment,
                                   stdout=output, stderr=subprocess.STDOUT, timeout=600)
    text = log.read_text(encoding="utf-8", errors="replace")
    if completed.returncode or (marker is not None and marker not in text):
        print("\n".join(text.splitlines()[-30:]), flush=True)
        raise RuntimeError(f"Command failed ({completed.returncode}); inspect {log}")


def simulate(key: str) -> dict:
    project = ROOT / PROJECTS[key]
    logs = ROOT / "results" / key
    run([sys.executable, "-m", "unittest", "discover", "-s", "tools", "-p", "test_*.py", "-v"],
        project, logs / "reference_model.log")
    build = project / "build" / "portable_smoke"
    build.mkdir(parents=True, exist_ok=True)
    rtl = ([project / "rtl" / "apb3_spi_master.sv"] if key == "spi" else
           [project / "rtl" / "axi4_ahb5_lite_bridge_pkg.sv", project / "rtl" / "axi4_ahb5_lite_bridge.sv"])
    sources = rtl + ([project / "tb" / "ahb5_lite_memory_model.sv"] if key == "bridge" else []) + [project / "tb" / "tb_top_smoke.sv"]
    run(["iverilog", "-g2012", "-Wall", "-s", "tb_top_smoke", "-o", build / "smoke.vvp", *sources],
        build, logs / "smoke_compile.log")
    run(["vvp", build / "smoke.vvp"], build, logs / "smoke_simulate.log", "SMOKE_TEST_PASS")
    if key == "bridge":
        run(["iverilog", "-g2012", "-s", "tb_parameter_sweep", "-o", build / "parameters.vvp",
             *rtl, project / "tb" / "tb_parameter_sweep.sv"], build, logs / "parameter_elaboration_compile.log")
        run(["vvp", build / "parameters.vvp"], build, logs / "parameter_elaboration.log", "PARAMETER_SWEEP_PASS")
    xml = project / "results" / f"{key}_regression.xml"
    coverage = project / "results" / "functional_coverage.json"
    for path in (xml, coverage):
        path.unlink(missing_ok=True)
    runner = "run_spi_regression.py" if key == "spi" else "run_bridge_regression.py"
    run([sys.executable, project / "tests" / "cocotb" / runner], project, logs / "cocotb.log")
    junit = check_junit(xml)
    cov = json.loads(coverage.read_text(encoding="utf-8"))
    check_coverage(cov)
    result = {"regression": junit, "functional_coverage": cov}
    if key == "spi":
        deep_xml = project / "results" / "deepening" / "green" / "results.xml"
        deep_xml.unlink(missing_ok=True)
        run([sys.executable, project / "tests" / "cocotb" / "run_spi_deepening.py", "--phase", "green"],
            project, logs / "deepening.log")
        result["deepening"] = check_junit(deep_xml)
    result["rtl_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in rtl}
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", choices=["all", *PROJECTS], default="all")
    parser.add_argument("--formal", action="store_true", help="Also run scoped SPI proofs and cover tasks")
    args = parser.parse_args()
    for tool in ("iverilog", "vvp"):
        if not shutil.which(tool):
            parser.error(f"{tool} is not on PATH; activate OSS CAD Suite first")
    report = {"started_utc": datetime.now(timezone.utc).isoformat(), "python": sys.version,
              "projects": {}, "formal_requested": args.formal, "status": "RUNNING"}
    destination = ROOT / "results" / "verification_summary.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2), encoding="utf-8")
    try:
        run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"], ROOT, ROOT / "results" / "evidence_gate.log")
        for key in PROJECTS if args.project == "all" else (args.project,):
            report["projects"][key] = simulate(key)
        if args.formal:
            run([sys.executable, ROOT / PROJECTS["spi"] / "formal" / "run_formal.py"], ROOT, ROOT / "results" / "formal.log")
            index = json.loads((ROOT / PROJECTS["spi"] / "results" / "formal" / "latest.json").read_text(encoding="utf-8"))
            proof = json.loads(Path(index["manifest"]).read_text(encoding="utf-8"))
            if not index.get("passed") or not proof.get("passed"):
                raise RuntimeError("Formal runner did not produce a complete passing manifest")
            report["formal"] = {"manifest": index["manifest"], "tasks": proof["tasks"], "tools": proof["tools"],
                                "sources": proof["sources"], "scope": proof["scope"]}
        report["status"] = "PASS"
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired, ET.ParseError) as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{report['status']}: {destination}")
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
