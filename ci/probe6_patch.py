"""Pure text transformation of the exact pinned upstream source. No execution."""
import re


def once(text, before, after):
    assert text.count(before) == 1, (before, text.count(before))
    return text.replace(before, after)


def derive(files, arm):
    result = dict(files)
    name = "src/util.cpp"
    text = result[name]
    include = '#include "lisar_probe6_trace.hpp"\n'
    if arm:
        # The previously measured hypothesis is retained; no new numerical fix.
        include = '#include "lisar_probe_precision.hpp"\n' + include
    text = once(text, '#include "util.h"', include + '#include "util.h"')
    left = "lisar_probe::wide_digamma" if arm else "boost::math::digamma"
    text = once(text, "return boost::math::digamma(a) - boost::math::digamma(b + 1);",
        "return lisar_probe6::beta(a, b, " + left + "(a), " + left + "(b + 1));")
    result[name] = text

    name = "src/fgseaMultilevel.cpp"
    text = once(result[name], '#include "fgseaMultilevel.h"',
        '#include "lisar_probe6_trace.hpp"\n#include "fgseaMultilevel.h"')
    anchor = "    if (TYPEOF(ranks) != INTSXP) {"
    text = once(text, anchor,
        '    lisar_probe6::begin_call();\n'
        '    lisar_probe6::integer("input.seed", seed);\n'
        '    lisar_probe6::integer("input.pathwaySize", pathwaySize);\n'
        '    lisar_probe6::integer("input.sampleSize", sampleSize);\n'
        '    lisar_probe6::value("input.moveScale", moveScale);\n'
        '    lisar_probe6::value("input.eps", eps);\n'
        '    lisar_probe6::integer("input.sign", int(sign));\n' + anchor)
    anchor = "    const vector<double> esVector = as<std::vector<double> >(enrichmentScores);"
    text = once(text, anchor, anchor + '\n'
        '    for (int j = 0; j < posRanks.size(); ++j)\n'
        '        lisar_probe6::integer("input.absolute_rank", posRanks[j], j);\n'
        '    for (int j = 0; j < esVector.size(); ++j)\n'
        '        lisar_probe6::value("input.ES", esVector[j], j);')
    anchor = "    double minES = *min_element(begin(esVector), end(esVector));"
    text = once(text, anchor, anchor + '\n'
        '    lisar_probe6::value("input.maxES", maxES);\n'
        '    lisar_probe6::value("input.minES", minES);')
    anchor = "        pvalRes.push_back(get<0>(res));"
    text = once(text, anchor,
        '        lisar_probe6::value("output.cppMPval", get<0>(res), i);\n'
        '        lisar_probe6::integer("output.cppIsCpGeHalf", int(get<1>(res)), i);\n'
        '        lisar_probe6::value("output.log2err", get<2>(res), i);\n' + anchor)
    text = once(text, '    // return vector with pvalues and vector with conditional probability result',
        '    lisar_probe6::end_call();\n\n    // return vector with pvalues and vector with conditional probability result')
    result[name] = text

    name = "src/fgseaMultilevelSupplement.cpp"
    text = once(result[name], '#include "fgseaMultilevelSupplement.h"',
        '#include "lisar_probe6_trace.hpp"\n#include "fgseaMultilevelSupplement.h"')
    anchor = "    score_t NEED_ES{score_t::getMaxNS(), int64_t(score_t::getMaxNS() * ES_double), 1, 0};"
    text = once(text, anchor, anchor + '\n'
        '    lisar_probe6::score("extend.NEED_ES", NEED_ES, 0, false, -1);')
    start = "tuple <double, bool, double> EsRuler::getPvalue(double ES_double, double eps, bool sign){"
    text = once(text, start, start + '\n'
        '    lisar_probe6::begin_pvalue(ES_double, eps, sign, sampleSize, pathwaySize, ranks.size(), incorrectRuler);\n'
        '    lisar_probe6::integer("pvalue.level_count", levels.size());')
    before, after = text.split(start, 1)
    after = once(after, "    gsea_t ES{ES_score, 0};", "    gsea_t ES{ES_score, 0};\n"
        '    lisar_probe6::score("pvalue.ES_score", ES_score, 0, false, -1);')
    anchor = "    for (auto& lvl : levels) {"
    after = once(after, anchor,
        '    int lisar_probe6_level = 0;\n' + anchor + '\n'
        '        lisar_probe6::integer("level.index", lisar_probe6_level++);\n'
        '        lisar_probe6::score("level.bound", lvl.bound.first, lvl.bound.second, false, -1);\n'
        '        lisar_probe6::integer("level.low_count", lvl.lowScores.size());\n'
        '        lisar_probe6::integer("level.high_count", lvl.highScores.size());\n'
        '        for (int j = 0; j < lvl.lowScores.size(); ++j)\n'
        '            lisar_probe6::score("level.low_score", lvl.lowScores[j].first.first, lvl.lowScores[j].first.second, lvl.lowScores[j].second, j);\n'
        '        for (int j = 0; j < lvl.highScores.size(); ++j)\n'
        '            lisar_probe6::score("level.high_score", lvl.highScores[j].first.first, lvl.highScores[j].first.second, lvl.highScores[j].second, j);')
    # Preserve every original += expression and its order; log only after it.
    after, count = re.subn(r'(?m)^(\s*)(adjLogPval \+= betaMeanLog\([^\n]+\);)$',
        r'\1\2\n\1lisar_probe6::value("pvalue.accumulated_log", adjLogPval);', after)
    assert count == 5, count
    after, count = re.subn(r'(?m)^(\s*)(int numerator = \(sign \? cntLast : cntPositive\);)$',
        r'\1\2\n\1lisar_probe6::integer("pvalue.cntLast", cntLast);\n\1lisar_probe6::integer("pvalue.cntPositive", cntPositive);\n\1lisar_probe6::integer("pvalue.numerator", numerator);', after)
    assert count == 2, count
    assert after.count("exp(adjLogPval)") == 4
    after = after.replace("exp(adjLogPval)", "lisar_probe6::observe_exp(adjLogPval, exp(adjLogPval))")
    result[name] = before + start + after

    name = "R/fgseaMultilevel.R"
    text = result[name]
    anchor = '    result[, pval := pmin(1, cpp.res$cppMPval / denomProb)]'
    result[name] = once(text, anchor,
        '    get("lisar_probe6_division", envir = globalenv())(result, cpp.res, "before")\n' + anchor + '\n'
        '    get("lisar_probe6_division", envir = globalenv())(result, cpp.res, "after")')
    return result
