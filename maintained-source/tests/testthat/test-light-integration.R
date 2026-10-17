# Genuinely light integration: installed resource resolution, initializer,
# config validation and output estimation. No run_lisa, GSEA, plots or workers.
test_that("a temporary project validates and estimates one collection without execution", {
  root <- withr::local_tempdir("lisa-light-integration-")
  project <- lisa_init_project(file.path(root, "project"))
  config_path <- file.path(project, "study.yml")
  config <- yaml::read_yaml(config_path)
  config$collections <- list("GOBP-C2")
  config$pipeline$workers <- 1L
  yaml::write_yaml(config, config_path)
  validated <- validate_lisa_config(config_path)
  expect_true(validated$valid)
  expect_identical(validated$analyses, 2L)
  expect_identical(validated$contrasts, 1L)
  estimate <- plan_lisa_outputs(config_path)
  expect_true(is.data.frame(estimate$summary))
  expect_true(nrow(estimate$summary) > 0L)
  expect_true(is.data.frame(estimate$policy))
  expect_false(dir.exists(file.path(project, "out")))
  expect_length(list.files(project, pattern = "run_manifest[.]tsv$", recursive = TRUE), 0L)
})
