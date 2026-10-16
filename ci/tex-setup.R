# Native isolated toolchain; do not skip the PDF or silently downgrade checks.
stopifnot(Sys.getenv("GITHUB_ACTIONS") == "true", Sys.getenv("RUNNER_ENVIRONMENT") == "github-hosted")
root <- Sys.getenv("LISAR_VALIDATION_ROOT")
target <- file.path(root, "tinytex")
stopifnot(dir.exists(root), !file.exists(target))
tinytex::install_tinytex(dir = target, bundle = "TinyTeX-1", add_path = FALSE)
bins <- list.dirs(file.path(target, "bin"), recursive = FALSE, full.names = TRUE)
stopifnot(length(bins) == 1L)
Sys.setenv(PATH = paste(bins, Sys.getenv("PATH"), sep = .Platform$path.sep))
write(bins, Sys.getenv("GITHUB_PATH"), append = TRUE)
tinytex::tlmgr_install(c("makeindex", "latexmk", "collection-latexrecommended",
  "collection-fontsrecommended", "collection-latexextra"))
commands <- Sys.which(c("pdflatex", "makeindex", "kpsewhich", "bibtex", "tlmgr"))
jsonlite::write_json(list(commands = as.list(commands), tinytex_root = target),
  file.path(root, "tex-install.json"), auto_unbox = TRUE, pretty = TRUE)
stopifnot(all(nzchar(commands)))
if (.Platform$OS.type == "windows") write("R_TEXI2DVICMD=emulation", Sys.getenv("GITHUB_ENV"), append = TRUE)
