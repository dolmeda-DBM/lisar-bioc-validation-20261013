# lisaR — experimental Bioconductor candidate validation

This temporary repository validates an **experimental candidate, not a release**.
The main project is [DBM-OlmedaLab/lisaR](https://github.com/DBM-OlmedaLab/lisaR).
The complete candidate package is in `candidate/lisaR_0.99.0.tar.gz`; its
SHA-256 and every archive member are recorded in `candidate/manifest.json`.
No source history, unpublished research data, or credentials are included.

## Full Bioconductor validation

The workflow is manual only and accepts an exact commit SHA.
The workflow `bioconductor-validation.yml` uses **standard public-repository**
runners `macos-15-intel` (Intel), `macos-15` (ARM64), `ubuntu-24.04` and
`windows-2025`, one at a time, with R **4.6.1**, Bioconductor **3.24**
and testthat **3.3.2**. There is no private/larger-runner fallback or cache.
See [GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

Each architecture runs independent native commands on the exact input tarball:

- Ordinary `R CMD check`, with default check flags.
- BBS-route `R CMD check --test-dir=longtests`, even if ordinary fails.
- Reference `R CMD check --no-build-vignettes` in addition to the full check.
- Clean build and installation, full BiocCheckGitClone on a separately reviewed
  maintained-source clone (never a tarball-derived export),
  and BiocCheck on the candidate tarball, with no checks excluded.
- Actual PDF/manual toolchain preflight, recorded independently of test execution.

Linux repeats ordinary checks and longtests in fresh network namespaces with
explicit isolation evidence. Other-platform runs do not claim network isolation.
The Linux online/core, ordinary-offline and longtests-offline phases are three
independent hosted jobs with separate immutable evidence artifacts. A later offline
timeout cannot erase a previously uploaded core or ordinary-offline artifact.
All three phases remain required; splitting does not reuse a prior platform PASS.
Linux records elapsed time and native peak resident memory. Old platform PASS
results are not reused for a changed candidate. This is validation, not submission.

No rebuilt package replaces the input. Warnings, errors, omissions, native
return codes and incomplete evidence remain visible; a green workflow is not
a claim of Bioconductor acceptance. Errors block readiness; warnings and notes
remain visible and require review. Avoidable warnings must be resolved, and any
remaining warnings justified without claiming they are accepted by Bioconductor.

Maintained-source provenance must be verified separately before this revision can
be launched. The harness refuses a missing proof instead of stripping generated
fields or documentation from a built package to pass a source-repository check.

### Shiny scope

The complete Suggests set, including Shiny, is installed in the isolated runner
library. Shiny backend tests use the package fixtures; no backend-only
supplements or relaxed Suggests checks are enabled for this validation.
No Shiny app/UI is launched or deployed by the workflow.

## Evidence

Full-validation public artifacts are retained for **seven days**. They contain this candidate's
synthetic-package diagnostics only: native check logs/Rout files, session and
dependency versions, archive and test-file hashes, longtests' original TSV/RDS,
and bounded fallback-fixture snapshots explicitly marked potentially incomplete.
Ordinary testthat emits native Rout, not a new fabricated TSV/RDS.
Download the logs and artifacts before removing the temporary repository.
Copies of a public repository may persist after deletion.

The package and these validation scripts are licensed GPL-3.0-or-later.

## Portable test-only acceptance

This candidate changes tests only: production statistics and the original
fixtures are byte-identical to the baseline. P-value comparisons use
relative tolerance 1e-12 with zero absolute tolerance; structure,
significance, support and run integrity remain exact. No produced values
or identifiers are rounded or replaced. Additional reference tables
are original R1 Intel outputs with pinned provenance, not new expected outputs.

All four platforms validate the same new exact candidate/head. Dependencies are
ordinary upstream CRAN/Bioconductor; no numerical or namespace experimental patches.
The only additional Windows fixture change shortens a synthetic temporary parent
name; production path limits, assertions and calculations are unchanged.
