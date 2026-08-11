-- Tests/run.lua
-- Primary entry point. Run from the psm-addon repo root:
--
--     lua.exe Tests/run.lua
--
-- (Any Lua 5.1-compatible interpreter works; the WoW client is 5.1, which is why
-- .luacheckrc sets std = "lua51". LuaJIT is fine too.)
--
-- Exits non-zero on failure so CI and pre-commit hooks can gate on it.

os.exit(dofile("Tests/suite.lua")() and 0 or 1)
