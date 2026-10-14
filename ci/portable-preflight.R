# Native GitHub runner only. Parse new R files and execute real adversarial tests.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true",
  Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted",
  Sys.getenv("LISAR_REPOSITORY_PRIVATE") == "false", getRversion() == "4.6.1")
library(testthat)
root <- file.path(Sys.getenv("LISAR_VALIDATION_ROOT"), "input", "lisaR")
for (suite in c("tests", "longtests")) {
  helper <- file.path(root, suite, "testthat", "helper-portable-inference.R")
  tests <- file.path(root, suite, "testthat", "test-portable-inference.R")
  parse(file = helper); parse(file = tests)
  parse(file = file.path(root, suite, "testthat.R"))
  parse(file = file.path(root, suite, "testthat", "test-quick-start.R"))
  env <- new.env(parent = globalenv())
  sys.source(helper, envir = env)
  result <- testthat::test_file(tests, env = env, reporter = "summary")
  rows <- as.data.frame(result)
  stopifnot(nrow(rows) > 0L, !any(rows$failed > 0L), !any(rows$error), !any(rows$skipped))
}
cat("Native R portability comparator adversarial tests completed; not global package PASS\n")
