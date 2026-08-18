-- Tests/spec/locale_spec.lua
-- The locale lookup, and the net under the retrofit.
--
-- A10 converts ~250 hardcoded strings into L() calls. English-as-key makes a typo'd key
-- render as the typo'd English rather than a blank label, so the failure is visible --
-- but only to whoever happens to open that panel. The last test here makes it visible
-- at build time instead, by proving every L() key in either addon was declared.
--
-- That check is the reason the enUS entries are written out despite being identity
-- mappings: without a declared list, "undeclared key" and "any key at all" are the same
-- thing, and L.missing carries no signal.

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

local Addon = dofile("Tests/wow/addon.lua")

local function freshL()
    return Addon.load("PetStableManagement/Shared/Locale.lua").L
end

describe("locale lookup", function()
    it("returns the registered text for a declared key", function()
        local L = freshL()
        eq(L("Panel failed to show!"), "|cFFFF0000Panel failed to show!|r", "declared key")
    end)

    it("returns the key itself for an undeclared one", function()
        local L = freshL()
        eq(L("No such string anywhere"), "No such string anywhere", "fallback")
    end)

    it("counts undeclared keys in L.missing, and leaves declared ones out", function()
        local L = freshL()
        L("No such string anywhere")
        L("No such string anywhere")
        L("Panel failed to show!")
        eq(L.missing["No such string anywhere"], 2, "counted twice")
        eq(L.missing["Panel failed to show!"], nil, "declared key not recorded")
    end)

    it("applies format arguments only when some are passed", function()
        local L = freshL()
        eq(L("Pet data snapshot created: %d pets saved.", 7),
           "|cFF00FF00Pet data snapshot created: 7 pets saved.|r", "formatted")
        -- Without args the text is returned untouched, so a literal % cannot crash a
        -- caller that never intended a format string.
        eq(L("100% complete"), "100% complete", "unformatted")
    end)
end)

--------------------------------------------------------------------------------
-- Every L() key in the source is declared
--------------------------------------------------------------------------------

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

-- Comments are not call sites. Same reasoning as boundary_spec: a checker that flags the
-- note explaining a string would teach people to delete the explanation.
local function CodeLines(source)
    local stripped = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-%[=%[.-%]=%]", "")
    local lines = {}
    for line in (stripped .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
    end
    return lines
end

local function TocFiles(tocPath, dir)
    local source = ReadFile(tocPath)
    local files = {}
    for line in (source or ""):gmatch("(.-)\n") do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line:match("%.lua$") and not line:match("^#") then
            files[#files + 1] = dir .. line:gsub("\\", "/")
        end
    end
    return files
end

describe("locale keys", function()
    it("declares every key either addon asks for", function()
        local L = freshL()

        local files = TocFiles("PetStableManagement/PetStableManagement.toc",
                               "PetStableManagement/")
        for _, path in ipairs(TocFiles(
                "PetStableManagement_ModelsBrowser/PetStableManagement_ModelsBrowser.toc",
                "PetStableManagement_ModelsBrowser/")) do
            files[#files + 1] = path
        end

        local undeclared, sites = {}, 0
        for _, path in ipairs(files) do
            local source = ReadFile(path)
            for i, line in ipairs(source and CodeLines(source) or {}) do
                for key in line:gmatch('[nsPSM]+%.L%("([^"]*)"') do
                    sites = sites + 1
                    L(key)
                    if L.missing[key] then
                        undeclared[#undeclared + 1] = path .. ":" .. i .. ' -- "' .. key .. '"'
                    end
                end
            end
        end

        truthy(sites > 0, "found no L() call sites at all -- the pattern has gone stale")
        eq(#undeclared, 0, "undeclared L() keys:\n      " .. table.concat(undeclared, "\n      "))
    end)
end)
