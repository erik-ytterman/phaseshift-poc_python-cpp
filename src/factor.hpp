#pragma once

#include <cstdint>
#include <vector>

// Return the prime factors of `n` in ascending order. 0 and 1 have none.
std::vector<std::uint64_t> factor_impl(std::uint64_t n);
