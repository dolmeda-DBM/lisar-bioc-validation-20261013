# lisaR — experimental Bioconductor candidate validation

This temporary repository validates an **experimental candidate, not a release**.
The main project is [DBM-OlmedaLab/lisaR](https://github.com/DBM-OlmedaLab/lisaR).
The complete candidate package is in `candidate/lisaR_0.99.0.tar.gz`; its
SHA-256 and every archive member are recorded in `candidate/manifest.json`.
No source history, unpublished research data, or credentials are included.

## macOS checks

The workflow is manual only and accepts an exact commit SHA.
It uses the **standard public-repository** runners `macos-15-intel` (Intel) and
`macos-15` (ARM64), one at a time, with R **4.6.1**, Bioconductor **3.24**
and testthat **3.3.2**. There is no private/larger-runner fallback or cache.
See [GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

Each architecture runs independent native commands on the exact input tarball:

- Ordinary `R CMD check`, with default check flags.
- BBS-route `R CMD check --test-dir=longtests`, even if ordinary fails.

No rebuilt package replaces the input. Warnings, errors, omissions, native
return codes and incomplete evidence remain visible; a green workflow is not
a claim of Bioconductor acceptance. BiocCheck and Windows/Linux acceptance are
separate gates, not results of this workflow.

### Shiny scope

The complete Suggests set, including Shiny, is installed in the isolated runner
library. Shiny backend tests use the package fixtures; no backend-only
supplements or relaxed Suggests checks are enabled for this validation.
No Shiny app/UI is launched or deployed by the workflow.

## Evidence

Public artifacts are retained for **one day**. They contain this candidate's
synthetic-package diagnostics only: native check logs/Rout files, session and
dependency versions, archive and test-file hashes, longtests' original TSV/RDS,
and bounded fallback-fixture snapshots explicitly marked potentially incomplete.
Ordinary testthat emits native Rout, not a new fabricated TSV/RDS.
Download the logs and artifacts before removing the temporary repository.
Copies of a public repository may persist after deletion.

The package and these validation scripts are licensed GPL-3.0-or-later.
