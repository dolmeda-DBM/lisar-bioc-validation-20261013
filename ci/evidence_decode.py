"""Evidence decoding repairs only. Never rewrite native originals."""
import copy
from pathlib import Path
import runner

def source_pins(checkdir, manifest, longtests):
    # testthat generates failure reproducers inside tests/testthat/_problems.
    # They are diagnostics, not candidate input. Exclude only that exact tree;
    # preserve and separately hash it, and reject all other unexpected R files.
    expected = {x['path']: x for x in manifest['archive_files']}
    rows = []
    root = checkdir / 'tests'
    for path in sorted(root.rglob('*.R')):
        if path.is_symlink(): raise ValueError('Symlink in executed test tree')
        relative = path.relative_to(root).as_posix()
        if relative.startswith('testthat/_problems/'): continue
        archive = ('longtests/' if longtests else 'tests/') + relative
        reference = expected.get(archive)
        actual = runner.sha(path)
        rows.append({'check_path': 'tests/' + relative, 'archive_path': archive,
                     'sha256': actual, 'expected_sha256': reference['sha256'] if reference else None,
                     'matched': actual == reference['sha256'] if reference else False})
    return rows

def problem_diagnostics(checkdir):
    root = checkdir / 'tests/testthat/_problems'
    return [{'check_path': p.relative_to(checkdir).as_posix(), 'sha256': runner.sha(p)}
            for p in sorted(root.rglob('*')) if p.is_file() and not p.is_symlink()]

def canonical_summary(summary):
    """Only normalize relative evidence inventory paths, not messages/counts."""
    value = copy.deepcopy(summary)
    if 'files' in value:
        files = value['files']
        if not isinstance(files, list) or any(not isinstance(p, str) for p in files):
            raise ValueError('Invalid evidence file inventory')
        normalized = [p.replace('\\', '/') for p in files]
        if any(p.startswith('/') or ':' in p or '..' in p.split('/') for p in normalized):
            raise ValueError('Unsafe evidence relative path')
        if len(normalized) != len(set(normalized)): raise ValueError('Duplicate normalized evidence path')
        value['files'] = normalized
    return value
