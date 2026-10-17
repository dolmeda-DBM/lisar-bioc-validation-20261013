"""Build metadata classification only; all drift remains visible for review."""
GENERATED = frozenset(('DESCRIPTION','MD5','build/partial.rdb','build/vignette.rds'))
def packaging(path):
    return path in GENERATED or path.startswith('inst/doc/')
def compare(expected, actual):
    changed=[p for p in expected if actual.get(p)!=expected[p]]
    missing=[p for p in expected if p not in actual]
    added=sorted(set(actual)-set(expected))
    return {'changed_or_missing_shipped_files':changed,
        'missing_shipped_files':missing,
        'nonpackaging_source_changes':[p for p in changed if not packaging(p) or p in missing],
        'added_build_files':added,'unapproved_added_files':[p for p in added if not packaging(p)],
        'generated_metadata_exact_allowlist':sorted(GENERATED)}
