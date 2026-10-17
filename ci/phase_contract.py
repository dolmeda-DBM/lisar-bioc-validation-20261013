"""Complete required phase coverage. Splitting never omits a required check."""
PLATFORMS = ('linux-x86_64','windows-x86_64','macos-x86_64','macos-arm64')
REQUIRED_PHASES = tuple((p,'core') for p in PLATFORMS) + (
    ('linux-x86_64','ordinary-offline'), ('linux-x86_64','longtests-offline'))
CORE_CHECKS = ('reference-default','ordinary-default','longtests-default')
UNITS = ('build','install','GitClone','BiocCheck')
BASE_STEPS = ('initialize','provision','texsetup','tex','portable')
def checks(phase):
    assert phase in ('core','ordinary-offline','longtests-offline')
    return CORE_CHECKS if phase == 'core' else (phase,)
def units(phase):
    return UNITS if phase == 'core' else ()
def step_ids(phase):
    return BASE_STEPS + (('build','install','ordinary','longtests','reference','gitclone','bioccheck')
        if phase == 'core' else ('offline',) if phase == 'ordinary-offline' else ('longoffline',))
def artifact(platform,phase,run_id):
    assert (platform,phase) in REQUIRED_PHASES
    return f'bioc-{platform}-{phase}-{run_id}-1'
def parse(name,run_id):
    matches=[(platform,phase) for platform,phase in REQUIRED_PHASES
             if artifact(platform,phase,run_id)==name]
    assert len(matches)==1, 'Unexpected phase artifact'
    return matches[0]
