-- Tests/spec/loaderinputs_spec.lua
-- The two browser loaders' dependency sets, enforced against the functions they cache.
--
-- `renderinputs_spec` does this for the Owned Pets render. These two removed their 0.2s
-- expiry in the same change and had nothing checking them, which the commit that removed it
-- said out loud: "the browser's loaders deserve the same audit and do not have it yet."
-- Without an expiry an unmodelled input is **permanent** staleness -- the filter simply
-- stops working until something unrelated moves -- so the dependency lists have to be
-- re-derived by a machine rather than by whoever last read the file.
--
-- **This one has to be transitive, and that is the whole difference.** The Owned Pets
-- computation reads `ns.state` inline, so scanning one function body is the complete
-- answer. Both loaders instead delegate: `_CalculateModelsData` calls `DisplayPassesFilters`,
-- which is where `favoriteModels`, `selectedTamingRules` and `selectedConditions` are read,
-- and none of them appear in the caller. A per-function scan would report "fully covered"
-- while three of the eleven slices had no visible justification at all -- a green test
-- proving nothing, which is worse than no test.

local T = ...
local describe, it, eq = T.describe, T.it, T.eq

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function StripComments(src)
    return (src:gsub("([^\n]*)", function(line) return (line:gsub("%-%-.*$", "")) end))
end

--------------------------------------------------------------------------------
-- Function extraction
--------------------------------------------------------------------------------

-- Bodies run from a definition to the next *top-level* one. Deliberately the same crude
-- rule `renderinputs_spec` uses rather than a keyword-depth counter: both files define
-- every function at column zero, so the rule is exact here, and a depth counter would add a
-- Lua parser's worth of failure modes to a test whose job is to be trusted when it fails.
local function IndexFunctions(src)
    local byName = {}
    local starts = {}

    for pos in src:gmatch("()\nlocal function [%w_]+%s*%(") do
        starts[#starts + 1] = pos + 1
    end
    for pos in src:gmatch("()\nfunction [%w_%.]+[:%.][%w_]+%s*%(") do
        starts[#starts + 1] = pos + 1
    end
    table.sort(starts)

    for i = 1, #starts do
        local from = starts[i]
        local to   = (starts[i + 1] and starts[i + 1] - 1) or #src
        local body = src:sub(from, to)
        local name = body:match("^local function ([%w_]+)")
                  or body:match("^function [%w_%.]+[:%.]([%w_]+)")
        if name then byName[name] = body end
    end

    return byName
end

-- Everything reachable from `entry` without leaving the file, concatenated.
--
-- **Callees are matched by bare name**, so `self:_IsZoneMatch(...)`, `Loader:_IsZoneMatch(...)`
-- and a plain `DisplayPassesFilters(...)` all resolve the same way. That over-matches in
-- principle -- a same-named function in another module would be followed as if it were this
-- one -- and over-matching is the safe direction: it can only pull in *more* state reads and
-- demand *more* justification. Under-matching is what silently passes.
local function TransitiveBody(byName, entry)
    local seen, order = {}, {}

    local function visit(name)
        if seen[name] or not byName[name] then return end
        seen[name] = true
        order[#order + 1] = byName[name]
        for callee in byName[name]:gmatch("[%w_]+%s*%(") do
            visit((callee:gsub("%s*%($", "")))
        end
        for callee in byName[name]:gmatch("[:%.]([%w_]+)%s*%(") do
            visit(callee)
        end
    end

    visit(entry)
    if not seen[entry] then return nil end
    return table.concat(order, "\n"), seen
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

-- Three kinds of input, because the loaders have three kinds. `PSM.state.x` is the obvious
-- one; the other two are why a scan for `PSM.state` alone would under-report:
--
--   * `PSM.FilterState:Get("x")` -- the toggles never touch `PSM.state` at a call site.
--   * `panel.x` -- the search box and the player's zone live on the panel frame, which is
--     precisely the "state living in a frame is invisible to invalidation" case that cost
--     the Owned Pets render its `panelWidth` slice.
local function InputsRead(body)
    local seen, list = {}, {}
    local function add(key)
        if not seen[key] then seen[key] = true; list[#list + 1] = key end
    end

    for field in body:gmatch("PSM%.state%.([%w_]+)") do add("state." .. field) end
    for _ in body:gmatch("FilterState:Get%(") do add("FilterState:Get") end
    for field in body:gmatch("[^%w_]panel%.([%w_]+)") do add("panel." .. field) end

    table.sort(list)
    return list
end

--------------------------------------------------------------------------------
-- The audit record
--------------------------------------------------------------------------------

-- Each input maps to the slice that reports it moving. Adding a row is the decision a
-- failure asks for, and it is not made without adding the slice.
--
-- **`state.isStableOpen` is the one row that needs its reasoning written down.** It is not a
-- filter: it chooses between `CollectStablePets` and `LoadPersistentDataForDisplay`, and both
-- write `stablePets`. So the computed answer varies with `stablePets` -- which `pets`
-- fingerprints -- not with the flag. Flipping the flag on its own changes nothing, because
-- the branch only fires when the list is empty. It is mapped to `pets` for that reason, and
-- **not** given a slice of its own: a slice here would recompute the whole model list every
-- time the player walked up to a stable master, for an answer that cannot have changed.
local COVERED = {
    ["state.modelsPanel"]            = "panel",
    ["state.isStableOpen"]           = "pets",     -- steers the load; see above
    ["state.stablePets"]             = "pets",
    ["state.selectedModelsFamilies"] = "families",
    ["state.selectedExpansions"]     = "expansions",
    ["state.selectedLocations"]      = "locations",
    ["state.selectedTamingRules"]    = "tamingRules",
    ["state.selectedConditions"]     = "conditions",
    ["state.favoriteModels"]         = "favorites",
    ["FilterState:Get"]              = "toggles",
    ["panel.searchBox"]              = "search",
    ["panel.currentPlayerZone"]      = "zone",
}

local LOADERS = {
    {
        label = "Models view",
        path  = "PetStableManagement_ModelsBrowser/ModelsBrowser/ModelsDataLoader.lua",
        entry = "_CalculateModelsData",
        list  = "MODELS_RESULT_SLICES",
    },
    {
        label = "NPC view",
        path  = "PetStableManagement_ModelsBrowser/ModelsBrowser/NPCDataLoader.lua",
        entry = "_CalculateNPCData",
        list  = "NPC_RESULT_SLICES",
    },
}

for _, loader in ipairs(LOADERS) do
    describe(loader.label .. " loader inputs", function()
        local src   = ReadFile(loader.path)
        local clean = src and StripComments(src)
        local byName = clean and IndexFunctions(clean)
        -- Not `byName and TransitiveBody(...)`: `and` truncates a multiple return to one
        -- value, so `reached` would be nil however many helpers the walk actually visited --
        -- and the test below would pass by measuring nothing.
        local body, reached
        if byName then body, reached = TransitiveBody(byName, loader.entry) end

        it("finds the function it is about to audit", function()
            eq(src ~= nil, true, loader.path .. " is readable")
            eq(body ~= nil, true, loader.entry .. " located")
        end)

        -- Stated separately from the audit because a transitive walk that quietly stopped at
        -- the entry function would make every later test pass for the wrong reason.
        it("follows the helpers the computation delegates to", function()
            local count = 0
            for _ in pairs(reached or {}) do count = count + 1 end
            eq(count > 1, true,
                loader.entry .. " reaches file-local helpers (reached " .. count .. ")")
        end)

        it("reads no input the slice list does not cover", function()
            local uncovered = {}
            for _, input in ipairs(InputsRead(body)) do
                if not COVERED[input] then uncovered[#uncovered + 1] = input end
            end
            if #uncovered > 0 then
                error(("%s reads %d input(s) with no slice behind them:\n  %s\n\nThese "
                    .. "selectors have no expiry, so an unmodelled input is permanent "
                    .. "staleness rather than a slow refresh. Declare a slice, add it to %s, "
                    .. "and record the mapping in COVERED in this file.")
                    :format(loader.entry, #uncovered, table.concat(uncovered, "\n  "),
                            loader.list), 0)
            end
            eq(#uncovered, 0, "uncovered inputs")
        end)

        it("declares every slice its inputs require", function()
            local declared = src:match("local " .. loader.list .. " = {(.-)}")
            eq(declared ~= nil, true, loader.list .. " found")
            -- Unmapped inputs are skipped rather than crashed on: the test above owns that
            -- failure and names the field, and a `nil` concatenated here would bury its
            -- message under a stack trace from the wrong test.
            for _, input in ipairs(InputsRead(body)) do
                local slice = COVERED[input]
                if slice then
                    eq(declared:find('"' .. slice .. '"', 1, true) ~= nil, true,
                        slice .. " (for " .. input .. ") is in " .. loader.list)
                end
            end
        end)

        -- The reverse direction, and it is not symmetry for its own sake: NPCDataLoader's own
        -- comment on this list says "declaring a dependency the compute ignores buys cache
        -- misses for nothing", which is what happened before `tamingRules` and `conditions`
        -- were actually read there. A slice that nothing justifies is a slow cache with no
        -- correctness gained.
        it("declares no slice nothing reads", function()
            local declared = src:match("local " .. loader.list .. " = {(.-)}")
            local justified = {}
            for _, input in ipairs(InputsRead(body)) do
                if COVERED[input] then justified[COVERED[input]] = true end
            end

            local unused = {}
            for slice in declared:gmatch('"([%w_]+)"') do
                if not justified[slice] then unused[#unused + 1] = slice end
            end
            if #unused > 0 then
                error(("%s declares %d slice(s) nothing in %s reads:\n  %s\n\nEach one is a "
                    .. "cache miss bought for no correctness. Either the dependency is stale "
                    .. "and should go, or the read exists somewhere this audit cannot see -- "
                    .. "in which case say where, in COVERED.")
                    :format(loader.list, #unused, loader.entry,
                            table.concat(unused, "\n  ")), 0)
            end
            eq(#unused, 0, "unjustified slices")
        end)
    end)
end

-- **The premise the whole audit rests on.**
--
-- Both computations call across module boundaries -- `PetModels.SelectionAllows`,
-- `TamingSetPasses`, `NpcPassesConditions`, `NpcExpansion`, `NpcLocation` -- and the walk
-- above stops at the file it is reading. That is only sound while those callees are pure
-- readers of the generated `ModelsData` tables, which today they are: `PetModels.lua`
-- contains no `PSM.state` read at all.
--
-- Pinned as a property rather than as an allowlist of function names, because the roster of
-- callees changes with every refactor while the property is what actually has to hold. If
-- someone gives a resolver a filter-dependent branch, this fails and says so, instead of the
-- audit silently going partial.
describe("Loader audit premise", function()
    it("PetModels reads no filter state", function()
        local src = ReadFile("PetStableManagement_ModelsBrowser/ModelsBrowser/PetModels.lua")
        eq(src ~= nil, true, "PetModels.lua is readable")

        local hits = {}
        for field in StripComments(src):gmatch("PSM%.state%.([%w_]+)") do
            hits[#hits + 1] = field
        end
        if #hits > 0 then
            error(("PetModels.lua now reads PSM.state (%s).\n\nThe loader input audits stop "
                .. "at the file boundary on the premise that PetModels only resolves "
                .. "generated ModelsData. A filter input reached through it is invisible to "
                .. "them, so either move the read to the loader or extend the audit to "
                .. "follow into this file.")
                :format(table.concat(hits, ", ")), 0)
        end
        eq(#hits, 0, "PSM.state reads in PetModels.lua")
    end)
end)
