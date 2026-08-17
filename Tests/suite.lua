-- Tests/suite.lua
-- Loads the framework, runs every spec, prints the report.
-- Returns true when everything passed.
--
-- Kept separate from run.lua so both entry points (lua.exe and the lupa
-- bootstrap) share one definition of "the suite" and neither duplicates it.
--
-- Paths are relative to the psm-addon repo root, so run from there.

local T = dofile("Tests/framework.lua")

-- Explicit, ordered list: Lua has no portable directory listing without LuaFileSystem,
-- and an explicit list is a feature here -- adding a spec is a visible diff.
local SPECS = {
    "Tests/spec/models_data_spec.lua",
    "Tests/spec/utils_spec.lua",
    "Tests/spec/loader_spec.lua",
    "Tests/spec/boundary_spec.lua",
    "Tests/spec/publicapi_spec.lua",
    "Tests/spec/filterstate_spec.lua",
    "Tests/spec/encoding_spec.lua",
    "Tests/spec/selections_spec.lua",
    "Tests/spec/store_spec.lua",
    "Tests/spec/specialtames_spec.lua",
    "Tests/spec/renderinputs_spec.lua",
}

return function()
    for _, path in ipairs(SPECS) do
        local chunk, err = loadfile(path)
        if not chunk then
            io.write("\nCould not load " .. path .. ":\n  " .. tostring(err) .. "\n")
            io.write("(are you running from the psm-addon repo root?)\n")
            return false
        end
        local ok, runErr = pcall(chunk, T)
        if not ok then
            -- A spec that blows up at file scope (bad dofile path, syntax-level
            -- surprise) would otherwise report zero tests and look like success.
            io.write("\nSpec crashed while loading: " .. path .. "\n  " .. tostring(runErr) .. "\n")
            return false
        end
    end
    return T.report()
end
