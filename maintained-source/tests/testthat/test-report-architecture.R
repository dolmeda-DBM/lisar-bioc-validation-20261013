report_architecture_config <- function(mode = "standard", formats = list(png = TRUE, svg = FALSE, pdf = FALSE),
                                       source_data = TRUE, recipes = FALSE) {
  list(
    pipeline = list(
      schema_version = "1.0.0", profile = "targeted", evidence_mode = "full_de",
      run_kegg_maps = FALSE,
      duplicate_policies = list(
        de_table_duplicate_policy = "error", matrix_duplicate_policy = "error",
        mapped_id_collision_policy = "error"
      )
    ),
    collections = list("GOBP-C2", "GOMF"),
    single_de = list(list(analysis_id = "A", de_path = "a.tsv", species = "Homo sapiens"),
                     list(analysis_id = "B", de_path = "b.tsv", species = "Homo sapiens")),
    contrasts = list(list(contrast_id = "A_vs_B", analysis_a = "A", analysis_b = "B")),
    report = list(mode = mode, formats = formats, source_data = source_data, recipes = recipes)
  )
}

make_report_architecture_run <- function() {
  root <- tempfile("lisaR-extension-source-")
  collection <- file.path(root, "outputs", "single_de", "A", "collection_GOBP-C2")
  dir.create(file.path(collection, "lisa_tables"), recursive = TRUE)
  dir.create(file.path(collection, "enrichment"), recursive = TRUE)
  dir.create(file.path(collection, "inputs"), recursive = TRUE)
  dir.create(file.path(root, "config"), recursive = TRUE)

  categories <- data.frame(
    category_id = c("CAT_A", "CAT_B"), macrogroup_id = c("SUPER_1", "SUPER_1"),
    category_display_name = c("Category A", "Category B"), macrogroup_name = "Super one",
    macrogroup_order = 1, category_order_within_macrogroup = 1:2,
    n_genesets = 1, color = c("#0072B2", "#D55E00"), stringsAsFactors = FALSE
  )
  gsea <- data.frame(
    pathway = c("KEGG_ALPHA", "GO_BETA"), padj = c(0.01, 0.02), NES = c(1.5, -1.2),
    category_id = categories$category_id, macrogroup_id = categories$macrogroup_id,
    category_display_name = categories$category_display_name,
    macrogroup_name = categories$macrogroup_name, macrogroup_order = 1,
    category_order_within_macrogroup = 1:2, color = categories$color,
    stringsAsFactors = FALSE
  )
  lisaR:::write_lisa_tsv(categories,
    file.path(collection, "lisa_tables", "A_semantic_GSEA_category_summary.tsv"))
  lisaR:::write_lisa_tsv(gsea,
    file.path(collection, "enrichment", "A_GSEA_semantic_annotated.tsv"))
  # A symbol-only table deliberately makes gene-level products inapplicable;
  # this fixture exercises the real canonical-table category renderer only.
  lisaR:::write_lisa_tsv(data.frame(symbol = c("G1", "G2")),
    file.path(collection, "inputs", "A_standardized_DE.tsv"))
  lisaR:::write_lisa_tsv(data.frame(analysis_id = "A", species = "Homo sapiens"),
    file.path(root, "config", "de_index.tsv"))
  lisaR:::write_lisa_tsv(data.frame(contrast_id = "A_vs_B", output_id = "profile",
    contrast_a = "A", contrast_b = "B", label_a = "Analysis A", label_b = "Analysis B"),
    file.path(root, "config", "contrast_index.tsv"))
  contrast_dir <- file.path(root, "outputs", "category_contrasts", "A_vs_B_profile",
    "collection_GOBP-C2", "lisa_tables")
  dir.create(contrast_dir, recursive = TRUE)
  lisaR:::write_lisa_tsv(data.frame(
    category_id = c("CAT_A", "CAT_B"), category_display_name = c("Category A", "Category B"),
    macrogroup_id = "SUPER_1", macrogroup_name = "Super one",
    contrast_a_label = "Analysis A", contrast_b_label = "Analysis B",
    mean_NES_A = c(1.5, -1.2), mean_NES_B = c(-0.4, -0.8),
    stringsAsFactors = FALSE),
    file.path(contrast_dir, "profile_semantic_GSEA_category_contrast.tsv"))
  contract <- lisa_test_run_contract()
  lisaR:::write_lisa_tsv(
    data.frame(
      key = names(contract), value = unname(contract),
      stringsAsFactors = FALSE
    ),
    file.path(root, "run_contract.tsv")
  )
  manifest <- lisaR:::lisa_run_manifest(root)
  lisaR:::write_lisa_tsv(manifest, file.path(root, "run_manifest.tsv"))
  lisaR:::write_lisa_tsv(data.frame(event = "validated", stringsAsFactors = FALSE),
    file.path(root, "run_events.tsv"))
  root
}

extension_selection <- function(mode, categories = NULL, formats = list(png = TRUE, svg = FALSE, pdf = FALSE),
                                source_data = TRUE, recipes = FALSE,
                                products = "member_gene_sets", contrasts = NULL) {
  selection <- list(mode = mode, products = products)
  if (!is.null(categories)) selection$categories <- categories
  if (!is.null(contrasts)) selection$contrasts <- contrasts
  list(selection = selection,
    report = list(mode = mode, formats = formats, source_data = source_data, recipes = recipes))
}

test_that("standard estimator is bounded and full warns before execution", {
  standard <- plan_lisa_outputs(report_architecture_config("standard"),
    category_counts = c(`GOBP-C2` = 500, GOMF = 500))
  expect_identical(standard$summary$expected_figure_files, 5070L)
  expect_identical(standard$summary$selected_categories, 0L)
  expect_identical(standard$summary$member_gene_set_categories, 0L)
  expect_true(all(c("lisa_overview", "lisa_direction_overview", "gene_set_overview", "category_evidence", "category_member_evidence",
    "category_navigation", "gene_evidence", "contrast_category_evidence",
    "category_nes_clean", "category_nes_percentages", "category_nes_direction", "category_nes_dispersion") %in% standard$products$product))
  expect_identical(standard$summary$category_nes_variant_figures, 40L)
  expect_identical(standard$summary$contrast_evidence_categories, 1000L)
  expect_identical(standard$summary$category_evidence_categories, 2000L)
  expect_identical(standard$summary$category_member_evidence_categories, 2000L)
  legacy_config <- report_architecture_config("standard")
  legacy_config$report$category_evidence <- FALSE
  legacy <- plan_lisa_outputs(legacy_config,
    category_counts = c(`GOBP-C2` = 500, GOMF = 500))
  expect_identical(legacy$summary$expected_figure_files, 2064L)
  expect_match(standard$summary$warning, "one evidence matrix per applicable LISA category")

  full <- plan_lisa_outputs(report_architecture_config("full"),
    category_counts = c(`GOBP-C2` = 500, GOMF = 500))
  expect_gt(full$summary$expected_figure_files, standard$summary$expected_figure_files)
  expect_match(full$summary$warning, "thousands of figures")
  expect_true(all(c("kegg", "contrast_profile", "contrast_heatmap") %in% full$products$product))
  expect_true("gene_cards" %in% full$products$product)
  legacy_full_config <- report_architecture_config("full")
  legacy_full_config$report$legacy_gene_products <- TRUE
  expect_true("gene_cards" %in% plan_lisa_outputs(legacy_full_config)$products$product)
})

test_that("selected is only available as an extension of a completed run", {
  expect_error(
    plan_lisa_outputs(report_architecture_config("selected")),
    "not a study report mode|must be created from a completed standard run"
  )
})

test_that("extension index preserves URL path separators", {
  report_root <- tempfile("lisaR-extension-index-")
  dir.create(report_root)
  lisaR:::lisa_extension_write_index(
    report_root,
    list(mode = "full", source_run = tempfile("source-run-")),
    data.frame(path = "artifacts/space dir/plot #1.png", stringsAsFactors = FALSE)
  )
  html <- paste(readLines(file.path(report_root, "index.html"), warn = FALSE), collapse = "\n")
  # This inventory carries no category sidecar, so the asset is unclassified
  # and rendered as a download link rather than an inline <img>; the encoding
  # contract under test applies identically to either attribute.
  expect_match(html, 'href="artifacts/space%20dir/plot%20%231.png"', fixed = TRUE)
  expect_false(grepl("%2F", html, fixed = TRUE))

  expect_identical(
    lisaR:::lisa_extension_url_path(c(
      "artifacts/a%2Fb.png",
      "artifacts\\café & \"<.png"
    )),
    c(
      "artifacts/a%252Fb.png",
      "artifacts/caf%C3%A9%20%26%20%22%3C.png"
    )
  )
})

test_that("standard plots include member gene sets for semantic collections", {
  semantic <- lisaR:::lisa_collection_registry("GOBP-C2")
  hallmarks <- lisaR:::lisa_collection_registry("HALLMARKS")
  expect_identical(lisaR:::lisa_plots_for_collection(semantic, "standard"),
    c("lollipop", "direction_lollipop", "dotplot", "barplot", "category_pathways"))
  expect_identical(lisaR:::lisa_plots_for_collection(hallmarks, "standard"),
    "lollipop")
})


test_that("unknown selections suggest valid IDs", {
  source <- make_report_architecture_run()
  expect_error(
    plan_lisa_extension(source, extension_selection("selected", "CAT_C")),
    "Nearest valid ID.*CAT_A|CAT_B"
  )
})



test_that("interrupted staging is cleaned without touching canonical files", {
  source <- make_report_architecture_run()
  before <- lisaR:::lisa_run_manifest(source)
  out <- tempfile("lisaR-interrupted-")
  testthat::local_mocked_bindings(
    write_lisa_gsea_category_pathway_plots = function(...) stop("injected renderer interruption"),
    .package = "lisaR"
  )
  expect_error(render_lisa_categories(source,
    extension_selection("selected", "CAT_A"), out), "injected renderer interruption")
  expect_false(dir.exists(out))
  expect_false(any(grepl(paste0("[.]", basename(out), "[.]staging-"),
    list.files(dirname(out), all.files = TRUE))))
  expect_identical(lisaR:::lisa_run_manifest(source), before)
})

test_that("extension collection preserves the underlying copy diagnostic", {
  root <- tempfile("lisa-extension-collect-diagnostic-")
  dir.create(root)
  on.exit(lisa_test_cleanup_path(root), add = TRUE)
  source <- file.path(root, "source")
  destination <- file.path(root, "destination")
  dir.create(source)
  writeLines("figure", file.path(source, "CAT_A_plot.png"))
  # A figure is only collected once its own source sidecar declares the
  # category attachment (see lisa_extension_collect); without it the family
  # is never attached and lisa_guarded_copy is never reached.
  writeLines(c("category_id", "CAT_A"), file.path(source, "CAT_A_plot_source.tsv"))
  old_run_root <- getOption("lisaR.run_root", NULL)
  options(lisaR.run_root = root)
  on.exit(options(lisaR.run_root = old_run_root), add = TRUE)
  testthat::local_mocked_bindings(
    lisa_guarded_copy = function(...) stop("injected filesystem write error"),
    .package = "lisaR"
  )

  expect_error(
    lisaR:::lisa_extension_collect(source, destination, "CAT_A"),
    "CAT_A_plot.png; injected filesystem write error",
    fixed = TRUE
  )
})

test_that("legacy configuration versions and output keys require explicit migration", {
  cfg <- report_architecture_config()
  for (version in c("0.5.0", "0.6.0")) {
    cfg$pipeline$schema_version <- version
    expect_error(lisaR:::lisa_validate_pipeline_config(cfg), "LISA-CONFIG-MIGRATION-000")
    expect_identical(cfg$pipeline$schema_version, version)
  }
  cfg$pipeline$schema_version <- "1.0.0"
  cfg$pipeline$run_gene_level <- TRUE
  expect_error(lisaR:::lisa_validate_pipeline_config(cfg), "LISA-CONFIG-MIGRATION-001")
})


test_that("extension file policy scans before deleting and never follows links", {
  base <- tempfile("lisa-extension-policy-link-")
  dir.create(base)
  on.exit(lisa_test_cleanup_path(base), add = TRUE)
  root <- lisaR:::lisa_run_root(file.path(base, "report"))
  png <- file.path(root, "remove.png")
  outside <- file.path(base, "outside.png")
  writeLines("inside", png)
  writeLines("outside", outside)
  link <- file.path(root, "linked.png")
  if (!isTRUE(suppressWarnings(file.symlink(outside, link)))) {
    skip("file.symlink() is unavailable in this test environment")
  }
  report <- list(
    formats = c(png = FALSE, svg = FALSE, pdf = FALSE),
    source_data = FALSE, recipes = FALSE
  )
  expect_error(
    lisaR:::lisa_extension_apply_file_policy(root, report), "Symbolic"
  )
  expect_true(file.exists(png))
  expect_identical(readLines(outside, warn = FALSE), "outside")
})

test_that("extension manifest is re-read twice and reconciled against the tree", {
  skip_if_not_installed("ggplot2")
  source <- make_report_architecture_run()
  output <- tempfile("lisa-extension-manifest-")
  calls <- 0L
  real_validate <- lisaR:::lisa_extension_validate_manifest
  testthat::local_mocked_bindings(
    lisa_extension_validate_manifest = function(...) {
      calls <<- calls + 1L
      real_validate(...)
    },
    .package = "lisaR"
  )
  render_lisa_categories(
    source, extension_selection("selected", "CAT_A"), output
  )
  expect_identical(calls, 2L)
  expect_silent(real_validate(output))

  undeclared <- file.path(output, "undeclared.txt")
  writeLines("undeclared", undeclared)
  expect_error(real_validate(output), "declared and observed files differ")
  unlink(undeclared)

  manifest <- lisaR:::read_lisa_tsv(
    file.path(output, "extension_manifest.tsv")
  )
  victim <- file.path(output, manifest$path[[1]])
  writeLines("tampered", victim, useBytes = TRUE)
  expect_error(real_validate(output), "changed after the manifest")
})
