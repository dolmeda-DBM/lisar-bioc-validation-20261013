# Exact preserved long cases; helpers below are unchanged original text.
lisa_nes_variant_fixture <- function() {
  x <- data.frame(category_id = c(rep("MIX", 5), "ONE", "NONE", "NONE", "ZERO", "ZERO", "OTHER_UNCLASSIFIED"),
    pathway = c("s1", "s2", "s3", "s4", "s5", "001", "n1", "n2", "z1", "z2", "u1"),
    NES = c(-2, -1, 0, 1, 4, 1.2345678901234567, 2, 8, -1, 1, 99),
    padj = c(.01, .02, .03, .04, .05, .001, .3, NA, .01, .01, .001),
    stringsAsFactors = FALSE)
  # One repeated dictionary assignment is not another enriched set.
  rbind(x, x[1L, , drop = FALSE])
}

lisa_nes_variant_summary_fixture <- function() {
  data.frame(category_id = c("MIX", "ONE", "NONE", "ZERO", "EMPTY"),
    category_display_name = c("Mixed directions", "Single member", "No significant support", "Exactly zero mean", "No members"),
    mean_NES = c(.4, 1.2345678901234567, NA, 0, NA),
    n_genesets = c(5L, 1L, 0L, 2L, 0L), stringsAsFactors = FALSE)
}

test_that("contrast variants keep independent supports and the unchanged existing delta", {
  a <- lisa_nes_variant_summary_fixture()
  b <- a
  b$mean_NES <- -b$mean_NES
  members_b <- lisa_nes_variant_fixture(); members_b$NES <- -members_b$NES
  contrast <- data.frame(category_id = a$category_id,
    display_mean_NES_A = c(a$mean_NES[1:2], .3, 0, NA),
    display_mean_NES_B = c(b$mean_NES[1:2], -.2, 0, NA),
    delta_mean_NES = c(.8, 2 * a$mean_NES[[2]], .5, 0, NA))
  before <- contrast
  v <- lisaR:::lisa_prepare_contrast_nes_variants(contrast, a, b,
    lisa_nes_variant_fixture(), members_b, .05)
  expect_identical(contrast, before)
  expect_identical(v$source$delta_mean_NES[1:5], contrast$delta_mean_NES)
  expect_false(any(grepl("delta.*(p25|p75|quantile)", names(v$source))))
  sa <- v$source[v$source$side == "A", ]; sb <- v$source[v$source$side == "B", ]
  expect_equal(sa$p25_NES, -sb$p75_NES)
  expect_equal(sa$positive_pct, sb$negative_pct)
  expect_identical(sa$endpoint_state[[3L]], "contextual_not_significant")
  expect_true(is.na(sa$median_NES[[3L]]))
  expect_true(is.na(sb$p25_NES[[3L]]))
  expect_no_warning(ggplot2::ggplot_build(lisaR:::plot_lisa_category_nes_variant(v, "dispersion")))
  # JSON serialization changes the representation of named side labels. The
  # legend order must not depend on ggplot's implicit guide hash ordering.
  skip_if_not_installed("png")
  folder <- tempfile("paired-nes-recipe-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  files <- lisaR:::render_lisa_category_nes_variants(v, folder, formats = "png",
    width = 10, height = 5, dpi = 90)
  for (i in seq_len(nrow(files))) {
    target <- file.path(folder, paste0("replayed-", files$variant[[i]], ".png"))
    lisaR:::lisa_reproduce_category_nes_variant(files$source[[i]], files$settings[[i]], target)
    expect_identical(png::readPNG(files$path[[i]]), png::readPNG(target))
  }
})

test_that("default selection produces four variants, explicit subset produces only its files", {
  skip_if_not_installed("ggplot2")
  expect_identical(lisaR:::lisa_nes_variants_validate(), c("clean", "percentages", "direction", "dispersion"))
  for (bad in list(character(), c("clean", "clean"), "all", NA_character_))
    expect_error(lisaR:::lisa_nes_variants_validate(bad), "nonempty unique")
  v <- lisaR:::lisa_prepare_category_nes_variants(lisa_nes_variant_summary_fixture(), lisa_nes_variant_fixture(), .05)
  dir <- tempfile("nes-selected-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- lisaR:::render_lisa_category_nes_variants(v, dir, variants = "direction",
    formats = "png", width = 10, height = 5, dpi = 90)
  expect_equal(nrow(out), 1)
  expect_identical(out$variant, "direction")
  expect_true(all(file.exists(c(out$path, out$source, out$settings))))
  expect_length(list.files(dir, pattern = "clean|dispersion"), 0)
  settings <- jsonlite::read_json(out$settings[[1]], simplifyVector = TRUE)
  expect_identical(settings$variant, "direction")
  expect_identical(settings$presentation_version, "2.0")
  expect_identical(settings$render_context$profile, "fresh_r_process_v1")
  expect_equal(settings$x_limits, v$metadata$x_limits)
  expect_match(settings$quantiles, "type 7")
})

test_that("exact-source recipe reproduces pixels and rejects content changes", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("png")
  summary <- lisa_nes_variant_summary_fixture()
  summary$category_id[[2L]] <- "001"
  x <- lisa_nes_variant_fixture(); x$category_id[x$category_id == "ONE"] <- "001"
  v <- lisaR:::lisa_prepare_category_nes_variants(summary, x, .05)
  dir <- tempfile("nes-recipe-"); dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- lisaR:::render_lisa_category_nes_variants(v, dir, variants = "dispersion",
    formats = "png", width = 10, height = 5, dpi = 90)
  target <- file.path(dir, "reproduced.png")
  expect_no_warning(lisaR:::lisa_reproduce_category_nes_variant(out$source[[1]], out$settings[[1]], target))
  expect_identical(png::readPNG(out$path[[1]]), png::readPNG(target))
  stored <- utils::read.delim(out$source[[1]], colClasses = "character", quote = '"', check.names = FALSE)
  expect_true("001" %in% stored$category_id)
  expect_identical(as.numeric(stored$mean_NES[[2]]), summary$mean_NES[[2]])
  cat("\n", file = out$source[[1]], append = TRUE)
  expect_error(lisaR:::lisa_reproduce_category_nes_variant(out$source[[1]], out$settings[[1]], target), "hash mismatch")
})

test_that("contrast subsets preserve canonical membership, endpoints and delta", {
  a <- lisa_nes_variant_summary_fixture(); b <- a
  b$mean_NES[[2L]] <- -b$mean_NES[[2L]]
  members_b <- lisa_nes_variant_fixture()
  members_b$NES[members_b$category_id == "ONE"] <- -members_b$NES[members_b$category_id == "ONE"]
  contrast <- data.frame(category_id = a$category_id,
    display_mean_NES_A = c(a$mean_NES[1:2], .3, 0, NA),
    display_mean_NES_B = c(b$mean_NES[1:2], -.2, 0, NA),
    delta_mean_NES = c(0, 2 * a$mean_NES[[2L]], .5, 0, NA),
    is_same_direction = c(TRUE, FALSE, FALSE, FALSE, FALSE),
    is_opposite_direction = c(FALSE, TRUE, FALSE, FALSE, FALSE))
  prepared <- lisaR:::lisa_prepare_contrast_nes_variants(contrast, a, b,
    lisa_nes_variant_fixture(), members_b, .05)
  before <- prepared
  same <- lisaR:::lisa_nes_select_plot_set(prepared, "same_direction")
  opposite <- lisaR:::lisa_nes_select_plot_set(prepared, "opposite_direction")
  expect_identical(same$source$category_id, c("MIX", "MIX"))
  expect_identical(opposite$source$category_id, c("ONE", "ONE"))
  expect_identical(same$source$delta_mean_NES, c(0, 0))
  expect_identical(opposite$source$delta_mean_NES, rep(contrast$delta_mean_NES[[2L]], 2))
  expect_identical(same$metadata$x_limits, prepared$metadata$x_limits)
  expect_identical(opposite$metadata$x_limits, prepared$metadata$x_limits)
  expect_identical(prepared, before)
  missing <- prepared; missing$source$is_same_direction <- NULL
  expect_error(lisaR:::lisa_nes_select_plot_set(missing, "same_direction"), "canonical contrast membership")
  expect_error(lisaR:::lisa_nes_plot_sets_validate(character(), "contrast"), "Invalid nonempty")
  expect_error(lisaR:::lisa_nes_plot_sets_validate("opposite_direction", "single"), "Invalid nonempty")
  skip_if_not_installed("ggplot2")
  directory <- tempfile("nes-subsets-")
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  files <- lisaR:::render_lisa_category_nes_variants(prepared, directory, variants = "percentages",
    formats = "png", width = 10, height = 5, dpi = 72,
    plot_sets = c("all", "same_direction", "opposite_direction"))
  expect_identical(files$plot_set, c("all", "same_direction", "opposite_direction"))
  expect_length(unique(files$path), 3L)
  expect_identical(basename(files$path[[1L]]), "category_nes_percentages.png")
  expect_identical(basename(files$path[[2L]]), "category_nes_same_direction_percentages.png")
  for (i in seq_len(nrow(files))) {
    settings <- jsonlite::read_json(files$settings[[i]], simplifyVector = TRUE)
    expect_identical(settings$plot_set, files$plot_set[[i]])
    expect_identical(settings$source_sha256, digest::digest(file = files$source[[i]], algo = "sha256"))
  }
})

test_that("fresh-device origin and replay ignore preceding 180 and 300 dpi plots", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("png")
  skip_if_not(capabilities("cairo"))
  s <- lisa_nes_variant_summary_fixture()
  s$category_display_name <- paste(s$category_display_name, "with a deliberately long scientific label")
  s$macrogroup_name <- c("First long supercategory", "First long supercategory", rep("Second supercategory", 3))
  a <- s; b <- s; b$mean_NES <- -b$mean_NES
  members_b <- lisa_nes_variant_fixture(); members_b$NES <- -members_b$NES
  contrast <- data.frame(category_id = a$category_id,
    display_mean_NES_A = c(a$mean_NES[1:2], .3, 0, NA),
    display_mean_NES_B = c(b$mean_NES[1:2], -.2, 0, NA),
    delta_mean_NES = c(.8, 2 * a$mean_NES[[2L]], .5, 0, NA))
  prepared <- lisaR:::lisa_prepare_contrast_nes_variants(contrast, a, b,
    lisa_nes_variant_fixture(), members_b, .05,
    label_a = "Responders: ON-treatment minus PRE-treatment",
    label_b = "Progressors: ON-treatment minus PRE-treatment",
    subtitle = "Two independently adjusted analyses\nPositive delta indicates a larger change in A.")
  directory <- tempfile("nes-device-history-"); dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  previous <- ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) +
    ggplot2::geom_text(label = "Text-rich previous drawing") + ggplot2::theme_minimal()
  for (history in c(180, 300)) {
    ggplot2::ggsave(file.path(directory, paste0("previous-", history, ".png")), previous,
      width = 4, height = 3, dpi = history)
    files <- lisaR:::render_lisa_category_nes_variants(prepared, file.path(directory, paste0("origin-", history)),
      formats = "png", width = 13, height = 7, dpi = 180)
    for (i in seq_len(nrow(files))) {
      target <- file.path(directory, paste0("replay-", history, "-", files$variant[[i]], ".png"))
      lisaR:::lisa_reproduce_category_nes_variant(files$source[[i]], files$settings[[i]], target)
      expect_identical(png::readPNG(files$path[[i]]), png::readPNG(target))
      if (history == 300) expect_identical(png::readPNG(target),
        png::readPNG(file.path(directory, paste0("replay-180-", files$variant[[i]], ".png"))))
    }
  }
})
