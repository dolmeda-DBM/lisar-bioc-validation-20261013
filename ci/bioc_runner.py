"""Runner-only full P8 validation adapter. No submission, retry or PASS inference."""
import json, os, platform, shutil, subprocess, sys, time
from pathlib import Path
import runner as native
import cross_runner as cross
import bioc_check
import evidence_decode
import build_identity

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
    phase = os.environ['LISAR_VALIDATION_PHASE']
    assert phase in (('core','ordinary-offline','longtests-offline') if platform.system() == 'Linux' else ('core',))
    return config, manifest, tarball

def initialize():
    # Reuse exact extraction verification, absent owned short root and temp setup.
    cross.initialize()
    root = cross.owned_root()
    data = json.loads((root / 'run-intent.json').read_text())
    data.update(workflow_path=WORKFLOW, validation_profile='bioconductor-readiness-full-v1',
        provision_source_sha256=native.sha('ci/provision-bioc.R'),
        prior_platform_passes_reused=False, submission_authorized=False,
        validation_phase=os.environ['LISAR_VALIDATION_PHASE'])
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
    assert os.environ['LISAR_VALIDATION_PHASE'] == 'core'
    root = native.owned_root()
    executable = os.environ['LISAR_R_EXECUTABLE']
    if command == 'build':
        # Build from the reviewed maintained source, as Bioconductor builds from Git.
        proof = json.loads(Path('candidate/maintained-source-manifest.json').read_text())
        assert proof['candidate_sha256'] == manifest['tarball_sha256']
        assert proof['status'] == 'MAINTAINED_SOURCE_IDENTITY_PARENT_REVIEWED'
        source = root/'s'/'lisaR'
        assert not source.parent.exists(), 'No retry/overwrite'
        shutil.copytree(Path('maintained-source'), source)
        copied = {q.relative_to(source).as_posix(): native.sha(q) for q in source.rglob('*') if q.is_file()}
        assert not any(q.is_symlink() for q in source.rglob('*'))
        assert copied == {f['path']: f['sha256'] for f in proof['files']}, 'Maintained source drift'
        code = invoke(command, [executable, 'CMD', 'build', str(source)])
        built = root/'build/lisaR_0.99.0.tar.gz'
        if built.exists():
            import tarfile
            with tarfile.open(built) as archive:
                files = {m.name.removeprefix('lisaR/'): native.hashlib.sha256(archive.extractfile(m).read()).hexdigest()
                         for m in archive.getmembers() if m.isfile()}
            expected = {f['path']:f['sha256'] for f in manifest['archive_files']}
            identity = build_identity.compare(expected, files)
            native.record(root/'build/source-identity.json', {**identity,
                'built_tarball_sha256':native.sha(built),
                'packaging_differences_require_owner_review':True,
                'checked_tarball_is_original_exact_candidate':True})
            if identity['nonpackaging_source_changes'] or identity['unapproved_added_files']:
                code = code or 1
        else: code = code or 1
    elif command == 'install':
        lib = root/'install-library'; assert not lib.exists(); lib.mkdir()
        code = invoke(command, [executable, 'CMD', 'INSTALL', '--library='+str(lib), str(tarball)])
    else:
        assert command in ('GitClone', 'BiocCheck')
        code = invoke(command, [shutil.which('Rscript'), '--vanilla', str(Path('ci/bioc-specific.R').resolve()), command])
    raise SystemExit(code)

OFFLINE_SHELL = 'ip link set lo up && U=$1 && P=$2 && shift 2 && exec runuser -u "$U" -- env "PATH=$P" "$@"'

def offline_command(argv):
    # Fresh process and network namespace; no host firewall/agent/network changes.
    # Loopback is brought up as on any real host; no external route exists.
    # sudo's secure_path drops the step PATH (TinyTeX), so carry it explicitly.
    return ['sudo', '-n', '--preserve-env', 'unshare', '--net', '--', 'sh', '-c', OFFLINE_SHELL,
            'lisar-offline', os.environ['USER'], os.environ['PATH']] + argv

def namespace_proof(stagepath):
    code = ("import json,os,shutil,socket; s=socket.socket(); s.settimeout(2); r=s.connect_ex(('1.1.1.1',443)); "
            "l=socket.socket(); l.bind(('127.0.0.1',0)); l.listen(1); c=socket.socket(); c.settimeout(2); "
            "lo=c.connect_ex(l.getsockname()); tex=shutil.which('pdflatex'); "
            "print(json.dumps({'namespace':os.readlink('/proc/self/ns/net'),'external_connect_errno':r,"
            "'loopback_connect_errno':lo,'pdflatex':tex})); raise SystemExit(0 if r and lo == 0 and tex else 1)")
    result = subprocess.run(offline_command([sys.executable, '-c', code]), capture_output=True, text=True, check=False)
    proof = {'parent_namespace':os.readlink('/proc/self/ns/net'), 'returncode':result.returncode,
             'stdout':result.stdout, 'stderr':result.stderr, 'method':'fresh Linux network namespace'}
    native.record(stagepath/'network-isolation.json', proof)
    assert result.returncode == 0
    observed = json.loads(result.stdout)
    assert observed['namespace'] != proof['parent_namespace'] and observed['external_connect_errno'] != 0
    assert observed['loopback_connect_errno'] == 0 and observed['pdflatex']
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
                     schema='lisar-full-bioc-evidence-v1', validation_phase=os.environ['LISAR_VALIDATION_PHASE'])
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
    elif command == 'verify-root':
        guard()
        root = native.owned_root()
        assert root == Path('/private/tmp/l') and not root.is_symlink()
        intent = json.loads((root/'run-intent.json').read_text())
        assert intent['head_sha'] == os.environ['GITHUB_SHA']
        assert intent['candidate_sha256'] == os.environ['EXPECTED_CANDIDATE_SHA256']
        assert str(intent['run_id']) == os.environ['GITHUB_RUN_ID']
    elif command == 'check':
        stage = sys.argv[2]; phase = os.environ['LISAR_VALIDATION_PHASE']
        assert stage in (bioc_check.STAGES[:3] if phase == 'core' else (phase,))
        bioc_check.check(stage)
    elif command in ('build','install','GitClone','BiocCheck'): unit(command)
    elif command == 'collect': collect()
    elif command == 'outcomes': outcomes()
    else: raise SystemExit('Unknown bounded command')
