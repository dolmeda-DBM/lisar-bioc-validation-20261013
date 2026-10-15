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
import hashlib
import cross_check
from pathlib import Path
import runner as native

WORKFLOW = ".github/workflows/cross-platform-validation.yml"
PLATFORMS = {"Linux": ("Linux", "x86_64", "linux-x86_64"),
             "Windows": ("Windows", "AMD64", "windows-x86_64")}
APPROVED_MACOS_HEAD = "b2e149cbc3a3e4937caa8c562b98f38adb1a142b"
CI_CHANGED = {WORKFLOW, "ci/cross_runner.py"}
CI_ADDED = {"ci/cross_check.py", "ci/tex-preflight.R", "ci/provision-internal.R"}
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
    assert run.get("head_sha") == APPROVED_MACOS_HEAD
    proof = unchanged_macos_tree()
    assert run.get("event") == "workflow_dispatch" and run.get("path") == ".github/workflows/macos-validation.yml"
    assert run.get("status") == "completed" and run.get("conclusion") == "success"
    return {"run_id": int(run_id), "parent_review_sha256": review,
            "head_sha": APPROVED_MACOS_HEAD, "source_tree_proof": proof}


def unchanged_macos_tree():
    """Mac passed an older commit; prove all non-cross-CI blobs are identical."""
    request = urllib.request.Request(
        "https://api.github.com/repos/" + native.REPOSITORY + "/git/trees/" + APPROVED_MACOS_HEAD + "?recursive=1",
        headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"],
                 "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        tree = json.load(response)
    assert tree.get("truncated") is False
    assert all(x["type"] in ("tree", "blob") for x in tree["tree"])
    baseline = {x["path"]: (x["mode"], x["sha"]) for x in tree["tree"] if x["type"] == "blob"}
    tracked = subprocess.check_output(["git", "ls-files", "-s", "-z"]).decode().split("\0")
    current = {}
    for line in filter(None, tracked):
        prefix, name = line.split("\t", 1)
        mode, blob, index_stage = prefix.split()
        assert index_stage == "0" and mode in ("100644", "100755")
        path = Path(name)
        assert path.is_file() and not path.is_symlink()
        data = path.read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        assert actual == blob, "Dirty checkout: " + name
        current[name] = (mode, blob)
    assert set(current) == set(baseline) | CI_ADDED, "Unexpected new or removed files"
    assert CI_CHANGED <= set(baseline)
    protected = set(baseline) - CI_CHANGED
    assert all(current[name] == baseline[name] for name in protected), "Non-cross-CI source drift"
    return {"status": "EXACT_PROTECTED_GIT_BLOBS_MATCH_MACOS", "macos_head_sha": APPROVED_MACOS_HEAD,
            "protected_blobs": {name: baseline[name][1] for name in sorted(protected)},
            "allowed_changed_paths": sorted(CI_CHANGED), "allowed_added_paths": sorted(CI_ADDED)}


def short_root():
    # New standard hosted VM only. Never reclaim, delete or reuse this path.
    return Path(Path(os.environ["RUNNER_TEMP"]).anchor) / "l" if os.environ["RUNNER_OS"] == "Windows" else Path("/tmp/l")


def owned_root():
    declared = Path(os.environ["LISAR_VALIDATION_ROOT"])
    root = short_root()
    assert declared == root and root.is_dir() and not root.is_symlink()
    assert root.resolve(strict=True) == root
    receipt = json.loads((root / "run-intent.json").read_text())
    assert receipt["repository"] == native.REPOSITORY
    assert receipt["run_id"] == os.environ["GITHUB_RUN_ID"]
    assert receipt["head_sha"] == os.environ["EXPECTED_HEAD_SHA"]
    assert receipt["candidate_sha256"] == os.environ["EXPECTED_CANDIDATE_SHA256"]
    return root


def initialize():
    guard()
    reference = macos_reference()
    destination = short_root()
    assert not destination.exists() and not destination.is_symlink(), "Owned short root already exists; do not overwrite"
    native.initialize()
    # initialize writes GITHUB_ENV for the NEXT step, not os.environ in this
    # process. Set only this process's owned path before adding provenance.
    root = Path(os.environ["RUNNER_TEMP"]).resolve(strict=True) / (
        "lisar-validation-" + os.environ["GITHUB_RUN_ID"] + "-" +
        os.environ["GITHUB_RUN_ATTEMPT"] + "-" + os.environ["LISAR_EXPECTED_ARCH"])
    # The Linux runner workspace and /tmp can be on different filesystems.
    # Copy into an absent owned destination; preserve the original extraction.
    shutil.copytree(root, destination)
    root = destination
    os.environ["LISAR_VALIDATION_ROOT"] = str(root)
    temporary = root / "p"
    temporary.mkdir()
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
        for key, value in {"LISAR_VALIDATION_ROOT": root, "TMPDIR": temporary, "TMP": temporary, "TEMP": temporary}.items():
            output.write(key + "=" + str(value) + "\n")
    root = owned_root()
    data = json.loads((root / "run-intent.json").read_text(encoding="utf-8"))
    data.update(workflow_path=WORKFLOW, macos_reference=reference,
                platform_key=os.environ["LISAR_RUNTIME_PLATFORM"],
                dependency_recipe="ordinary unmodified CRAN/Bioconductor provision",
                provision_source_sha256=native.sha("ci/provision-internal.R"),
                portable_preflight_sha256=native.sha("ci/portable-preflight.R"))
    native.record(root / "run-intent.json", data)


def r_driver(command):
    guard()
    root = native.owned_root()
    executable = shutil.which("Rscript")
    assert executable, "No native project Rscript resolved"
    script = {"provision": "ci/provision-internal.R", "portable": "ci/portable-preflight.R", "tex": "ci/tex-preflight.R"}[command]
    # Python opens native Windows paths; Git Bash never redirects through a
    # backslash-form GITHUB_ENV directory. No runtime recipe or source mutation.
    with (root / (command + ".log")).open("xb") as output:
        if command == "provision":
            parsed = subprocess.run([executable, "--vanilla", "-e",
                                     'stopifnot(getRversion() == "4.6.1"); parse(file = "ci/provision-internal.R"); print(R.version.string)'],
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
    cross_check.check(stage)


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
    diagnostics = native.owned_root() / "tex-diagnostics"
    if diagnostics.is_dir() and not diagnostics.is_symlink():
        for source in sorted(diagnostics.rglob("*")):
            assert not source.is_symlink()
            if not source.is_file():
                continue
            assert source.stat().st_size <= 16 * 1024 ** 2
            relative = source.relative_to(native.owned_root())
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            manifest["files"].append({"path": relative.as_posix(), "bytes": source.stat().st_size,
                                      "sha256": native.sha(source)})
    pdf = native.owned_root() / "manual-preflight.pdf"
    if pdf.is_file() and not pdf.is_symlink():
        shutil.copy2(pdf, destination / pdf.name)
        manifest["files"].append({"path": pdf.name, "bytes": pdf.stat().st_size, "sha256": native.sha(pdf)})
    manifest.update(schema="lisar-cross-platform-native-evidence-v1", workflow_path=WORKFLOW,
                    platform_key=os.environ["LISAR_RUNTIME_PLATFORM"],
                    macos_reference=json.loads((destination / "run-intent.json").read_text())["macos_reference"])
    native.record(path, manifest)
    path = destination / "results.json"
    results = json.loads(path.read_text(encoding="utf-8"))
    results["scope"] = "Internal Linux/Windows ordinary/longtests functional portability; no PDF manual or Bioconductor submission gate"
    results["validation_profile"] = "internal-functional-portability-no-manual-v1"
    results["manual_pdf_required"] = False
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
native.owned_root = owned_root
if __name__ == "__main__":
    command = sys.argv[1]
    if command == "initialize": initialize()
    elif command in ("provision", "portable", "tex"): r_driver(command)
    elif command == "outcomes": outcomes()
    elif command == "check": check(sys.argv[2])
    elif command == "collect": collect()
    else: raise SystemExit("Unknown bounded command")
