"""Bounded, native ephemeral GitHub diagnosis. NEVER full package acceptance."""
import collections
import difflib
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

from runner import guard, owned_root, record, sha
from probe3_native import (source_archive, inventory, finalize_derivative, header_guard, run)
from probe6_patch import derive


def context(require_r=True):
    guard()
    assert os.environ["GITHUB_SHA"] == os.environ["EXPECTED_HEAD_SHA"]
    config = json.loads(Path("ci/probe6-config.json").read_text())
    assert config["execution_priority"] == "low"
    root = owned_root()
    return root, config, Path(os.environ["LISAR_R_EXECUTABLE"]) if require_r else None


def preflight():
    root, config, _ = context(False)
    output = root / "probe6"
    output.mkdir()  # no overwrites or reruns
    names = [str(p.relative_to(Path("ci"))) for p in Path("ci").rglob("*") if p.is_file()]
    assert len(names) == len(set(n.casefold() for n in names)), "Case-folded ci file collision"
    for p in Path("ci").rglob("*"):
        assert not p.is_symlink()
    precision = Path("ci/probe3_precision.hpp").read_text()
    assert precision.index("#include <memory>") < precision.index("#include <boost/")
    assert Path("ci/probe6_trace.hpp").read_text().index("#include <memory>") >= 0
    assert config["fgsea"]["source_tar_sha256"] == "caffc4412072f1d816c48bd26c6546e38d22d3a14f230dfc88f5e10220c63c87"
    record(output / "preflight.json", {"status": "STATIC_PREREQUISITES_ONLY_NOT_NATIVE_NUMERICAL_PASS",
        "casefold_unique_files": len(names), "memory_before_Boost": True,
        "maximum_original48_null_smokes": 4,
        "Intel_untraced_control_condition": "only if traced exact source differs from original Intel binary",
        "no_new_numerical_hypothesis": True})


def prerequisites():
    root, config, r = context()
    output = root / "probe6/header-prerequisites"
    output.mkdir()
    include = Path(os.environ["LISAR_PRIMITIVE_BH_INCLUDE"]).resolve(strict=True)
    header_guard(include, config, output)
    values = {}
    for name in ("CXX20", "CXX20FLAGS", "CPPFLAGS"):
        values[name] = subprocess.check_output([str(r), "CMD", "config", name], text=True).strip()
    record(output / "R-compiler-config.json", values)
    run(shlex.split(values["CXX20"]) + shlex.split(values["CXX20FLAGS"]) +
        ["-I" + str(include), "-Ici", "-fsyntax-only", "ci/probe6_prerequisite.cpp"],
        output, "native-header-syntax-only", 120)


def provider6(mode, directory, env, r):
    run([r.parent / "Rscript", "--vanilla", "ci/probe6_provider.R", mode, directory],
        directory, "fresh-provider", 120, env)
    result = json.loads((directory / "provider-result.json").read_text())
    assert result["failure"] is None and result["effective_binding_identical_to_DelayedArray"] is True
    if mode == "derived": assert result["warnings"] == []
    return result


def namespace():
    root, config, r = context()
    directory = root / "probe6/namespace-rebuild"
    directory.mkdir()
    baseline = directory / "fresh-baseline"
    baseline.mkdir()
    provider6("baseline", baseline, os.environ.copy(), r)
    source = source_archive("SummarizedExperiment", config["SummarizedExperiment"], directory)
    target = source / "NAMESPACE"
    original = target.read_text()
    assert sha(target) == config["SummarizedExperiment"]["original_NAMESPACE_sha256"]
    assert original.count("import(S4Arrays)\n") == 1
    target.write_text(original.replace("import(S4Arrays)\n",
        'import(S4Arrays, except = "makeNindexFromArrayViewport")\n'))
    assert sha(target) == config["SummarizedExperiment"]["derived_NAMESPACE_sha256"]
    shutil.copyfile("ci/probe3-licenses/Artistic-2.0.txt", source / "Artistic-2.0.txt")
    changed = finalize_derivative(source, directory,
        "# Probe6 diagnostic namespace derivative\n\nExact source 1.43.0/ffe9db3; only exclude the earlier S4Arrays import of makeNindexFromArrayViewport, keeping the independently measured DelayedArray provider. No warning suppression or installed-file edit. Original notices retained; this and further modified source distributable under the original Artistic License 2.0 section 4(c). Full licence added; original MD5 independently verified, derived MD5 openly regenerated. Not a package PASS or adoption.\n")
    assert changed == ["Artistic-2.0.txt", "LISAR_PROBE3_DERIVATION.md", "MD5", "NAMESPACE"]
    lib = directory / "library"
    lib.mkdir()
    run([r, "CMD", "INSTALL", "--preclean", "--library=" + str(lib), source],
        directory, "source-install", 450)
    env = os.environ.copy()
    env["R_LIBS"] = str(lib) + ":" + os.environ["R_LIBS"]
    derived = directory / "fresh-derived"
    derived.mkdir()
    result = provider6("derived", derived, env, r)
    header_guard(Path(result["BH_include"]), config, derived)
    lisar_lib = root / "probe6/lisar-library"
    lisar_lib.mkdir()
    run([r, "CMD", "INSTALL", "--library=" + str(lisar_lib), "candidate/lisaR_0.99.0.tar.gz"],
        directory, "lisar-install", 180, env)


def environment(root, fgsea_lib=None):
    env = os.environ.copy()
    libs = [root / "probe6/lisar-library"]
    if fgsea_lib is not None: libs += [fgsea_lib]
    libs += [root / "probe6/namespace-rebuild/library"]
    env["R_LIBS"] = ":".join(str(p) for p in libs) + ":" + os.environ["R_LIBS"]
    assert "LISAR_PROBE_FORCE_WIDE_STRING_CONSTANTS" not in env
    for name in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"):
        env[name] = "http://127.0.0.1:9"
    env.update({"NCPUS": "2", "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1"})
    return env


def smoke(root, r, variant, env):
    output = root / "probe6" / variant
    output.mkdir()
    (output / "trace").mkdir()
    env = dict(env, LISAR_PROBE6_TRACE_DIR=str(output / "trace"))
    run([r.parent / "Rscript", "--vanilla", "ci/probe6_smoke.R", variant, output],
        output, "R-smoke", 600, env)
    result = json.loads((output / "result.json").read_text())
    assert result["failure"] is None and result["family_size"] == 48
    assert result["warnings"] == [] and result["internal_run_gate"] == "PASS"
    calls = sorted((output / "trace").glob("cpp-call-*"))
    assert 0 < len(calls) <= 256
    for call in calls:
        assert (call / "input.rds").is_file() and (call / "return.rds").is_file()
        identity = json.loads((call / "identity.json").read_text())
        assert identity["observer_did_not_draw_R_RNG"] is True
    if variant in ("source-intel-traced", "source-arm-beta-traced"):
        assert all((call / "cpp-trace.tsv").is_file() for call in calls)
        assert list((output / "trace").glob("r-division-before-*"))
        assert list((output / "trace").glob("r-division-after-*"))
    return output


def binary():
    root, _, r = context()
    assert os.environ["LISAR_EXPECTED_ARCH"] == "x86_64"
    smoke(root, r, "binary-intel", environment(root))


def capture_contract():
    root, _, r = context()
    run([r.parent / "Rscript", "--vanilla", "ci/probe6_capture_contract.R"],
        root / "probe6", "native-capture-contract", 60, os.environ.copy())


def compile_proof(source, directory, include):
    dependencies = set()
    used_units = {}
    for name in ("util", "fgseaMultilevel", "fgseaMultilevelSupplement"):
        dep = source / "src" / (name + ".d")
        assert dep.is_file(), "Compiler dependency proof missing: " + str(dep)
        data = dep.read_text().replace("\\\n", " ")
        words = shlex.split(data.split(":", 1)[1])
        paths = []
        for word in words:
            path = Path(word)
            if not path.is_absolute(): path = source / "src" / path
            path = path.resolve(strict=True)
            assert path.is_file() and path.stat().st_size <= 16 * 1024**2
            paths.append(str(path))
            dependencies.add(path)
        used_units[name] = paths
    assert 0 < len(dependencies) <= 8192
    assert include / "boost/math/special_functions/digamma.hpp" in dependencies
    assert include / "boost/math/special_functions/trigamma.hpp" in dependencies
    record(directory / "compile-dependencies.json", {"status": "ACTUAL_NATIVE_NON_SYSTEM_COMPILER_DEPENDENCIES",
        "compile_option": "-MMD: emit dependencies only; default floating point flags unchanged",
        "translation_units": used_units, "files": [{"path": str(p), "bytes": p.stat().st_size,
            "sha256": sha(p)} for p in sorted(dependencies)]})


def build(root, config, r, mode):
    arm = os.environ["LISAR_EXPECTED_ARCH"] == "arm64"
    assert mode in ("traced", "untraced-control")
    assert mode != "untraced-control" or not arm
    directory = root / "probe6" / ("fgsea-" + mode)
    directory.mkdir()
    verified = json.loads((root / "probe6/namespace-rebuild/fresh-derived/provider-result.json").read_text())
    include = Path(verified["BH_include"]).resolve(strict=True)
    header_guard(include, config, directory)
    source = source_archive("fgsea", config["fgsea"], directory)
    originals = {}
    for name, expected in config["fgsea"]["trace_source_sha256"].items():
        assert sha(source / name) == expected
        originals[name] = (source / name).read_text()
    if mode == "traced":
        for name, changed in derive(originals, arm).items():
            (source / name).write_text(changed)
            (directory / (name.replace("/", "-") + ".diff")).write_text("".join(difflib.unified_diff(
                originals[name].splitlines(True), changed.splitlines(True), fromfile="upstream/"+name, tofile="probe6/"+name)))
        shutil.copyfile("ci/probe6_trace.hpp", source / "src/lisar_probe6_trace.hpp")
        if arm:
            shutil.copyfile("ci/probe3_precision.hpp", source / "src/lisar_probe_precision.hpp")
            shutil.copyfile("ci/probe3-licenses/BSL-1.0.txt", source / "BSL-1.0.txt")
        changed = finalize_derivative(source, directory,
            "# Probe6 observation derivative, not a numerical fix\n\nUpstream fgsea 1.39.2/31cb676 exact original MIT source preserved separately. Add exact integer state/binary64 observations around existing inputs, narrowed digamma returns/subtraction, unchanged ordered += steps, original native exp evaluated once, cpp returns, and original R denominator division. Preserve sampleSize101, RNG, fixture, formula order, original default compiler floating-point flags and original licences. ARM alone retains the already tested betaMeanLog-only software64 hypothesis from probe5, with BH constants as-is; no additional arithmetic remedy. Intel retains the original native beta operands. Observer effects are NOT assumed absent: compare full original fixture and every captured cpp input/return against Intel original binary, and conditionally compile an untouched source control if they differ. Original MD5 verified; derivative MD5 explicitly regenerated; retain original notices and full BSL for the reused helper. Diagnostic source only, no adoption/full PASS.\n")
        expected = {"LISAR_PROBE3_DERIVATION.md", "MD5", "R/fgseaMultilevel.R", "src/util.cpp",
            "src/fgseaMultilevel.cpp", "src/fgseaMultilevelSupplement.cpp", "src/lisar_probe6_trace.hpp"}
        if arm: expected |= {"BSL-1.0.txt", "src/lisar_probe_precision.hpp"}
        assert set(changed) == expected
    else:
        record(directory / "unmodified-source-control.json", {"status": "UPSTREAM_SOURCE_UNMODIFIED_CONTROL",
            "files_before_compile": inventory(source)})
    lib = directory / "library"
    lib.mkdir()
    env = environment(root)
    assert not env.get("PKG_CXXFLAGS"), "Unreviewed package compiler overrides"
    env["PKG_CXXFLAGS"] = "-MMD"
    for setting in ("CXX20", "CXX20FLAGS", "CPPFLAGS"):
        (directory / (setting + ".txt")).write_text(subprocess.check_output([str(r), "CMD", "config", setting], text=True))
    run([r, "CMD", "INSTALL", "--preclean", "--library=" + str(lib), source],
        directory, "source-install", 600, env)
    compile_proof(source, directory, include)
    return directory, lib


def compare(root, left, right):
    a, b = root / "probe6" / left, root / "probe6" / right
    comparisons = {name: {"left_sha256": sha(a / name), "right_sha256": sha(b / name),
        "byte_identical": (a / name).read_bytes() == (b / name).read_bytes()}
        for name in ("actual.tsv", "raw.tsv", "family.tsv", "category.tsv")}
    def returns(path):
        result = collections.defaultdict(list)
        for call in sorted((path / "trace").glob("cpp-call-*")):
            identity = json.loads((call / "identity.json").read_text())
            result[identity["args_digest"]].append(sha(call / "return-bits.tsv"))
        return {k: sorted(v) for k, v in result.items()}
    first, second = returns(a), returns(b)
    inputs_equal = collections.Counter({k: len(v) for k, v in first.items()}) == collections.Counter({k: len(v) for k, v in second.items()})
    result = {"status": "EXACT_NATIVE_OBSERVER_COMPARISON_NOT_PACKAGE_ACCEPTANCE",
        "left": left, "right": right, "tables": comparisons,
        "exact_CPP_argument_multisets_identical": inputs_equal,
        "exact_CPP_return_bits_identical": first == second,
        "all_observed_numerical_outputs_identical": inputs_equal and first == second and
            all(c["byte_identical"] for c in comparisons.values()),
        "source_vs_observer_cause": "Unresolved if mismatch; untouched source control required",
        "full_package_pass_claimed": False}
    record(root / "probe6" / (left + "_vs_" + right + ".json"), result)
    return result


def source():
    root, config, r = context()
    arm = os.environ["LISAR_EXPECTED_ARCH"] == "arm64"
    directory, lib = build(root, config, r, "traced")
    env = environment(root, lib)
    env["LISAR_PROBE6_DERIVATION"] = str(directory / "derivation.json")
    variant = "source-arm-beta-traced" if arm else "source-intel-traced"
    smoke(root, r, variant, env)
    if not arm:
        comparison = compare(root, "binary-intel", variant)
        if not comparison["all_observed_numerical_outputs_identical"]:
            # One bounded, previously untested Intel source control, never a retry loop.
            directory, lib = build(root, config, r, "untraced-control")
            env = environment(root, lib)
            env["LISAR_PROBE6_DERIVATION"] = str(directory / "unmodified-source-control.json")
            smoke(root, r, "source-intel-untraced-control", env)
            compare(root, "binary-intel", "source-intel-untraced-control")
            compare(root, "source-intel-untraced-control", variant)


def manifest():
    root, config, _ = context(False)
    output = root / "probe6"
    output.mkdir(exist_ok=True)
    for p in root.iterdir():
        if p.is_file() and not p.is_symlink() and p.suffix in (".json", ".log", ".txt"):
            shutil.copyfile(p, output / p.name)
    # The earlier BH syntax prerequisite is small; preserve its own proof/logs.
    primitive = root / "primitive"
    for name in ("BH-DESCRIPTION.txt", "BH-description-print.txt", "BH-BSL-1.0.txt",
                 "primitive-preflight-sessionInfo.txt", "BH-include-path.txt"):
        if (primitive / name).is_file(): shutil.copyfile(primitive / name, output / name)
    files = [f for f in inventory(output) if f["path"] != "probe6-manifest.json"]
    bounds = config["trace_limits"]
    assert len(files) <= bounds["file_count"] and sum(f["bytes"] for f in files) <= bounds["total_artifact_bytes"]
    assert all(f["bytes"] <= bounds["max_artifact_file_bytes"] for f in files)
    record(output / "probe6-manifest.json", {"status": "TRACE_DIAGNOSTIC_ONLY_NOT_PACKAGE_ACCEPTANCE",
        "repository": os.environ["GITHUB_REPOSITORY"], "run_id": os.environ["GITHUB_RUN_ID"],
        "run_attempt": 1, "head_sha": os.environ["GITHUB_SHA"], "execution_priority": "low",
        "candidate_sha256": json.loads(Path("candidate/manifest.json").read_text())["tarball_sha256"],
        "architecture": os.environ["LISAR_EXPECTED_ARCH"], "full_package_pass_claimed": False,
        "stage_outcomes": {n: os.environ.get(n, "not-set") for n in ("PREFLIGHT_OUTCOME", "HEADER_OUTCOME",
            "PROVISION_OUTCOME", "NAMESPACE_OUTCOME", "BINARY_OUTCOME", "SOURCE_OUTCOME")}, "files": files})


if __name__ == "__main__":
    commands = {"preflight": preflight, "prerequisites": prerequisites, "namespace": namespace,
        "capture-contract": capture_contract, "binary": binary, "source": source, "manifest": manifest}
    assert sys.argv[1] in commands
    commands[sys.argv[1]]()
