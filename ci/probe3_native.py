"""Native ephemeral macOS diagnosis only. No package acceptance implied."""
import csv
import difflib
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

from runner import guard, owned_root, record, sha


def context(require_r=True):
    guard()
    assert os.environ["GITHUB_SHA"] == os.environ["EXPECTED_HEAD_SHA"]
    root = owned_root()
    config = json.loads(Path("ci/probe3-config.json").read_text())
    assert config["execution_priority"] == "low"
    return root, config, Path(os.environ["LISAR_R_EXECUTABLE"]) if require_r else None


def run(command, directory, label, timeout, env=None):
    # Persist exact arguments before every native invocation, with no shell.
    record(directory / (label + "-intent.json"), {"argv": [str(x) for x in command],
        "timeout_seconds": timeout, "status": "NATIVE_DIAGNOSTIC_ONLY"})
    try:
        with (directory / (label + "-stdout.log")).open("wb") as stdout, \
             (directory / (label + "-stderr.log")).open("wb") as stderr:
            code = subprocess.run([str(x) for x in command], stdout=stdout, stderr=stderr,
                timeout=timeout, env=env, check=False).returncode
    except subprocess.TimeoutExpired:
        (directory / (label + "-timeout.txt")).write_text(str(timeout) + "\n")
        raise
    (directory / (label + "-exit-code.txt")).write_text(str(code) + "\n")
    if code != 0:
        raise RuntimeError(label + " failed: " + str(code))


def header_guard(include, config, directory):
    assert include.is_dir() and not include.is_symlink()
    observations = {}
    for name, expected in config["critical_BH_header_sha256"].items():
        actual = sha(include / name)
        observations[name] = {"expected": expected, "observed": actual}
        assert actual == expected, (name, actual, expected)
    record(directory / "critical-BH-headers.json", observations)


def primitives():
    root, config, r = context()
    output = root / "primitive"
    assert output.is_dir()
    include = Path(os.environ["LISAR_PRIMITIVE_BH_INCLUDE"]).resolve(strict=True)
    header_guard(include, config, output)
    for name, expected in config["fgsea"]["primitive_source_sha256"].items():
        assert sha(Path("ci/primitive-source") / name) == expected
    for name in ("CXX20", "CXX20FLAGS", "CPPFLAGS"):
        value = subprocess.check_output([str(r), "CMD", "config", name], text=True).strip()
        (output / (name + ".txt")).write_text(value + "\n")
    compiler = shlex.split((output / "CXX20.txt").read_text())
    flags = shlex.split((output / "CXX20FLAGS.txt").read_text())
    run(compiler[:1] + ["--version"], output, "compiler-version", 20)
    for fp in ("default-flags", "strict-fp"):
        for constants in ("BH-as-is", "wide-string-control"):
            directory = output / (fp + "-" + constants)
            directory.mkdir()
            binary = directory / "native-primitives"
            command = compiler + flags + ["-I" + str(include), "-Ici", "-include",
                "ci/probe3_precision.hpp"]
            if fp == "strict-fp": command += ["-ffp-contract=off", "-fno-fast-math"]
            if constants == "wide-string-control": command += ["-DLISAR_PROBE_FORCE_WIDE_STRING_CONSTANTS=1"]
            source_arguments = ["ci/probe3_primitives.cpp", "ci/primitive-source/util.cpp"]
            run(command + ["-MM"] + source_arguments, directory, "dependencies", 60)
            command += source_arguments + ["-o", str(binary)]
            run(command, directory, "compile", 240)
            run([binary, directory], directory, "primitive", 90)
            # All original/source/BH compiler dependencies are preserved as hashes.
            # -MM excludes system headers; record both original translation units.
            dependency_text = (directory / "dependencies-stdout.log").read_text().replace("\\\n", " ")
            words = []
            for line in dependency_text.splitlines():
                if line.strip(): words += shlex.split(line.split(":", 1)[1])
            records = []
            for name in sorted(set(words)):
                path = Path(name).resolve(strict=True)
                assert path.is_file() and path.stat().st_size <= 16 * 1024**2
                records.append({"path": str(path), "bytes": path.stat().st_size, "sha256": sha(path)})
            assert len(records) <= 8192
            record(directory / "compile-dependencies.json", records)
    # A forced Wide-only constant-control build must leave every native/default
    # binary64 result unchanged. No expected numbers are stored or substituted.
    for fp in ("default-flags", "strict-fp"):
        def native_values(path):
            with path.open() as stream:
                return {(r["function"], r["input_type"], r["mode"], r["a"], r["b"]): r["binary64_bits_hex"]
                    for r in csv.DictReader(stream, delimiter="\t")
                    if r["mode"] in ("default_Boost", "explicit_no_promote", "exact_original_util_cpp", "native_libm")}
        first = native_values(output / (fp + "-BH-as-is") / "primitives.tsv")
        second = native_values(output / (fp + "-wide-string-control") / "primitives.tsv")
        assert first and first == second, "Wide control changed a non-Wide native result"
        record(output / (fp + "-native-control-equivalence.json"),
            {"status": "NATIVE_ONLY_BITS_IDENTICAL_NOT_PACKAGE_PASS", "rows_compared": len(first)})


def source_archive(package, spec, directory):
    archive_path = directory / (package + "-upstream-original.tar.gz")
    assert not archive_path.exists()
    run(["curl", "--fail", "--location", "--max-time", "120", "--max-filesize",
        str(32 * 1024**2), "--output", archive_path, spec["source_url"]],
        directory, "exact-source-download", 150)
    assert 0 < archive_path.stat().st_size <= 32 * 1024**2
    assert sha(archive_path) == spec["source_tar_sha256"]
    source = directory / "source"
    source.mkdir()
    with tarfile.open(archive_path) as archive:
        members = archive.getmembers()
        assert len(members) <= 2000 and sum(m.size for m in members) <= 64 * 1024**2
        for member in members:
            name = PurePosixPath(member.name)
            assert name.parts[0] == package and not name.is_absolute() and ".." not in name.parts
            assert member.isfile() or member.isdir()
            target = source / name
            if member.isdir(): target.mkdir(parents=True, exist_ok=True)
            else:
                assert member.size <= 16 * 1024**2
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())
    source = source / package
    description = (source / "DESCRIPTION").read_text()
    assert "\nVersion: " + spec["version"] + "\n" in "\n" + description
    assert "\ngit_last_commit: " + spec["git_last_commit"] + "\n" in "\n" + description
    (directory / "upstream-DESCRIPTION.txt").write_text(description)
    count = 0
    for line in (source / "MD5").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{32}) [ *](.+)", line)
        assert match, line
        name = PurePosixPath(match[2]) # binary '*' consumed by the delimiter regex
        assert not name.is_absolute() and ".." not in name.parts
        assert hashlib.md5((source / name).read_bytes()).hexdigest() == match[1]
        count += 1
    record(directory / "original-source.json", {"package": package, "version": spec["version"],
        "git_last_commit": spec["git_last_commit"], "url": spec["source_url"],
        "tar_sha256": sha(archive_path), "original_MD5_entries_verified": count,
        "files": inventory(source)})
    return source


def inventory(root):
    records = []
    for path in sorted(root.rglob("*")):
        assert not path.is_symlink()
        if path.is_file():
            records.append({"path": path.relative_to(root).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)})
    return records


def finalize_derivative(source, directory, notes):
    (source / "LISAR_PROBE3_DERIVATION.md").write_text(notes)
    # Preserve original tar/MD5 independently. Regenerate the derived MD5 openly,
    # including added notices and original generated files, never ignore warning.
    records = [p for p in sorted(source.rglob("*")) if p.is_file() and p.name != "MD5"]
    (source / "MD5").write_text("".join(hashlib.md5(p.read_bytes()).hexdigest() + " *" +
        p.relative_to(source).as_posix() + "\n" for p in records))
    before = {r["path"]: r for r in json.loads((directory / "original-source.json").read_text())["files"]}
    after = {r["path"]: r for r in inventory(source)}
    changed = [name for name in sorted(set(before) | set(after)) if before.get(name) != after.get(name)]
    record(directory / "derivation.json", {"status": "SOURCE_DERIVATIVE_HYPOTHESIS_NOT_ADOPTED",
        "changed_files": changed, "original_files": list(before.values()), "derived_files": list(after.values()),
        "MD5_handling": "Verified upstream binary-marker records, preserved original tar/MD5, explicitly regenerated derived MD5", "version_kept": True})
    return changed


def provider(mode, directory, env, rscript):
    run([rscript, "--vanilla", "ci/probe3_provider.R", mode, directory], directory, "fresh-provider", 120, env)
    result = json.loads((directory / "provider-result.json").read_text())
    assert result["failure"] is None and result["effective_binding_identical_to_DelayedArray"] is True
    if mode == "derived": assert result["warnings"] == []
    return result


def namespace():
    root, config, r = context()
    assert os.environ["LISAR_EXPECTED_ARCH"] == "arm64"
    directory = root / "primitive/namespace-rebuild"
    directory.mkdir()
    baseline = directory / "fresh-baseline"
    baseline.mkdir()
    rscript = r.parent / "Rscript"
    provider("baseline", baseline, os.environ.copy(), rscript)
    source = source_archive("SummarizedExperiment", config["SummarizedExperiment"], directory)
    target = source / "NAMESPACE"
    original = target.read_text()
    assert sha(target) == config["SummarizedExperiment"]["original_NAMESPACE_sha256"]
    assert original.count("import(S4Arrays)\n") == 1
    changed = original.replace("import(S4Arrays)\n", "import(S4Arrays, except = \"makeNindexFromArrayViewport\")\n")
    target.write_text(changed)
    assert sha(target) == config["SummarizedExperiment"]["derived_NAMESPACE_sha256"]
    (directory / "NAMESPACE.diff").write_text("".join(difflib.unified_diff(original.splitlines(True), changed.splitlines(True), fromfile="upstream/NAMESPACE", tofile="derived/NAMESPACE")))
    shutil.copyfile("ci/probe3-licenses/Artistic-2.0.txt", source / "Artistic-2.0.txt")
    changed_files = finalize_derivative(source, directory,
        "# Modified source, diagnostic only\n\nSummarizedExperiment 1.43.0 upstream git ffe9db3. Only exclude the earlier S4Arrays import of makeNindexFromArrayViewport, retaining the native observed DelayedArray provider. No installed namespace edit or warning suppression. Original notices retained. This modified source and all further modified source may be redistributed under the Original Artistic License 2.0 (section 4(c)); no package adoption/PASS claimed. Added this notice/full licence and explicitly regenerated MD5.\n")
    assert changed_files == ["Artistic-2.0.txt", "LISAR_PROBE3_DERIVATION.md", "MD5", "NAMESPACE"]
    lib = directory / "library"
    lib.mkdir()
    run([r, "CMD", "INSTALL", "--preclean", "--library=" + str(lib), source], directory, "source-install", 450)
    env = os.environ.copy()
    env["R_LIBS"] = str(lib) + ":" + os.environ["R_LIBS"]
    derived = directory / "fresh-derived"
    derived.mkdir()
    result = provider("derived", derived, env, rscript)
    header_guard(Path(result["BH_include"]), config, derived)


def prototype():
    root, config, r = context()
    assert os.environ["LISAR_EXPECTED_ARCH"] == "arm64"
    namespace = root / "primitive/namespace-rebuild"
    verified = json.loads((namespace / "fresh-derived/provider-result.json").read_text())
    assert verified["failure"] is None and verified["warnings"] == []
    assert verified["effective_binding_identical_to_DelayedArray"] is True
    directory = root / "primitive/fgsea-prototype"
    directory.mkdir()
    header_guard(Path(verified["BH_include"]), config, directory)
    source = source_archive("fgsea", config["fgsea"], directory)
    target = source / "src/util.cpp"
    original = target.read_text()
    assert sha(target) == config["fgsea"]["primitive_source_sha256"]["util.cpp"]
    old = "return boost::math::digamma(a) - boost::math::digamma(b + 1);"
    assert original.count(old) == 1 and original.count("#include \"util.h\"") == 1
    changed = original.replace("#include \"util.h\"", "#include \"lisar_probe_precision.hpp\"\n#include \"util.h\"").replace(old,
        "return lisar_probe::wide_digamma(a) - lisar_probe::wide_digamma(b + 1);")
    target.write_text(changed)
    shutil.copyfile("ci/probe3_precision.hpp", source / "src/lisar_probe_precision.hpp")
    shutil.copyfile("ci/probe3-licenses/BSL-1.0.txt", source / "BSL-1.0.txt")
    (directory / "util.cpp.diff").write_text("".join(difflib.unified_diff(original.splitlines(True), changed.splitlines(True), fromfile="upstream/src/util.cpp", tofile="prototype/src/util.cpp")))
    changed_files = finalize_derivative(source, directory,
        "# Arithmetic hypothesis, not a production fix\n\nfgsea 1.39.2 upstream git 31cb676. Change only betaMeanLog digamma evaluation to software base-2 arithmetic with a 64-bit mantissa (et_off), preserve upstream unsigned-long tag64 and each function narrowing to double BEFORE subtraction. Trigamma, all other formulas, RNG, sampleSize101, all original scientific source/tests/oracles remain unchanged. Default BH constants-as-is; no global override enabled in this prototype. Preserve original MIT LICENCE/copyright and included helper/Boost BSL-1.0. Full exact changes in external derivation.json; MD5 explicitly regenerated. No adoption or package PASS claim; compare Intel/ARM primitive bits and actual original48-null output.\n")
    assert changed_files == ["BSL-1.0.txt", "LISAR_PROBE3_DERIVATION.md", "MD5", "src/lisar_probe_precision.hpp", "src/util.cpp"]
    lib = directory / "library"
    lib.mkdir()
    env = os.environ.copy()
    env["R_LIBS"] = str(lib) + ":" + str(namespace / "library") + ":" + os.environ["R_LIBS"]
    assert "LISAR_PROBE_FORCE_WIDE_STRING_CONSTANTS" not in env
    for setting in ("CXX20", "CXX20FLAGS", "CPPFLAGS"):
        (directory / (setting + ".txt")).write_text(subprocess.check_output([str(r), "CMD", "config", setting], text=True))
    run([r, "CMD", "INSTALL", "--preclean", "--library=" + str(lib), source], directory, "prototype-install", 600, env)
    lisar_lib = root / "primitive/lisar-library"
    lisar_lib.mkdir()
    run([r, "CMD", "INSTALL", "--library=" + str(lisar_lib), "candidate/lisaR_0.99.0.tar.gz"], directory, "lisar-install", 180, env)
    env["R_LIBS"] = str(lisar_lib) + ":" + env["R_LIBS"]
    for name in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"):
        env[name] = "http://127.0.0.1:9"
    env.update({"NCPUS": "2", "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1"})
    smoke = root / "probe/software64-beta-prototype"
    smoke.mkdir(parents=True)
    # Exactly one original48-null smoke, same result/output/capture gates.
    run([r.parent / "Rscript", "--vanilla", "ci/probe3_smoke.R", "software64-beta-prototype", smoke], smoke, "R-smoke", 600, env)


def manifest():
    # Artifact preservation must not depend on successful R/BH initialization.
    root, _, _ = context(require_r=False)
    output = root / "primitive"
    output.mkdir(exist_ok=True)
    for path in root.iterdir():
        if path.is_file() and not path.is_symlink() and path.suffix in (".json", ".log", ".txt"):
            shutil.copyfile(path, output / path.name)
    smoke = root / "probe/software64-beta-prototype"
    if smoke.exists(): shutil.copytree(smoke, output / "original48-null-smoke")
    files = [r for r in inventory(output) if r["path"] != "primitive-manifest.json"]
    assert len(files) <= 50000 and sum(r["bytes"] for r in files) <= 2 * 1024**3
    assert all(r["bytes"] <= 128 * 1024**2 for r in files)
    record(output / "primitive-manifest.json", {"status":"DIAGNOSTIC_ONLY_NOT_PACKAGE_ACCEPTANCE",
        "repository":os.environ["GITHUB_REPOSITORY"], "run_id":os.environ["GITHUB_RUN_ID"],
        "run_attempt":1, "head_sha":os.environ["GITHUB_SHA"], "execution_priority":"low",
        "candidate_sha256":json.loads(Path("candidate/manifest.json").read_text())["tarball_sha256"],
        "architecture":os.environ["LISAR_EXPECTED_ARCH"], "full_package_pass_claimed":False,
        "stage_outcomes":{name:os.environ.get(name, "not-set") for name in
            ("PRIMITIVE_OUTCOME", "PROVISION_OUTCOME", "NAMESPACE_OUTCOME", "PROTOTYPE_OUTCOME")},
        "files":files})


if __name__ == "__main__":
    command = sys.argv[1]
    assert command in ("primitives", "namespace", "prototype", "manifest")
    {"primitives":primitives, "namespace":namespace, "prototype":prototype, "manifest":manifest}[command]()
