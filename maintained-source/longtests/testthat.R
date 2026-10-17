# Installed-package longtests runner. No pkgload or source namespace.
# BBS runs this entrypoint after RunLongTests: TRUE. Manual invocation accepts
# zero or one exact test basename to bound a single verification unit.
library(testthat)
library(lisaR)
stopifnot(file.exists(file.path(find.package("lisaR"), "Meta", "package.rds")))
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
explicit <- Sys.getenv("LISAR_LONGTEST_ROOT", "")
# R CMD check copies --test-dir contents into <package>.Rcheck/tests.
# Accept that actual working directory, not a presumed literal basename.
candidates <- c(getwd(), explicit,
  if (length(file_arg) == 1L) dirname(sub("^--file=", "", file_arg)),
  file.path(getwd(), "longtests"))
candidates <- unique(candidates[nzchar(candidates)])
candidates <- candidates[dir.exists(file.path(candidates, "testthat")) &
  file.exists(file.path(candidates, "testthat.R")) &
  file.exists(file.path(candidates, "ownership.tsv"))]
if (!length(candidates)) stop("Cannot locate owned longtests/testthat")
root <- normalizePath(candidates[[1L]], winslash = "/", mustWork = TRUE)
owned <- utils::read.delim(file.path(root, "ownership.tsv"), stringsAsFactors = FALSE)
expected <- c("helper-portable-inference.R", "test-portable-inference.R",
  "helper-run-contract.R",
  "test-audit-trace-regressions.R",
  "test-category-plot-variants.R",
  "test-quick-start.R",
  "test-report-architecture.R",
  "helper-explore.R",
  "test-explore-engine.R",
  "test-explore-export.R",
  "test-explore-repairs.R",
  "test-explore-h4.R",
  "test-explore-h5.R",
  "test-explore-lifecycle.R")
stopifnot(identical(sort(owned$file), sort(expected)), !anyDuplicated(owned$file))
actual <- sort(list.files(file.path(root, "testthat"), pattern = "^[^.].*[.]R$"))
stopifnot(identical(actual, sort(expected)))
for (i in seq_len(nrow(owned))) {
  path <- file.path(root, "testthat", owned$file[[i]])
  stopifnot(!nzchar(Sys.readlink(path)), file.exists(path),
    identical(dirname(normalizePath(path, winslash = "/", mustWork = TRUE)),
      normalizePath(file.path(root, "testthat"), winslash = "/", mustWork = TRUE)),
    identical(digest::digest(file = path, algo = "sha256"), owned$sha256[[i]]))
}
evidence <- Sys.getenv("LISAR_LONGTEST_EVIDENCE", "")
if (nzchar(evidence)) {
  dir.create(evidence, recursive = TRUE, showWarnings = FALSE)
  utils::write.table(data.frame(working_directory = getwd(), runner_root = root,
    installed_package = find.package("lisaR"), file_argument = paste(file_arg, collapse = ";")),
    file.path(evidence, "longtests-route.tsv"), sep = "\t", row.names = FALSE)
}
args <- commandArgs(trailingOnly = TRUE)
files <- sort(list.files(file.path(root, "testthat"), pattern = "^test-.*[.]R$", full.names = TRUE))
if (length(args)) {
  stopifnot(length(args) == 1L, args %in% basename(files))
  files <- files[basename(files) == args]
}
env <- testthat::test_env("lisaR")
helpers <- sort(list.files(file.path(root, "testthat"), pattern = "^helper.*[.]R$", full.names = TRUE))
for (helper in helpers) sys.source(helper, envir = env)
failed <- FALSE
for (file in files) {
  result <- testthat::test_file(file, env = env, reporter = "summary")
  rows <- as.data.frame(result)
  # Preserve the full list-column evidence as RDS; never serialize it as TSV.
  evidence <- Sys.getenv("LISAR_LONGTEST_EVIDENCE", "")
  if (nzchar(evidence)) {
    dir.create(evidence, recursive = TRUE, showWarnings = FALSE)
    saveRDS(result, file.path(evidence, paste0(basename(file), ".rds")))
    utils::write.table(rows[, setdiff(names(rows), "result"), drop = FALSE],
      file.path(evidence, paste0(basename(file), ".tsv")), sep = intToUtf8(9L), quote = TRUE, row.names = FALSE)
  }
  failed <- failed || any(rows$failed > 0L) || any(rows$error)
}
if (failed) stop("Installed lisaR longtests had failed expectations or errors")
