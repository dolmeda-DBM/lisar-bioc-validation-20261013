test_that("portable inference accepts only bounded p variation with exact semantics", {
  e <- data.frame(collection = c("A", "A"), pathway = c("one", "two"),
    pval = c("1e-10", "0.2"), NES = c("2", "-1"), stringsAsFactors = FALSE)
  a <- e; a$pval[1] <- sprintf("%.17g", 1e-10 * (1 + 1e-13))
  expect_true(portable_compare_inference(a, e, c("collection", "pathway")))
  a <- e; a$pval[1] <- "1e-9"
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "tolerance")
  for (bad in c("NaN", "Inf", "-Inf", "garbage", "-0.1", "1.1")) {
    a <- e; a$pval[1] <- bad
    expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "invalid p")
    b <- a
    expect_error(portable_compare_inference(a, b, c("collection", "pathway")), "invalid p")
  }
  a <- e; a$NES[1] <- "2.000000000000001"
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "exact column")
  a <- e; a$pval[1] <- NA_character_
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "missing p")
  b <- a
  expect_true(portable_compare_inference(a, b, c("collection", "pathway")))
  b$pval[1] <- "1"
  expect_error(portable_compare_inference(a, b, c("collection", "pathway")), "missing p")
  b <- e; b$pval[1] <- "0"; a <- b; a$pval[1] <- "1e-300"
  expect_error(portable_compare_inference(a, b, c("collection", "pathway")), "zero p")
  expect_true(portable_compare_inference(b, b, c("collection", "pathway")))
  a <- e[1, , drop = FALSE]
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "row count")
  a <- e; a$pathway[2] <- "one"
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "duplicate key")
  a <- e; a$pathway[2] <- "different"
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "membership")
  a <- e[2:1, ]; rownames(a) <- NULL
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "row order")
  a <- e; a$extra <- "unexpected"
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "schema")
  a <- e[c("pathway", "collection", "pval", "NES")]
  expect_error(portable_compare_inference(a, e, c("collection", "pathway")), "schema")
})

test_that("relative agreement cannot hide threshold crosses or ties", {
  for (threshold in c(.05, .01, .001, .0001)) {
    e <- data.frame(id = "one", pval = sprintf("%.17g", threshold), stringsAsFactors = FALSE)
    a <- e; a$pval <- sprintf("%.17g", threshold * (1 + 1e-13))
    expect_error(portable_compare_inference(a, e, "id"), "classification boundary")
  }
  e <- data.frame(id = c("one", "two"), pval = c("0.2", "0.2"), stringsAsFactors = FALSE)
  a <- e; a$pval[1] <- sprintf("%.17g", .2 * (1 + 1e-13))
  expect_error(portable_compare_inference(a, e, "id"), "ranking or tie")
  e$pval[1] <- sprintf("%.17g", .2 * (1 - 1e-13))
  expect_error(portable_compare_inference(a, e, "id"), "ranking or tie")
})

test_that("content IDs remain local and exact semantic outputs cannot drift", {
  e <- data.frame(id = c("one", "two"), pval = c("0.2", "0.3"),
    analysis_id = "smoke", family_id = "smoke:0123456789abcdef", support_grade = "S4",
    minimum_enriched_sets = "2", significant = "FALSE", stringsAsFactors = FALSE)
  a <- e; a$family_id <- "smoke:fedcba9876543210"
  expect_true(portable_compare_inference(a, e, "id"))
  a$family_id[1] <- e$family_id[1]
  expect_error(portable_compare_inference(a, e, "id"), "family_id")
  for (column in c("support_grade", "minimum_enriched_sets", "significant")) {
    a <- e; a[[column]][1] <- "changed"
    expect_error(portable_compare_inference(a, e, "id"), "exact column")
  }
})
