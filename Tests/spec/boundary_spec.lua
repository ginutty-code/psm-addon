-- Tests/spec/boundary_spec.lua
-- The core <-> Models Browser boundary, enforced.
--
-- Two addons share one global table, `_G.PSM`. Core defines ~38 members on it; the
-- browser is meant to consume only the handful core deliberately exports. Nothing in the
-- language enforces that -- `PSM.AnythingAtAll` is valid Lua from either side -- so the
-- boundary has until now been a convention, held up by whoever remembered it.
--
-- This spec is the enforcement. It reads core's PUBLIC_API declaration, works out which
-- members the browser owns for itself, and fails on any other `PSM.x` a browser file
-- touches. luacheck cannot do this: it sees one global named `PSM`, never its fields.
--
-- It is also the safety net for A3's `ns` conversion. When core's internals become
-- `ns`-private, a browser file still reaching for one goes from "silently nil at runtime,
-- in whichever rare panel exercises it" to "named here, before the game is even opened".

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

-- Lua 5.1 (the client's dialect, and lupa's) compiles a string with `loadstring`; 5.2+
-- folded that into `load`. Both entry points have to work -- run.lua may find a 5.4
-- interpreter on PATH while CI uses 5.1.
local LoadString = loadstring or load

local CORE_FILE   = "PetStableManagement/Shared/PublicAPI.lua"
local CORE_TOC    = "PetStableManagement/PetStableManagement.toc"
local CORE_DIR    = "PetStableManagement/"
local BROWSER_TOC = "PetStableManagement_ModelsBrowser/PetStableManagement_ModelsBrowser.toc"
local BROWSER_DIR = "PetStableManagement_ModelsBrowser/"

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

--------------------------------------------------------------------------------
-- Reading Lua as code, not as text
--------------------------------------------------------------------------------

-- Comments are not references. On this spec's first run it reported `PSM.CreateFrame` in
-- ModelsPanel.lua -- from the comment explaining why that file deliberately does *not*
-- call it. A checker that flags the note warning against the thing is worse than no
-- checker, because the obvious fix is to delete the explanation.
--
-- Returns an array of comment-free lines, so a violation can be reported at a line number
-- the reader can actually open. A `--` inside a string literal would be mis-stripped, but
-- that only risks a *missed* reference on a line also containing a quoted "--", which
-- occurs nowhere in either addon.
local function CodeLines(source)
    local stripped = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-%[=%[.-%]=%]", "")
    local lines = {}
    for line in (stripped .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
    end
    return lines
end

--------------------------------------------------------------------------------
-- The declared surface
--------------------------------------------------------------------------------

-- Parsed out of PublicAPI.lua rather than duplicated here: two copies of a contract is how the
-- contract starts being wrong. The block is extracted and compiled as real Lua, so a
-- malformed declaration fails loudly instead of silently yielding a short list -- which
-- would make this whole spec pass by testing nothing.
local function DeclaredPublicAPI()
    local source = ReadFile(CORE_FILE)
    if not source then return nil, CORE_FILE .. " not found (run from the repo root)" end

    local body = source:match("local PUBLIC_API = (%b{})")
    if not body then return nil, "no `local PUBLIC_API = { ... }` block in " .. CORE_FILE end

    local chunk, err = LoadString("return " .. body)
    if not chunk then return nil, "PUBLIC_API block is not valid Lua: " .. tostring(err) end

    local ok, list = pcall(chunk)
    if not ok or type(list) ~= "table" then return nil, "PUBLIC_API did not evaluate to a table" end

    local set = {}
    for _, name in ipairs(list) do set[name] = true end
    return set, nil, #list
end

--------------------------------------------------------------------------------
-- The browser's files, and what it defines for itself
--------------------------------------------------------------------------------

-- Taken from the .toc, not a hand-kept list: the .toc is what the client actually loads,
-- so a new browser file is covered the moment it ships rather than whenever someone
-- remembers to add it here.
local function TocFiles(tocPath, dir)
    local toc = ReadFile(tocPath)
    if not toc then return nil end
    local files = {}
    for line in toc:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed:match("%.lua$") and not trimmed:match("^#") then
            files[#files + 1] = dir .. trimmed:gsub("\\", "/")
        end
    end
    return files
end

local function BrowserFiles() return TocFiles(BROWSER_TOC, BROWSER_DIR) end
local function CoreFiles()    return TocFiles(CORE_TOC,    CORE_DIR)    end

-- `PSM.Foo = ...` and `function PSM.Foo...` -- the browser's own members. Collected from
-- every browser file including Data/, because the generated tables define members
-- (PSM.ConditionsData, PSM.NotesData) that the hand-written files then consume.
--
-- Dot syntax only, deliberately. Core assigns two members dynamically as `PSM[key] = f`
-- (RowManager's rotation and movement tickers), which this cannot see -- and should not:
-- they are core internals, and the browser reaching for one is exactly the violation
-- worth catching. It did catch it on the first run.
local DEFINITION_PATTERNS = {
    "PSM%.([%a_][%w_]*)%s*=",
    "function%s+PSM%.([%a_][%w_]*)",
}

local function OwnedByBrowser(files)
    local owned = {}
    for _, path in ipairs(files) do
        local source = ReadFile(path)
        if source then
            for _, line in ipairs(CodeLines(source)) do
                for _, pattern in ipairs(DEFINITION_PATTERNS) do
                    for name in line:gmatch(pattern) do owned[name] = true end
                end
            end
        end
    end
    return owned
end

-- Data/ is generated by psm-data: it defines members and consumes nothing, and any
-- violation there would have to be fixed in the generator rather than the file.
local function IsGenerated(path)
    return path:match("/Data/") ~= nil
end

--------------------------------------------------------------------------------
-- Specs
--------------------------------------------------------------------------------

describe("core/browser boundary", function()
    local publicAPI, apiErr, apiCount = DeclaredPublicAPI()
    local files = BrowserFiles() or {}

    it("finds core's PUBLIC_API declaration", function()
        truthy(publicAPI, apiErr or "PUBLIC_API")
        -- Guards against the extraction quietly matching something tiny: if this list
        -- ever collapsed, every reference below would be reported and the failure would
        -- read as a hundred boundary violations rather than one broken parser.
        truthy(apiCount and apiCount >= 8,
            "PUBLIC_API has a plausible size (got " .. tostring(apiCount) .. ")")
    end)

    it("finds the browser's files via its .toc", function()
        truthy(#files > 0, "browser .lua files listed in the .toc")
    end)

    it("never reaches for a core member outside PUBLIC_API", function()
        local owned      = OwnedByBrowser(files)
        local violations = {}

        for _, path in ipairs(files) do
            if not IsGenerated(path) then
                local source = ReadFile(path)
                for n, line in ipairs(source and CodeLines(source) or {}) do
                    for name in line:gmatch("PSM%.([%a_][%w_]*)") do
                        if not publicAPI[name] and not owned[name] then
                            violations[#violations + 1] =
                                ("%s:%d  PSM.%s"):format(path, n, name)
                        end
                    end
                end
            end
        end

        if #violations > 0 then
            table.sort(violations)
            error(("browser reaches %d core member(s) outside PUBLIC_API:\n  %s\n\n"
                .. "Prefer giving the browser a service over widening the surface -- "
                .. "a name added to PUBLIC_API in PublicAPI.lua can never change "
                .. "without touching both addons.")
                :format(#violations, table.concat(violations, "\n  ")), 0)
        end
        eq(#violations, 0, "boundary violations")
    end)

    it("exports nothing the browser has stopped using", function()
        -- The opposite drift: a name outlives its last consumer and the boundary looks
        -- wider than it is. Worth failing on -- this surface is small enough that every
        -- entry should be justified by a live reference, and `Loader` was on the planned
        -- list purely because nobody had checked.
        local used = {}
        for _, path in ipairs(files) do
            if not IsGenerated(path) then
                local source = ReadFile(path)
                for _, line in ipairs(source and CodeLines(source) or {}) do
                    for name in line:gmatch("PSM%.([%a_][%w_]*)") do used[name] = true end
                end
            end
        end

        local unused = {}
        for name in pairs(publicAPI or {}) do
            if not used[name] then unused[#unused + 1] = name end
        end
        table.sort(unused)
        eq(#unused, 0,
            "PUBLIC_API entries with no browser consumer (" .. table.concat(unused, ", ") .. ")")
    end)
end)

--------------------------------------------------------------------------------
-- The other direction
--------------------------------------------------------------------------------

-- Core calls the browser too -- the minimap and slash commands toggle its panels, the
-- popups resolve models and taming rules through it -- and until 3g *nothing checked that
-- direction*. It did not need checking while `_G.PSM = ns` made one table of two names:
-- the browser's `PSM.ModelsPanel = {}` landed in core's namespace, so core's
-- `ns.ModelsPanel` found it.
--
-- Separating the tables made all 47 of those reads nil. Every one is guarded, so none of
-- them would have errored -- the browser would have loaded and the feature would quietly
-- not be there, which is the failure mode this repo keeps re-learning. They now go through
-- `ns.Browser`, and this is what keeps them there: the next core file to write
-- `ns.ModelsPanel` is named here rather than discovered in-game.
describe("core -> browser boundary", function()
    local coreFiles    = CoreFiles() or {}
    local browserFiles = BrowserFiles() or {}

    it("finds core's files via its .toc", function()
        truthy(#coreFiles > 0, "core .lua files listed in the .toc")
    end)

    it("reaches the browser only through ns.Browser", function()
        local owned      = OwnedByBrowser(browserFiles)
        local violations = {}

        -- `ns.Browser.ModelsPanel` is not a match: the pattern captures `Browser`, and the
        -- name after it is never preceded by `ns.`. So the bridge is invisible here and
        -- only the direct reads are reported, which is the whole point.
        for _, path in ipairs(coreFiles) do
            local source = ReadFile(path)
            for n, line in ipairs(source and CodeLines(source) or {}) do
                for name in line:gmatch("ns%.([%a_][%w_]*)") do
                    if owned[name] then
                        violations[#violations + 1] = ("%s:%d  ns.%s"):format(path, n, name)
                    end
                end
            end
        end

        if #violations > 0 then
            table.sort(violations)
            error(("core reads %d browser-owned name(s) off its own namespace:\n  %s\n\n"
                .. "The browser is a separate addon with its own `ns`, so these resolve to "
                .. "nil -- silently, since each one is guarded. Use `ns.Browser.X`, which "
                .. "forwards to the shared global (see Core.lua).")
                :format(#violations, table.concat(violations, "\n  ")), 0)
        end
        eq(#violations, 0, "core reads of browser members off ns")
    end)

    -- Crossing into the other addon is legitimate; rummaging in its drawers is not.
    -- PanelManager used to clear four of the browser's cache and timer fields by hand,
    -- which put four private names on the surface and -- because a C_Timer handle is
    -- owned by the timer system, not by the field holding it -- dropped two live timers
    -- without cancelling them. `ModelsPanel:ReleaseCaches()` replaced the lot.
    --
    -- The `_` prefix is this codebase's private marker on both sides of the boundary.
    it("reaches browser modules, never browser private fields", function()
        local violations = {}
        for _, path in ipairs(coreFiles) do
            local source = ReadFile(path)
            for n, line in ipairs(source and CodeLines(source) or {}) do
                for name in line:gmatch("ns%.Browser%.(_[%a_][%w_]*)") do
                    violations[#violations + 1] = ("%s:%d  ns.Browser.%s"):format(path, n, name)
                end
            end
        end
        if #violations > 0 then
            table.sort(violations)
            error(("core touches %d private browser field(s):\n  %s\n\n"
                .. "Ask the browser to do it instead -- a service keeps the name off the "
                .. "surface, and keeps the knowledge of what clearing it entails (a timer "
                .. "needs :Cancel(), not = nil) in the addon that owns the field.")
                :format(#violations, table.concat(violations, "\n  ")), 0)
        end
        eq(#violations, 0, "private browser fields touched by core")
    end)

    -- Guards the guard. If `OwnedByBrowser` ever returned an empty set -- a renamed .toc, a
    -- changed definition pattern -- the check above would pass by examining nothing, and
    -- would keep passing forever.
    it("knows which names the browser owns", function()
        local owned, count = OwnedByBrowser(browserFiles), 0
        for _ in pairs(owned) do count = count + 1 end
        truthy(count >= 10, "browser-owned names found (got " .. count .. ")")
        truthy(owned.ModelsPanel, "ModelsPanel is recognised as browser-owned")
    end)
end)
