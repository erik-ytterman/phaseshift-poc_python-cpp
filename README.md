# python-cpp

A Python package with a native core written in C++23, built with
[nanobind](https://nanobind.readthedocs.io) and
[scikit-build-core](https://scikit-build-core.readthedocs.io) (CMake),
managed by [uv](https://docs.astral.sh/uv/). Ruff, mypy, pytest, py-spy,
clang-format, clang-tidy, CMake, Ninja, auditwheel and
[just](https://just.systems) are installed as project dev tools.

It has the same functionality and Python API as its Rust twin,
[`phaseshift-poc_python-rust`](https://github.com/erik-ytterman/phaseshift-poc_python-rust),
and passes the same Python tests.

The distribution name is `python-cpp`; the import name is `python_cpp`.

---

## Prerequisites

Only uv and a C++23 compiler are needed (tested with GCC 13.3, 14.2 and 15.2,
glibc 2.39 and 2.43). Everything else, including CMake, Ninja, the clang
tools and `just`, is installed by uv into the project venv. CI tests Ubuntu 24.04 (GCC 13) and 26.04 (GCC 15)
with Python 3.13, 3.14 and 3.15.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
sudo apt install g++          # or your platform's equivalent
```

## Daily workflow

```bash
source ./activate.sh           # activate the venv + enable `just` tab completion
just                           # list recipes
just check                     # lint, type-check and test everything
deactivate                     # leave the venv
```

Without activating, prefix commands with `uv run` (e.g. `uv run just check`).

There is no separate build step: every `uv run` (which the recipes use)
installs dependencies and rebuilds the C++ extension if a C++ file changed.
See [From clone to runnable project](#from-clone-to-runnable-project) for
what happens.

| Recipe | What it does |
|---|---|
| `just fmt` | Format Python (Ruff) and C++ (clang-format) |
| `just lint` | Ruff, format checks, clang-tidy, compiler warnings as errors |
| `just typecheck` | mypy (strict) |
| `just test` | C++ tests (`ctest`) + `pytest` |
| `just check` | `lint` + `typecheck` + `test` |
| `just profile <script> [args]` | py-spy flame graph incl. C++ frames → `profile.svg` |
| `just build` | Release wheel (stripped, manylinux) into `dist/` |
| `just clean` | Remove venv, build output and caches |

## Creating a new project

[`scripts/new-pycpp.sh`](scripts/new-pycpp.sh) creates a project like
this one:

```bash
scripts/new-pycpp.sh my-pkg                     # directory defaults to the name
scripts/new-pycpp.sh --python 3.14 my-pkg ~/x   # Python version (default 3.13), directory
```

It starts from `uv init --lib --build-backend scikit`, replaces the
template's pybind11 code with nanobind, adds the dev tools and the
configuration described below, copies `justfile`, `activate.sh`,
`.clang-format`, `.clang-tidy` and the CI files in `.github/` from this repo
(dropping CI Python versions older than `--python`), and finishes with
`just check`. The result is standalone, with its own venv and git repo and no
reference to this repo; later changes here don't affect it. It has no C++
tests yet (`ctest` reports "No tests were found" and passes).

The name must be lowercase letters, digits and single hyphens (e.g.
`my-pkg`); the import name replaces hyphens with underscores (`my_pkg`).
The Python version must be 3.12 or later (the stable ABI build needs it).

Requirements: uv, a C++ compiler and git, and GNU `sed` (Linux). Run the
script from a checkout of this repo, since that is where it copies those
files from; the current directory doesn't matter.

Example, creating `fast-math` next to this repo:

```bash
cd ~/Work
phaseshift-poc_python-cpp/scripts/new-pycpp.sh --python 3.13 fast-math
# ... uv output, then `just check` builds, lints and tests it, ending with:
# Created fast-math. Next: cd fast-math && source ./activate.sh
```

```
fast-math/
├── pyproject.toml  uv.lock  .python-version  CMakeLists.txt
├── justfile  activate.sh  .clang-format  .clang-tidy  .gitignore  README.md
├── .github/                ci.yml and dependabot.yml, as in this repo
├── src/
│   ├── core.cpp            NB_MODULE(_core, m) with hello_from_bin()
│   └── fast_math/
│       ├── __init__.py     hello() wraps _core.hello_from_bin()
│       ├── _core.pyi
│       └── py.typed
└── tests/test_smoke.py
```

```bash
cd fast-math && source ./activate.sh
python -c "import fast_math; print(fast_math.hello())"   # Hello from fast-math!
```

From there, add functions as in [Adding a native function](#adding-a-native-function).

---

## Project layout

```
phaseshift-poc_python-cpp/
├── pyproject.toml          Python project definition + tool and build config
├── uv.lock                 exact Python dependency versions (commit it)
├── .python-version         Python version uv uses
├── CMakeLists.txt          C++ build: library, extension module, C++ tests
├── .clang-format           C++ formatting rules
├── .clang-tidy             C++ lint rules
├── justfile                task shortcuts
├── activate.sh             activate venv + just completion (source it)
├── src/
│   ├── factor.hpp/.cpp     plain C++ logic, no Python
│   ├── core.cpp            nanobind bindings → compiled to python_cpp._core
│   └── python_cpp/
│       ├── __init__.py     public Python API, wraps _core
│       ├── _core.pyi       type signatures for the C++ module
│       └── py.typed        marker: package ships type information
├── tests/                  pytest tests (test_*.py)
│   └── cpp/                C++ tests (doctest)
├── examples/               runnable demos
├── .github/
│   ├── workflows/ci.yml    runs `just check` and `just build` on push and PRs
│   └── dependabot.yml      weekly PRs that update the CI actions
└── scripts/
    └── new-pycpp.sh        scaffolds a new project like this one
```

The C++ code is a **private core** (`_core`, leading underscore = "don't
import directly"); users only import the **public package** `python_cpp`.

The name `_core` must match in two places: `NB_MODULE(_core, m)` in
`core.cpp` and `nanobind_add_module(_core ...)` in `CMakeLists.txt`. Its
stub must be named `_core.pyi`. `install(... DESTINATION ${PROJECT_NAME})`
puts it inside the package, so `project()` must be named like the import
name.

---

## Adding a native function

Four files change every time, five if you add a `.cpp` file (list it in
`CMakeLists.txt`). Using `factor` as the example:

**1. C++ — [`src/factor.cpp`](src/factor.cpp) and
[`src/core.cpp`](src/core.cpp).** Keep the logic in a plain C++ function
(declared in [`src/factor.hpp`](src/factor.hpp)) so the C++ tests can test
it without Python, and add a thin binding in `core.cpp`:

```cpp
std::vector<std::uint64_t> factor(nb::handle n) {
    const std::uint64_t value = to_uint64(n);
    nb::gil_scoped_release release;
    return factor_impl(value);
}

NB_MODULE(_core, m) {
    m.def("factor", &factor, nb::arg("n"), nb::sig("def factor(n: int) -> list[int]"),
          "Return the prime factors of `n` in ascending order. ...");
}
```

Include the nanobind headers before any standard header: they include
`Python.h`, which [must come first](https://docs.python.org/3/c-api/intro.html#include-files).
Otherwise newer glibc versions (2.43+) make `pyconfig.h` redefine
`_POSIX_C_SOURCE`, which `-Werror` turns into a build failure.

Add a test in [`tests/cpp/test_factor.cpp`](tests/cpp/test_factor.cpp):

```cpp
TEST_CASE("factors") {
    CHECK(factor_impl(12) == Factors{2, 2, 3});
}
```

**2. Type stub — [`src/python_cpp/_core.pyi`](src/python_cpp/_core.pyi).**
Type checkers can't inspect the compiled `.so`, so declare the signature by
hand:

```python
def factor(n: int) -> list[int]: ...
```

**3. Public API — [`src/python_cpp/__init__.py`](src/python_cpp/__init__.py).**
Wrap the native function in a plain Python function. This keeps the public
name and signature independent of the C++ side. The wrapper needs its own
docstring, because the one in `m.def` ends up on `_core.factor`.

```python
from python_cpp import _core


def factor(n: int) -> list[int]:
    """Return the prime factors of `n` in ascending order."""
    return _core.factor(n)
```

**4. Test — [`tests/test_factor.py`](tests/test_factor.py).**

```python
import python_cpp


def test_factor() -> None:
    assert python_cpp.factor(12) == [2, 2, 3]
```

Then run `just check`.

### Type mapping

nanobind converts types at the boundary. Standard library types need their
header (`#include <nanobind/stl/vector.h>` etc.), or the call fails at
runtime with a `TypeError`. Some common mappings:

| C++ | Header | Python stub |
|---|---|---|
| `std::int64_t`, `std::uint64_t` | | `int` |
| `double` | | `float` |
| `bool` | | `bool` |
| `std::string` / `std::string_view` | `stl/string.h` / `stl/string_view.h` | `str` |
| `std::vector<T>` | `stl/vector.h` | `list[T]` (copied in and out) |
| `std::unordered_map<K, V>` | `stl/unordered_map.h` | `dict[K, V]` |
| `std::optional<T>` | `stl/optional.h` | `T \| None` |
| a thrown `nb::python_error` / C++ exception | | raises an exception |

A Python `int` is unbounded, so values that don't fit the C++ type raise at
runtime even though mypy accepts the call. nanobind raises `TypeError` for
those, also for an out-of-range `int`. `factor` takes an `nb::handle` and
converts it itself (`to_uint64` in `core.cpp`) to match the Rust version
exactly: `OverflowError` for negative values and values ≥ 2⁶⁴, `TypeError`
for a `float` or other non-integers, and objects with `__index__` (such as
NumPy integers) accepted. Document the valid range in the docstring.

`nb::sig` only changes the signature line nanobind puts at the top of
`_core.factor.__doc__`; without it, that line would say `n: object`.

---

## How it works

### From clone to runnable project

One command takes a fresh clone to a working package:

```bash
uv sync          # or any `uv run ...`, e.g. `uv run just check`
```

That runs these steps:

1. **Python.** uv reads `.python-version` (3.13) and uses a matching
   interpreter, downloading one into `~/.local/share/uv/python` if none is
   installed.
2. **Venv.** uv creates `.venv/` in the project.
3. **Dependencies.** uv installs the exact versions from `uv.lock` into
   `.venv`, including the `dev` group (scikit-build-core, nanobind, CMake,
   Ninja, the clang tools, ruff, mypy, pytest, py-spy, auditwheel, just).
   This comes first because of `no-build-isolation-package`: the project is
   built with the venv's own build tools.
4. **Build.** `[build-system]` in `pyproject.toml` names scikit-build-core
   as the build backend, so uv asks it for an **editable** build (PEP 660).
   scikit-build-core then:
   - runs CMake and Ninja in `build/cp313-abi3-linux_x86_64/`
     (`build-dir = "build/{wheel_tag}"`), in `RelWithDebInfo` mode
     (`-O3 -g`), with `BUILD_TESTING=OFF`
   - builds the `factor` library and the `_core` extension against the
     stable ABI (`STABLE_ABI` in `CMakeLists.txt`, `wheel.py-api = "cp313"`:
     one binary for every Python ≥ 3.13)
   - writes a wheel holding `_core.abi3.so` and an import hook,
     `_editable_skbc_python_cpp.py`, with a `.pth` file that loads it
5. **Install.** uv installs that wheel, which puts the `.so` into
   `.venv/lib/python3.13/site-packages/python_cpp/` and the hook next to it.
6. **Run.** At startup the venv's Python runs the hook because of the
   `.pth` file. `import python_cpp` then loads
   `src/python_cpp/__init__.py` from the source tree, and its
   `import _core` loads the `.so` from `site-packages`.

C++ code is compiled once, into `build/<wheel tag>/`. After that, every
`uv run` compares the files listed in `[tool.uv] cache-keys` (the C++
sources, `CMakeLists.txt`, `pyproject.toml`) with the last build, and
repeats steps 4–5 only if one changed. Ninja then recompiles only the
changed files (about 1.5 s for an edit, including uv's overhead).

### Editable install

Because the hook points at `src/` instead of holding a copy of the Python
code, edits show up without reinstalling. That is also how `examples/` and
`tests/` find the package: through the venv, not their location on disk.

| You edit | Takes effect |
|---|---|
| `.py` files | Immediately (read from `src/`) |
| `.pyi` stubs | Next mypy run |
| C++ files, `CMakeLists.txt` | Next `uv run` or `uv sync` (rebuilds on change) |

Unlike maturin, scikit-build-core doesn't put the compiled `.so` into
`src/`, so there's nothing to gitignore there.

uv also caches the editable wheel, `.so` included. When the venv is
recreated (e.g. after `just clean`) and no source file changed, uv
reinstalls that wheel without compiling. To force a full rebuild, run
`uv sync --reinstall-package python-cpp`. It only works with the
venv's Python: a system `python3` gives `ModuleNotFoundError`.

### Building a wheel for distribution

`just build` builds a regular wheel and repairs it with auditwheel:

1. `uv build --wheel --no-build-isolation` with a separate build dir
   (`build/release`) and `install.strip=true`, into `build/wheel/`. It is
   tagged `cp313-abi3-linux_x86_64`, which PyPI and pip on other machines
   don't accept as portable.
2. `auditwheel repair` checks which system libraries and symbol versions
   the `.so` needs and retags it, e.g.
   `python_cpp-0.2.0-cp313-abi3-manylinux_2_34_x86_64.whl` in `dist/`.
   The `manylinux_2_XX` part is the build machine's glibc version or
   lower, so build on an old system (or in a manylinux container) for a
   wheel that installs on more systems. (maturin does this step itself.)

Unlike the editable wheel, it contains the package itself (`__init__.py`,
`_core.abi3.so`, `_core.pyi`, `py.typed`), with no link back to your source.
It doesn't touch `.venv`.

Install it in any environment with Python ≥ 3.13 on the same platform
(here Linux x86_64, glibc ≥ the version in the tag). No compiler is needed
there:

```bash
uv pip install dist/python_cpp-*.whl   # or: pip install ...
```

| Command | Compiles C++ | Installs into `.venv` | Output |
|---|---|---|---|
| `uv sync` / `uv run` | If changed | Yes, editable | `.so` in `site-packages` + import hook |
| `just build` | Yes | **No** | Self-contained wheel in `dist/` |

### Avoiding needless rebuilds

- `no-build-isolation-package` in `pyproject.toml` makes uv build in the
  project venv. An isolated build env gets a new path every time, so CMake
  would find a different Python and nanobind and rebuild everything.
- `build-dir = "build/{wheel_tag}"` keeps CMake's build tree between
  builds. Without it, scikit-build-core uses a temporary directory and
  rebuilds from scratch.
- The `justfile` runs its own CMake build in `build/cmake` (Debug, with
  tests, warnings as errors) for `ctest` and clang-tidy, and `just build`
  uses `build/release`, so none of them disturb the editable build.

---

## Configuration

What this project adds to uv's scikit-build template:

- **[`pyproject.toml`](pyproject.toml):** `[tool.ruff]`, `[tool.mypy]`
  (strict, covering `src/python_cpp`, `tests` and `examples`) and
  `[tool.pytest.ini_options]`. `[tool.scikit-build]` gets
  `cmake.build-type = "RelWithDebInfo"` with `-O3` instead of CMake's
  default `-O2` (as optimized as Rust's release profile) and
  `install.strip = false` (symbols for py-spy), `wheel.py-api = "cp313"` (stable ABI tag) and
  `BUILD_TESTING=OFF`. `[tool.uv]` gets `no-build-isolation-package` (see
  above). `[build-system]` requires nanobind instead of pybind11. The
  template already has `build-dir` and `cache-keys` covering the C++ files.
- **[`CMakeLists.txt`](CMakeLists.txt):** replaced. C++23, warnings,
  `compile_commands.json` for clang-tidy, the `factor` library, the nanobind
  extension, and the doctest-based C++ tests. doctest is a single header,
  downloaded at configure time and checked against its SHA-256. C++ module
  scanning is off (`CMAKE_CXX_SCAN_FOR_MODULES`): with GCC ≥ 14 it adds
  GCC-only flags to `compile_commands.json` that clang-tidy rejects.
- **[`.clang-format`](.clang-format), [`.clang-tidy`](.clang-tidy):** C++
  style (LLVM, 4 spaces, 100 columns) and lint checks (bugprone,
  performance, modernize), all warnings errors.
- **[`justfile`](justfile):** the recipes above.
- **[`activate.sh`](activate.sh):** see
  [Activating the venv and `just` completion](#activating-the-venv-and-just-completion).
- **[`.gitignore`](.gitignore):** `profile.svg` and tool caches. The
  template already covers `build/` and `dist/`.
- **[`.github/workflows/ci.yml`](.github/workflows/ci.yml):** runs
  `uv run just check` and `uv run just build` on every push to `main` and
  on pull requests, on Ubuntu 24.04 and 26.04 with Python 3.13, 3.14 and
  3.15 (setup-uv's `python-version` overrides `.python-version`). The C++
  compiler is the runner's own `g++`. The actions are pinned by commit
  hash, with the version in a comment.
- **[`.github/dependabot.yml`](.github/dependabot.yml):** Dependabot checks
  the actions weekly and opens one PR with any updates (new hash and
  version comment), which CI then tests.

Keep `uv.lock` committed.

Why nanobind rather than pybind11 (which the uv template uses): pybind11
can't build against the stable ABI, so it needs one wheel per Python
version. nanobind gives one abi3 wheel, as PyO3 does.

---

## Working with GitHub

CI runs on GitHub Actions, with the files described under
[Configuration](#configuration). This section explains how to find the
actions it uses, and how to work with GitHub from the terminal.

### Finding GitHub Actions and their versions

Each `uses: <owner>/<repo>@<ref>` line in a workflow names a GitHub
repository, `https://github.com/<owner>/<repo>`, and the version of it to
run. For example, `actions/checkout` is
[github.com/actions/checkout](https://github.com/actions/checkout). That
repository holds the action's documentation:

- **README:** usage examples and the inputs it accepts (the `with:` keys).
  `action.yml` in the repository root defines those inputs and their
  defaults.
- **Releases page** (`https://github.com/<owner>/<repo>/releases`): every
  version, with release notes that list breaking changes. Read them before
  moving to a new major version.
- **[GitHub Marketplace](https://github.com/marketplace?type=actions):**
  search for actions; each listing links to its repository.

`<ref>` can be a major-version tag (`@v7`, moved by the maintainer to each
new v7.x release; not every action publishes these), an exact tag
(`@v7.0.1`), or a commit hash. This repo pins hashes, which never change,
and puts the version in a comment. GitHub's
[security guide](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions)
recommends that. From the terminal:

```bash
gh release list -R actions/checkout --limit 5             # newest versions
gh release view v7.0.1 -R actions/checkout                # release notes
gh api repos/actions/checkout/git/ref/tags/v7.0.1 -q .object.sha   # hash to pin
```

If the last command's `.object.type` is `tag` rather than `commit`, the tag
is annotated: look up that object with
`gh api repos/<owner>/<repo>/git/tags/<sha> -q .object.sha` to get the
commit. Dependabot (see [Configuration](#configuration)) does all of this weekly
and opens a PR.

The workflow syntax itself (`on:`, `jobs:`, `runs-on:`, `steps:`) is
documented in GitHub's
[workflow syntax reference](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax),
and the runner images (what `ubuntu-24.04` contains, such as its GCC
version) in [actions/runner-images](https://github.com/actions/runner-images).

### Using `gh`, the GitHub CLI

[`gh`](https://cli.github.com) runs GitHub operations from the terminal:
repositories, CI runs, pull requests and the API. Building and testing this
project doesn't need it, only working with GitHub does. Install it from
[cli.github.com](https://cli.github.com) or your package manager (on Ubuntu:
`sudo apt install gh`).

**Logging in.** `gh auth login` opens a browser, or prints a one-time code
to enter at <https://github.com/login/device>, and stores a token in the
system keyring:

```bash
gh auth login                                  # choose GitHub.com, then SSH or HTTPS
gh auth status                                 # account, git protocol and token scopes
gh auth refresh -h github.com -s delete_repo   # add a scope (here: deleting repos)
```

The token's scopes limit what `gh` can do. The default ones (`repo`,
`read:org`, `gist`) cover everything below except deleting a repository,
which needs `delete_repo`. When a command fails with HTTP 403, `gh` names
the missing scope.

**Repositories.** Inside a clone, `gh` acts on the repository of its
`origin` remote; anywhere else, name it with `-R <owner>/<repo>`.

```bash
gh repo view --web                             # open this repo in the browser
gh repo create my-pkg --private --source=. --remote=origin --push   # publish a local repo
gh repo delete <owner>/my-pkg --yes            # delete it (needs delete_repo; can't be undone)
```

With `--source=.`, `gh repo create` makes a GitHub repository from the
current git repository and pushes it. That works for a project made by
`scripts/new-pycpp.sh`, and its CI starts with the first push.

**CI runs.**

```bash
gh run list -L 5                               # latest runs: status, result, title, ID
gh run list -w CI -c "$(git rev-parse HEAD)"   # CI runs for the current commit
gh run watch <run-id> --exit-status            # follow a run; exits with 1 if it fails
gh run view <run-id>                           # summary, one line per job
gh run view <run-id> --log-failed              # logs of the failed steps only
gh run rerun <run-id> --failed                 # rerun only the failed jobs
```

`-c` needs the full commit hash, which `git rev-parse HEAD` prints; a short
one matches nothing. `gh run list` shows every workflow, including
Dependabot's (`Dependabot Updates`), so `-w CI` selects ours by its `name:`
in `ci.yml`. A run appears a few seconds after the push, so a list made
right away can be empty.

**Pull requests.** Dependabot's updates arrive as pull requests:

```bash
gh pr list                                     # open PRs
gh pr checks <number>                          # CI results for a PR
gh pr merge <number> --squash --delete-branch  # merge it once CI passes
```

**Scripting.** Most commands take `--json <fields>` and `-q <jq filter>`.
Use them in scripts: the plain output is meant for people and can change
between versions. `gh api` makes any REST API call.

```bash
gh run view <run-id> --json jobs -q '.jobs[] | .name + ": " + .conclusion'
gh api repos/<owner>/<repo>/actions/runs -q .total_count
```

`gh <command> --help` lists every option; the
[manual](https://cli.github.com/manual) has the same in full.

**Example: testing a new project's CI.** CI only runs on GitHub, so testing
the CI files that `scripts/new-pycpp.sh` copies needs a repository there.
This publishes a scaffolded project privately, waits for its CI and deletes
it again:

```bash
scripts/new-pycpp.sh --python 3.14 throwaway-ci
cd throwaway-ci
git add -A && git commit -m "Scaffold for a CI test"
git branch -M main          # CI runs on pushes to main; git's default may be master
gh repo create throwaway-ci --private --source=. --remote=origin --push
sleep 10                    # let the run appear
id=$(gh run list -w CI -c "$(git rev-parse HEAD)" --json databaseId -q '.[0].databaseId')
gh run watch "$id" --exit-status && gh run view "$id"
gh repo delete "$(gh api user -q .login)/throwaway-ci" --yes
cd .. && rm -rf throwaway-ci
```

---

## Activating the venv and `just` completion

`just` is installed only in the project venv (the `rust-just` dev
dependency), and `rust-just` ships only the binary, so the shell has no tab
completion for it. [`activate.sh`](activate.sh) handles both without
touching any file outside the project:

```bash
source ./activate.sh       # from the project root
just <TAB><TAB>            # lists the recipes
```

- It activates the venv first, then registers completion with
  `eval "$(JUST_COMPLETE=bash just)"`. The order matters: that line runs
  `just`, which must already be on `PATH`. This is also why the line can't
  go in `~/.bashrc`: no venv is active at shell startup.
- It recreates a missing venv (e.g. after `just clean`) with `uv sync`, and
  stops with an error if that fails.
- It must be **sourced**, not executed; `./activate.sh` prints a hint and
  exits.
- It works from any directory, and across projects: each project's
  `activate.sh` uses that project's `just`.
- Bash only. Completion lasts only for the current shell.
- It exports `JUST_COMPLETION_REGISTERED=1`. If the venv is active without
  it (e.g. activated with `source .venv/bin/activate`), plain `just` prints
  a hint to source `activate.sh`.

To activate automatically in every terminal, add to `~/.bashrc`:

```bash
[ -f ~/path/to/project/activate.sh ] && source ~/path/to/project/activate.sh
```

`uv run just <TAB>` completes uv's arguments, not just's.

---

## Validating the setup

1. **Checks pass:** `just check`.
2. **Checks catch errors.** Break things on purpose, then revert:

   | Introduce | Expect failure from |
   |---|---|
   | Unused `import os` | `just lint` (Ruff F401) |
   | `x: int = "a"` | `just typecheck` |
   | Function missing from `_core.pyi` | `just typecheck` |
   | `int unused = 5;` in C++ | `just lint` (compiler warning as error) |
   | Badly indented C++ | `just lint` (clang-format) |
   | A failing `CHECK` in `tests/cpp/` | `just test` (ctest) |
   | `assert False` in a test | `just test` |

3. **Clean rebuild:**

   ```bash
   deactivate
   uv run just clean
   uv sync --reinstall-package python-cpp   # compile, not reuse uv's cached build
   uv run just check && uv run just build
   ```

4. **Fresh clone.** This proves everything needed is committed:

   ```bash
   cd /tmp && rm -rf fresh && git clone <repo> fresh && cd fresh
   uv run just check
   ```

---

## Performance notes

- **Builds are already optimized.** The editable build uses
  `RelWithDebInfo` with `-O3 -g` (optimized, with symbols for py-spy), so
  benchmark directly:

  ```bash
  uv run python examples/do_factorize.py 10000000000000061   # a 17-digit prime, ~0.5 s
  ```

  The `build/cmake` tree used by `just test` is a Debug build; that only
  affects the C++ tests.
- **Check the generated code for hot loops.** GCC compiled the natural
  form of the factor loop (`d <= n / d` plus `n % d`) to two 64-bit divisions
  per step, where Rust's LLVM backend uses one; that made it 2× slower than
  the Rust version. `factor.cpp` now derives the remainder from the
  quotient, so each step costs one division.
- **Compared with the Rust version.** Both spend almost all their time in
  the CPU's 64-bit division, one per odd candidate. Best of three
  alternating runs on an Intel i7-8550U, timing the `factor` call alone:

  | Prime | Rust | C++ (`-O3`) |
  |---|---|---|
  | 17 digits (10¹⁶ + 61) | 0.357 s | 0.360 s (+1%) |
  | Largest below 2⁶⁴ (2⁶⁴ − 59, ~2.1 billion divisions) | 15.8 s | 16.2 s (+3%) |

  With CMake's default `RelWithDebInfo` flags (`-O2`), C++ was about 7%
  slower.
- **Keep hot code out of `core.cpp`.** `nanobind_add_module` compiles the
  module's own sources with `-Os` (smallest size), which overrides `-O3`.
  That suits binding code, but heavy work belongs in a separate library like
  `factor`, which gets `-O3`. (nanobind's `NOMINSIZE` option turns `-Os` off.)
- **Crossing the boundary costs.** Converting a large Python list to a
  `std::vector` copies every element. C++ pays off when it does real work
  per item, or with NumPy arrays via `nb::ndarray` (zero-copy).
- Release the GIL during long C++ computations with
  `nb::gil_scoped_release`, as `factor` does. Don't touch Python objects
  while it is released.
- On macOS, `py-spy` needs `sudo`.

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `just <TAB>` does nothing, or only completes file names | Completion not registered in this shell (`just` prints a hint) | `source ./activate.sh`; verify with `complete -p just` |
| `ModuleNotFoundError: python_cpp` | Not using the venv's Python | `uv run python ...` or `source ./activate.sh` |
| C++ change not visible | Ran `python` in the activated venv, which doesn't rebuild | `uv run python ...` or `uv sync` |
| Prompt shows the venv but commands fail | `.venv` deleted (e.g. `just clean`) while active | `deactivate`, then `source ./activate.sh` |
| `TypeError` calling a function that takes or returns a `std::` type | Missing `nanobind/stl/...` header | Include the header for that type in `core.cpp` |
| CMake errors after moving the project | Stale paths in `build/` | `just clean` |
