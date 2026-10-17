# Real optional classes at the shared, pre-output boundary. Full scientific runs
# are deliberately not duplicated here; compare them in the released heavy slot.
p4_route_values <- function(object, method, columns, selectors = list()) {
  direction <- "higher in treated than control"
  prepared <- do.call(prepare_lisa_de_input, c(list(
    data = object, method = method, columns = columns,
    positive_direction = direction), selectors))
  simple <- NULL
  engine <- NULL
  original_normalize <- lisaR:::lisa_normalize_de_for_engine
  if (inherits(object, "TopTags")) {
    testthat::local_mocked_bindings(
      topTags = function(...) stop("UNEXPECTED automatic edgeR conversion"),
      .package = "edgeR")
    testthat::local_mocked_bindings(
      p.adjust = function(...) stop("UNEXPECTED automatic FDR"),
      .package = "stats")
  }
  testthat::local_mocked_bindings(
    lisa_run_build_config = function(declarations, ...) {
      simple <<- declarations[[1L]]$full_data
      stop("P4-ACCEPTED", call. = FALSE)
    },
    lisa_normalize_de_for_engine = function(...) {
      engine <<- original_normalize(...)
      stop("P4-ACCEPTED", call. = FALSE)
    },
    .package = "lisaR"
  )
  expect_error(do.call(run_lisa, c(list(
    de = object, output_dir = tempfile("p4-simple-"),
    species = "Homo sapiens", positive_direction = direction,
    method = method, columns = if (length(columns)) columns else NULL), selectors)), "P4-ACCEPTED")
  lower_columns <- columns
  if (length(lower_columns)) names(lower_columns) <- paste0(names(lower_columns), "_col")
  expect_error(do.call(run_lisa_de, c(list(
    input = object, output_dir = tempfile("p4-de-"),
    positive_direction = direction, method = method), lower_columns,
    selectors)), "P4-ACCEPTED")
  expect_equal(simple, prepared$full_data)
  expect_equal(engine$data, prepared$data)
  list(prepared = prepared, simple = simple, engine = engine)
}

p4_rejected_routes <- function(object, columns = list(), selectors = list(),
                               pattern, method = "edgeR") {
  root <- tempfile("p4-no-files-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  before <- list.files(root, all.files = TRUE, recursive = TRUE,
                       include.dirs = TRUE, no.. = TRUE)
  original_settings <- lisaR:::lisa_run_resolve_settings
  testthat::local_mocked_bindings(
    lisa_atomic_temp_path = function(...) stop("UNEXPECTED hash/write temp"),
    lisa_rds_object_sha256 = function(...) stop("UNEXPECTED object hash"),
    lisa_run_resolve_settings = function(...) stop("UNEXPECTED readiness"),
    .package = "lisaR"
  )
  # Only the edgeR direct rejection is required to precede all settings.
  # Other class validation comes after pure simple settings, so temporarily
  # unmock that function for their selector/mapping error cases.
  if (!inherits(object, c("DGEExact", "DGELRT", "DGEList"))) {
    testthat::local_mocked_bindings(
      lisa_run_resolve_settings = original_settings,
      .package = "lisaR"
    )
  }
  calls <- list(
    list(fun = prepare_lisa_de_input, args = c(list(data = object,
      method = method, columns = if (length(columns)) columns else NULL,
      positive_direction = "treated-control"),
      selectors)),
    list(fun = run_lisa, args = c(list(de = object,
      output_dir = file.path(root, "simple"), species = "Homo sapiens",
      method = method, columns = if (length(columns)) columns else NULL,
      positive_direction = "treated-control"),
      selectors)))
  lower <- columns
  if (length(lower)) names(lower) <- paste0(names(lower), "_col")
  calls[[3L]] <- list(fun = run_lisa_de, args = c(list(input = object,
    output_dir = file.path(root, "lower"), method = method,
    positive_direction = "treated-control"), lower, selectors))
  messages <- vapply(calls, function(route) {
    error <- tryCatch(do.call(route$fun, route$args), error = identity)
    expect_s3_class(error, "error")
    expect_match(conditionMessage(error), pattern)
    conditionMessage(error)
  }, character(1))
  expect_identical(list.files(root, all.files = TRUE, recursive = TRUE,
    include.dirs = TRUE, no.. = TRUE), before)
  if (inherits(object, c("DGEExact", "DGELRT"))) {
    expect_length(unique(messages), 1L)
  }
  invisible(messages)
}

p4_real_edger <- function() {
  counts <- matrix(c(10,12,40,42,20,18,55,58,30,28,70,75,
                     12,11,33,36,90,100,80,82,45,40,42,44),
    nrow = 6, byrow = TRUE,
    dimnames = list(paste0("GENE", 1:6), paste0("S", 1:4)))
  group <- factor(c("control", "control", "treated", "treated"),
                  levels = c("control", "treated"))
  dge <- edgeR::calcNormFactors(edgeR::DGEList(counts, group = group))
  exact <- edgeR::exactTest(dge, dispersion = 0.1)
  design <- stats::model.matrix(~ group)
  fit <- edgeR::glmFit(dge, design, dispersion = 0.1)
  lrt <- edgeR::glmLRT(fit, coef = "grouptreated")
  list(dge = dge, exact = exact, lrt = lrt)
}

test_that("real edgeR tests reject identically before readiness/hash/files on all routes", {
  skip_if_not_installed("edgeR")
  x <- p4_real_edger()
  for (test in x[c("exact", "lrt")]) {
    # Even user-added FDR/rank cannot turn a test class into prepared TopTags.
    test$table$FDR <- rep(0.25, nrow(test$table))
    test$table$signed_rank <- test$table$logFC
    p4_rejected_routes(test, columns = list(rank = "signed_rank"),
      pattern = "This edgeR DGEExact/DGELRT object.*topTags.*does not select an FDR")
  }
  p4_rejected_routes(x$dge, pattern = "DGEList contains counts")
})

test_that("real TopTags preserves all rows/order/names/P/FDR/NA on all routes", {
  skip_if_not_installed("edgeR")
  x <- p4_real_edger()
  for (test in x[c("exact", "lrt")]) {
    tt <- edgeR::topTags(test, n = Inf, sort.by = "none", adjust.method = "BY")
    # logFC is the explicit signed-effect ranking for this one-df comparison,
    # not sign(LR) or sign(F). These deliberate NAs exercise preservation.
    tt$table$signed_rank <- tt$table$logFC
    tt$table$signed_rank[2] <- NA_real_
    tt$table$PValue[3] <- NA_real_
    tt$table$FDR[4] <- NA_real_
    original <- tt$table
    values <- p4_route_values(tt, "edgeR", list(rank = "signed_rank"))
    expect_identical(tt$table, original)
    expect_identical(rownames(values$prepared$full_data), rownames(original))
    expect_identical(values$prepared$full_data$pvalue, original$PValue)
    expect_identical(values$prepared$full_data$padj, original$FDR)
    expect_identical(values$prepared$full_data$rank_value, original$signed_rank)
    expect_identical(values$engine$raw_data, original)
    expect_equal(nrow(values$prepared$full_data), nrow(original))
    expect_error(prepare_lisa_de_input(tt, positive_direction = "treated-control"),
                 "explicit compatible signed rank")
    for (rank in c("LR", "PValue", "FDR")) {
      tt$table[[rank]] <- rep(1, nrow(tt$table))
      expect_error(prepare_lisa_de_input(tt, columns = list(rank = rank),
        positive_direction = "treated-control"), "LISA-DE-INPUT-005")
    }
    tt$table$signed_rank <- -tt$table$logFC
    values <- p4_route_values(tt, "edgeR", list(rank = "signed_rank"),
      selectors = list(rank_direction = "opposite_to_effect"))
    expect_identical(values$prepared$full_data$rank_value, tt$table$logFC)
  }
})

test_that("explicitly mapped real DataFrame and prepared SE rowData use all routes", {
  skip_if_not_installed("SummarizedExperiment")
  # S4Vectors is already a dependency of the optional SE package.
  frame <- getExportedValue("S4Vectors", "DataFrame")(
    id = c("GENE1", "GENE2", "GENE3"), effect = c(1, -2, .2),
    signed = c(3, -4, NA), P = c(.01, .02, NA), q = c(.03, .04, NA))
  mapping <- list(symbol = "id", logfc = "effect", rank = "signed",
                  pvalue = "P", padj = "q")
  values <- p4_route_values(frame, "DESeq2", mapping)
  expect_identical(values$prepared$full_data$padj, frame$q)
  se <- SummarizedExperiment::SummarizedExperiment(
    assays = list(counts = matrix(1:6, nrow = 3)), rowData = frame)
  values <- p4_route_values(se, "DESeq2", mapping,
    selectors = list(results_location = "rowData"))
  expect_identical(values$prepared$full_data$rank_value, frame$signed)
  p4_rejected_routes(frame, pattern = "requires explicit columns", method = "DESeq2")
  p4_rejected_routes(se, columns = mapping,
    pattern = "explicitly select results_location", method = "DESeq2")
  bad_ids <- mapping
  bad_ids$symbol <- ".rownames"
  p4_rejected_routes(frame, columns = bad_ids,
    pattern = "default sequential row names", method = "DESeq2")
})

test_that("real MArrayLM requires a single selected moderated signed coefficient", {
  skip_if_not_installed("limma")
  fit_fun <- getExportedValue("limma", "lmFit")
  moderate <- getExportedValue("limma", "eBayes")
  expression <- matrix(c(4,5,8,9,7,8,3,4,3,4,5,7,8,9,10,9,
                         4,7,8,11,8,6,3,5,5,8,9,7,11,10,13,12),
    nrow = 8, byrow = TRUE,
    dimnames = list(paste0("GENE", 1:8), paste0("S", 1:4)))
  group <- factor(c("control", "control", "treated", "treated"))
  design <- stats::model.matrix(~ group)
  unfitted <- fit_fun(expression, design)
  fitted <- moderate(unfitted)
  selectors <- list(limma_coef = "grouptreated", limma_adjust_method = "BH")
  values <- p4_route_values(fitted, "limma", list(), selectors)
  expect_identical(values$prepared$full_data$rank_value,
                   as.numeric(fitted$t[, "grouptreated"]))
  p4_rejected_routes(fitted, pattern = "one explicit.*coefficient", method = "limma")
  p4_rejected_routes(fitted, selectors = list(limma_coef = c("(Intercept)", "grouptreated")),
    pattern = "one explicit.*coefficient", method = "limma")
  p4_rejected_routes(unfitted, selectors = selectors,
    pattern = "must be fitted and moderated", method = "limma")
  p4_rejected_routes(fitted, selectors = list(limma_coef = "grouptreated"),
    pattern = "declare limma_adjust_method", method = "limma")
  p4_rejected_routes(fitted, columns = list(rank = "F"), selectors = selectors,
    pattern = "LISA-DE-INPUT-00[45]", method = "limma")
})

test_that("DESeqDataSet selectors reuse existing validation on all three routes", {
  skip_if_not_installed("DESeq2")
  # Existing fixture/suite covers real fitting and DESeq2 selector shapes.
  fixture_env <- new.env()
  eval(parse(file = testthat::test_path("test-g3-deseq2-input-contract.R"))[[1L]],
       envir = fixture_env)
  dds <- fixture_env$make_g3_deseq2_dds()
  selectors <- list(deseq2_name = "condition_treated_vs_control")
  values <- p4_route_values(dds, "DESeq2", list(), selectors)
  expected <- DESeq2::results(dds, name = selectors$deseq2_name)
  expect_identical(values$prepared$full_data$pvalue, expected$pvalue)
  expect_identical(values$prepared$full_data$padj, expected$padj)
  p4_rejected_routes(dds, pattern = "LISA-INPUT-DESEQ2-001", method = "DESeq2")
  p4_rejected_routes(dds, selectors = c(selectors,
    list(deseq2_contrast = c("condition", "treated", "control"))),
    pattern = "LISA-INPUT-DESEQ2-002", method = "DESeq2")
  p4_rejected_routes(dds, selectors = list(deseq2_name = "absent"),
    pattern = "LISA-INPUT-DESEQ2-004", method = "DESeq2")
  p4_rejected_routes(dds, selectors = list(deseq2_contrast = c("condition", "treated")),
    pattern = "LISA-INPUT-DESEQ2-005", method = "DESeq2")
})

# Regressions for three independently demonstrated P4 defects. These exercise
# the actual lower-level route through recursive branches and written inputs,
# not a mocked first-normalization checkpoint; GSEA/ORA remain off.
p4_no_gsea_args <- function() {
  resource <- function(file) system.file("extdata", "quick-start", file,
                                        package = "lisaR")
  list(lisa_dictionary = "sample",
    lisa_dictionary_path = resource("example_dictionary_v3_0.tsv"),
    category_map_path = resource("example_category_map_v1_1.tsv"),
    term2gene_path = resource("example_term2gene_v2_1.tsv"),
    run_gsea = FALSE, run_ora = FALSE, outputs = c("tables", "qc"),
    plots = character(), export_formats = "tsv", verbose = FALSE)
}

test_that("real TopTags source columns survive actual two-universe recursion", {
  skip_if_not_installed("edgeR")
  tt <- edgeR::topTags(p4_real_edger()$lrt, n = Inf, sort.by = "none",
                       adjust.method = "BH")
  tt$table$signed_rank <- tt$table$logFC
  tt$table$FDR[2] <- NA_real_
  tt$table$signed_rank[3] <- NA_real_
  original <- tt$table
  root <- tempfile("p4-two-universes-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  result <- do.call(run_lisa_de, c(list(input = tt, output_dir = root,
    comparison_name = "native", universes = c("GOMF", "GOCC"),
    symbol_col = ".rownames", rank_col = "signed_rank",
    logfc_col = "logFC", pvalue_col = "PValue", padj_col = "FDR",
    positive_direction = "higher in treated than control"), p4_no_gsea_args()))
  expect_named(result, c("GOMF", "GOCC"))
  for (universe in names(result)) {
    path <- file.path(result[[universe]]$output_dir, "inputs",
                      "native_standardized_DE.tsv")
    expect_true(file.exists(path))
    actual <- utils::read.delim(path, check.names = FALSE, na.strings = c("", "NA"))
    expect_identical(actual$symbol, rownames(original))
    expect_equal(actual$rank_value, original$signed_rank)
    expect_equal(actual$pvalue, original$PValue)
    expect_equal(actual$padj, original$FDR)
    expect_equal(nrow(actual), nrow(original))
    expect_equal(result[[universe]]$ranking_qc$n_standardized_rows, nrow(original))
    expect_equal(nrow(result[[universe]]$gsea), 0L)
  }
  expect_identical(tt$table, original)
})

test_that("legacy prepared z and score tables keep their actual ranking values", {
  for (column in c("z", "score")) {
    table <- data.frame(symbol = c("GENE1", "GENE2"), logFC = c(1, -2),
      PValue = c(.01, .02), FDR = c(.03, .04))
    table[[column]] <- c(7, -8) # deliberately distinct from logFC
    root <- tempfile(paste0("p4-legacy-", column, "-"))
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    result <- do.call(run_lisa_de, c(list(input = table, output_dir = root,
      comparison_name = column, universes = "GOMF"), p4_no_gsea_args()))
    actual <- utils::read.delim(file.path(result$output_dir, "inputs",
      paste0(column, "_standardized_DE.tsv")), check.names = FALSE)
    expect_identical(result$ranking_qc$rank_col, column)
    expect_equal(actual$rank_value, table[[column]])
    expect_false(identical(actual$rank_value, table$logFC))
  }
})

test_that("legacy omitted-direction DESeq2 filtering remains distinct from explicit preparation", {
  skip_if_not_installed("DESeq2")
  frame <- getExportedValue("S4Vectors", "DataFrame")(
    symbol = c("GENE1", "", NA, "GENE4", "GENE5"),
    log2FoldChange = c(1, 2, 3, 4, -1), stat = c(3, 4, 5, NA, -3),
    pvalue = c(.01, .02, .03, .04, .05), padj = c(.03, .04, .05, .06, .07),
    row.names = paste0("source", 1:5))
  res <- DESeq2::DESeqResults(frame)
  root <- tempfile("p4-legacy-deseq-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  result <- do.call(run_lisa_de, c(list(input = res, output_dir = root,
    comparison_name = "legacy", symbol_col = "symbol",
    rank_col = "stat", universes = "GOMF"), p4_no_gsea_args()))
  actual <- utils::read.delim(file.path(root, "inputs", "legacy_standardized_DE.tsv"),
                             check.names = FALSE)
  expect_identical(actual$symbol, c("GENE1", "GENE5"))
  expect_equal(actual$rank_value, c(3, -3))
  expect_equal(result$ranking_qc$n_input_rows, 5L)
  expect_equal(result$ranking_qc$n_standardized_rows, 2L)
  # The explicit prepared route still retains permitted missing ranks.
  res$symbol <- paste0("GENE", 1:5)
  explicit_root <- tempfile("p4-explicit-deseq-")
  on.exit(unlink(explicit_root, recursive = TRUE), add = TRUE)
  explicit <- do.call(run_lisa_de, c(list(input = res, output_dir = explicit_root,
    comparison_name = "explicit", symbol_col = "symbol", rank_col = "stat",
    universes = "GOMF", positive_direction = "treated-control"),
    p4_no_gsea_args()))
  actual <- utils::read.delim(file.path(explicit_root, "inputs",
    "explicit_standardized_DE.tsv"), check.names = FALSE, na.strings = c("", "NA"))
  expect_identical(actual$symbol, res$symbol)
  expect_equal(actual$rank_value, res$stat)
  expect_true(is.na(actual$rank_value[4L]))
  expect_equal(explicit$ranking_qc$n_standardized_rows, 5L)
})

# One targeted actual-route regression: native DESeq2 results contain both
# Ensembl feature row names and a baseline symbol column; symbol_col is omitted.
test_that("lower-level native DESeq2 keeps baseline symbol columns ahead of Ensembl row names", {
  skip_if_not_installed("DESeq2")
  for (column in c("symbol", "gene_symbol")) {
    frame <- S4Vectors::DataFrame(baseMean = c(50, 70),
      log2FoldChange = c(1, -2), lfcSE = c(.2, .3), stat = c(3, -4),
      pvalue = c(.01, .02), padj = c(.03, .04),
      row.names = c("ENSG000001", "ENSG000002"))
    frame[[column]] <- c("TP53", "EGFR")
    res <- DESeq2::DESeqResults(frame)
    for (direction in list(NULL, "treated relative to control")) {
      root <- tempfile("p4-deseq-native-symbols-")
      on.exit(unlink(root, recursive = TRUE), add = TRUE)
      # Deliberately omit symbol_col; exercise the public actual route.
      args <- c(list(input = res, output_dir = root,
        comparison_name = "symbols", universes = "GOMF"), p4_no_gsea_args())
      if (!is.null(direction)) args$positive_direction <- direction
      result <- do.call(run_lisa_de, args)
      actual <- utils::read.delim(file.path(result$output_dir, "inputs",
        "symbols_standardized_DE.tsv"), check.names = FALSE)
      expect_identical(actual$symbol, c("TP53", "EGFR"))
      expect_false(identical(actual$symbol, rownames(res)))
      expect_equal(actual$rank_value, res$stat)
      expect_equal(result$ranking_qc$n_standardized_rows, 2L)
    }
    # An explicit helper identity declaration still means exactly what it says.
    prepared <- prepare_lisa_de_input(res,
      columns = list(symbol = ".rownames"),
      positive_direction = "treated relative to control")
    expect_identical(prepared$full_data$symbol, rownames(res))
  }
})
