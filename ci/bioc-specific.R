# Actual full online BiocCheck APIs. No offline exclusions or submission.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true", Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted")
mode <- commandArgs(trailingOnly = TRUE)[[1L]]
stopifnot(mode %in% c("GitClone", "BiocCheck"))
root <- Sys.getenv("LISAR_VALIDATION_ROOT")
manifest <- jsonlite::read_json(file.path(Sys.getenv("GITHUB_WORKSPACE"), "candidate", "manifest.json"), simplifyVector = TRUE)
tarball <- file.path(Sys.getenv("GITHUB_WORKSPACE"), manifest$tarball)
stopifnot(identical(digest::digest(file = tarball, algo = "sha256", serialize = FALSE), manifest$tarball_sha256))
package <- tarball
if (mode == "GitClone") {
  # An actual local Git clone of the exact exported candidate, not the CI wrapper.
  source <- file.path(root, "input", "lisaR")
  git <- function(args) stopifnot(system2(Sys.which("git"), args) == 0L)
  git(c("-C", shQuote(source), "init"))
  git(c("-C", shQuote(source), "config", "core.autocrlf", "false"))
  git(c("-C", shQuote(source), "add", "--all"))
  git(c("-C", shQuote(source), "-c", "user.name=Validation", "-c", "user.email=validation@example.invalid", "commit", "-m", "Exact-candidate"))
  package <- file.path(getwd(), "clone")
  git(c("clone", "--no-hardlinks", shQuote(source), shQuote(package)))
  for (i in seq_len(nrow(manifest$archive_files))) {
    row <- manifest$archive_files[i, ]
    stopifnot(identical(digest::digest(file = file.path(package, row$path), algo = "sha256", serialize = FALSE), row$sha256))
  }
}
error <- NULL
value <- tryCatch(if (mode == "GitClone") BiocCheck::BiocCheckGitClone(package = package)
  else BiocCheck::BiocCheck(package = package, checkDir = getwd(), callr = FALSE),
  error = function(e) { error <<- conditionMessage(e); NULL })
saveRDS(value, "actual-result.rds")
object <- if (!is.null(value)) value else tryCatch(get(".BiocCheck", envir = asNamespace("BiocCheck")), error = function(e) NULL)
counts <- if (!is.null(object)) tryCatch(setNames(lapply(c("error", "warning", "note"), object$getNum),
  c("errors", "warnings", "notes")), error = function(e) list(count_query_error = conditionMessage(e))) else NULL
if (!is.null(object)) capture.output(print(object), file = "object.txt")
jsonlite::write_json(list(mode = mode, error = error, counts = counts,
  BiocCheck_version = as.character(packageVersion("BiocCheck")),
  candidate_sha256 = manifest$tarball_sha256, excluded_checks = character(),
  submission = FALSE, readiness_pass_claimed = FALSE), "diagnostics.json", auto_unbox = TRUE, pretty = TRUE, null = "null")
stopifnot(is.null(error), !is.null(counts), is.numeric(counts$errors), is.numeric(counts$warnings),
  counts$errors == 0, counts$warnings == 0)
