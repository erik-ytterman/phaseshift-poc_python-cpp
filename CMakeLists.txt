cmake_minimum_required(VERSION 3.26...4.4)
project(python_cpp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# No C++ modules here. Scanning for them (CMake's default with GCC >= 14) adds
# GCC-only flags to compile_commands.json that clang-tidy rejects
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
# compile_commands.json, read by clang-tidy
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Warnings for this project's targets only. They are fatal in `just lint`/`just test`,
# which turn on WARNINGS_AS_ERRORS, but not for nanobind's own sources
set(warnings -Wall -Wextra -Wpedantic)
option(WARNINGS_AS_ERRORS "Make compiler warnings in this project's code errors" OFF)
if(WARNINGS_AS_ERRORS)
    list(APPEND warnings -Werror)
endif()

# Plain C++ logic, shared by the extension and the C++ tests
add_library(factor STATIC src/factor.cpp)
target_include_directories(factor PUBLIC src)
target_compile_options(factor PRIVATE ${warnings})
set_target_properties(factor PROPERTIES POSITION_INDEPENDENT_CODE ON)

# The extension module. Development.SABIModule and STABLE_ABI build against the
# stable ABI (abi3): one binary for every Python >= 3.13 (matches requires-python)
find_package(Python 3.13 REQUIRED COMPONENTS Interpreter Development.Module Development.SABIModule)
execute_process(
    COMMAND "${Python_EXECUTABLE}" -m nanobind --cmake_dir
    OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE nanobind_ROOT)
find_package(nanobind CONFIG REQUIRED)
nanobind_add_module(_core STABLE_ABI NB_STATIC src/core.cpp)
target_link_libraries(_core PRIVATE factor)
target_compile_options(_core PRIVATE ${warnings})
install(TARGETS _core DESTINATION ${PROJECT_NAME})

# C++ tests (BUILD_TESTING is turned off for the Python build in pyproject.toml)
include(CTest)
if(BUILD_TESTING)
    include(FetchContent)
    FetchContent_Declare(doctest
        URL https://raw.githubusercontent.com/doctest/doctest/v2.4.12/doctest/doctest.h
        URL_HASH SHA256=94029a7d32da24a56249658147dbd2b33ff0b9ed665295cbbaf19aafff5b0ced
        DOWNLOAD_NO_EXTRACT TRUE
        SOURCE_DIR ${CMAKE_BINARY_DIR}/_deps/doctest/doctest)
    FetchContent_MakeAvailable(doctest)

    add_executable(test_factor tests/cpp/test_factor.cpp)
    target_include_directories(test_factor SYSTEM PRIVATE ${CMAKE_BINARY_DIR}/_deps/doctest)
    target_link_libraries(test_factor PRIVATE factor)
    target_compile_options(test_factor PRIVATE ${warnings})
    add_test(NAME test_factor COMMAND test_factor)
endif()
