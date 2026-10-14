# Native runner-only, minimal BH preparation for the primitive diagnostic.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true",
  Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted",
  Sys.getenv("LISAR_REPOSITORY_PRIVATE") == "false",
  Sys.getenv("GITHUB_REPOSITORY") == "dolmeda-DBM/lisar-bioc-validation-20261013",
  Sys.getenv("GITHUB_RUN_ATTEMPT") == "1",
  Sys.getenv("GITHUB_SHA") == Sys.getenv("EXPECTED_HEAD_SHA"),
  Sys.info()[["sysname"]] == "Darwin",
  Sys.info()[["machine"]] == Sys.getenv("LISAR_EXPECTED_ARCH"), getRversion() == "4.6.1")
root <- normalizePath(Sys.getenv("LISAR_VALIDATION_ROOT"), mustWork = TRUE)
output <- file.path(root, "primitive")
stopifnot(!dir.exists(output))
dir.create(output)
lib <- file.path(output, "BH-library")
dir.create(lib)
utils::install.packages("BH", lib = lib, repos = "https://cloud.r-project.org", dependencies = FALSE)
.libPaths(c(lib, .libPaths()))
description <- utils::packageDescription("BH")
capture.output(description, file = file.path(output, "BH-description-print.txt"))
stopifnot(identical(description$Version, "1.90.0-1"),
  utils::packageVersion("BH") == package_version("1.90.0-1"))
include <- normalizePath(system.file("include", package = "BH"), mustWork = TRUE)
writeLines(include, file.path(output, "BH-include-path.txt"))
stopifnot(file.copy(system.file("DESCRIPTION", package = "BH"),
  file.path(output, "BH-DESCRIPTION.txt"), overwrite = FALSE),
  file.copy(system.file("LICENSE_1_0.txt", package = "BH"),
    file.path(output, "BH-BSL-1.0.txt"), overwrite = FALSE))
capture.output(sessionInfo(), file = file.path(output, "primitive-preflight-sessionInfo.txt"))
writeLines(c(paste0("LISAR_PRIMITIVE_BH_INCLUDE=", include),
  paste0("LISAR_R_EXECUTABLE=", file.path(R.home("bin"), "R"))),
  Sys.getenv("GITHUB_ENV"), sep = "\n", useBytes = TRUE)
