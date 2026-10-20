#include "factor.hpp"

std::vector<std::uint64_t> factor_impl(std::uint64_t n) {
    std::vector<std::uint64_t> factors;
    while (n >= 2 && n % 2 == 0) {
        factors.push_back(2);
        n /= 2;
    }
    // Only odd divisors remain. The remainder is derived from the quotient, so each
    // step costs one division (GCC otherwise divides twice: for n / d and n % d)
    for (std::uint64_t d = 3;; d += 2) {
        std::uint64_t quotient = n / d;
        if (quotient < d) {
            break;
        }
        while (n - quotient * d == 0) {
            factors.push_back(d);
            n = quotient;
            quotient = n / d;
        }
    }
    if (n > 1) {
        factors.push_back(n);
    }
    return factors;
}
