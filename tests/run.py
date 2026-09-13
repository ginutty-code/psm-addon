"""Run the Lua test suite without installing a Lua interpreter.

Usage, from the psm-addon repo root:

    uv run --with lupa python tests/run.py

lupa bundles several Lua builds; this picks the Lua 5.1 one, the same dialect the
WoW client runs, so results match `lua.exe tests/run.lua` exactly.

This is a bootstrap, not a second test runner -- tests/suite.lua is the single
source of truth and this file only supplies it an interpreter. Prefer the plain
`lua.exe tests/run.lua` path for day-to-day use; this exists so the suite is
runnable on a machine with no Lua installed (and in CI without a Lua toolchain).
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    try:
        from lupa import lua51
    except ImportError:
        print(
            "lupa is required for this bootstrap.\n"
            "  uv run --with lupa python tests/run.py\n"
            "or install a Lua 5.1 interpreter and use: lua.exe tests/run.lua",
            file=sys.stderr,
        )
        return 2

    # suite.lua resolves its paths relative to the repo root.
    import os

    os.chdir(REPO_ROOT)

    runtime = lua51.LuaRuntime(unpack_returned_tuples=True)
    suite = runtime.execute('return dofile("tests/suite.lua")')
    return 0 if suite() else 1


if __name__ == "__main__":
    sys.exit(main())
