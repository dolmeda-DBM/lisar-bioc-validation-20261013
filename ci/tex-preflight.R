# CI-only native PDF/index toolchain check. No tests or package edits.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true",
  Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted",
  Sys.getenv("GITHUB_REPOSITORY") == "dolmeda-DBM/lisar-bioc-validation-20261013",
  Sys.getenv("GITHUB_RUN_ATTEMPT") == "1", getRversion() == "4.6.1")
root <- Sys.getenv("LISAR_VALIDATION_ROOT")
stopifnot(dir.exists(root))
# Verify the effective R temporary directory, not merely environment strings.
expected_tmp <- normalizePath(file.path(root, "p"), winslash = "/", mustWork = TRUE)
actual_tmp <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
stopifnot(startsWith(actual_tmp, paste0(expected_tmp, "/")))
if (.Platform$OS.type == "windows") {
  stopifnot(identical(Sys.getenv("R_TEXI2DVICMD"), "emulation"))
}
commands <- Sys.which(c("pdflatex", "makeindex", "texi2dvi", "kpsewhich", "bibtex"))
stopifnot(nzchar(commands[["pdflatex"]]), nzchar(commands[["makeindex"]]))
pdf <- file.path(root, "manual-preflight.pdf")
stopifnot(!file.exists(pdf))
args <- c("CMD", "Rd2pdf", "--no-preview", "--no-clean",
  paste0("--output=", shQuote(pdf)), shQuote(file.path(root, "input", "lisaR")))
receipt <- list(status = "PREFLIGHT_INTENT_NOT_PACKAGE_PASS", argv = args,
  R = R.version.string, commands = as.list(commands),
  R_TEXI2DVICMD = Sys.getenv("R_TEXI2DVICMD"),
  temporary = tempdir(), temporary_environment = as.list(Sys.getenv(c("TMPDIR", "TMP", "TEMP"))))
jsonlite::write_json(receipt, file.path(root, "tex-preflight.json"), auto_unbox = TRUE, pretty = TRUE)
diagnostics <- file.path(root, "tex-diagnostics")
stopifnot(!dir.exists(diagnostics))
dir.create(diagnostics)
status <- system2(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"), args)
diagnostic_files <- list.files(tempdir(), pattern = "\\.(log|tex|idx|ind|ilg|aux|out)$", recursive = TRUE, full.names = TRUE)
for (path in diagnostic_files) {
  relative <- substring(path, nchar(tempdir()) + 2L)
  target <- file.path(diagnostics, relative)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  stopifnot(file.copy(path, target, overwrite = FALSE))
}
receipt$returncode <- status
receipt$pdf_exists <- file.exists(pdf)
receipt$pdf_bytes <- if (file.exists(pdf)) unname(file.info(pdf)$size) else 0
receipt$status <- if (identical(status, 0L) && receipt$pdf_bytes > 0) "PDF_PREFLIGHT_PASS_NOT_PACKAGE_PASS" else "PDF_PREFLIGHT_FAILED"
jsonlite::write_json(receipt, file.path(root, "tex-preflight.json"), auto_unbox = TRUE, pretty = TRUE)
stopifnot(identical(status, 0L), file.exists(pdf), file.info(pdf)$size > 0)
