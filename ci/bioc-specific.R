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
  # Must be a separately reviewed maintained-source tree. Never the built tar export.
  workspace <- Sys.getenv("GITHUB_WORKSPACE")
  proof_path <- file.path(workspace, "candidate", "maintained-source-manifest.json")
  stopifnot(file.exists(proof_path))
  proof <- jsonlite::read_json(proof_path, simplifyVector = TRUE)
  stopifnot(identical(proof$candidate_sha256, manifest$tarball_sha256),
            identical(proof$status, "MAINTAINED_SOURCE_IDENTITY_PARENT_REVIEWED"))
  source <- file.path(workspace, "maintained-source")
  stopifnot(dir.exists(source), !dir.exists(file.path(source, ".git")))
  actual <- sort(list.files(source, recursive = TRUE, all.files = TRUE,
                            no.. = TRUE, include.dirs = FALSE))
  stopifnot(identical(actual, sort(proof$files$path)), !any(nzchar(Sys.readlink(file.path(source, actual)))))
  for (i in seq_len(nrow(proof$files))) {
    row <- proof$files[i, ]
    stopifnot(identical(digest::digest(file = file.path(source, row$path), algo = "sha256", serialize = FALSE), row$sha256))
  }
  # Do not mutate the checkout: initialize a fresh copy, then make the actual clone.
  repository <- file.path(getwd(), "reviewed-source-repository")
  stopifnot(!file.exists(repository), dir.create(repository))
  for (path in actual) {
    target <- file.path(repository, path)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(file.path(source, path), target, overwrite = FALSE))
  }
  git <- function(args) stopifnot(system2(Sys.which("git"), args) == 0L)
  git(c("-C", shQuote(repository), "init"))
  git(c("-C", shQuote(repository), "config", "core.autocrlf", "false"))
  git(c("-C", shQuote(repository), "add", "--all"))
  git(c("-C", shQuote(repository), "-c", "user.name=Validation", "-c", "user.email=validation@example.invalid", "commit", "-m", "Reviewed-maintained-source"))
  package <- file.path(getwd(), "clone")
  git(c("clone", "--no-hardlinks", shQuote(repository), shQuote(package)))
  for (i in seq_len(nrow(proof$files))) {
    row <- proof$files[i, ]
    stopifnot(identical(digest::digest(file = file.path(package, row$path), algo = "sha256", serialize = FALSE), row$sha256))
  }
  file.copy(proof_path, "maintained-source-manifest.json", overwrite = FALSE)

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
