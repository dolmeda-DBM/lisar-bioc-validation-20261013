"""GPL-3.0-or-later. Runner-only guards, native checks and evidence preservation.

No retry, test rewriting, network provisioning, or interpretation of missing
counts as zero. This module has no effect until explicitly run in the guarded
ephemeral GitHub runner.
"""
from pathlib import Path, PurePosixPath
import csv
import datetime
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import time

REPOSITORY = "dolmeda-DBM/lisar-bioc-validation-20261013"
STAGES = ("ordinary-default", "longtests-default",
          "ordinary-backend-only", "longtests-backend-only")


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def record(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def inputs():
    config = json.loads(Path("ci/config.json").read_text())
    manifest = json.loads(Path("candidate/manifest.json").read_text())
    assert config["repository"] == REPOSITORY
    assert type(config["allow_shiny_backend"]) is bool
    assert type(config["backend_supplement_when_shiny_excluded"]) is bool
    assert config["execution_priority"] == "low" and config["workers"] == 2
    assert manifest["R_version"] == "4.6.1"
    assert manifest["Bioconductor_version"] == "3.24"
    assert manifest["testthat_version"] == "3.3.2"
    tarpath = Path(manifest["tarball"]).resolve(strict=True)
    assert tarpath == (Path.cwd() / "candidate/lisaR_0.99.0.tar.gz").resolve(strict=True)
    assert sha(tarpath) == manifest["tarball_sha256"]
    return config, manifest, tarpath


def guard():
    assert os.environ.get("GITHUB_ACTIONS") == "true", "Runner only"
    assert os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted", "Standard GitHub-hosted only"
    assert os.environ.get("LISAR_REPOSITORY_PRIVATE") == "false", "Public/free only"
    assert os.environ.get("GITHUB_REPOSITORY") == REPOSITORY, "Wrong repository"
    assert os.environ.get("GITHUB_RUN_ATTEMPT") == "1", "No same-run replay"
    assert platform.system() == "Darwin", "Native macOS only"
    actual_arch = platform.machine()
    assert actual_arch == os.environ["LISAR_EXPECTED_ARCH"], (actual_arch, os.environ["LISAR_EXPECTED_ARCH"])
    return inputs()


def owned_root():
    root = Path(os.environ["LISAR_VALIDATION_ROOT"]).resolve(strict=True)
    temporary = Path(os.environ["RUNNER_TEMP"]).resolve(strict=True)
    assert root.parent == temporary and root.name.startswith("lisar-validation-")
    assert not root.is_symlink()
    return root


def initialize():
    config, manifest, tarpath = guard()
    expected = os.environ["EXPECTED_HEAD_SHA"]
    assert re.fullmatch("[0-9a-f]{40}", expected), "Exact commit SHA required"
    assert os.environ["GITHUB_SHA"] == expected
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    assert head == expected, "Checkout drift"
    root = Path(os.environ["RUNNER_TEMP"]).resolve(strict=True) / (
        "lisar-validation-" + os.environ["GITHUB_RUN_ID"] + "-" +
        os.environ["GITHUB_RUN_ATTEMPT"] + "-" + os.environ["LISAR_EXPECTED_ARCH"])
    assert not root.exists(), "Preserve previous attempt; no overwrite"
    root.mkdir()
    supplemental = (not config["allow_shiny_backend"] and
                    config["backend_supplement_when_shiny_excluded"])
    with Path(os.environ["GITHUB_ENV"]).open("a") as f:
        f.write("LISAR_VALIDATION_ROOT=" + str(root) + "\n")
        f.write("LISAR_BACKEND_SUPPLEMENT=" + ("true" if supplemental else "false") + "\n")
    record(root / "run-intent.json", {
        "status": "PREPARING_NOT_PACKAGE_PASS", "at": stamp(),
        "repository": REPOSITORY, "head_sha": head,
        "run_id": os.environ["GITHUB_RUN_ID"], "run_attempt": 1,
        "execution_priority": "low", "system": platform.platform(),
        "architecture": platform.machine(), "runner_name": os.environ.get("RUNNER_NAME"),
        "runner_os": os.environ.get("RUNNER_OS"), "candidate_sha256": sha(tarpath),
        "config": config, "scientific_oracles": manifest["scientific_oracles"],
        "R_version": manifest["R_version"], "Bioconductor_version": manifest["Bioconductor_version"],
        "testthat_version": manifest["testthat_version"],
        "workflow_source": "manual exact-commit dispatch; no private/larger-runner fallback"
    })
    observed = []
    destination = root / "input"
    destination.mkdir()
    seen = set()
    with tarfile.open(tarpath) as archive:
        for member in archive.getmembers():
            p = PurePosixPath(member.name)
            assert not p.is_absolute() and ".." not in p.parts and p.parts[0] == "lisaR"
            assert member.isfile() or member.isdir(), "Nonregular archive entry"
            assert str(p) not in seen, "Duplicate archive entry"
            seen.add(str(p))
            target = destination.joinpath(*p.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                data = archive.extractfile(member).read()
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                observed.append({"path": "/".join(p.parts[1:]), "bytes": len(data),
                                 "sha256": hashlib.sha256(data).hexdigest()})
    assert sorted(observed, key=lambda x: x["path"]) == manifest["archive_files"]
    fixture = destination / "lisaR" / manifest["scientific_oracles"]["fixture_path"]
    assert sha(fixture) == manifest["scientific_oracles"]["category_inference_sha256"]
    record(root / "archive-verification.json", {
        "status": "EXACT_ARCHIVE_HASHES_VERIFIED_NOT_RUNTIME_PASS",
        "candidate_sha256": sha(tarpath), "archive_file_count": len(observed),
        "archive_files": sorted(observed, key=lambda x: x["path"]),
        "input_is_unchanged": True, "extracted_only_for_dependency_inspection": True
    })


def native_summary(checkdir):
    log = checkdir / "00check.log"
    if not log.exists():
        return {"status": "NO_CHECK_LOG_COUNTS_UNKNOWN", "errors": None,
                "warnings": None, "notes": None}
    lines = log.read_text(errors="replace").splitlines()
    summaries = [x for x in lines if x.startswith("Status:")]
    if not summaries:
        return {"status": "NO_TERMINAL_SUMMARY_COUNTS_UNKNOWN", "errors": None,
                "warnings": None, "notes": None}
    last = summaries[-1]
    counts = {"errors": 0, "warnings": 0, "notes": 0}
    keys = {"ERROR": "errors", "WARNING": "warnings", "NOTE": "notes"}
    for value, kind in re.findall(r"(\d+)\s+(ERROR|WARNING|NOTE)", last):
        counts[keys[kind]] = int(value)
    if last.strip() != "Status: OK" and not re.search(r"\d+\s+(ERROR|WARNING|NOTE)", last):
        return {"status": "UNRECOGNIZED_TERMINAL_SUMMARY_COUNTS_UNKNOWN",
                "native_summary": last, "errors": None, "warnings": None, "notes": None}
    return {"status": "NATIVE_TERMINAL_SUMMARY_NOT_GLOBAL_PASS", "native_summary": last, **counts}


def test_evidence(stagepath, checkdir):
    files = sorted((stagepath / "test-evidence").glob("test-*.R.tsv"))
    if files:
        totals = {key: 0 for key in ("passed", "failed", "errors", "warnings", "skipped")}
        for path in files:
            with path.open(newline="") as f:
                for row in csv.DictReader(f, delimiter="\t"):
                    totals["passed"] += int(float(row["passed"]))
                    totals["failed"] += int(float(row["failed"]))
                    totals["warnings"] += int(float(row["warning"]))
                    totals["skipped"] += int(float(row["skipped"]))
                    totals["errors"] += int(row["error"].upper() == "TRUE")
        return {"status": "NATIVE_LONGTEST_TSV_TOTALS_NOT_GLOBAL_PASS",
                "files": [str(x.relative_to(stagepath)) for x in files], **totals}
    lines = []
    for path in sorted((checkdir / "tests").glob("*.Rout*")):
        lines.extend(path.read_text(errors="replace").splitlines())
    lines = [re.sub(r"\x1b\[[0-9;]*m", "", x) for x in lines]
    found = [x for x in lines if re.search(
        r"FAIL\s+\d+.*WARN\s+\d+.*SKIP\s+\d+.*PASS\s+\d+", x)]
    if found:
        last = found[-1]
        return {"status": "NATIVE_ROUT_SUMMARY_NOT_GLOBAL_PASS", "native_summary": last,
                **{out: int(re.search(key + r"\s+(\d+)", last).group(1))
                   for key, out in [("FAIL", "failed"), ("WARN", "warnings"),
                                    ("SKIP", "skipped"), ("PASS", "passed")]}}
    return {"status": "NO_NATIVE_TEST_SUMMARY_COUNTS_UNKNOWN_NOT_ZERO",
            "passed": None, "failed": None, "errors": None, "warnings": None, "skipped": None}


def source_pins(checkdir, manifest, longtests):
    expected = {x["path"]: x for x in manifest["archive_files"]}
    root = checkdir / "tests"
    rows = []
    if root.exists():
        for path in sorted(root.rglob("*.R")):
            if path.is_symlink() or not path.is_file():
                continue
            relative = path.relative_to(root).as_posix()
            archive_name = ("longtests/" if longtests else "tests/") + relative
            reference = expected.get(archive_name)
            rows.append({"check_path": "tests/" + relative, "archive_path": archive_name,
                         "sha256": sha(path),
                         "expected_sha256": reference["sha256"] if reference else None,
                         "matched": sha(path) == reference["sha256"] if reference else None})
    return rows


def snapshot(temporary, destination, seen, errors):
    for owned in sorted(temporary.glob("Rtmp*/lq-std-*")):
        if owned.is_symlink() or not owned.is_dir():
            continue
        for source in sorted(owned.rglob("*")):
            if source.is_symlink() or not source.is_file():
                continue
            relative = source.relative_to(temporary).as_posix()
            try:
                size = source.stat().st_size
                assert size <= 128 * 1024 ** 2
                projected = sum(x["bytes"] for x in seen.values()) - seen.get(relative, {}).get("bytes", 0) + size
                assert len(seen) < 10000 or relative in seen
                assert projected <= 2 * 1024 ** 3
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if relative not in seen or seen[relative]["source_mtime_ns"] != source.stat().st_mtime_ns:
                    shutil.copy2(source, target)
                    seen[relative] = {"bytes": target.stat().st_size, "sha256": sha(target),
                                      "source_mtime_ns": source.stat().st_mtime_ns, "observed_at": stamp()}
            except (FileNotFoundError, PermissionError) as exc:
                if len(errors) < 1000:
                    errors.append({"path": relative, "error": str(exc)})
    record(destination / "snapshot-manifest.json", {
        "status": "OBSERVED_SYNTHETIC_FIXTURE_PARTIAL_COMPLETENESS_REQUIRES_REVIEW",
        "expected_source": "unchanged bundled STANDARD fallback", "files": seen,
        "transient_capture_errors": errors, "max_bytes": 2 * 1024 ** 3,
        "max_files": 10000, "max_file_bytes": 128 * 1024 ** 2
    })


def check(stage):
    config, manifest, tarpath = guard()
    assert stage in STAGES
    backend_only = stage.endswith("backend-only")
    if backend_only:
        assert not config["allow_shiny_backend"]
        assert config["backend_supplement_when_shiny_excluded"]
    root = owned_root()
    stagepath = root / stage
    assert not stagepath.exists(), "No retry/overwrite of check"
    stagepath.mkdir()
    temporary = root / (stage + "-temporary")
    temporary.mkdir()
    longtests = stage.startswith("longtests")
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("_R_CHECK_"):
            env.pop(key)
    for key in ("LISAR_LONGTEST_ROOT", "LISAR_EXPLORE_FIXTURE_RUN",
                "LISAR_REVIEWED_FIXTURE_RUN", "LISAR_LONGTEST_EVIDENCE"):
        env.pop(key, None)
    env.update(TMPDIR=str(temporary), TMP=str(temporary), TEMP=str(temporary),
               NCPUS="2", OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MAKEFLAGS="-j1")
    if backend_only:
        env["_R_CHECK_FORCE_SUGGESTS_"] = "false"
    # Preserve the previous synthetic/offline check scope. Proxies are deterrents,
    # not an OS network sandbox and not a privacy certification.
    env.update(http_proxy="http://127.0.0.1:9", https_proxy="http://127.0.0.1:9",
               HTTP_PROXY="http://127.0.0.1:9", HTTPS_PROXY="http://127.0.0.1:9",
               no_proxy="localhost,127.0.0.1,::1", NO_PROXY="localhost,127.0.0.1,::1")
    if longtests:
        evidence = stagepath / "test-evidence"
        evidence.mkdir()
        env["LISAR_LONGTEST_EVIDENCE"] = str(evidence)
    executable = Path(env["LISAR_R_EXECUTABLE"]).resolve(strict=True)
    argv = [str(executable), "CMD", "check"]
    if longtests:
        argv.append("--test-dir=longtests")
    argv.append(str(tarpath))
    record(stagepath / "intent.json", {
        "status": "NATIVE_CHECK_INTENT", "at": stamp(), "argv": argv, "cwd": str(stagepath),
        "candidate_sha256": sha(tarpath), "backend_only": backend_only,
        "default_check_flags": not backend_only,
        "force_suggests": env.get("_R_CHECK_FORCE_SUGGESTS_", "default"),
        "workers": 2, "fixture_injection": False, "external_fixture": False,
        "allow_shiny_backend": config["allow_shiny_backend"]
    })
    start = time.monotonic()
    snapshots = stagepath / "fallback-snapshots"
    if longtests:
        snapshots.mkdir()
    seen, errors, capture_failure = {}, [], None
    returncode, launch_error = 127, None
    with (stagepath / "stdout.log").open("wb") as stdout, (stagepath / "stderr.log").open("wb") as stderr:
        try:
            child = subprocess.Popen(argv, cwd=stagepath, env=env, stdout=stdout, stderr=stderr)
            while True:
                if longtests and capture_failure is None:
                    try:
                        snapshot(temporary, snapshots, seen, errors)
                    except Exception as exc:
                        capture_failure = str(exc)
                        # Preserve the native worker. Do not terminate it for a collector fault.
                try:
                    returncode = child.wait(timeout=15)
                    break
                except subprocess.TimeoutExpired:
                    pass
            if longtests and capture_failure is None:
                try:
                    snapshot(temporary, snapshots, seen, errors)
                except Exception as exc:
                    capture_failure = str(exc)
        except OSError as exc:
            launch_error = str(exc)
    elapsed = time.monotonic() - start
    checkdir = stagepath / "lisaR.Rcheck"
    pins = source_pins(checkdir, manifest, longtests)
    integrity_failures = [x for x in pins if x["matched"] is False]
    wrapper_code = returncode if returncode != 0 else (1 if launch_error or capture_failure or integrity_failures else 0)
    result = {
        "status": "NATIVE_CHECK_COMPLETED_NOT_GLOBAL_PASS" if returncode == 0 else "NATIVE_CHECK_FAILED",
        "stage": stage, "R_returncode": returncode, "wrapper_returncode": wrapper_code,
        "ended_at": stamp(), "elapsed_seconds": elapsed, "launch_error": launch_error,
        "capture_failure": capture_failure, "candidate_sha256": sha(tarpath),
        "native_check_summary": native_summary(checkdir),
        "native_test_summary": test_evidence(stagepath, checkdir),
        "test_source_pins": pins, "integrity_failures": integrity_failures,
        "backend_only": backend_only, "full_check_pass_claimed": False,
        "scientific_oracles": manifest["scientific_oracles"]
    }
    record(stagepath / "result.json", result)
    print(json.dumps(result, indent=2))
    raise SystemExit(wrapper_code)


def collect():
    config, manifest, tarpath = guard()
    root = owned_root()
    destination = root / "evidence"
    assert not destination.exists(), "No repeat evidence collection"
    destination.mkdir()
    files, links = [], []
    for item in sorted(root.iterdir()):
        if item.name == "evidence":
            continue
        if item.is_symlink():
            links.append(item.name)
            continue
        if item.is_dir() and item.name not in STAGES:
            continue
        if item.is_file() and item.suffix not in (".json", ".log", ".txt", ".tsv", ".rds"):
            continue
        paths = sorted(item.rglob("*")) if item.is_dir() else [item]
        for source in paths:
            if source.is_symlink():
                links.append(source.relative_to(root).as_posix())
                continue
            if not source.is_file():
                continue
            target = destination / source.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            files.append({"path": target.relative_to(destination).as_posix(),
                          "bytes": target.stat().st_size, "sha256": sha(target)})
    record(destination / "evidence-manifest.json", {
        "status": "PRESERVATION_ONLY_NOT_GLOBAL_PASS", "collected_at": stamp(),
        "repository": REPOSITORY, "head_sha": os.environ["GITHUB_SHA"],
        "run_id": os.environ["GITHUB_RUN_ID"], "run_attempt": 1,
        "candidate_sha256": sha(tarpath), "config": config, "files": files,
        "symlinks_not_followed": links,
        "excluded": "installed library, extracted input, package installers and raw temporary roots"
    })
    summaries = []
    for stage in STAGES:
        path = root / stage / "result.json"
        summaries.append(json.loads(path.read_text()) if path.exists()
                         else {"stage": stage, "status": "NOT_RUN_OR_RESULT_MISSING",
                               "R_returncode": None, "counts": None})
    record(destination / "results.json", {
        "status": "DIAGNOSTICS_NOT_GLOBAL_ACCEPTANCE", "candidate_sha256": sha(tarpath),
        "config": config, "stages": summaries,
        "scope": "macOS candidate package only; no Linux/Windows/BiocCheck/UI acceptance"
    })
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as f:
            f.write("## Native macOS diagnostics\n\n")
            f.write("| Stage | Native R return code | Check summary |\n|---|---|---|\n")
            for result in summaries:
                summary = result.get("native_check_summary", {}).get("native_summary", "not observed")
                f.write(f"| {result['stage']} | {result.get('R_returncode')} | {summary} |\n")
            f.write("\nBackend-only supplements are not full/default check PASS. "
                    "Missing counts are unknown, not zero. Download evidence before repository removal.\n")


if __name__ == "__main__":
    command = sys.argv[1]
    if command == "initialize":
        initialize()
    elif command == "check":
        check(sys.argv[2])
    elif command == "collect":
        collect()
    else:
        raise SystemExit("Unknown command")
