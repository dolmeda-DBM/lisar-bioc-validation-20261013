# Copyright (C) 2026 Agencia Estatal Consejo Superior de Investigaciones
# Científicas (CSIC). Author: David Olmeda Casadomé.
# This file is part of lisaR, free software under the GNU General Public
# License version 3 (GPL-3). See the DESCRIPTION file.

# Shared, private class boundary for all three DE entry points. This layer
# extracts complete prepared results, never expression/count assays, and does
# not filter, reorder, sign an unsigned test or choose an edgeR FDR adjustment.
lisa_reject_unprepared_edger <- function(x) {
  if (inherits(x, c("DGEExact", "DGELRT"))) {
    stop(paste0(
      "This edgeR DGEExact/DGELRT object is not a prepared results table with FDR. ",
      "Convert it explicitly with: tt <- edgeR::topTags(x, n=Inf, sort.by=\"none\"). ",
      "Then supply tt and required signed ranking to lisaR. ",
      "lisaR does not select an FDR adjustment or infer a signed ranking from F/LR."
    ), call. = FALSE)
  }
  if (inherits(x, "DGEList")) {
    stop("LISA-INPUT-EDGER-001: DGEList contains counts, not DE results. Supply a prepared TopTags table and explicit signed ranking.", call. = FALSE)
  }
  invisible(TRUE)
}

# Public run_lisa() calls this before settings/readiness. A named collection of
# results is checked recursively; native list classes are not collections.
lisa_check_de_class_boundary <- function(x) {
  lisa_reject_unprepared_edger(x)
  if (is.list(x) && !is.data.frame(x) && !isS4(x) &&
      !inherits(x, c("TopTags", "MArrayLM"))) {
    for (item in x) lisa_check_de_class_boundary(item)
  }
  invisible(TRUE)
}

lisa_de_require_mapping <- function(columns, field) {
  roles <- c("symbol", "logfc", "rank", "pvalue", "padj")
  if (!is.list(columns) || !all(roles %in% names(columns)) ||
      !all(vapply(columns[roles], function(value)
        is.character(value) && length(value) == 1L && !is.na(value) &&
          nzchar(value), logical(1)))) {
    stop("LISA-DE-CLASS-001 ", field,
         " requires explicit columns for symbol, logfc, rank, pvalue and padj. ",
         "Use symbol = \".rownames\" only for declared non-default IDs.",
         call. = FALSE)
  }
}

lisa_de_check_lrt <- function(value, columns) {
  description <- tryCatch({
    metadata <- methods::slot(value, "elementMetadata")
    as.character(metadata[["description"]])
  }, error = function(e) character())
  stat_note <- description[grepl("statistic", description, ignore.case = TRUE)]
  if (length(stat_note) && any(grepl("LRT|likelihood ratio", stat_note,
                                    ignore.case = TRUE)) &&
      (is.null(columns$rank) || identical(columns$rank, "stat"))) {
    stop("LISA-RUN-DE-006 DESeq2 LRT stat is unsigned; supply an explicit compatible signed rank column.", call. = FALSE)
  }
}

lisa_adapt_de_object <- function(value, columns = list(), method = NULL,
                                 deseq2_name = NULL, deseq2_contrast = NULL,
                                 limma_coef = NULL, limma_adjust_method = NULL,
                                 results_location = NULL) {
  lisa_reject_unprepared_edger(value)
  if (is.null(columns)) columns <- list()
  if (!is.list(columns)) {
    stop("LISA-DE-INPUT-004 columns must be a named column mapping.", call. = FALSE)
  }
  source_class <- paste(class(value), collapse = "/")
  source <- ""
  detected <- NULL
  defaults <- list()
  native <- FALSE
  if (inherits(value, "DESeqDataSet")) {
    # Reuse the existing exactly-one-selector and selector-shape validation.
    value <- extract_de_table(value, "deseq2_dds", deseq2_contrast,
                              deseq2_name, .as_table = FALSE)
    source <- "DESeqDataSet selected results"
  } else if (!is.null(deseq2_name) || !is.null(deseq2_contrast)) {
    stop("LISA-DE-CLASS-002 DESeq2 selectors apply only to a DESeqDataSet.", call. = FALSE)
  }
  if (inherits(value, "DESeqResults")) {
    lisa_de_check_lrt(value, columns)
    frame <- as.data.frame(value)
    detected <- "DESeq2"
    defaults <- list(symbol = ".rownames")
    native <- TRUE
    if (!nzchar(source)) source <- "DESeqResults object"
  } else if (inherits(value, "TopTags")) {
    frame <- as.data.frame(lisa_edger_result_table(value))
    detected <- "edgeR"
    defaults <- list(symbol = ".rownames")
    native <- TRUE
    source <- "TopTags object"
    padj <- columns$padj %||% "FDR"
    if (!padj %in% names(frame)) {
      stop("LISA-RUN-DE-008 TopTags lacks prepared adjusted P values. Convert explicitly with edgeR::topTags and your chosen adjust.method; lisaR does not compute FDR.", call. = FALSE)
    }
    if (is.null(columns$rank)) {
      stop("LISA-DE-INPUT-005 TopTags requires an explicit compatible signed rank column and declared positive_direction; F/LR is not a signed rank.", call. = FALSE)
    }
  } else if (inherits(value, "MArrayLM")) {
    lisa_require_optional("limma", "adapting fitted moderated limma results")
    coef_names <- colnames(value$coefficients)
    valid_coef <- is.character(limma_coef) && length(limma_coef) == 1L &&
      !is.na(limma_coef) && nzchar(limma_coef) &&
      sum(coef_names == limma_coef) == 1L
    if (!valid_coef) {
      stop("LISA-DE-CLASS-003 MArrayLM requires one explicit, unambiguous coefficient name in limma_coef; no multi-df F ranking is inferred.", call. = FALSE)
    }
    coefficient <- match(limma_coef, coef_names)
    if (!is.matrix(value$t) || !is.matrix(value$p.value) ||
        !identical(dim(value$t), dim(value$coefficients)) ||
        !identical(dim(value$p.value), dim(value$coefficients)) ||
        !any(is.finite(value$t[, coefficient]))) {
      stop("LISA-DE-CLASS-004 MArrayLM must be fitted and moderated with a signed t statistic and P values for the selected coefficient.", call. = FALSE)
    }
    if (!is.character(limma_adjust_method) ||
        length(limma_adjust_method) != 1L || is.na(limma_adjust_method) ||
        !limma_adjust_method %in% stats::p.adjust.methods) {
      stop("LISA-DE-CLASS-005 declare limma_adjust_method explicitly; lisaR does not choose the adjustment for MArrayLM.", call. = FALSE)
    }
    frame <- getExportedValue("limma", "topTable")(value, coef = coefficient, number = Inf,
      sort.by = "none", adjust.method = limma_adjust_method, p.value = 1)
    if (nrow(frame) != nrow(value$coefficients) ||
        !identical(rownames(frame), rownames(value$coefficients))) {
      stop("LISA-DE-CLASS-004 limma extraction did not preserve every fitted row in source order.", call. = FALSE)
    }
    detected <- "limma"
    defaults <- list(symbol = ".rownames")
    native <- TRUE
    source <- paste0("MArrayLM coefficient=", limma_coef,
                     ";adjust.method=", limma_adjust_method)
  } else if (inherits(value, "SummarizedExperiment")) {
    lisa_require_optional("SummarizedExperiment", "locating prepared rowData DE results")
    if (!identical(results_location, "rowData")) {
      stop("LISA-DE-CLASS-006 explicitly select results_location = \"rowData\" and map an already prepared DE table; expression/count assays are not DE results.", call. = FALSE)
    }
    lisa_de_require_mapping(columns, "SummarizedExperiment rowData")
    if (is.null(method)) {
      stop("LISA-DE-CLASS-006 declare method for the already prepared rowData DE table.", call. = FALSE)
    }
    frame <- as.data.frame(SummarizedExperiment::rowData(value))
    source <- "SummarizedExperiment prepared rowData"
    native <- TRUE
  } else if (inherits(value, "DataFrame")) {
    lisa_de_require_mapping(columns, "S4Vectors DataFrame")
    if (is.null(method)) {
      stop("LISA-DE-CLASS-001 declare method for the explicitly mapped DataFrame.", call. = FALSE)
    }
    frame <- as.data.frame(value)
    source <- "S4Vectors DataFrame prepared results"
    native <- TRUE
  } else if (is.data.frame(value) || is.matrix(value)) {
    frame <- as.data.frame(value)
  } else if (is.character(value)) {
    table <- lisa_run_read_de_table(value, "DE input")
    frame <- table$data
    source <- table$source
  } else {
    stop("LISA-RUN-DE-004 unsupported DE input class: ",
         paste(class(value), collapse = "/"), ".", call. = FALSE)
  }
  if (!inherits(value, "MArrayLM") &&
      (!is.null(limma_coef) || !is.null(limma_adjust_method))) {
    stop("LISA-DE-CLASS-002 limma selectors apply only to MArrayLM.", call. = FALSE)
  }
  if (!inherits(value, "SummarizedExperiment") && !is.null(results_location)) {
    stop("LISA-DE-CLASS-002 results_location applies only to SummarizedExperiment.", call. = FALSE)
  }
  if (!is.null(detected) && !is.null(method) && !identical(method, detected)) {
    stop("LISA-DE-CLASS-007 declared method conflicts with the native result class.", call. = FALSE)
  }
  for (key in names(defaults)) {
    if (is.null(columns[[key]])) columns[key] <- defaults[key]
  }
  list(data = frame, method = method %||% detected, columns = columns,
       source = source, source_class = source_class, native = native)
}

# run_lisa_de keeps its historical table-column conventions. Its native-class
# route uses the same canonical validation as prepare_lisa_de_input/run_lisa,
# before resources, readiness, caches or output directories can be created.
lisa_normalize_de_for_engine <- function(input, symbol_col, rank_col, logfc_col,
                                         pvalue_col, padj_col,
                                         positive_direction, rank_direction,
                                         deseq2_name, deseq2_contrast,
                                         limma_coef, limma_adjust_method,
                                         results_location, method = NULL,
                                         gene_id_col = NULL) {
  columns <- Filter(Negate(is.null), list(symbol = symbol_col, rank = rank_col,
    logfc = logfc_col, pvalue = pvalue_col, padj = padj_col))
  adapted <- lisa_adapt_de_object(input, columns = columns, method = method,
    deseq2_name = deseq2_name, deseq2_contrast = deseq2_contrast,
    limma_coef = limma_coef, limma_adjust_method = limma_adjust_method,
    results_location = results_location)
  # This lower-level route historically prefers explicit symbol columns to
  # feature row names. Do not change the helper's declared identity mapping.
  if (is.null(symbol_col) && inherits(input, c("DESeqDataSet", "DESeqResults"))) {
    candidates <- c("human_symbol", "symbol", "gene_symbol", "gene_name",
                    "SYMBOL", "external_gene_name")
    indices <- match(tolower(candidates), tolower(names(adapted$data)))
    indices <- indices[!is.na(indices)]
    if (length(indices)) adapted$columns$symbol <- names(adapted$data)[indices[[1L]]]
  }
  rank_direction <- match.arg(rank_direction, c("same_as_effect", "opposite_to_effect"))
  # Historical DESeq2 lower-level calls may omit a prose direction. This
  # route retains that permission without fabricating a declaration. TopTags
  # and newly adapted classes require the explicit direction used by the helper.
  legacy_deseq <- inherits(input, c("DESeqDataSet", "DESeqResults")) &&
    is.null(positive_direction)
  if (identical(adapted$columns$symbol, "rowname") && adapted$native) {
    adapted$columns$symbol <- ".rownames"
  }
  if (legacy_deseq) {
    if (is.null(rank_col)) rank_col <- "stat"
    if (rank_col %in% c("F", "LR", "pvalue", "padj")) {
      stop("LISA-DE-INPUT-005 rank must name a signed statistic.", call. = FALSE)
    }
    columns <- adapted$columns
    if (identical(columns$symbol, ".rownames")) columns$symbol <- "rowname"
    columns$rank <- rank_col
    if (rank_direction == "opposite_to_effect") {
      adapted$data[[rank_col]] <- -adapted$data[[rank_col]]
    }
    # Retain historical lower-level omission-of-direction row filtering.
    return(list(data = adapted$data, raw_data = adapted$data,
      columns = columns, preserve_rows = FALSE))
  }
  if (isTRUE(adapted$native)) {
    prepared <- prepare_lisa_de_input(adapted$data,
      method = adapted$method, columns = adapted$columns,
      positive_direction = positive_direction, rank_direction = rank_direction)
    engine_data <- prepared$data
    if (!is.null(gene_id_col) && !gene_id_col %in% names(engine_data)) {
      if (!gene_id_col %in% names(adapted$data)) {
        stop("Column not found: ", gene_id_col, call. = FALSE)
      }
      engine_data[[gene_id_col]] <- adapted$data[[gene_id_col]]
    }
    return(list(data = engine_data, raw_data = adapted$data,
      columns = list(symbol = "symbol", rank = "rank_value",
        logfc = "log2FoldChange", pvalue = "pvalue", padj = "padj"),
      preserve_rows = TRUE))
  }
  if (!is.null(rank_col) && rank_col %in% c("F", "LR", "F.statistic", "Chisq", "chisq",
                                           pvalue_col, padj_col)) {
    stop("LISA-DE-INPUT-005 rank must be a compatible signed statistic, not unsigned F/LR or significance.", call. = FALSE)
  }
  if (rank_direction == "opposite_to_effect") {
    if (is.null(rank_col) || !rank_col %in% names(adapted$data) ||
        !is.numeric(adapted$data[[rank_col]])) {
      stop("LISA-DE-INPUT-005 opposite rank_direction requires an explicit numeric rank_col.", call. = FALSE)
    }
    adapted$data[[rank_col]] <- -adapted$data[[rank_col]]
  }
  list(data = adapted$data, columns = columns, preserve_rows = FALSE)
}
