#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
// Under clang (clang-tidy), doctest includes <ciso646>, which libstdc++ >= 15
// flags with a #warning in C++20 and later
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-W#warnings"
#endif
#include <doctest/doctest.h>
#ifdef __clang__
#pragma clang diagnostic pop
#endif

#include <cstdint>
#include <limits>
#include <vector>

#include "factor.hpp"

using Factors = std::vector<std::uint64_t>;

TEST_CASE("factors") {
    CHECK(factor_impl(12) == Factors{2, 2, 3});
    CHECK(factor_impl(360) == Factors{2, 2, 2, 3, 3, 5});
    CHECK(factor_impl(97) == Factors{97});
    CHECK(factor_impl(2) == Factors{2});
    CHECK(factor_impl(1024) == Factors(10, 2));
    CHECK(factor_impl(2ULL * 9 * 25) == Factors{2, 3, 3, 5, 5});
}

TEST_CASE("edge cases") {
    CHECK(factor_impl(0).empty());
    CHECK(factor_impl(1).empty());
    CHECK(factor_impl(std::numeric_limits<std::uint64_t>::max()) ==
          Factors{3, 5, 17, 257, 641, 65537, 6700417});
    // Square of a prime: the divisor must reach exactly sqrt(n)
    CHECK(factor_impl(65'521ULL * 65'521ULL) == Factors{65'521, 65'521});
}
