# Exact preserved long cases; helpers below are unchanged original text.


lollipop_audit_fixture <- function() data.frame(
  category_id = c("CAT_B", "CAT_EMPTY", "CAT_A"),
  category_display_name = c("B programme", "No support", "A programme"),
  macrogroup_id = c("M2", "M1", "M1"),
  macrogroup_name = c("Second group", "First group", "First group"),
  macrogroup_order = c(2, 1, 1), category_order_within_macrogroup = c(1, 2, 1),
  mean_NES = c(-1.2, NA_real_, 1.8), n_genesets = c(2L, 0L, 5L),
  same_direction_pct = c(50, NA_real_, 80), consistency = c(.5, NA_real_, .8),
  color = c("#115599", "#777777", "#BB5500"), stringsAsFactors = FALSE)

test_that("lollipop recipes retain geometry support groups order and context", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("png")
  fixture <- lollipop_audit_fixture()
  script <- system.file("scripts", "reproduce_lisa_figure.R", package = "lisaR")
  exprs <- parse(script)
  for (variant in c("plain", "direction")) for (grouped in c(TRUE, FALSE)) {
    source <- tempfile(fileext = ".tsv")
    original <- tempfile(fileext = ".png")
    replay <- tempfile(fileext = ".png")
    title <- "Response %00"
    subtitle <- "On treatment\nminus pretreatment"
    lisaR:::lisa_write_lollipop_figure_source(fixture, source, grouped,
      "mean_NES", title, subtitle, "Positive favours on treatment",
      annotation_variant = variant, figure_width = 6, figure_height = 4,
      figure_dpi = 72)
    e <- new.env(parent = globalenv())
    e$output_png <- replay
    for (expr in exprs) if (is.call(expr) && identical(expr[[1L]], as.name("<-")) &&
        identical(expr[[2L]], as.name("render_lisa_lollipop"))) eval(expr, e)
    written <- utils::read.delim(source, check.names = FALSE, quote = "")
    e$render_lisa_lollipop(written)
    renderer <- if (variant == "plain") lisaR:::plot_lisa_gsea_lollipop else lisaR:::plot_lisa_gsea_direction_lollipop
    plot <- renderer(fixture, grouped, "mean_NES")
    plot <- lisaR:::lisa_apply_plot_context(plot, title, subtitle, "Positive favours on treatment")
    ggplot2::ggsave(original, plot, width = 6, height = 4, dpi = 72,
      bg = "white", device = function(filename, width, height, bg) {
        grDevices::png(filename, width = width, height = height,
          units = "in", res = 72, type = "cairo", bg = bg)
      }, limitsize = FALSE)
    expect_equal(png::readPNG(replay), png::readPNG(original), tolerance = 1 / 255)
    expect_identical(written$selected_for_plot, c(TRUE, FALSE, TRUE))
    expect_identical(written$color, fixture$color)
  }
})
