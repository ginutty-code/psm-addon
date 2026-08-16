-- Tests/spec/selections_spec.lua
-- PSM.Selections: behaviour, and the enforcement that makes it the *only* writer.
--
-- The second half is the point. A5.1's store invalidates on writes that go through a
-- setter, so a single missed write is not a slow path -- it is a selector that never
-- updates again. Whether every write was caught could not be answered by reading the code,
-- because the sets were mutated through helpers that only saw a parameter:
--
--     SelectAll(PSM.state.selectedModelsFamilies, list)   -- writes stateMap[k] inside
--
-- No search for `selectedModelsFamilies` finds that write. So the write count was a lower
-- bound with no way to become an upper bound, and "we funnelled them all" was an assertion
-- rather than a fact. The source scan below turns it into a fact, re-checked on every run.

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

local Addon = dofile("Tests/wow/addon.lua")

local STATE_FIELDS = {
    "selectedModelsFamilies", "selectedExpansions", "selectedLocations",
    "selectedTamingRules", "selectedConditions",
}

local function freshSelections()
    local ns = Addon.namespace()
    ns.state = {}
    return Addon.load("PetStableManagement/State/Selections.lua", ns).Selections, ns
end

describe("Selections", function()
    it("creates a slice's table on first use", function()
        local S, ns = freshSelections()
        S:Set("families", "Wolf", true)
        eq(ns.state.selectedModelsFamilies.Wolf, true, "written through to state")
    end)

    it("maps every slice to its state field", function()
        local S, ns = freshSelections()
        for slice in pairs(S.SLICES) do S:Set(slice, "x", true) end
        for _, field in ipairs(STATE_FIELDS) do
            truthy(ns.state[field], field .. " exists")
            eq(ns.state[field].x, true, field .. " written")
        end
    end)

    it("raises on an unknown slice", function()
        local S = freshSelections()
        eq(pcall(function() S:Set("familes", "Wolf", true) end), false, "Set raises on a typo")
        eq(pcall(function() return S:Get("nope") end), false, "Get raises")
    end)

    it("sets every key in a list", function()
        local S, ns = freshSelections()
        S:SetAll("locations", { "Durotar", "Elwynn" }, true)
        eq(ns.state.selectedLocations.Durotar, true, "first")
        eq(ns.state.selectedLocations.Elwynn, true, "second")
    end)

    -- The identity guarantee. Call sites used to write `ns.state.selectedExpansions = {}`,
    -- which detaches any alias another function is still holding -- and hard-to-find
    -- aliases are the reason this module exists. One table for the session removes it.
    it("empties in place, keeping one table identity", function()
        local S, ns = freshSelections()
        S:SetAll("expansions", { "Classic", "TBC" }, true)
        local before = ns.state.selectedExpansions
        S:Clear("expansions")
        eq(ns.state.selectedExpansions, before, "same table object")
        eq(next(ns.state.selectedExpansions), nil, "and it is empty")
    end)

    it("replaces contents without replacing the table", function()
        local S, ns = freshSelections()
        S:SetAll("tamingRules", { "old" }, true)
        local before = ns.state.selectedTamingRules
        S:Replace("tamingRules", { new = "inverted" })
        eq(ns.state.selectedTamingRules, before, "same table object")
        eq(ns.state.selectedTamingRules.new, "inverted", "new value")
        eq(ns.state.selectedTamingRules.old, nil, "old value gone")
    end)

    it("fills only when empty", function()
        local S, ns = freshSelections()
        eq(S:FillIfEmpty("families", { "Wolf", "Bear" }, true), true, "filled")
        eq(S:FillIfEmpty("families", { "Cat" }, true), false, "second call is a no-op")
        eq(ns.state.selectedModelsFamilies.Cat, nil, "and did not add")
    end)

    -- `next(tbl) ~= nil` is what call sites wrote by hand, and it is not the same test: a
    -- key explicitly set to false is present but not selected.
    it("reports selection by truthiness, not presence", function()
        local S = freshSelections()
        eq(S:Any("families"), false, "empty")
        S:Set("families", "Wolf", false)
        eq(S:Any("families"), false, "present but false is not selected")
        S:Set("families", "Bear", true)
        eq(S:Any("families"), true, "truthy value counts")
    end)
end)

--------------------------------------------------------------------------------
-- Enforcement
--------------------------------------------------------------------------------

local STRING_RE = '["\'].-["\']'

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function CodeLines(source)
    local stripped = source:gsub("%-%-%[%[.-%]%]", "")
    local lines = {}
    for line in (stripped .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
    end
    return lines
end

local TOCS = {
    { toc = "PetStableManagement/PetStableManagement.toc", dir = "PetStableManagement/" },
    { toc = "PetStableManagement_ModelsBrowser/PetStableManagement_ModelsBrowser.toc",
      dir = "PetStableManagement_ModelsBrowser/" },
}

-- The module itself, plus Core.lua, which declares the fields in its `state` literal.
local ALLOWED = {
    ["PetStableManagement/State/Selections.lua"] = true,
    ["PetStableManagement/Core.lua"] = true,
}

local function ShippedFiles()
    local files = {}
    for _, source in ipairs(TOCS) do
        local toc = ReadFile(source.toc)
        for line in (toc or ""):gmatch("[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed:match("%.lua$") and not trimmed:match("^#") then
                files[#files + 1] = source.dir .. trimmed:gsub("\\", "/")
            end
        end
    end
    return files
end

describe("Selections is the only writer", function()
    local files = ShippedFiles()

    it("finds the shipped files", function()
        truthy(#files > 20, "shipped .lua files (got " .. #files .. ")")
    end)

    -- Two shapes of write, both banned outside the module:
    --   state.selectedX      = ...   (replacing the table)
    --   state.selectedX[key] = ...   (mutating a key)
    --
    -- Anchored on `state.`, because the same five names are also keys in SavedVariables --
    -- `PetStableManagementDB.filters.selectedLocations`. Those are the persisted copy and
    -- are written freely; this module owns the *session* tables. The first version of this
    -- check missed that and reported eleven saves as violations, which would have taught
    -- the reader that the rule is noise.
    it("has no direct assignment to a selection table", function()
        local violations = {}
        for _, path in ipairs(files) do
            if not ALLOWED[path] then
                for n, line in ipairs(CodeLines(ReadFile(path) or "")) do
                    for _, field in ipairs(STATE_FIELDS) do
                        -- Three shapes, because Lua writes a key two ways and this check
                        -- first shipped knowing only one of them. An injected
                        -- `state.selectedLocations.Durotar = true` sailed past a rule that
                        -- matched `[key] =` but not `.key =` -- the same dot-versus-bracket
                        -- blind spot that hid RowManager's tickers during the ns conversion,
                        -- met again from the other side.
                        if line:match("state%." .. field .. "%s*=[^=]")
                           or line:match("state%." .. field .. "%b[]%s*=[^=]")
                           or line:match("state%." .. field .. "%s*%.%s*[%w_]+%s*=[^=]") then
                            violations[#violations + 1] =
                                ("%s:%d  %s"):format(path, n, line:match("^%s*(.-)%s*$"))
                        end
                    end
                end
            end
        end
        if #violations > 0 then
            table.sort(violations)
            error(("%d direct write(s) to a selection table:\n  %s\n\n"
                .. "Route these through PSM.Selections (Set/SetAll/Clear/Replace). A write "
                .. "that bypasses it is invisible to A5.1's store, which makes the "
                .. "dependent selector permanently stale rather than merely slow.")
                :format(#violations, table.concat(violations, "\n  ")), 0)
        end
        eq(#violations, 0, "direct writes")
    end)

    -- The rule that catches the SelectAll shape. Passing the table to a function hands over
    -- the ability to write it, somewhere no search for the field name will look.
    --
    -- **The allowlist is the audited set, and that is the mechanism, not a loophole.**
    -- Nothing static can tell a read-only callee from a mutating one, so the question is
    -- only ever "which callees has someone checked". Naming them here means a *new* way of
    -- passing a selection table fails the build and has to be justified, while the audited
    -- ones stay quiet. Adding a name is the decision the failure is asking for.
    local READ_ONLY_CALLEES = {
        pairs = true, ipairs = true, next = true, type = true, tostring = true,
        DeepCopy = true,                    -- Utils, returns a copy
        TamingSetPasses = true,             -- PetModels, pure predicate
        ConditionsHaveActive = true,        -- PetModels, pure predicate
        NpcPassesConditions = true,         -- PetModels, pure predicate
        IsLocationSelected = true,          -- NPCDataLoader, pure predicate
        IsExpansionSelected = true,         -- NPCDataLoader, pure predicate
        _IsLocationSelected = true,         -- ModelsDataLoader, pure predicate
        _IsExpansionSelected = true,        -- ModelsDataLoader, pure predicate
        ComputeMatchingFamilies = true,     -- SpecialTames, returns a new set
    }

    -- The identifier owning the innermost unclosed `(` to the left of `pos`. Scanning for
    -- the enclosing call rather than the token immediately before the field, because the
    -- table is often not the first argument -- `IsLocationSelected(uiMapName, state.x)`.
    local function EnclosingCallee(line, pos)
        local depth = 0
        for i = pos - 1, 1, -1 do
            local c = line:sub(i, i)
            if c == ")" then
                depth = depth + 1
            elseif c == "(" then
                if depth == 0 then
                    return line:sub(1, i - 1):match("([%w_]+)[%s]*$")
                end
                depth = depth - 1
            end
        end
        return nil
    end

    it("never passes a selection table to an unaudited function", function()
        local violations = {}
        for _, path in ipairs(files) do
            if not ALLOWED[path] then
                for n, line in ipairs(CodeLines(ReadFile(path) or "")) do
                    local masked = line:gsub(STRING_RE, '""')
                    for _, field in ipairs(STATE_FIELDS) do
                        local init = 1
                        while true do
                            local s, e = masked:find("state%." .. field .. "%s*[,%)]", init)
                            if not s then break end
                            local callee = EnclosingCallee(masked, s)
                            if not (callee and READ_ONLY_CALLEES[callee]) then
                                violations[#violations + 1] = ("%s:%d  %s"):format(
                                    path, n, line:match("^%s*(.-)%s*$"))
                            end
                            init = e
                        end
                    end
                end
            end
        end
        if #violations > 0 then
            table.sort(violations)
            error(("%d site(s) pass a selection table to an unaudited function:\n  %s\n\n"
                .. "The callee can write it, and the write is invisible to any search for "
                .. "the field name -- which is exactly how SelectAll's three call sites "
                .. "went uncounted. Either pass the slice name and let PSM.Selections do "
                .. "the write, or -- if the callee provably only reads -- add it to "
                .. "READ_ONLY_CALLEES above, which is the audit record.")
                :format(#violations, table.concat(violations, "\n  ")), 0)
        end
        eq(#violations, 0, "tables passed as arguments")
    end)
end)
