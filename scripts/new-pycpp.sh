#!/usr/bin/env bash
# Scaffold a Python package with a native C++23 core (nanobind + scikit-build-core, managed by uv).
# Usage: new-pycpp.sh [--python X.Y] <name> [directory]
set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [--python X.Y] <name> [directory]" >&2
    exit "${1:-2}"
}

python_version="3.13"
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --python) [[ $# -ge 2 ]] || usage; python_version="$2"; shift 2 ;;
        -h | --help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *) args+=("$1"); shift ;;
    esac
done
[[ ${#args[@]} -ge 1 && ${#args[@]} -le 2 ]] || usage

name="${args[0]}"
dir="${args[1]:-$name}"
module="${name//-/_}"
py_tag="py${python_version//./}" # 3.13 -> py313
cp_tag="cp${python_version//./}" # 3.13 -> cp313

[[ "$python_version" =~ ^3\.[0-9]+$ ]] || { echo "Invalid --python: $python_version" >&2; exit 2; }
# The stable ABI build (nanobind STABLE_ABI) needs Python 3.12 or later
(( ${python_version#3.} >= 12 )) || { echo "--python must be 3.12 or later" >&2; exit 2; }
# uv normalizes other names (My.Pkg -> my-pkg), which would break the paths below
[[ "$name" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] ||
    { echo "Invalid name: $name (use lowercase letters, digits and single hyphens)" >&2; exit 2; }
[[ -e "$dir" ]] && { echo "Already exists: $dir" >&2; exit 1; }
for tool in uv c++ git; do
    command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done

# This repo is the template for the project-independent files
template_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# An active venv from another project would confuse uv
unset VIRTUAL_ENV

# The new project is standalone: --no-workspace keeps uv from adding it as a
# member of an enclosing project, and it gets its own git repo even when
# created inside another one (uv init skips git init there)
uv init --lib --build-backend scikit --no-workspace \
    --python "$python_version" --name "$name" "$dir"
cd "$dir"
[[ -d .git ]] || git init -q
uv add --dev scikit-build-core nanobind cmake ninja clang-format clang-tidy \
    ruff mypy py-spy pytest rust-just auditwheel patchelf

# --- CMakeLists.txt and the C++ source: nanobind instead of pybind11 -------
rm src/main.cpp
cat >CMakeLists.txt <<EOF
cmake_minimum_required(VERSION 3.26...4.4)
project($module LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# compile_commands.json, read by clang-tidy
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Warnings for this project's targets only. They are fatal in \`just lint\`/\`just test\`,
# which turn on WARNINGS_AS_ERRORS, but not for nanobind's own sources
set(warnings -Wall -Wextra -Wpedantic)
option(WARNINGS_AS_ERRORS "Make compiler warnings in this project's code errors" OFF)
if(WARNINGS_AS_ERRORS)
    list(APPEND warnings -Werror)
endif()

# The extension module. Development.SABIModule and STABLE_ABI build against the
# stable ABI (abi3): one binary for every Python >= $python_version (matches requires-python)
find_package(Python $python_version REQUIRED COMPONENTS Interpreter Development.Module Development.SABIModule)
execute_process(
    COMMAND "\${Python_EXECUTABLE}" -m nanobind --cmake_dir
    OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE nanobind_ROOT)
find_package(nanobind CONFIG REQUIRED)
nanobind_add_module(_core STABLE_ABI NB_STATIC src/core.cpp)
target_compile_options(_core PRIVATE \${warnings})
install(TARGETS _core DESTINATION \${PROJECT_NAME})

# C++ tests: add_executable + add_test (BUILD_TESTING is turned off for the
# Python build in pyproject.toml)
include(CTest)
EOF

cat >src/core.cpp <<EOF
// A Python module implemented in C++. The name in NB_MODULE must match the
// target name in CMakeLists.txt, else Python will not be able to import it.
#include <string_view>

#include <nanobind/nanobind.h>
#include <nanobind/stl/string_view.h>

namespace nb = nanobind;

namespace {

std::string_view hello_from_bin() { return "Hello from $name!"; }

} // namespace

// NOLINTNEXTLINE(bugprone-signed-bitwise): flagged inside nanobind's macro
NB_MODULE(_core, m) {
    m.def("hello_from_bin", &hello_from_bin, "Return a greeting from the C++ core.");
}
EOF

# --- pyproject.toml --------------------------------------------------------
sed -i 's/"pybind11>=3"/"nanobind>=3.1"/' pyproject.toml

sed -i 's|^build-dir = "build/{wheel_tag}"$|# A persistent build dir keeps rebuilds incremental (a temporary one rebuilds everything)\
build-dir = "build/{wheel_tag}"\
# Optimized, with symbols so py-spy can name C++ frames (`just build` strips the wheel)\
cmake.build-type = "RelWithDebInfo"\
install.strip = false\
# Stable ABI wheel tag ('"$cp_tag"'-abi3), matching STABLE_ABI in CMakeLists.txt\
wheel.py-api = "'"$cp_tag"'"\
# The C++ tests are built by `just test`, not by the Python build\
cmake.define.BUILD_TESTING = "OFF"|' pyproject.toml

sed -i 's|^\[tool\.uv\]$|[tool.uv]\
# Build in the project venv: an isolated build env gets a new path every time,\
# which makes CMake reconfigure and rebuild from scratch on each C++ change\
no-build-isolation-package = ["'"$name"'"]|' pyproject.toml

# Fail loudly if the uv template changed and an edit above matched nothing
for setting in '"nanobind>=3.1"' 'wheel.py-api' 'no-build-isolation-package'; do
    grep -qF "$setting" pyproject.toml ||
        { echo "pyproject.toml edit failed ($setting); has uv's template changed?" >&2; exit 1; }
done

cat >>pyproject.toml <<EOF

[tool.ruff]
line-length = 100
target-version = "$py_tag"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "RUF"]

[tool.mypy]
strict = true
files = ["src/$module", "tests"]
mypy_path = "src"
explicit_package_bases = true

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = ["--import-mode=importlib"]
EOF

# --- Python API: wrap the native functions ---------------------------------
cat >"src/$module/__init__.py" <<EOF
from $module import _core


def hello() -> str:
    """Return a greeting from the C++ core."""
    return _core.hello_from_bin()
EOF

mkdir -p tests
cat >tests/test_smoke.py <<EOF
import $module


def test_hello() -> None:
    assert isinstance($module.hello(), str)
EOF

# --- .gitignore ------------------------------------------------------------
cat >>.gitignore <<EOF

# py-spy output
profile.svg

# Tool caches
.mypy_cache/
.ruff_cache/
.pytest_cache/
EOF

# --- Project-independent files, copied from this repo ----------------------
cp "$template_dir/justfile" "$template_dir/activate.sh" \
    "$template_dir/.clang-format" "$template_dir/.clang-tidy" .

# --- Build and verify ------------------------------------------------------
uv run just check

echo
echo "Created $dir. Next: cd $dir && source ./activate.sh"
