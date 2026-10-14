"""GPL-3.0-or-later. Hosted Linux/Windows admission adapter only.

Reuse runner.py's native checks and preservation verbatim. No dependency
derivation, mathematical wrapper, scientific fallback, or retry is installed.
"""
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path
import runner as native

WORKFLOW = ".github/workflows/cross-platform-validation.yml"
PLATFORMS = {"Linux": ("Linux", "x86_64", "linux-x86_64"),
             "Windows": ("Windows", "AMD64", "windows-x86_64")}
OUTCOMES = ("PROVISION_OUTCOME", "PORTABLE_OUTCOME", "ORDINARY_OUTCOME", "LONGTESTS_OUTCOME")


def guard():
    assert os.environ.get("GITHUB_ACTIONS") == "true", "Runner only"
    assert os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted", "Standard hosted only"
    assert os.environ.get("LISAR_REPOSITORY_PRIVATE") == "false", "Public/free only"
    assert os.environ.get("GITHUB_REPOSITORY") == native.REPOSITORY, "Wrong repository"
    assert os.environ.get("GITHUB_RUN_ATTEMPT") == "1", "No same-run replay"
    osname = os.environ["RUNNER_OS"]
    assert osname in PLATFORMS, "Native Linux/Windows only"
    expected_system, machine, key = PLATFORMS[osname]
    assert platform.system() == expected_system and platform.machine() == machine, "Wrong native runner"
    assert os.environ["LISAR_EXPECTED_ARCH"] == machine
    assert os.environ["LISAR_RUNTIME_PLATFORM"] == key
    assert os.environ.get("GITHUB_WORKFLOW_REF", "").startswith(native.REPOSITORY + "/" + WORKFLOW + "@")
    assert re.fullmatch(r"[0-9a-f]{40}", os.environ["EXPECTED_HEAD_SHA"])
    assert os.environ["GITHUB_SHA"] == os.environ["EXPECTED_HEAD_SHA"]
    config, manifest, tarball = native.inputs()
    assert config["allow_shiny_backend"] is True
    assert config["backend_supplement_when_shiny_excluded"] is False
    assert manifest["tarball_sha256"] == os.environ["EXPECTED_CANDIDATE_SHA256"]
    return config, manifest, tarball


def macos_reference():
    run_id, review = os.environ["VERIFIED_MACOS_RUN_ID"], os.environ["MACOS_REVIEW_SHA256"]
    assert re.fullmatch(r"[1-9][0-9]*", run_id) and re.fullmatch(r"[0-9a-f]{64}", review)
    request = urllib.request.Request(
        "https://api.github.com/repos/" + native.REPOSITORY + "/actions/runs/" + run_id,
        headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"],
                 "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
    with urllib.request.urlopen(request, timeout=30) as response:
        run = json.load(response)
    assert run.get("id") == int(run_id) and run.get("run_attempt") == 1
    assert run.get("repository", {}).get("full_name") == native.REPOSITORY
    assert run.get("head_sha") == os.environ["EXPECTED_HEAD_SHA"]
    assert run.get("event") == "workflow_dispatch" and run.get("path") == ".github/workflows/macos-validation.yml"
    assert run.get("status") == "completed" and run.get("conclusion") == "success"
    return {"run_id": int(run_id), "parent_review_sha256": review}


def initialize():
    guard()
    reference = macos_reference()
    native.initialize()
    # initialize writes GITHUB_ENV for the NEXT step, not os.environ in this
    # process. Set only this process's owned path before adding provenance.
    root = Path(os.environ["RUNNER_TEMP"]).resolve(strict=True) / (
        "lisar-validation-" + os.environ["GITHUB_RUN_ID"] + "-" +
        os.environ["GITHUB_RUN_ATTEMPT"] + "-" + os.environ["LISAR_EXPECTED_ARCH"])
    os.environ["LISAR_VALIDATION_ROOT"] = str(root)
    root = native.owned_root()
    data = json.loads((root / "run-intent.json").read_text(encoding="utf-8"))
    data.update(workflow_path=WORKFLOW, macos_reference=reference,
                platform_key=os.environ["LISAR_RUNTIME_PLATFORM"],
                dependency_recipe="ordinary unmodified CRAN/Bioconductor provision",
                provision_source_sha256=native.sha("ci/provision-cross.R"),
                portable_preflight_sha256=native.sha("ci/portable-preflight.R"))
    native.record(root / "run-intent.json", data)


def r_driver(command):
    guard()
    root = native.owned_root()
    executable = shutil.which("Rscript")
    assert executable, "No native project Rscript resolved"
    script = "ci/provision-cross.R" if command == "provision" else "ci/portable-preflight.R"
    # Python opens native Windows paths; Git Bash never redirects through a
    # backslash-form GITHUB_ENV directory. No runtime recipe or source mutation.
    with (root / (command + ".log")).open("xb") as output:
        if command == "provision":
            parsed = subprocess.run([executable, "--vanilla", "-e",
                                     'stopifnot(getRversion() == "4.6.1"); parse(file = "ci/provision-cross.R"); print(R.version.string)'],
                                    stdout=output, stderr=subprocess.STDOUT, check=False)
            if parsed.returncode:
                raise SystemExit(parsed.returncode)
        result = subprocess.run([executable, "--vanilla", script],
                                stdout=output, stderr=subprocess.STDOUT, check=False)
    raise SystemExit(result.returncode)


def outcomes():
    guard()
    values = {key: os.environ[key] for key in OUTCOMES}
    assert all(value in ("success", "failure", "cancelled", "skipped") for value in values.values())
    native.record(native.owned_root() / "stage-outcomes.json", values)


def check(stage):
    guard()
    assert stage in ("ordinary-default", "longtests-default")
    native.check(stage)


def collect():
    guard()
    summary_path = os.environ.pop("GITHUB_STEP_SUMMARY", None)
    try:
        native.collect()
    finally:
        if summary_path:
            os.environ["GITHUB_STEP_SUMMARY"] = summary_path
    destination = native.owned_root() / "evidence"
    path = destination / "evidence-manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest.update(schema="lisar-cross-platform-native-evidence-v1", workflow_path=WORKFLOW,
                    platform_key=os.environ["LISAR_RUNTIME_PLATFORM"],
                    macos_reference=json.loads((destination / "run-intent.json").read_text())["macos_reference"])
    native.record(path, manifest)
    path = destination / "results.json"
    results = json.loads(path.read_text(encoding="utf-8"))
    results["scope"] = "Native Linux/Windows full ordinary/longtests regression; no global acceptance"
    native.record(path, results)
    if summary_path:
        with Path(summary_path).open("a", encoding="utf-8") as output:
            output.write("## Native " + os.environ["RUNNER_OS"] + " diagnostics\n\n")
            output.write("| Stage | Native R return code | Check summary |\n|---|---|---|\n")
            for result in results["stages"]:
                summary = result.get("native_check_summary", {}).get("native_summary", "not observed")
                output.write(f"| {result['stage']} | {result.get('R_returncode')} | {summary} |\n")
            output.write("\nPreservation only; native evidence and owner review remain required.\n")


# Admission-only adaptation; native algorithms, production R and mathematics
# are untouched. ci/runner.py remains byte-for-byte the approved Mac driver.
native.guard = guard
if __name__ == "__main__":
    command = sys.argv[1]
    if command == "initialize": initialize()
    elif command in ("provision", "portable"): r_driver(command)
    elif command == "outcomes": outcomes()
    elif command == "check": check(sys.argv[2])
    elif command == "collect": collect()
    else: raise SystemExit("Unknown bounded command")
