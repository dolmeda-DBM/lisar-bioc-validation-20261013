# Test-only contract. Never changes produced tables, identifiers or statistics.
portable_read_inference <- function(path) {
  utils::read.delim(path, check.names = FALSE, stringsAsFactors = FALSE,
    colClasses = "character", na.strings = c("", "NA"), quote = "\"")
}

portable_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("Portable inference: ", message), call. = FALSE)
}

portable_order <- function(x) sign(outer(x, x, "-"))

portable_family_id <- function(x) {
  if (!"family_id" %in% names(x)) return(invisible(NULL))
  id <- x$family_id
  portable_require(length(id) > 0L && !anyNA(id) && length(unique(id)) == 1L,
    "family_id must be unique and coherent within a run")
  portable_require("analysis_id" %in% names(x) && !anyNA(x$analysis_id) &&
    length(unique(x$analysis_id)) == 1L, "family_id analysis identity")
  portable_require(grepl("^[0-9a-f]{16}$", sub(paste0("^", x$analysis_id[[1L]], ":"), "", id[[1L]])) &&
    startsWith(id[[1L]], paste0(x$analysis_id[[1L]], ":")), "family_id format")
  invisible(id[[1L]])
}

portable_compare_inference <- function(actual, expected, keys,
    p_columns = intersect(c("pval", "p_for_inference", "category_p_adjusted"), names(expected))) {
  portable_require(is.data.frame(actual) && is.data.frame(expected), "data frames required")
  portable_require(identical(names(actual), names(expected)) && !anyDuplicated(names(actual)),
    "schema differs")
  portable_require(length(keys) > 0L && all(keys %in% names(actual)), "key schema")
  portable_require(nrow(actual) == nrow(expected) && nrow(actual) > 0L, "row count differs")
  portable_require(all(p_columns %in% c("pval", "p_for_inference", "category_p_adjusted")) &&
    all(p_columns %in% names(expected)), "unauthorized tolerant column")
  key <- function(x) {
    portable_require(!anyNA(x[keys]) && all(vapply(x[keys], function(z) all(nzchar(z)), logical(1))),
      "missing key")
    portable_require(!anyDuplicated(x[keys]), "duplicate key")
    x[keys]
  }
  portable_require(identical(key(actual), key(expected)), "key membership or row order differs")
  portable_family_id(actual)
  portable_family_id(expected)
  for (column in names(expected)) {
    a <- actual[[column]]; e <- expected[[column]]
    if (column == "family_id") next # Content IDs remain intact; compare locally, not across ISA.
    if (!column %in% p_columns) {
      portable_require(identical(a, e), paste("exact column differs:", column))
      next
    }
    portable_require(identical(is.na(a), is.na(e)), paste("missing p state:", column))
    av <- suppressWarnings(as.numeric(a)); ev <- suppressWarnings(as.numeric(e))
    present <- !is.na(a)
    portable_require(all(is.finite(av[present])) && all(is.finite(ev[present])) &&
      all(av[present] >= 0 & av[present] <= 1) && all(ev[present] >= 0 & ev[present] <= 1),
      paste("invalid p range/nonfinite:", column))
    av <- av[present]; ev <- ev[present]
    portable_require(identical(av == 0, ev == 0), paste("zero p state:", column))
    portable_require(all(abs(av - ev) <= 1e-12 * pmax(abs(av), abs(ev))),
      paste("relative p tolerance exceeded:", column))
    for (threshold in c(.05, .01, .001, .0001))
      portable_require(identical(av <= threshold, ev <= threshold),
        paste("p classification boundary:", column, threshold))
    portable_require(identical(portable_order(av), portable_order(ev)),
      paste("p ranking or tie differs:", column))
  }
  invisible(TRUE)
}

portable_compare_smoke <- function(actual_path, fixture, family_root) {
  baseline_root <- file.path(dirname(fixture), "portable-installation-smoke-baselines")
  provenance <- jsonlite::read_json(file.path(baseline_root, "PROVENANCE.json"))
  portable_require(identical(provenance$source_revision, "r1") &&
    identical(provenance$source_architecture, "x86_64") &&
    identical(provenance$source_candidate_sha256,
      "2759ef3ec395b6b55c0dfe16633bd304ce8b2e36b175cd3c7bbb8d73acce6815"), "baseline origin")
  for (entry in provenance$files) {
    portable_require(identical(digest::digest(file = file.path(baseline_root, entry$file),
      algo = "sha256", serialize = FALSE), entry$sha256), "baseline checksum")
  }
  paths <- c(raw = "raw_results.tsv", family = "hypothesis_family.tsv", category = "category_results.tsv")
  baseline <- c(raw = "raw-results.tsv", family = "hypothesis-family.tsv", category = "category-results.tsv")
  keys <- list(raw = c("collection", "pathway"), family = "hypothesis_id", category = c("collection", "category_id"))
  sizes <- c(raw = 48L, family = 48L, category = 16L)
  observed <- list()
  for (kind in names(paths)) {
    a <- portable_read_inference(file.path(family_root, paths[[kind]]))
    e <- portable_read_inference(file.path(baseline_root, baseline[[kind]]))
    portable_require(nrow(a) == sizes[[kind]], paste("full fixture cardinality:", kind))
    portable_compare_inference(a, e, keys[[kind]])
    observed[[kind]] <- a
  }
  a <- portable_read_inference(actual_path)
  e <- portable_read_inference(file.path(fixture, "category-inference-original.tsv"))
  portable_require(nrow(a) == 4L, "original GOBP-C2 cardinality")
  portable_compare_inference(a, e, c("collection", "category_id"))
  portable_require(identical(portable_family_id(a), portable_family_id(observed$category)),
    "family_id differs across products of the same run")
  portable_require(identical(sort(unique(observed$category$collection)),
    sort(c("GOBP-C2", "GOMF", "GOCC", "PATHWAYS"))), "collection membership")
  invisible(TRUE)
}
