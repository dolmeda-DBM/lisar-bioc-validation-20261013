// Diagnostic observer only; SPDX-License-Identifier: MIT.
// No statistical constants, expected results, rounding or replacement libm.
#pragma once
#include <memory>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>
#include <cfenv>

namespace lisar_probe6 {
inline thread_local std::ofstream stream;
inline thread_local unsigned long pvalue_index = 0;
inline thread_local unsigned long rows = 0;

inline void row(const char* field, long long index, const std::string& integer,
                const std::string& bits = "") {
    if (++rows > 1000000UL) throw std::runtime_error("probe6 trace row bound exceeded");
    stream << pvalue_index << '\t' << field << '\t' << index << '\t'
           << integer << '\t' << bits << '\n';
    if (!stream) throw std::runtime_error("probe6 trace write failed");
}
template <class T> inline void integer(const char* field, T value, long long index = -1) {
    row(field, index, std::to_string(value));
}
inline void value(const char* field, double value, long long index = -1) {
    static_assert(sizeof(double) == sizeof(std::uint64_t));
    static_assert(std::numeric_limits<double>::digits == 53);
    std::uint64_t bits;
    std::memcpy(&bits, &value, sizeof bits);
    // Format the stored binary64 word, not a recomputed decimal value.
    const char* digits = "0123456789abcdef";
    std::string hex(16, '0');
    for (int i = 15; i >= 0; --i) { hex[i] = digits[bits & 15]; bits >>= 4; }
    row(field, index, "", hex);
}
inline void begin_call() {
    const char* directory = std::getenv("LISAR_PROBE6_CALL_DIR");
    if (!directory || !*directory) throw std::runtime_error("probe6 missing R call capture directory");
    if (stream.is_open()) stream.close();
    stream.clear(); rows = 0; pvalue_index = 0;
    stream.open(std::string(directory) + "/cpp-trace.tsv", std::ios::out | std::ios::trunc);
    if (!stream) throw std::runtime_error("probe6 cannot open trace");
    stream << "pvalue_index\tfield\tindex\tinteger\tbinary64_bits_hex\n";
    integer("input.rounding_mode", std::fegetround());
}
inline void begin_pvalue(double ES, double eps, bool sign,
                         unsigned long sampleSize, unsigned long pathwaySize,
                         unsigned long rankCount, bool incorrect) {
    ++pvalue_index;
    value("pvalue.input_ES", ES); value("pvalue.input_eps", eps);
    integer("pvalue.input_sign", int(sign));
    integer("pvalue.sampleSize", sampleSize); integer("pvalue.pathwaySize", pathwaySize);
    integer("pvalue.rankCount", rankCount); integer("pvalue.incorrectRuler", int(incorrect));
}
template <class Score> inline void score(const char* prefix, const Score& s,
                                          std::uint64_t hash, bool positive, long long index) {
    row(prefix, index, std::to_string(s.NS) + "," + std::to_string(s.coef_NS) + "," +
        std::to_string(s.diff) + "," + std::to_string(s.coef_const) + "," +
        std::to_string(hash) + "," + std::to_string(int(positive)));
}
inline double beta(unsigned long a, unsigned long b, double left, double right) {
    // Original two narrowed digamma returns are subtracted exactly once.
    const double result = left - right;
    integer("beta.a", a); integer("beta.b", b);
    value("beta.left", left); value("beta.right", right); value("beta.return", result);
    return result;
}
inline double observe_exp(double input, double output) {
    // Native exp(input) has already been evaluated exactly once by the caller.
    value("exp.input", input); value("exp.return", output);
    return output;
}
inline void end_call() {
    integer("output.rounding_mode", std::fegetround());
    stream.flush();
    if (!stream) throw std::runtime_error("probe6 trace flush failed");
    stream.close();
}
} // namespace lisar_probe6
