\name{prepare_lisa_de_input}
\alias{prepare_lisa_de_input}
\title{Prepare an auditable differential-expression table for LISA}
\usage{
prepare_lisa_de_input(
  data,
  method = c("DESeq2", "edgeR", "limma"),
  columns = list(),
  positive_direction,
  rank_direction = c("same_as_effect", "opposite_to_effect"),
  duplicate_policy = "error",
  na_policy = c("retain", "error"),
  matrix_scale = NULL,
  deseq2_name = NULL, deseq2_contrast = NULL,
  limma_coef = NULL, limma_adjust_method = NULL, results_location = NULL
)
}
\arguments{
\item{data}{Complete prepared DE results: data frame, matrix with mapped
DE columns, TSV/TXT/TAB/CSV table path, DESeqResults, selected
fitted DESeqDataSet, TopTags, selected moderated MArrayLM, explicitly mapped
S4Vectors DataFrame, or prepared SummarizedExperiment rowData.}
\item{method}{Caller-declared table convention, not verification of producing software.}
\item{columns}{Named list mapping \code{symbol}, \code{logfc}, \code{rank},
\code{pvalue} and \code{padj} to source columns. Use \code{symbol = ".rownames"}
explicitly for non-default row names. Standard effect and P-value columns,
DESeq2 signed Wald \code{stat}, and limma \code{t} are defaults. Unsigned
DESeq2 LRT results require a separately computed signed rank. edgeR requires an explicit
signed rank column; unsigned multi-df F or LR statistics are never signed automatically.}
\item{positive_direction}{One non-empty description of what positive effects mean,
e.g. \code{"treated relative to control"}. No contrast is inferred.}
\item{rank_direction}{Whether the input signed rank is oriented like or opposite
to the effect. Opposite ranks are negated once. Comparable nonzero signs must agree.}
\item{duplicate_policy}{A LISA \code{"error"}, deterministic \code{select}, or
row-level \code{mapping_file} policy. DE statistics cannot be aggregated.
Identifier collisions are checked case-insensitively.}
\item{na_policy}{\code{"retain"} preserves missing statistics and records ranking
eligibility; \code{"error"} rejects them. Missing/empty identifiers, malformed
numbers and infinite statistics always raise errors.}
\item{matrix_scale}{Optional \code{"transformed"} or \code{"count_like"} declaration,
recorded separately. This function does not inspect or transform expression matrices.}
\item{deseq2_name, deseq2_contrast}{Exactly one selector for a fitted
\code{DESeqDataSet}; existing DESeq2 extraction and validation are reused.}
\item{limma_coef}{One explicit coefficient name for a fitted, moderated
\code{MArrayLM}. A multi-coefficient F test is not a signed ranking.}
\item{limma_adjust_method}{Explicit adjustment method passed to limma's
\code{topTable()} for the selected coefficient. Required for \code{MArrayLM}.}
\item{results_location}{For \code{SummarizedExperiment}, explicitly select
\code{"rowData"} containing already prepared DE results, declare \code{method}
and map all five columns. No assay is interpreted as DE results.}
}
\value{
List with canonical \code{data} and unfiltered \code{full_data} columns
\code{symbol}, \code{log2FoldChange}, \code{rank_value}, \code{pvalue}, \code{padj};
input-declaration \code{receipt}; \code{column_mapping}; \code{row_audit}; and
\code{duplicate_resolution}. \code{data} differs from \code{full_data} only when
an explicitly requested duplicate policy selects or remaps rows. Both effect and
rank describe \code{positive_direction}.
}
\description{
Adapts complete prepared DE tables and supported result classes through the
shared internal class boundary. Plain tables require no DE package. Preserves all tested rows, including non-significant and permitted
missing statistics, in \code{full_data}. Applies no adjusted-P filter, fits no
models, and infers no sample metadata. Default duplicate errors prevent implicit
row loss. Original noncanonical source columns are not copied into the output;
keep the source table as the original input artifact.
}
\details{
\code{DGEExact} and \code{DGELRT} are rejected before
output/readiness/hash files. Explicitly convert with
\code{edgeR::topTags(x, n = Inf, sort.by = "none", adjust.method = "<your choice>")},
then supply \code{TopTags} and a compatible explicitly selected signed rank.
Prepared P/FDR values, rows, source order and row names are preserved, including
permitted missing statistics. The rejection error renders this conversion
contract in one paragraph. Expression/count matrices are not prepared DE
tables. Serialized RDS paths remain excluded here; use the opt-in boundary in
\code{\link{run_lisa_de}}. \code{DataFrame} requires an explicit method and
all five column mappings; \code{.rownames} must be declared and must not be
default sequential IDs.
}
\examples{
results <- data.frame(gene = c("A", "B", "C"),
  log2FoldChange = c(1, -0.5, 0.1), stat = c(3, -1, 0.2),
  pvalue = c(0.001, 0.3, 0.8), padj = c(0.01, 0.6, NA))
prepared <- prepare_lisa_de_input(results, "DESeq2",
  columns = list(symbol = "gene"),
  positive_direction = "treated relative to control")
prepared$data
prepared$receipt
}
