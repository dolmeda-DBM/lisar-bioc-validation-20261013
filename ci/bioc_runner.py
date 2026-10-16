"""Runner-only full P8 validation adapter. No submission, retry or PASS inference."""
import json, os, platform, shutil, subprocess, sys, time
from pathlib import Path
import runner as native
import cross_runner as cross
import bioc_check
import evidence_decode

WORKFLOW = '.github/workflows/bioconductor-validation.yml'
PLATFORMS = {'linux-x86_64': ('Linux', 'x86_64'), 'windows-x86_64': ('Windows', 'AMD64'),
             'macos-x86_64': ('Darwin', 'x86_64'), 'macos-arm64': ('Darwin', 'arm64')}
STAGES = bioc_check.STAGES + ('build', 'install', 'GitClone', 'BiocCheck')

def guard():
    assert os.environ.get('GITHUB_ACTIONS') == 'true'
    assert os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
    assert os.environ.get('LISAR_REPOSITORY_PRIVATE') == 'false'
    assert os.environ.get('GITHUB_REPOSITORY') == native.REPOSITORY
    assert os.environ.get('GITHUB_RUN_ATTEMPT') == '1'
    assert (platform.system(), platform.machine()) == PLATFORMS[os.environ['LISAR_RUNTIME_PLATFORM']]
    assert os.environ.get('GITHUB_WORKFLOW_REF', '').startswith(native.REPOSITORY + '/' + WORKFLOW + '@')
    assert os.environ['GITHUB_SHA'] == os.environ['EXPECTED_HEAD_SHA']
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == os.environ['EXPECTED_HEAD_SHA']
    config, manifest, tarball = native.inputs()
    assert config['allow_shiny_backend'] is True and not config['backend_supplement_when_shiny_excluded']
    assert manifest['tarball_sha256'] == os.environ['EXPECTED_CANDIDATE_SHA256']
    return config, manifest, tarball

def initialize():
    # Reuse exact extraction verification, absent owned short root and temp setup.
    cross.initialize()
    root = cross.owned_root()
    data = json.loads((root / 'run-intent.json').read_text())
    data.update(workflow_path=WORKFLOW, validation_profile='bioconductor-readiness-full-v1',
        provision_source_sha256=native.sha('ci/provision-bioc.R'),
        prior_platform_passes_reused=False, submission_authorized=False)
    native.record(root / 'run-intent.json', data)

def invoke(command, argv, env=None):
    guard()
    destination = native.owned_root() / command
    assert not destination.exists(), 'No retry/overwrite'
    destination.mkdir()
    start = time.monotonic()
    actual = argv
    if platform.system() == 'Linux':
        actual = ['/usr/bin/time', '-v', '-o', str(destination / 'time-memory.txt')] + argv
    native.record(destination / 'intent.json', {'argv': actual, 'cwd': str(destination),
        'candidate_sha256': os.environ['EXPECTED_CANDIDATE_SHA256'], 'validation_profile': 'bioconductor-readiness-full-v1'})
    with (destination / 'stdout.log').open('xb') as output, (destination / 'stderr.log').open('xb') as error:
        result = subprocess.run(actual, cwd=destination, env=env, stdout=output, stderr=error, check=False)
    native.record(destination / 'native-exit.json', {'R_returncode': result.returncode,
        'elapsed_seconds': time.monotonic()-start, 'ended_at': native.stamp(), 'package_pass_claimed': False})
    return result.returncode

def r_driver(command):
    guard()
    script = {'provision': 'provision-bioc.R', 'portable': 'portable-preflight.R',
              'tex-setup': 'tex-setup.R', 'tex': 'tex-preflight.R'}[command]
    with (native.owned_root() / (command+'.log')).open('xb') as output:
        result = subprocess.run([shutil.which('Rscript'), '--vanilla', 'ci/'+script],
            stdout=output, stderr=subprocess.STDOUT, check=False)
    raise SystemExit(result.returncode)

def unit(command):
    config, manifest, tarball = guard()
    root = native.owned_root()
    executable = os.environ['LISAR_R_EXECUTABLE']
    if command == 'build':
        code = invoke(command, [executable, 'CMD', 'build', str(root/'input/lisaR')])
        built = root/'build/lisaR_0.99.0.tar.gz'
        if built.exists():
            import tarfile
            with tarfile.open(built) as archive:
                files = {m.name.removeprefix('lisaR/'): native.hashlib.sha256(archive.extractfile(m).read()).hexdigest()
                         for m in archive.getmembers() if m.isfile()}
            expected = {f['path']:f['sha256'] for f in manifest['archive_files']}
            changed = [p for p in expected if files.get(p) != expected[p]]
            # R CMD build regenerates package metadata, MD5 and inst/doc.
            # Record every difference; byte-pin all non-packaging source.
            packaging = lambda p: p in ('DESCRIPTION', 'MD5') or p.startswith('inst/doc/')
            unapproved = [p for p in changed if not packaging(p)]
            native.record(root/'build/source-identity.json', {'changed_or_missing_shipped_files': changed,
                'nonpackaging_source_changes': unapproved,
                'added_build_files': sorted(set(files)-set(expected)), 'built_tarball_sha256':native.sha(built),
                'packaging_differences_require_owner_review':True, 'checked_tarball_is_original_exact_candidate':True})
            if unapproved: code = code or 1
        else: code = code or 1
    elif command == 'install':
        lib = root/'install-library'; assert not lib.exists(); lib.mkdir()
        code = invoke(command, [executable, 'CMD', 'INSTALL', '--library='+str(lib), str(tarball)])
    else:
        assert command in ('GitClone', 'BiocCheck')
        code = invoke(command, [shutil.which('Rscript'), '--vanilla', str(Path('ci/bioc-specific.R').resolve()), command])
    raise SystemExit(code)

def offline_command(argv):
    # Fresh process and network namespace; no host firewall/agent/network changes.
    return ['sudo', '-n', '--preserve-env', 'unshare', '--net', '--', 'runuser',
            '-u', os.environ['USER'], '--'] + argv

def namespace_proof(stagepath):
    code = "import json,os,socket; s=socket.socket(); s.settimeout(2); r=s.connect_ex(('1.1.1.1',443)); print(json.dumps({'namespace':os.readlink('/proc/self/ns/net'),'external_connect_errno':r})); raise SystemExit(0 if r else 1)"
    result = subprocess.run(offline_command([sys.executable, '-c', code]), capture_output=True, text=True, check=False)
    proof = {'parent_namespace':os.readlink('/proc/self/ns/net'), 'returncode':result.returncode,
             'stdout':result.stdout, 'stderr':result.stderr, 'method':'fresh Linux network namespace'}
    native.record(stagepath/'network-isolation.json', proof)
    assert result.returncode == 0
    observed = json.loads(result.stdout)
    assert observed['namespace'] != proof['parent_namespace'] and observed['external_connect_errno'] != 0
    return proof

def collect():
    native.collect()
    destination = native.owned_root()/'evidence'
    manifest_path = destination/'evidence-manifest.json'
    inventory = json.loads(manifest_path.read_text())
    for name in ('tex-diagnostics', 'manual-preflight.pdf'):
        source = native.owned_root()/name
        if not source.exists(): continue
        paths = sorted(source.rglob('*')) if source.is_dir() else [source]
        for path in paths:
            assert not path.is_symlink()
            if not path.is_file(): continue
            relative = path.relative_to(native.owned_root())
            target = destination/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            inventory['files'].append({'path':relative.as_posix(), 'bytes':target.stat().st_size, 'sha256':native.sha(target)})
    inventory.update(workflow_path=WORKFLOW, platform_key=os.environ['LISAR_RUNTIME_PLATFORM'],
                     schema='lisar-full-bioc-evidence-v1')
    native.record(manifest_path, inventory)
    path = destination/'results.json'
    value = json.loads(path.read_text())
    value.update(scope='Full P8 candidate validation; no submission; owner review required',
        validation_profile='bioconductor-readiness-full-v1', readiness_pass_claimed=False)
    native.record(path, value)

def outcomes():
    guard()
    native.record(native.owned_root()/'stage-outcomes.json', json.loads(os.environ['BIOC_STAGE_OUTCOMES']))

original_short_root = cross.short_root
# macOS /tmp resolves to /private/tmp; keep the owned-root identity canonical.
cross.short_root = lambda: original_short_root().parent.resolve(strict=True) / original_short_root().name

native.guard = guard
native.owned_root = cross.owned_root
native.source_pins = evidence_decode.source_pins
native.problem_diagnostics = evidence_decode.problem_diagnostics
native.namespace_proof = namespace_proof
native.offline_command = offline_command
native.STAGES = STAGES
cross.guard = guard
cross.macos_reference = lambda: {'not_reused': True, 'reason':'New candidate; all native platforms rerun'}
if __name__ == '__main__':
    command = sys.argv[1]
    if command == 'initialize': initialize()
    elif command in ('provision','portable','tex-setup','tex'): r_driver(command)
    elif command == 'check': bioc_check.check(sys.argv[2])
    elif command in ('build','install','GitClone','BiocCheck'): unit(command)
    elif command == 'collect': collect()
    elif command == 'outcomes': outcomes()
    else: raise SystemExit('Unknown bounded command')
