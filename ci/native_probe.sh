#!/usr/bin/env bash
# INERT here. Invoke only after the existing guarded initialization/provisioning
# on the authorized ephemeral public ARM64 runner. No workstation execution.
set -euo pipefail
python3 - <<'PY'
import json,os,platform
from pathlib import Path
assert os.environ.get('GITHUB_ACTIONS')=='true'
assert os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted'
assert os.environ.get('LISAR_REPOSITORY_PRIVATE')=='false'
assert os.environ.get('GITHUB_REPOSITORY')=='dolmeda-DBM/lisar-bioc-validation-20261013'
assert os.environ.get('GITHUB_RUN_ATTEMPT')=='1'
assert platform.system()=='Darwin' and platform.machine()=='arm64'
assert os.environ['GITHUB_SHA']==os.environ['EXPECTED_HEAD_SHA']
root=Path(os.environ['LISAR_VALIDATION_ROOT']).resolve(strict=True)
assert root.parent==Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
assert root.name.startswith('lisar-validation-') and not (root/'probe').exists()
assert json.loads(Path('ci/config.json').read_text())['execution_priority']=='low'
PY
probe_root="${LISAR_VALIDATION_ROOT}/probe"
mkdir "$probe_root"
mkdir "$probe_root/lisar-library"
probe_r="${LISAR_R_EXECUTABLE}"
probe_rscript="$(dirname "$probe_r")/Rscript"
"$probe_r" CMD INSTALL --library="$probe_root/lisar-library" candidate/lisaR_0.99.0.tar.gz > "$probe_root/lisar-install.log" 2>&1
"$probe_r" CMD config CXX17 > "$probe_root/CXX17.txt"
"$probe_r" CMD config CXX17FLAGS > "$probe_root/CXX17FLAGS.txt"
clang --version > "$probe_root/clang-version.txt"
# No version fallback. Preserve the exact downloaded source bytes and their
# DESCRIPTION/git metadata; matching version alone is not binary provenance.
curl --fail --location --max-time 120 --output "$probe_root/fgsea_1.39.2-source.tar.gz" \
  https://bioconductor.org/packages/3.24/bioc/src/contrib/fgsea_1.39.2.tar.gz
python3 - <<'PY'
import hashlib,json,os,tarfile
from pathlib import Path,PurePosixPath
root=Path(os.environ['LISAR_VALIDATION_ROOT'])/'probe'
path=root/'fgsea_1.39.2-source.tar.gz'
assert 0<path.stat().st_size<=16*1024**2
with tarfile.open(path) as archive:
    members=archive.getmembers()
    assert len(members)<2000 and sum(m.size for m in members)<=64*1024**2
    for member in members:
        name=PurePosixPath(member.name)
        assert name.parts[0]=='fgsea' and not name.is_absolute() and '..' not in name.parts
        assert member.isfile() or member.isdir()
        target=root/'source'/name
        if member.isdir():target.mkdir(parents=True,exist_ok=True)
        else:
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(archive.extractfile(member).read())
    description=(root/'source/fgsea/DESCRIPTION').read_text()
    assert '\nVersion: 1.39.2\n' in '\n'+description
    (root/'source-DESCRIPTION.txt').write_text(description)
    records=[{'path':p.relative_to(root/'source/fgsea').as_posix(),'bytes':p.stat().st_size,
              'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
             for p in sorted((root/'source/fgsea').rglob('*')) if p.is_file()]
    (root/'source-manifest.json').write_text(json.dumps({'package':'fgsea','version':'1.39.2',
      'url':'https://bioconductor.org/packages/3.24/bioc/src/contrib/fgsea_1.39.2.tar.gz',
      'tar_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'files':records,
      'changed_source_files':[],'binary_source_identity_requires_DESCRIPTION_git_comparison':True},indent=2)+'\n')
PY
probe_base_libs="${probe_root}/lisar-library:${R_LIBS}"
probe_failed=0
for probe_variant in binary source-default source-strict-fp; do
  mkdir "$probe_root/$probe_variant"
  : > "$probe_root/$probe_variant/Makevars"
  probe_libs="$probe_base_libs"
  if [[ "$probe_variant" != binary ]]; then
    mkdir "$probe_root/$probe_variant/library"
    if [[ "$probe_variant" == source-strict-fp ]]; then
      printf '%s\n' 'CXXFLAGS += -ffp-contract=off -fno-fast-math' \
        'CXX11FLAGS += -ffp-contract=off -fno-fast-math' \
        'CXX14FLAGS += -ffp-contract=off -fno-fast-math' \
        'CXX17FLAGS += -ffp-contract=off -fno-fast-math' \
        'CXX20FLAGS += -ffp-contract=off -fno-fast-math' > "$probe_root/$probe_variant/Makevars"
    fi
    if R_LIBS="$probe_base_libs" R_MAKEVARS_USER="$probe_root/$probe_variant/Makevars" \
       "$probe_r" CMD INSTALL --preclean --library="$probe_root/$probe_variant/library" \
       "$probe_root/source/fgsea" > "$probe_root/$probe_variant/install.log" 2>&1; then
      printf '%s\n' 0 > "$probe_root/$probe_variant/install-exit-code.txt"
    else
      printf '%s\n' "$?" > "$probe_root/$probe_variant/install-exit-code.txt"
      probe_failed=1
      continue
    fi
    probe_libs="$probe_root/$probe_variant/library:$probe_base_libs"
  fi
  if R_LIBS="$probe_libs" R_MAKEVARS_USER="$probe_root/$probe_variant/Makevars" \
     NCPUS=2 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
     http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 \
     HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
     "$probe_rscript" --vanilla ci/native_probe.R "$probe_variant" "$probe_root/$probe_variant" \
     > "$probe_root/$probe_variant/stdout.log" 2> "$probe_root/$probe_variant/stderr.log"; then
    printf '%s\n' 0 > "$probe_root/$probe_variant/R-exit-code.txt"
  else
    printf '%s\n' "$?" > "$probe_root/$probe_variant/R-exit-code.txt"
    probe_failed=1
  fi
done
# An expected failing binary baseline remains a failed diagnostic job, not green
# acceptance. Upload all probe artifacts with if:always() in the reviewed workflow.
exit "$probe_failed"
