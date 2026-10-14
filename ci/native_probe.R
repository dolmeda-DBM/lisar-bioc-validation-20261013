# Inert until explicitly invoked on the authorized ephemeral public macOS runner.
# Diagnostic only: unchanged original synthetic 48-null fixture, never full PASS.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true",
  Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted",
  Sys.getenv("LISAR_REPOSITORY_PRIVATE") == "false",
  Sys.getenv("GITHUB_REPOSITORY") == "dolmeda-DBM/lisar-bioc-validation-20261013",
  Sys.info()[["sysname"]] == "Darwin", Sys.info()[["machine"]] == "arm64",
  getRversion() == "4.6.1", Sys.getenv("GITHUB_RUN_ATTEMPT") == "1")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, args[[1L]] %in% c("binary", "source-default", "source-strict-fp"))
variant <- args[[1L]]
output <- normalizePath(args[[2L]], mustWork = TRUE, winslash = "/")
root <- normalizePath(Sys.getenv("LISAR_VALIDATION_ROOT"), mustWork = TRUE, winslash = "/")
stopifnot(startsWith(output, paste0(root, "/probe/")))
manifest <- jsonlite::read_json("candidate/manifest.json", simplifyVector = TRUE)
stopifnot(identical(digest::digest(file = manifest$tarball, algo = "sha256", serialize = FALSE),
  "2759ef3ec395b6b55c0dfe16633bd304ce8b2e36b175cd3c7bbb8d73acce6815"),
  manifest$scientific_oracles$scientific_nulls == 48L,
  as.character(utils::packageVersion("BiocVersion")) == "3.24.0",
  as.character(utils::packageVersion("fgsea")) == "1.39.2",
  as.character(utils::packageVersion("hommel")) == "1.8")
pins <- c(fgsea = "1.39.2", hommel = "1.8", BH = "1.90.0-1", Rcpp = "1.1.2",
  BiocParallel = "1.47.0", data.table = "1.18.6.1", digest = "0.6.39", jsonlite = "2.0.0",
  SummarizedExperiment = "1.43.0", S4Arrays = "1.13.2", DelayedArray = "0.39.8", SparseArray = "1.13.4")
observed_versions <- vapply(names(pins), function(package)
  as.character(utils::packageVersion(package)), character(1))
observed_description_versions <- vapply(names(pins), function(package)
  utils::packageDescription(package, fields = "Version"), character(1))
version_matches <- stats::setNames(
  package_version(unname(observed_versions)) == package_version(unname(pins)), names(pins))
jsonlite::write_json(list(status = "VERSION_PIN_OBSERVATIONS_NOT_PACKAGE_PASS",
  variant = variant, repository = Sys.getenv("GITHUB_REPOSITORY"),
  run_id = Sys.getenv("GITHUB_RUN_ID"), head_sha = Sys.getenv("GITHUB_SHA"),
  raw_pins = as.list(pins),
  normalized_pins = as.list(stats::setNames(as.character(package_version(unname(pins))), names(pins))),
  observed_package_versions = as.list(observed_versions),
  observed_DESCRIPTION_versions = as.list(observed_description_versions),
  exact_package_version_matches = as.list(version_matches)),
  file.path(output, "version-observations.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
stopifnot(all(version_matches))
warnings_seen <- character()
failure <- NULL
result <- list(status = "DIAGNOSTIC_ONLY_NOT_FULL_NATIVE_PACKAGE_PASS",
  variant = variant, repository = Sys.getenv("GITHUB_REPOSITORY"),
  run_id = Sys.getenv("GITHUB_RUN_ID"), head_sha = Sys.getenv("GITHUB_SHA"),
  candidate_sha256 = manifest$tarball_sha256, execution_priority = "low",
  R = R.version.string, platform = R.version$platform,
  machine = .Machine, libraries = as.list(.libPaths()),
  makevars_user = Sys.getenv("R_MAKEVARS_USER"), full_check_pass_claimed = FALSE)
packages <- c("fgsea", "hommel", "BH", "Rcpp", "S4Arrays", "DelayedArray", "SparseArray", "SummarizedExperiment")
metadata <- lapply(packages, function(package) {
  location <- find.package(package)
  description <- utils::packageDescription(package)
  selected <- intersect(c("Package", "Version", "Built", "Repository", "Date/Publication",
    "git_url", "git_branch", "git_last_commit", "git_last_commit_date"), names(description))
  namespace <- file.path(location, "NAMESPACE")
  target <- file.path(output, paste0(package, "-NAMESPACE.txt"))
  stopifnot(file.copy(namespace, target, overwrite = FALSE))
  list(package = package, installed_path = location, description = unclass(description[selected]),
    namespace_sha256 = digest::digest(file = namespace, algo = "sha256", serialize = FALSE))
})
result$dependency_provenance <- metadata
jsonlite::write_json(result, file.path(output, "intent.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
tryCatch(withCallingHandlers({
  # Observe the import warning in a fresh R process; never muffle it or preload
  # the namespace outside the captured diagnostic boundary to hide it from tests.
  stopifnot(requireNamespace("SummarizedExperiment", quietly = TRUE))
  capture.output(str(getNamespaceImports("SummarizedExperiment")),
    file = file.path(output, "SummarizedExperiment-imports.txt"))
  capture.output(get("makeNindexFromArrayViewport", envir = asNamespace("SummarizedExperiment")),
    file = file.path(output, "makeNindexFromArrayViewport-effective-binding.txt"))
  result$effective_binding_identical_to_DelayedArray <- identical(
    get("makeNindexFromArrayViewport", envir = asNamespace("SummarizedExperiment")),
    getExportedValue("DelayedArray", "makeNindexFromArrayViewport"))
  stopifnot(requireNamespace("lisaR", quietly = TRUE),
    as.character(utils::packageVersion("lisaR")) == "0.99.0")
  fixture <- file.path(root, "input", "lisaR", "longtests", "testthat", "fixtures", "installation-smoke")
  expected <- file.path(fixture, "category-inference-original.tsv")
  golden <- "8eace6d85f431d936cfd43cda3bfb424e321e0c336c868fe4ea1ec7f206acb6b"
  stopifnot(identical(digest::digest(file = expected, algo = "sha256", serialize = FALSE), golden),
    identical(digest::digest(file = file.path(fixture, "study.yml"), algo = "sha256", serialize = FALSE),
      "4abaead1d622f562bbc2aa8ec85c02a470bcdcfc6cfcbd2fb1c8ef849993ef61"),
    identical(digest::digest(file = file.path(fixture, "de.tsv"), algo = "sha256", serialize = FALSE),
      "de71dcadf07dc9b939d5114aa86d0e3217b37f34b24ae671c733d8fa558bff25"))
  project <- file.path(output, "project")
  stopifnot(!dir.exists(project))
  dir.create(project)
  stopifnot(all(file.copy(list.files(fixture, full.names = TRUE), project, overwrite = FALSE)))
  run <- lisaR::run_lisa(file.path(project, "study.yml"))
  result$internal_run_gate <- lisaR::verify_lisa_run(run$output_dir)$gate
  family_root <- file.path(run$output_dir, "outputs", "category_inference", "installation_smoke")
  actual <- file.path(run$output_dir, "outputs", "single_de", "installation_smoke",
    "collection_GOBP-C2", "lisa_tables", "installation_smoke_LISA_category_inference.tsv")
  files <- c(actual = actual, expected = expected,
    raw = file.path(family_root, "raw_results.tsv"),
    family = file.path(family_root, "hypothesis_family.tsv"),
    category = file.path(family_root, "category_results.tsv"), method = file.path(family_root, "method.json"))
  result$files <- lapply(names(files), function(name) {
    source <- files[[name]]
    stopifnot(file.info(source)$size <= 1024^2)
    target <- file.path(output, paste0(name, if (name == "method") ".json" else ".tsv"))
    stopifnot(file.copy(source, target, overwrite = FALSE))
    list(name = name, path = basename(target), bytes = file.info(target)$size,
      sha256 = digest::digest(file = target, algo = "sha256", serialize = FALSE))
  })
  method <- jsonlite::read_json(files[["method"]])
  result$family_size <- method$family_size
  result$exact_original_oracle_match <- identical(digest::digest(file = actual, algo = "sha256", serialize = FALSE), golden)
}, warning = function(condition) {
  warnings_seen <<- c(warnings_seen, conditionMessage(condition))
  # Intentionally no muffleWarning restart: retain the original warning output.
}), error = function(condition) failure <<- conditionMessage(condition))
result$warnings <- as.list(warnings_seen)
result$failure <- failure
capture.output(sessionInfo(), file = file.path(output, "sessionInfo.txt"))
jsonlite::write_json(result, file.path(output, "result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA, null = "null")
quit(save = "no", status = if (is.null(failure) && !length(warnings_seen) &&
  isTRUE(result$exact_original_oracle_match) && identical(as.integer(result$family_size), 48L) &&
  identical(result$internal_run_gate, "PASS")) 0L else 1L)
