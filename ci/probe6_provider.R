# Fresh-process baseline/derived import observation. Never suppress warnings.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true",
  Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted",
  Sys.getenv("LISAR_REPOSITORY_PRIVATE") == "false",
  Sys.getenv("GITHUB_REPOSITORY") == "dolmeda-DBM/lisar-bioc-validation-20261013",
  Sys.getenv("GITHUB_RUN_ATTEMPT") == "1", Sys.getenv("GITHUB_SHA") == Sys.getenv("EXPECTED_HEAD_SHA"), Sys.info()[["sysname"]] == "Darwin",
  Sys.info()[["machine"]] == Sys.getenv("LISAR_EXPECTED_ARCH"), getRversion() == "4.6.1",
  !"SummarizedExperiment" %in% loadedNamespaces())
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, args[[1L]] %in% c("baseline", "derived"))
mode <- args[[1L]]
output <- normalizePath(args[[2L]], mustWork = TRUE)
root <- normalizePath(Sys.getenv("LISAR_VALIDATION_ROOT"), mustWork = TRUE)
stopifnot(startsWith(output, paste0(root, "/probe6/")))
warnings_seen <- character()
failure <- NULL
result <- list(status = "IMPORT_PROVIDER_DIAGNOSTIC_NOT_PACKAGE_PASS", mode = mode,
  process_id = Sys.getpid(), R = R.version.string, libraries = as.list(.libPaths()),
  head_sha = Sys.getenv("GITHUB_SHA"), run_id = Sys.getenv("GITHUB_RUN_ID"),
  execution_priority = "low", fresh_process_before_load = TRUE)
tryCatch(withCallingHandlers({
  stopifnot(identical(utils::packageDescription("BH")$Version, "1.90.0-1"),
    identical(utils::packageDescription("fgsea")$Version, "1.39.2"),
    identical(utils::packageDescription("fgsea")$git_last_commit, "31cb676"))
  result$BH_include <- normalizePath(system.file("include", package = "BH"), mustWork = TRUE)
  result$fgsea_upstream_description <- unclass(utils::packageDescription("fgsea")[
    c("Package", "Version", "Built", "git_last_commit")])
  expected <- if (mode == "baseline")
    "c3b7b22f11e4c2210c4d53b7d8c1d1c135c8b2d48082ac8cf6ebe7534dc8be57" else
    "67fa14850d505e0eccd114b01fe89c406884a1cde90156016f3b4b331c84df4f"
  description <- utils::packageDescription("SummarizedExperiment")
  stopifnot(identical(description$Version, "1.43.0"),
    identical(description$git_last_commit, "ffe9db3"),
    identical(digest::digest(file = file.path(find.package("SummarizedExperiment"), "NAMESPACE"),
      algo = "sha256", serialize = FALSE), expected),
    requireNamespace("SummarizedExperiment", quietly = TRUE))
  result$description <- unclass(description[c("Package", "Version", "Built", "License", "git_last_commit")])
  result$namespace_sha256 <- expected
  capture.output(str(getNamespaceImports("SummarizedExperiment")),
    file = file.path(output, "imports.txt"))
  binding <- get("makeNindexFromArrayViewport", envir = asNamespace("SummarizedExperiment"))
  result$effective_binding_identical_to_DelayedArray <- identical(binding,
    getExportedValue("DelayedArray", "makeNindexFromArrayViewport"))
  stopifnot(isTRUE(result$effective_binding_identical_to_DelayedArray))
  capture.output(binding, file = file.path(output, "effective-binding.txt"))
  result$effective_binding_sha256 <- digest::digest(binding, algo = "sha256")
}, warning = function(condition) {
  warnings_seen <<- c(warnings_seen, conditionMessage(condition))
  # No muffleWarning/suppressWarnings or warn=0: original warning reaches stderr.
}), error = function(condition) failure <<- conditionMessage(condition))
result$warnings <- as.list(warnings_seen)
result["failure"] <- list(failure) # Preserve an explicit null key on success.
capture.output(sessionInfo(), file = file.path(output, "sessionInfo.txt"))
jsonlite::write_json(result, file.path(output, "provider-result.json"), pretty = TRUE,
  auto_unbox = TRUE, digits = NA, null = "null")
quit(save = "no", status = if (is.null(failure) &&
  (mode == "baseline" || !length(warnings_seen))) 0L else 1L)
