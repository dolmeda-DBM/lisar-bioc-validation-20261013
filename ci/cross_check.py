"""Cross-only native driver copy; the sole behavioral change is a short temporary root.
Offline verification compares its body with runner.check after that single substitution.
"""
import os
import subprocess
import time
from pathlib import Path
import json
import runner as native
STAGES = native.STAGES

def check(stage):
    config, manifest, tarpath = native.guard()
    assert stage in STAGES
    backend_only = stage.endswith("backend-only")
    if backend_only:
        assert not config["allow_shiny_backend"]
        assert config["backend_supplement_when_shiny_excluded"]
    root = native.owned_root()
    stagepath = root / stage
    assert not stagepath.exists(), "No retry/overwrite of check"
    stagepath.mkdir()
    long_stage = stage.startswith("longtests")
    temporary = root / ("l" if long_stage else "o")
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
    native.record(stagepath / "intent.json", {
        "status": "NATIVE_CHECK_INTENT", "at": native.stamp(), "argv": argv, "cwd": str(stagepath),
        "candidate_sha256": native.sha(tarpath), "backend_only": backend_only,
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
                        native.snapshot(temporary, snapshots, seen, errors)
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
                    native.snapshot(temporary, snapshots, seen, errors)
                except Exception as exc:
                    capture_failure = str(exc)
        except OSError as exc:
            launch_error = str(exc)
    elapsed = time.monotonic() - start
    ended_at = native.stamp()
    # Preserve the observed native exit before any summary/source decoding.
    # A collector fault must neither erase R's exit nor fabricate a PASS receipt.
    native.record(stagepath / "native-exit.json", {
        "status": "OBSERVED_NATIVE_EXIT_NOT_GLOBAL_PASS", "stage": stage,
        "R_returncode": returncode, "ended_at": ended_at, "elapsed_seconds": elapsed,
        "launch_error": launch_error, "capture_failure": capture_failure,
        "stdout": "stdout.log", "stderr": "stderr.log"
    })
    checkdir = stagepath / "lisaR.Rcheck"
    processing_failures = []
    pins = []
    try:
        pins = native.source_pins(checkdir, manifest, longtests)
    except Exception as exc:
        processing_failures.append({"component": "test_source_pins", "error_type": type(exc).__name__, "error": str(exc)})
    summaries = {}
    for component, decode, keys in (
        ("native_check_summary", lambda: native.native_summary(checkdir), ("errors", "warnings", "notes")),
        ("native_test_summary", lambda: native.test_evidence(stagepath, checkdir, manifest),
         ("passed", "failed", "errors", "warnings", "skipped") if longtests else ("passed", "failed", "warnings", "skipped"))):
        summaries[component] = {"status": "NATIVE_SUMMARY_DECODING_FAILED_COUNTS_UNKNOWN_NOT_ZERO",
                                **{key: None for key in keys}}
        try:
            summaries[component] = decode()
            if any(type(summaries[component].get(key)) is not int or summaries[component][key] < 0 for key in keys):
                raise ValueError("Native summary has unknown/invalid counts")
        except Exception as exc:
            processing_failures.append({"component": component, "error_type": type(exc).__name__, "error": str(exc)})
    integrity_failures = [x for x in pins if x["matched"] is False]
    wrapper_code = returncode if returncode != 0 else (1 if launch_error or capture_failure or integrity_failures or processing_failures else 0)
    result = {
        "status": "NATIVE_CHECK_COMPLETED_NOT_GLOBAL_PASS" if returncode == 0 else "NATIVE_CHECK_FAILED",
        "stage": stage, "R_returncode": returncode, "wrapper_returncode": wrapper_code,
        "ended_at": ended_at, "elapsed_seconds": elapsed, "launch_error": launch_error,
        "capture_failure": capture_failure, "candidate_sha256": native.sha(tarpath),
        **summaries, "evidence_processing_failures": processing_failures,
        "test_source_pins": pins, "integrity_failures": integrity_failures,
        "backend_only": backend_only, "full_check_pass_claimed": False,
        "scientific_oracles": manifest["scientific_oracles"]
    }
    native.record(stagepath / "result.json", result)
    print(json.dumps(result, indent=2))
    raise SystemExit(wrapper_code)
