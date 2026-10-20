# List recipes (and hint if tab completion is missing)
default:
    @just --list
    @# VIRTUAL_ENV_PROMPT is set by activating the venv, not by `uv run`
    @if [ -n "${VIRTUAL_ENV_PROMPT:-}" ] && [ -z "${JUST_COMPLETION_REGISTERED:-}" ]; then \
        echo "hint: venv is active but just tab completion is not; run: source ./activate.sh" >&2; \
    fi

# Plain CMake builds (C++ tests, clang-tidy) get their own build dir, so they
# don't disturb the Python build in build/<wheel tag>
cmake_build := "build/cmake"

# C++ sources checked by clang-format and clang-tidy
cpp_files := `find src tests -name '*.cpp' -o -name '*.hpp' | sort | tr '\n' ' '`

# Format Python and C++
fmt:
    uv run ruff format .
    uv run clang-format -i {{cpp_files}}

# Lint and check formatting (Python and C++)
lint: _cmake
    uv run ruff check .
    uv run ruff format --check .
    uv run clang-format --dry-run -Werror {{cpp_files}}
    uv run clang-tidy --quiet -p {{cmake_build}} {{cpp_files}}

# Type-check Python (mypy strict)
typecheck:
    uv run mypy

# Run C++ and Python tests
test: _cmake
    uv run ctest --test-dir {{cmake_build}} --output-on-failure
    uv run pytest

# Remove all build artifacts and the venv
clean:
    rm -rf .venv build dist .mypy_cache .ruff_cache .pytest_cache
    rm -f profile.svg
    find . -name __pycache__ -type d -prune -exec rm -rf {} +

# Run every check (good for CI / pre-push)
check: lint typecheck test

# Profile a script (with its arguments), including C++ frames
profile script *args:
    uv run py-spy record --native -o profile.svg -- python "{{script}}" {{args}}

# Build a release wheel (stripped, manylinux-tagged) into dist/
build:
    rm -rf build/wheel
    uv build --wheel --no-build-isolation --out-dir build/wheel \
        -C build-dir=build/release -C install.strip=true
    uv run auditwheel repair --wheel-dir dist build/wheel/*.whl

# Configure and build the plain CMake tree (Debug, with tests, warnings as errors)
_cmake:
    uv run cmake -S . -B {{cmake_build}} -G Ninja -DCMAKE_BUILD_TYPE=Debug \
        -DCMAKE_COMPILE_WARNING_AS_ERROR=ON
    uv run cmake --build {{cmake_build}}
