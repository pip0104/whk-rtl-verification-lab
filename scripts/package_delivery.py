"""Package the verified worktree bytes, including compact selected evidence."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    summary_path = ROOT / "results/verification_summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if summary.get("status") != "PASS" or not summary.get("formal"):
        raise SystemExit("Run the complete --project all --formal verification first")
    if set(summary["projects"]) != {"spi", "bridge"}:
        raise SystemExit("Both projects must have fresh passing results")
    for project in summary["projects"].values():
        for name, expected in project["rtl_sha256"].items():
            if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != expected:
                raise SystemExit("RTL changed after verification: " + name)
    spi = ROOT / "WHK_APB3_SPI_Master_Controller"
    proof = json.loads(Path(summary["formal"]["manifest"]).read_text(encoding="utf-8"))
    if not proof.get("passed"):
        raise SystemExit("Formal proof manifest did not pass")
    for name, expected in proof["sources"].items():
        if hashlib.sha256((spi / name).read_bytes()).hexdigest() != expected:
            raise SystemExit("Formal source changed after verification: " + name)
    frozen = spi / "formal/evidence/20261024"
    frozen.mkdir(parents=True, exist_ok=True)
    manifest_path = Path(summary["formal"]["manifest"])
    shutil.copy2(manifest_path, frozen / "manifest.json")
    for name in proof["sources"]:
        destination = frozen / "sources" / Path(name).name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(spi / name, destination)
    for task in proof["tasks"]:
        name = task["name"]
        work = manifest_path.parent / name
        destination = frozen / name
        destination.mkdir(parents=True, exist_ok=True)
        for source in (work / "status", work / "logfile.txt", manifest_path.parent / f"{name}.console.log"):
            shutil.copy2(source, destination / source.name)
        for source in (work / "engine_0").glob("*"):
            if source.is_file() and source.suffix in (".txt", ".vcd"):
                filename = "engine_0.logfile.txt" if source.name == "logfile.txt" else source.name
                shutil.copy2(source, destination / filename)
    selected = ROOT / "evidence/final_run"
    selected.mkdir(parents=True, exist_ok=True)
    shutil.copy2(summary_path, selected / "verification_summary.json")
    for source in (ROOT / "results").rglob("*.log"):
        destination = selected / source.relative_to(ROOT / "results")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    for key, name in (("spi", "WHK_APB3_SPI_Master_Controller"), ("bridge", "WHK_AXI4_AHB5_Lite_Bridge")):
        for filename in (f"{key}_regression.xml", "functional_coverage.json"):
            destination = selected / key / filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name / "results" / filename, destination)
    raw = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT)
    paths = sorted({name for name in raw.decode("utf-8").split("\0") if name})
    hashes = {}
    for name in paths:
        path = (ROOT / name).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise SystemExit("Invalid packaging path: " + name)
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    destination = ROOT.parent / f"CPU-DV-Portfolio-verified-{stamp}.zip"
    with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in paths:
            archive.write(ROOT / name, "CPU-DV-Portfolio/" + name)
        archive.writestr("CPU-DV-Portfolio/DELIVERY_SHA256.json", json.dumps(hashes, indent=2, ensure_ascii=False))
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Archive integrity test failed")
        for name, expected in hashes.items():
            if hashlib.sha256(archive.read("CPU-DV-Portfolio/" + name)).hexdigest() != expected:
                raise SystemExit("Archive content mismatch: " + name)
    print(json.dumps({"archive": str(destination), "files": len(paths), "bytes": destination.stat().st_size,
                      "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
