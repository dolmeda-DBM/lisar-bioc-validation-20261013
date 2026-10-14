// Adapted from Boost math API/constant implementations.
// Copyright (c) 2006, 2011 John Maddock; Copyright (c) 2024 Matt Borland.
// Distributed under BSL-1.0; full terms retained in probe3-licenses/BSL-1.0.txt.
// Diagnostic hypothesis only. SPDX-License-Identifier: BSL-1.0.
// Policy/dispatch and optional BIG_CONSTANT instrumentation follow exact BH
// 1.90.0-1 Boost headers. Boost copyright/license retained in probe3-licenses.
// No expected numerical value, correction table, statistical change or rounding.
#pragma once
#include <memory>
#include <boost/multiprecision/fwd.hpp>
#include <boost/math/policies/policy.hpp>
#include <boost/math/tools/big_constant.hpp>
#include <boost/math/tools/promotion.hpp>
#include <cstdint>
#include <limits>
#include <type_traits>

namespace lisar_probe {
namespace mp = boost::multiprecision;
namespace bp = boost::math::policies;
using Wide64 = mp::number<mp::cpp_bin_float<64, mp::digit_base_2,
    void, std::int16_t, -16382, 16383>, mp::et_off>;
using DefaultPolicy = bp::policy<>;
using NoPromotePolicy = bp::policy<bp::promote_double<false>, bp::promote_float<false>>;
using ForwardPolicy = typename bp::normalise<DefaultPolicy,
    bp::promote_float<false>, bp::promote_double<false>,
    bp::discrete_quantile<>, bp::assert_undefined<>>::type;

template <class Input> struct Dispatch {
    using Result = typename boost::math::tools::promote_args<Input>::type;
    using DefaultEval = typename bp::evaluation<Result, DefaultPolicy>::type;
    using NoPromoteEval = typename bp::evaluation<Result, NoPromotePolicy>::type;
    static constexpr int precision = bp::precision<Input, DefaultPolicy>::type::value;
    static constexpr int digamma_tag = precision <= 0 || precision > 113 ? 0 :
        precision <= 24 ? 24 : precision <= 53 ? 53 : precision <= 64 ? 64 : 113;
    static constexpr int trigamma_tag = precision <= 0 ? 0 :
        precision <= 53 ? 53 : precision <= 64 ? 64 : precision <= 113 ? 113 : 0;
    static_assert(std::is_same<Result, double>::value);
};

#ifdef LISAR_PROBE_FORCE_WIDE_STRING_CONSTANTS
// A transitive earlier definition would defeat this control: fail compilation
// rather than label already-parsed math templates as instrumented.
#if defined(BOOST_MATH_SF_DIGAMMA_HPP) || defined(BOOST_MATH_SF_TRIGAMMA_HPP)
#error "Primitive string control must precede digamma/trigamma definitions"
#endif
inline std::uint64_t wide_string_calls = 0, wide_string_calls_D53 = 0, wide_string_calls_D64 = 0;
// A separate experimental binary enables this. It only changes constants for
// Wide64, using the SAME literal text present in exact upstream headers.
// Native double/long-double construction delegates unchanged to make_big_value.
template <class T, int RequiredBits, class A, class B>
constexpr T constant_control(boost::math::tools::largest_float value,
                            const char* source_text, A a, B b) {
    if constexpr (std::is_same<T, Wide64>::value) {
        ++wide_string_calls;
        if constexpr (RequiredBits == 53) ++wide_string_calls_D53;
        if constexpr (RequiredBits == 64) ++wide_string_calls_D64;
        return T(source_text);
    }
    else return boost::math::tools::make_big_value<T>(value, source_text, a, b);
}
#endif
} // namespace lisar_probe

#ifdef LISAR_PROBE_FORCE_WIDE_STRING_CONSTANTS
// Original Boost macro structure/dispatch is retained for every non-Wide64 T.
// The control build includes this header in ALL translation units to avoid
// mixing differently defined math templates within a binary.
#undef BOOST_MATH_BIG_CONSTANT
#define BOOST_MATH_BIG_CONSTANT(T, D, x) \
    lisar_probe::constant_control<T, D>(BOOST_MATH_LARGEST_FLOAT_C(x), BOOST_MATH_STRINGIZE(x), \
    std::integral_constant<bool, (std::is_convertible<boost::math::tools::largest_float, T>::value || std::is_floating_point<T>::value) && \
    ((D <= boost::math::tools::numeric_traits<boost::math::tools::largest_float>::digits) || \
     std::is_floating_point<T>::value || (boost::math::tools::numeric_traits<T>::is_specialized && \
     boost::math::tools::numeric_traits<T>::digits10 <= boost::math::tools::numeric_traits<boost::math::tools::largest_float>::digits10))>(), \
    std::is_constructible<T, const char*>())
#endif

// cpp_bin_float -> gamma -> polygamma transitively defines digamma/trigamma.
// Therefore the controlled macro MUST be installed above this include; fwd.hpp
// declares Wide64 beforehand without defining numeric_limits prematurely.
#include <boost/multiprecision/cpp_bin_float.hpp>
#include <boost/math/special_functions/digamma.hpp>
#include <boost/math/special_functions/trigamma.hpp>

namespace lisar_probe {
static_assert(std::numeric_limits<Wide64>::digits == 64);
static_assert(std::numeric_limits<Wide64>::radix == 2);
// Exact predicate from BH boost/math/tools/big_constant.hpp, evaluated only
// after cpp_bin_float's numeric_limits specialization is fully defined.
template <int RequiredBits> constexpr bool wide_constant_uses_largest_float =
    (std::is_convertible<boost::math::tools::largest_float, Wide64>::value ||
        std::is_floating_point<Wide64>::value) &&
    ((RequiredBits <= boost::math::tools::numeric_traits<boost::math::tools::largest_float>::digits) ||
        std::is_floating_point<Wide64>::value ||
        (boost::math::tools::numeric_traits<Wide64>::is_specialized &&
         boost::math::tools::numeric_traits<Wide64>::digits10 <=
         boost::math::tools::numeric_traits<boost::math::tools::largest_float>::digits10));
// Reproduce the upstream INPUT-TYPE dispatch and forwarding policy, replacing
// only the evaluation arithmetic. Each function narrows to binary64 BEFORE
// any betaMeanLog subtraction. Never subtract two wide values then cast once.
template <class Input> double wide_digamma(Input x) {
    using Tag = boost::math::integral_constant<int, Dispatch<Input>::digamma_tag>;
    const Wide64 value = boost::math::detail::digamma_imp(
        Wide64(x), static_cast<const Tag*>(nullptr), ForwardPolicy());
    return bp::checked_narrowing_cast<double, DefaultPolicy>(value, "diagnostic wide digamma");
}
template <class Input> double wide_trigamma(Input x) {
    using Tag = boost::math::integral_constant<int, Dispatch<Input>::trigamma_tag>;
    const Wide64 value = boost::math::detail::trigamma_dispatch(Wide64(x), ForwardPolicy(), Tag());
    return bp::checked_narrowing_cast<double, DefaultPolicy>(value, "diagnostic wide trigamma");
}
} // namespace lisar_probe
