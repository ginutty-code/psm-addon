-- Tests/framework.lua
-- Minimal describe/it test framework. No dependencies, Lua 5.1 compatible.
--
-- Deliberately not busted: LuaRocks on Windows wants a C toolchain to build
-- busted's dependencies, and this project needs assertions plus a non-zero exit
-- code, nothing more. If the suite ever outgrows this, swapping in busted is a
-- contained change -- the specs only use the handful of names exported here.
--
-- Returns the framework table; spec files receive it as their vararg (`local T = ...`).

local M = {
    passed   = 0,
    failures = {},
    _stack   = {},
}

local function currentLabel(extra)
    local parts = {}
    for i = 1, #M._stack do parts[i] = M._stack[i] end
    if extra then parts[#parts + 1] = extra end
    return table.concat(parts, " > ")
end

function M.describe(name, fn)
    M._stack[#M._stack + 1] = name
    local ok, err = pcall(fn)
    table.remove(M._stack)
    if not ok then
        -- A failure in describe-body (not inside an it) would otherwise vanish.
        M.failures[#M.failures + 1] = {
            name = currentLabel(name),
            err  = "error in describe body: " .. tostring(err),
        }
        io.write("E")
        io.flush()
    end
end

function M.it(name, fn)
    local full = currentLabel(name)
    local ok, err = pcall(fn)
    if ok then
        M.passed = M.passed + 1
        io.write(".")
    else
        M.failures[#M.failures + 1] = { name = full, err = tostring(err) }
        io.write("F")
    end
    io.flush()
end

--------------------------------------------------------------------------------
-- ASSERTIONS
--------------------------------------------------------------------------------
-- error(..., 3) so the reported position is the spec line, not this file.

local function fail(msg)
    error(msg, 3)
end

function M.eq(actual, expected, what)
    if actual ~= expected then
        fail(string.format("%s: expected %s, got %s",
            what or "value", tostring(expected), tostring(actual)))
    end
end

function M.neq(actual, unexpected, what)
    if actual == unexpected then
        fail(string.format("%s: expected anything but %s", what or "value", tostring(unexpected)))
    end
end

function M.truthy(v, what)
    if not v then
        fail(string.format("%s: expected truthy, got %s", what or "value", tostring(v)))
    end
end

function M.falsy(v, what)
    if v then
        fail(string.format("%s: expected falsy, got %s", what or "value", tostring(v)))
    end
end

function M.isType(v, expected, what)
    local actual = type(v)
    if actual ~= expected then
        fail(string.format("%s: expected type %s, got %s (%s)",
            what or "value", expected, actual, tostring(v)))
    end
end

-- Asserts fn raises. Returns the error so callers can inspect it.
function M.raises(fn, what)
    local ok, err = pcall(fn)
    if ok then
        fail(string.format("%s: expected an error, none raised", what or "call"))
    end
    return err
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

-- Counts every key, unlike `#`, which only measures the array part.
function M.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------

function M.report()
    io.write("\n\n")
    for _, f in ipairs(M.failures) do
        io.write(string.format("FAIL  %s\n      %s\n\n", f.name, f.err))
    end
    io.write(string.format("%d passed, %d failed\n", M.passed, #M.failures))
    return #M.failures == 0
end

return M
