# GPL-3.0-or-later. Runner-only provisioning, never a local workstation.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true",
  Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted",
  Sys.getenv("LISAR_REPOSITORY_PRIVATE") == "false",
  Sys.getenv("GITHUB_REPOSITORY") == "dolmeda-DBM/lisar-bioc-validation-20261013",
  Sys.info()[["sysname"]] %in% c("Linux", "Windows"), getRversion() == "4.6.1",
  Sys.getenv("GITHUB_RUN_ATTEMPT") == "1")
root <- Sys.getenv("LISAR_VALIDATION_ROOT")
stopifnot(nzchar(root), dir.exists(root))
lib <- file.path(root, "library")
stopifnot(!dir.exists(lib))
dir.create(lib)
.libPaths(c(lib, .libPaths()))
Sys.setenv(R_LIBS_USER = lib)
options(repos = c(CRAN = "https://cloud.r-project.org"), Ncpus = 1L)
capture.output(sessionInfo(), file = file.path(root, "provision-sessionInfo-before.txt"))
install.packages(c("BiocManager", "digest", "jsonlite", "remotes"), lib = lib)
config <- jsonlite::read_json("ci/config.json", simplifyVector = TRUE)
manifest <- jsonlite::read_json("candidate/manifest.json", simplifyVector = TRUE)
stopifnot(identical(config$repository, Sys.getenv("GITHUB_REPOSITORY")),
  is.logical(config$allow_shiny_backend), length(config$allow_shiny_backend) == 1L,
  !is.na(config$allow_shiny_backend), identical(config$execution_priority, "low"),
  config$workers == 2L, identical(manifest$R_version, "4.6.1"),
  identical(manifest$Bioconductor_version, "3.24"),
  identical(manifest$testthat_version, "3.3.2"),
  identical(digest::digest(file = manifest$tarball, algo = "sha256", serialize = FALSE),
    manifest$tarball_sha256))
if (!config$allow_shiny_backend) {
  stopifnot(length(find.package("shiny", quiet = TRUE)) == 0L,
    !"shiny" %in% loadedNamespaces())
}
source <- file.path(root, "input", "lisaR")
stopifnot(dir.exists(source))
desc <- read.dcf(file.path(source, "DESCRIPTION"))
# Trim AFTER removing a wrapped version constraint: avoid the historical hommel\\n bug.
fields <- intersect(c("Depends", "Imports", "Suggests", "LinkingTo"), colnames(desc))
packages <- unique(trimws(sub("[[:space:]]*\\(.*", "",
  trimws(unlist(strsplit(paste(desc[1L, fields], collapse = ","), ","))))))
packages <- setdiff(packages, c("R", rownames(installed.packages(priority = "base")), "testthat"))
if (!config$allow_shiny_backend) packages <- setdiff(packages, "shiny")
BiocManager::install(version = "3.24", lib = lib, ask = FALSE, update = FALSE)
stopifnot(as.character(BiocManager::version()) == "3.24")
BiocManager::install(packages, lib = lib, ask = FALSE, update = FALSE, dependencies = NA)
remotes::install_version("testthat", version = "3.3.2", lib = lib,
  upgrade = "never", dependencies = NA)
if (!config$allow_shiny_backend) {
  stopifnot(length(find.package("shiny", quiet = TRUE)) == 0L,
    !"shiny" %in% loadedNamespaces())
} else {
  stopifnot(requireNamespace("shiny", quietly = TRUE))
}
writeLines(c(paste0("R_LIBS=", paste(.libPaths(), collapse = .Platform$path.sep)),
  paste0("R_LIBS_USER=", lib),
  paste0("LISAR_R_EXECUTABLE=", file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"))),
  Sys.getenv("GITHUB_ENV"), sep = "\n", useBytes = TRUE)
stopifnot(getRversion() == "4.6.1",
  as.character(utils::packageVersion("BiocVersion")) == "3.24.0",
  as.character(utils::packageVersion("testthat")) == "3.3.2")
available <- setNames(vapply(c(packages, "testthat"), requireNamespace,
  logical(1), quietly = TRUE), c(packages, "testthat"))
jsonlite::write_json(list(status = "PROVISIONED_NOT_PACKAGE_PASS",
  R = R.version.string, Rscript = file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"),
  R_executable = file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"), libraries = as.list(.libPaths()),
  conda_prefix = Sys.getenv("CONDA_PREFIX", unset = NA_character_),
  namespaces_available = as.list(available),
  all_installed_packages = as.data.frame(installed.packages()[, c("Package", "Version", "LibPath"),
    drop = FALSE], stringsAsFactors = FALSE),
  Bioconductor_version = as.character(BiocManager::version()),
  candidate_sha256 = manifest$tarball_sha256, allow_shiny_backend = config$allow_shiny_backend,
  capabilities = as.list(capabilities()), system = as.list(Sys.info()),
  commands = as.list(Sys.which(c("R", "Rscript", "pandoc", "pdflatex", "make", "gcc", "g++")))),
  file.path(root, "environment.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
capture.output(sessionInfo(), file = file.path(root, "provision-sessionInfo-after.txt"))
stopifnot(all(available), nzchar(Sys.which("pandoc")), nzchar(Sys.which("pdflatex")))
