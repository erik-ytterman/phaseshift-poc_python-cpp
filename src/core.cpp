// A Python module implemented in C++. The name in NB_MODULE must match the
// target name in CMakeLists.txt, else Python will not be able to import it.
// nanobind includes Python.h, which must come before any standard header
#include <nanobind/nanobind.h>
#include <nanobind/stl/string_view.h>
#include <nanobind/stl/vector.h>

#include <cstdint>
#include <limits>
#include <string_view>
#include <vector>

#include "factor.hpp"

namespace nb = nanobind;

namespace {

std::string_view hello_from_bin() { return "Hello from python-cpp!"; }

// Convert like PyO3 does for u64: accept anything with __index__, raise
// TypeError for other types and OverflowError for n < 0 or n >= 2**64
std::uint64_t to_uint64(nb::handle obj) {
    nb::object index = nb::steal(PyNumber_Index(obj.ptr()));
    if (!index.is_valid()) {
        throw nb::python_error();
    }
    const unsigned long long value = PyLong_AsUnsignedLongLong(index.ptr());
    if (value == std::numeric_limits<unsigned long long>::max() && PyErr_Occurred() != nullptr) {
        throw nb::python_error();
    }
    return value;
}

std::vector<std::uint64_t> factor(nb::handle n) {
    const std::uint64_t value = to_uint64(n);
    // The GIL is released while factorizing, so other Python threads keep running
    nb::gil_scoped_release release;
    return factor_impl(value);
}

} // namespace

// NOLINTNEXTLINE(bugprone-signed-bitwise): flagged inside nanobind's macro
NB_MODULE(_core, m) {
    m.def("hello_from_bin", &hello_from_bin, "Return a greeting from the C++ core.");
    // nb::sig: the signature in the docstring would otherwise say `n: object`
    m.def("factor", &factor, nb::arg("n"), nb::sig("def factor(n: int) -> list[int]"),
          "Return the prime factors of `n` in ascending order.\n\n"
          "`n` must be in the range 0 <= n < 2**64; otherwise OverflowError is raised.\n"
          "0 and 1 have no prime factors and return an empty list.");
}
