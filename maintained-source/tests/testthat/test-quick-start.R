skip_unless_installed_lisar <- function() {
  loaded_root <- system.file(package = "lisaR")
  skip_if_not(
    nzchar(loaded_root) &&
      file.exists(file.path(loaded_root, "DESCRIPTION")) &&
      file.exists(file.path(loaded_root, "Meta", "package.rds")),
    "requires an installed lisaR tree, not a pkgload source namespace"
  )
}

expect_lisa_parallel_contract <- function(output_dir, workers_requested) {
  path <- file.path(output_dir, "parallel_execution.tsv")
  expect_true(file.exists(path))
  execution <- utils::read.delim(
    path, check.names = FALSE, stringsAsFactors = FALSE
  )
  required <- c(
    "platform", "backend_effective", "workers_requested", "workers_effective"
  )
  expect_gt(nrow(execution), 0L)
  expect_true(all(required %in% names(execution)))
  runtime_platform <- lisaR:::lisa_runtime_platform()
  requested <- as.integer(execution$workers_requested)
  effective <- as.integer(execution$workers_effective)
  backend <- as.character(execution$backend_effective)
  expect_true(all(execution$platform == runtime_platform))
  expect_true(all(requested == as.integer(workers_requested)))
  expect_true(all(effective >= 1L & effective <= requested))
  if (identical(runtime_platform, "linux")) {
    expected_backend <- ifelse(effective > 1L, "multicore", "sequential")
    expect_identical(backend, unname(expected_backend))
  } else {
    expect_true(all(effective == 1L))
    expect_true(all(backend == "sequential"))
  }
  invisible(execution)
}

test_that("sample-project initializer is additive and preserves existing paths", {
  target <- tempfile("lisaR-quick-start-")
  project <- lisa_init_project(target)
  expect_identical(project, normalizePath(target, winslash = "/"))
  expect_true(file.exists(file.path(project, "study.yml")))
  expect_true(file.exists(file.path(project, "data", "de_a.tsv")))
  expect_true(file.exists(file.path(project, "data", "de_b.tsv")))
  expect_true(file.exists(file.path(project, "data", "expr.tsv")))
  config <- yaml::read_yaml(file.path(project, "study.yml"))
  expect_identical(config$pipeline$schema_version, "1.0.0")
  expect_identical(config$pipeline$dictionary_resource, "lisa_dictionary_quickstart@1.1.0")
  expect_identical(config$report$mode, "standard")
  expect_identical(
    unlist(config$report$category_nes_variants, use.names = FALSE),
    c("clean", "percentages", "direction", "dispersion")
  )
  expect_error(lisa_init_project(target), "will not overwrite")

  occupied <- tempfile("lisaR-quick-start-occupied-")
  dir.create(occupied)
  writeLines("preserve", file.path(occupied, "user-file.txt"))
  expect_error(lisa_init_project(occupied), "will not overwrite")
  expect_identical(readLines(file.path(occupied, "user-file.txt")), "preserve")
})

test_that("sample-project initializer preserves an explicit parent", {
  fake_home <- tempfile("lisaR-quick-home-")
  dir.create(fake_home)
  on.exit(unlink(fake_home, recursive = TRUE, force = TRUE), add = TRUE)
  if (.Platform$OS.type != "windows") Sys.chmod(fake_home, "0755")
  home_mode <- as.integer(file.info(fake_home)$mode)
  project <- lisa_init_project(file.path(fake_home, "sample-project"))
  expect_true(file.exists(file.path(project, "study.yml")))
  expect_identical(dirname(project), normalizePath(fake_home, winslash = "/"))
  expect_identical(as.integer(file.info(fake_home)$mode), home_mode)
})

test_that("a fresh R process resolves a tilde child from startup HOME", {
  skip_unless_installed_lisar()
  fake_home <- tempfile("lisaR-startup-home-")
  dir.create(fake_home)
  on.exit(lisa_test_cleanup_path(fake_home), add = TRUE)
  child_script <- tempfile("lisaR-startup-home-", fileext = ".R")
  on.exit(unlink(child_script, force = TRUE), add = TRUE)
  writeLines(c(
    "library(lisaR)",
    paste0(
      "cat('LISAR_PACKAGE_ROOT=', normalizePath(system.file(package = ",
      "'lisaR'), winslash = '/', mustWork = TRUE), '\\n', sep = '')"
    ),
    "project <- lisa_init_project('~/child')",
    paste0(
      "cat('LISAR_HOME_CHILD=', normalizePath(project, winslash = '/', ",
      "mustWork = TRUE), '\\n', sep = '')"
    )
  ), child_script, useBytes = TRUE)

  library_value <- paste(unique(.libPaths()), collapse = .Platform$path.sep)
  withr::local_envvar(c(
    HOME = fake_home,
    R_USER = fake_home,
    R_LIBS = library_value
  ))
  output <- suppressWarnings(system2(
    lisaR:::lisa_rscript_executable(),
    c("--vanilla", shQuote(child_script)),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  expect_identical(status, 0L, info = paste(output, collapse = "\n"))

  package_line <- grep("^LISAR_PACKAGE_ROOT=", output, value = TRUE)
  child_line <- grep("^LISAR_HOME_CHILD=", output, value = TRUE)
  expect_length(package_line, 1L)
  expect_length(child_line, 1L)
  expect_identical(
    sub("^LISAR_PACKAGE_ROOT=", "", package_line),
    normalizePath(system.file(package = "lisaR"), winslash = "/",
                  mustWork = TRUE)
  )
  expect_identical(
    sub("^LISAR_HOME_CHILD=", "", child_line),
    normalizePath(file.path(fake_home, "child"), winslash = "/",
                  mustWork = TRUE)
  )
})

test_that("installation smoke stays temporary and has no visible installed example", {
  skip_unless_installed_lisar()
  fixture <- testthat::test_path("fixtures", "installation-smoke")
  project <- tempfile("lisaR-installation-smoke-")
  dir.create(project)
  expect_true(all(file.copy(list.files(fixture, full.names = TRUE), project)))
  config <- file.path(project, "study.yml")
  raw_config <- yaml::read_yaml(config)
  expect_identical(raw_config$report$mode, "standard")
  expect_identical(unlist(raw_config$collections, use.names = FALSE), "GOBP-C2")
  expect_true(isTRUE(raw_config$report$formats$png))
  expect_true(isTRUE(raw_config$report$source_data))
  expect_true(validate_lisa_config(config)$valid)
  result <- suppressWarnings(run_lisa(config))
  expect_identical(verify_lisa_run(result$output_dir)$gate, "PASS")
  expect_false(nzchar(system.file("examples", "installation-smoke", package = "lisaR")))
  family_root <- file.path(result$output_dir, "outputs", "category_inference", "installation_smoke")
  family <- lisaR:::read_lisa_tsv(file.path(family_root, "category_results.tsv"))
  method <- jsonlite::read_json(file.path(family_root, "method.json"))
  expect_identical(unique(as.character(family$analysis_id)), "installation_smoke")
  expect_length(unique(as.character(family$family_id)), 1L)
  expect_true(all(family$family_size == 12L))
  expect_identical(as.integer(method$family_size), 12L)
  expect_setequal(unique(as.character(family$collection)), "GOBP-C2")
  expect_setequal(unlist(method$collections, use.names = FALSE), "GOBP-C2")
  expect_identical(unique(as.character(family$family_scope)),
    "All eligible unique gene-set nulls across configured LISA category collections within one DE analysis; HALLMARKS excluded")
})


test_that("custom category macrogroups receive a deterministic fallback palette", {
  category_map <- data.frame(
    category_id = c("CUSTOM_A", "CUSTOM_B"),
    macrogroup_id = c("CUSTOM_GROUP", "CUSTOM_GROUP"),
    stringsAsFactors = FALSE
  )
  colours <- lisaR:::build_lisa_palette(category_map, "lisa_default")
  expect_length(colours, 2L)
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}$", colours)))
})
