// SPDX-License-Identifier: BSL-1.0. Native diagnostic only, never acceptance.
#include "probe3_precision.hpp"
#include "primitive-source/util.h"
#include <boost/version.hpp>
#include <array>
#include <cfenv>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <locale>
#include <sstream>
#include <stdexcept>
#include <string>

static_assert(BOOST_VERSION == 109000, "Exact BH/Boost version required");
static_assert(sizeof(double) == sizeof(std::uint64_t));
static_assert(std::numeric_limits<double>::digits == 53);
static_assert(std::numeric_limits<double>::is_iec559);
static_assert(std::is_same<decltype(boost::math::digamma(1UL)), double>::value);
static_assert(std::is_same<decltype(boost::math::trigamma(1)), double>::value);

std::uint64_t bits(double x) {
    std::uint64_t answer;
    std::memcpy(&answer, &x, sizeof(answer));
    return answer;
}
void row(std::ostream& stream, const char* function, const char* input_type,
         const char* mode, int a, int b, double value) {
    if (!std::isfinite(value)) throw std::runtime_error("Nonfinite positive-domain primitive");
    std::ostringstream hexadecimal, representation;
    hexadecimal << std::hexfloat << value;
    representation << std::hex << std::setfill('0') << std::setw(16) << bits(value);
    stream << function << '\t' << input_type << '\t' << mode << '\t' << a << '\t' << b
           << '\t' << std::setprecision(std::numeric_limits<double>::max_digits10) << value
           << '\t' << hexadecimal.str() << '\t' << representation.str() << '\n';
}
template <class T> void limits(std::ostream& out, const char* type) {
    out << type << '\t' << sizeof(T) << '\t' << std::numeric_limits<T>::radix << '\t'
        << std::numeric_limits<T>::digits << '\t' << std::numeric_limits<T>::digits10 << '\t'
        << std::numeric_limits<T>::min_exponent << '\t' << std::numeric_limits<T>::max_exponent << '\n';
}
template <class Input> void dispatch(std::ostream& out, const char* name) {
    using D = lisar_probe::Dispatch<Input>;
    out << name << '\t' << D::precision << '\t' << D::digamma_tag << '\t' << D::trigamma_tag
        << '\t' << std::numeric_limits<typename D::DefaultEval>::digits
        << '\t' << std::is_same<typename D::DefaultEval, long double>::value
        << '\t' << std::numeric_limits<typename D::NoPromoteEval>::digits << '\n';
}
template <class Input> std::array<double, 3> digamma(Input x) {
    return {boost::math::digamma(x), boost::math::digamma(x, lisar_probe::NoPromotePolicy()),
            lisar_probe::wide_digamma(x)};
}
template <class Input> std::array<double, 3> trigamma(Input x) {
    return {boost::math::trigamma(x), boost::math::trigamma(x, lisar_probe::NoPromotePolicy()),
            lisar_probe::wide_trigamma(x)};
}
int main(int argc, char** argv) {
    if (argc != 2) throw std::runtime_error("One previously-created output directory required");
    std::locale::global(std::locale::classic());
    const std::string output(argv[1]);
    std::ofstream meta(output + "/limits.tsv"), policy(output + "/dispatch.tsv"), data(output + "/primitives.tsv"), settings(output + "/metadata.tsv");
    if (!meta || !policy || !data || !settings) throw std::runtime_error("Output stream could not open");
    meta << "type\tsizeof\tradix\tdigits\tdigits10\tmin_exponent\tmax_exponent\n";
    settings << "key\tvalue\n";
    limits<double>(meta, "double"); limits<long double>(meta, "long double");
    limits<unsigned long>(meta, "unsigned long"); limits<int>(meta, "int");
    limits<lisar_probe::Wide64>(meta, "software64_et_off");
    limits<boost::math::tools::largest_float>(meta, "Boost largest_float");
    settings << "Boost_numeric_traits_largest_float_digits\t"
         << boost::math::tools::numeric_traits<boost::math::tools::largest_float>::digits << "\n";
    policy << "input\tprecision_input\tdigamma_tag\ttrigamma_tag\tdefault_eval_digits\tdefault_eval_is_long_double\tno_promote_eval_digits\n";
    dispatch<unsigned long>(policy, "unsigned long"); dispatch<int>(policy, "int");
    settings << "rounding_mode\t" << std::fegetround() << "\n";
    settings << "default_promote_double\t" << lisar_probe::DefaultPolicy::promote_double_type::value << "\n";
    settings << "wide_as_is_BIG_CONSTANT_D53_uses_largest_float\t" << lisar_probe::wide_constant_uses_largest_float<53> << "\n";
    settings << "wide_as_is_BIG_CONSTANT_D64_uses_largest_float\t" << lisar_probe::wide_constant_uses_largest_float<64> << "\n";
#ifdef LISAR_PROBE_FORCE_WIDE_STRING_CONSTANTS
    settings << "wide_constant_construction\tforce_source_string_hypothesis\n";
#else
    settings << "wide_constant_construction\texact_BH_as_is\n";
#endif
#ifdef BOOST_MATH_NO_LONG_DOUBLE_MATH_FUNCTIONS
    settings << "BOOST_MATH_NO_LONG_DOUBLE_MATH_FUNCTIONS\t1\n";
#else
    settings << "BOOST_MATH_NO_LONG_DOUBLE_MATH_FUNCTIONS\t0\n";
#endif
#ifdef BOOST_MATH_USE_FLOAT128
    settings << "BOOST_MATH_USE_FLOAT128\t1\n";
#else
    settings << "BOOST_MATH_USE_FLOAT128\t0\n";
#endif
    settings << "compiler\t" << __VERSION__ << "\n";
    data << "function\tinput_type\tmode\ta\tb\tdecimal\thexfloat\tbinary64_bits_hex\n";
    const char* modes[] = {"default_Boost", "explicit_no_promote", "software64_input_dispatch"};
    std::array<std::array<double, 3>, 103> psi{};
    std::array<std::array<double, 3>, 103> tri{};
    for (int n = 1; n <= 102; ++n) {
        const auto pu = digamma(static_cast<unsigned long>(n)), pi = digamma(n);
        const auto tu = trigamma(static_cast<unsigned long>(n)), ti = trigamma(n);
        psi[n] = pu; tri[n] = ti;
        for (int mode = 0; mode < 3; ++mode) {
            row(data, "digamma", "unsigned long", modes[mode], n, 0, pu[mode]);
            row(data, "digamma", "int", modes[mode], n, 0, pi[mode]);
            row(data, "trigamma", "unsigned long", modes[mode], n, 0, tu[mode]);
            row(data, "trigamma", "int", modes[mode], n, 0, ti[mode]);
        }
        row(data, "log", "double", "native_libm", n, 0, std::log(static_cast<double>(n)));
        row(data, "log", "long double then cast", "native_libm", n, 0, static_cast<double>(std::log(static_cast<long double>(n))));
        row(data, "log", "software64 then cast", "software64", n, 0, static_cast<double>(log(lisar_probe::Wide64(n))));
        row(data, "exp_log", "double", "native_libm", n, 0, std::exp(std::log(static_cast<double>(n))));
    }
    // Cartesian primitive domain, not a statistical parameter modification.
    // b+1 ranges 1..102; each psi is already double before the subtraction.
    for (int a = 1; a <= 102; ++a) for (int b = 0; b <= 101; ++b) {
        const double exact_original = betaMeanLog(a, b); // exact upstream util.cpp
        if (bits(exact_original) != bits(psi[a][0] - psi[b + 1][0]))
            throw std::runtime_error("Original util.cpp differs from default API per-function cast boundary");
        row(data, "betaMeanLog", "unsigned long", "exact_original_util_cpp", a, b, exact_original);
        for (int mode = 0; mode < 3; ++mode)
            row(data, "betaMeanLog", "unsigned long", modes[mode], a, b, psi[a][mode] - psi[b + 1][mode]);
    }
    for (int level = 0; level <= 32; ++level) {
        row(data, "multilevelError", "int", "exact_original_util_cpp", level, 101, multilevelError(level, 101));
        for (int mode = 0; mode < 3; ++mode)
            row(data, "multilevelError", "int", modes[mode], level, 101,
                std::sqrt(level * (tri[51][mode] - tri[102][mode])) / std::log(2));
    }
#ifdef LISAR_PROBE_FORCE_WIDE_STRING_CONSTANTS
    settings << "wide_string_constant_calls\t" << lisar_probe::wide_string_calls << "\n";
    settings << "wide_string_constant_calls_D53\t" << lisar_probe::wide_string_calls_D53 << "\n";
    settings << "wide_string_constant_calls_D64\t" << lisar_probe::wide_string_calls_D64 << "\n";
    if (!lisar_probe::wide_string_calls_D53 || !lisar_probe::wide_string_calls_D64)
        throw std::runtime_error("String constant control did not actually route both source dispatches");
#endif
    if (!meta.good() || !policy.good() || !data.good() || !settings.good()) throw std::runtime_error("Output write failed");
}
