# Native diagnostic observers only. No RNG draws, result replacement or rounding.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true", Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted",
  Sys.getenv("LISAR_REPOSITORY_PRIVATE") == "false",
  Sys.getenv("GITHUB_REPOSITORY") == "dolmeda-DBM/lisar-bioc-validation-20261013",
  Sys.getenv("GITHUB_RUN_ATTEMPT") == "1", Sys.getenv("GITHUB_SHA") == Sys.getenv("EXPECTED_HEAD_SHA"),
  Sys.info()[["sysname"]] == "Darwin", Sys.info()[["machine"]] == Sys.getenv("LISAR_EXPECTED_ARCH"),
  getRversion() == "4.6.1")
lisar_probe6_trace <- normalizePath(Sys.getenv("LISAR_PROBE6_TRACE_DIR"), mustWork = TRUE)
stopifnot(startsWith(lisar_probe6_trace, paste0(normalizePath(Sys.getenv("LISAR_VALIDATION_ROOT"), mustWork = TRUE), "/probe6/")))
lisar_probe6_sequence <- 0L
lisar_probe6_seed <- function() {
  if (exists(".Random.seed", envir = globalenv(), inherits = FALSE))
    digest::digest(get(".Random.seed", envir = globalenv()), algo = "sha256") else "absent"
}
lisar_probe6_new <- function(kind) {
  lisar_probe6_sequence <<- lisar_probe6_sequence + 1L
  path <- file.path(lisar_probe6_trace, paste0(kind, "-", Sys.getpid(), "-", lisar_probe6_sequence))
  stopifnot(!file.exists(path), dir.create(path))
  path
}
lisar_probe6_bits <- function(values) {
  vapply(as.double(values), function(x)
    paste(sprintf("%02x", as.integer(writeBin(x, raw(), size = 8L, endian = "big"))), collapse = ""), character(1))
}
lisar_probe6_numeric <- function(object, path) {
  result <- list()
  for (name in names(object)) {
    x <- object[[name]]
    if (is.double(x) || is.integer(x) || is.logical(x)) {
      result[[length(result) + 1L]] <- data.frame(field = name, index = seq_along(x),
        binary64_bits_hex = lisar_probe6_bits(x), stringsAsFactors = FALSE)
    }
  }
  stopifnot(length(result) > 0L)
  utils::write.table(do.call(rbind, result), path, sep = "\t", row.names = FALSE, quote = FALSE)
}
lisar_probe6_cpp_entry <- function(frame) {
  seed_before <- lisar_probe6_seed()
  args <- mget(c("enrichmentScores", "ranks", "pathwaySize", "sampleSize", "seed", "eps", "sign", "moveScale", "logStatus"),
    envir = frame, inherits = FALSE)
  stopifnot(is.integer(args$ranks), args$sampleSize == 101L,
    length(args$enrichmentScores) > 0L)
  path <- lisar_probe6_new("cpp-call")
  saveRDS(args, file.path(path, "input.rds"), version = 3L, compress = FALSE)
  lisar_probe6_numeric(args, file.path(path, "input-bits.tsv"))
  previous <- Sys.getenv("LISAR_PROBE6_CALL_DIR", unset = NA_character_)
  assign(".lisar_probe6_path", path, envir = frame)
  assign(".lisar_probe6_previous_dir", previous, envir = frame)
  Sys.setenv(LISAR_PROBE6_CALL_DIR = path)
  seed_after <- lisar_probe6_seed()
  jsonlite::write_json(list(status = "INPUT_CAPTURE_NOT_PACKAGE_PASS", seed_before = seed_before,
    seed_after = seed_after, observer_did_not_draw_R_RNG = identical(seed_before, seed_after),
    args_digest = digest::digest(args, algo = "sha256"),
    input_rds_sha256 = digest::digest(file = file.path(path, "input.rds"), algo = "sha256", serialize = FALSE)),
    file.path(path, "identity.json"), pretty = TRUE, auto_unbox = TRUE)
  stopifnot(identical(seed_before, seed_after))
  invisible(NULL)
}
lisar_probe6_cpp_exit <- function(frame, value) {
  seed_before <- lisar_probe6_seed()
  path <- get(".lisar_probe6_path", envir = frame, inherits = FALSE)
  saveRDS(value, file.path(path, "return.rds"), version = 3L, compress = FALSE)
  lisar_probe6_numeric(value, file.path(path, "return-bits.tsv"))
  previous <- get(".lisar_probe6_previous_dir", envir = frame, inherits = FALSE)
  if (is.na(previous)) Sys.unsetenv("LISAR_PROBE6_CALL_DIR") else Sys.setenv(LISAR_PROBE6_CALL_DIR = previous)
  stopifnot(identical(seed_before, lisar_probe6_seed()))
  invisible(NULL)
}
lisar_probe6_multilevel_entry <- function(frame) {
  seed_before <- lisar_probe6_seed()
  args <- mget(c("multilevelPathwaysList", "stats", "sampleSize", "seed", "eps", "sign"), frame, inherits = FALSE)
  path <- lisar_probe6_new("r-groups")
  saveRDS(args, file.path(path, "input.rds"), version = 3L, compress = FALSE)
  for (i in seq_along(args$multilevelPathwaysList)) {
    group <- as.data.frame(args$multilevelPathwaysList[[i]])
    stopifnot(all(c("pathway", "ES", "denomProb", "modeFraction") %in% names(group)))
    table <- data.frame(pathway = group$pathway, ES_bits = lisar_probe6_bits(group$ES),
      denomProb_bits = lisar_probe6_bits(group$denomProb), modeFraction = group$modeFraction,
      size = group$size, stringsAsFactors = FALSE)
    utils::write.table(table, file.path(path, paste0("group-", i, ".tsv")), sep = "\t", row.names = FALSE, quote = FALSE)
  }
  stopifnot(identical(seed_before, lisar_probe6_seed()))
  invisible(NULL)
}
lisar_probe6_final <- function(value) {
  seed_before <- lisar_probe6_seed()
  path <- lisar_probe6_new("r-fgsea-return")
  saveRDS(value, file.path(path, "return.rds"), version = 3L, compress = FALSE)
  table <- data.frame(pathway = value$pathway, pval_bits = lisar_probe6_bits(value$pval),
    ES_bits = lisar_probe6_bits(value$ES), stringsAsFactors = FALSE)
  utils::write.table(table, file.path(path, "pathway-bits.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)
  stopifnot(identical(seed_before, lisar_probe6_seed()))
  invisible(NULL)
}
lisar_probe6_division <- function(result, cpp.res, stage) {
  seed_before <- lisar_probe6_seed()
  path <- lisar_probe6_new(paste0("r-division-", stage))
  # All operands and actual R results are observed without repeating division.
  table <- data.frame(pathway = result$pathway, ES_bits = lisar_probe6_bits(result$ES),
    cppMPval_bits = lisar_probe6_bits(cpp.res$cppMPval), denomProb_bits = lisar_probe6_bits(result$denomProb),
    actual_pval_bits = lisar_probe6_bits(result$pval), modeFraction = result$modeFraction,
    stringsAsFactors = FALSE)
  utils::write.table(table, file.path(path, "operands-and-actual.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)
  stopifnot(identical(seed_before, lisar_probe6_seed()))
  invisible(NULL)
}
lisar_probe6_attach <- function() {
  stopifnot(requireNamespace("fgsea", quietly = TRUE))
  for (name in c("fgseaMultilevelCpp", "multilevelImpl", "fgseaMultilevel")) {
    fun <- get(name, envir = asNamespace("fgsea"))
    stopifnot(!inherits(fun, "functionWithTrace"))
    capture.output(fun, file = file.path(lisar_probe6_trace, paste0(name, "-untraced-function.txt")))
  }
  trace("fgseaMultilevelCpp", where = asNamespace("fgsea"), print = FALSE,
    tracer = quote(get("lisar_probe6_cpp_entry", envir = globalenv())(environment())),
    exit = quote(get("lisar_probe6_cpp_exit", envir = globalenv())(environment(), returnValue())))
  trace("multilevelImpl", where = asNamespace("fgsea"), print = FALSE,
    tracer = quote(get("lisar_probe6_multilevel_entry", envir = globalenv())(environment())))
  trace("fgseaMultilevel", where = asNamespace("fgsea"), print = FALSE,
    exit = quote(get("lisar_probe6_final", envir = globalenv())(returnValue())))
  invisible(NULL)
}
