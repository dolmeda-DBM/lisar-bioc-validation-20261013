# Native-only non-scientific contract test of trace frame/default/return handling.
root <- normalizePath(Sys.getenv("LISAR_VALIDATION_ROOT"), mustWork = TRUE)
path <- file.path(root, "probe6", "capture-contract")
stopifnot(!file.exists(path), dir.create(path))
Sys.setenv(LISAR_PROBE6_TRACE_DIR = path)
source("ci/probe6_capture.R", local = globalenv()) # Includes full native guard.
f <- function(enrichmentScores, ranks, pathwaySize, sampleSize, seed, eps, sign,
              moveScale = 1.0, logStatus = FALSE) {
  data.frame(cppMPval = 0.25, cppIsCpGeHalf = TRUE, log2err = 0.5)
}
inputs <- list(enrichmentScores = 0.25, ranks = c(2L, 1L), pathwaySize = 1L,
  sampleSize = 101L, seed = 17L, eps = 0, sign = FALSE)
expected <- do.call(f, inputs)
trace("f", where = globalenv(), print = FALSE,
  tracer = quote(get("lisar_probe6_cpp_entry", envir = globalenv())(environment())),
  exit = quote(get("lisar_probe6_cpp_exit", envir = globalenv())(environment(), returnValue())))
observed <- do.call(f, inputs)
untrace("f", where = globalenv())
stopifnot(identical(expected, observed), !nzchar(Sys.getenv("LISAR_PROBE6_CALL_DIR")))
calls <- list.dirs(path, recursive = FALSE, full.names = TRUE)
stopifnot(length(calls) == 1L, identical(readRDS(file.path(calls, "return.rds")), expected),
  identical(readRDS(file.path(calls, "input.rds")), c(inputs, list(moveScale = 1, logStatus = FALSE))))
jsonlite::write_json(list(status = "NATIVE_OBSERVER_CONTRACT_ONLY_NOT_SCIENTIFIC_PASS",
  frame_and_missing_defaults_captured = TRUE, return_unchanged = TRUE,
  previous_environment_restored = TRUE, no_fgsea_calculation = TRUE,
  head_sha = Sys.getenv("GITHUB_SHA"), run_id = Sys.getenv("GITHUB_RUN_ID")),
  file.path(path, "contract-result.json"), pretty = TRUE, auto_unbox = TRUE)
