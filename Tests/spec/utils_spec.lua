-- Tests/spec/utils_spec.lua
-- Covers the genuinely pure helpers in Shared/Utils.lua.
--
-- Scope note: only the frame-free, API-free functions are here. Debounce (needs
-- C_Timer + PSM.Config), GetSpellNameCompat / HasAnimalCompanionTalent (need the
-- client API) and CreateButtonTooltipOverlay / ShowContextMenu (build frames) are
-- deliberately untested rather than covered by lying stubs -- they become
-- reachable once A3/A6 move the API surface behind Core/Compat.lua.

local T = ...
local describe, it, eq, truthy, isType =
      T.describe, T.it, T.eq, T.truthy, T.isType

dofile("Tests/wow/stubs.lua").install()

_G.PSM = nil  -- Utils.lua self-creates the namespace; prove it rather than assume.
dofile("PetStableManagement/Shared/Utils.lua")
local U = _G.PSM.Utils

describe("Utils namespace", function()
    it("creates PSM and attaches Utils", function()
        isType(_G.PSM, "table", "_G.PSM")
        isType(U, "table", "PSM.Utils")
    end)
end)

describe("Utils.DeepCopy", function()
    it("returns non-tables unchanged", function()
        eq(U.DeepCopy(42), 42, "number")
        eq(U.DeepCopy("hi"), "hi", "string")
        eq(U.DeepCopy(nil), nil, "nil")
        eq(U.DeepCopy(true), true, "boolean")
    end)

    it("copies nested tables by value", function()
        local src  = { a = 1, nested = { b = 2, deep = { c = 3 } }, list = { 1, 2, 3 } }
        local copy = U.DeepCopy(src)
        eq(copy.a, 1, "scalar")
        eq(copy.nested.b, 2, "nested scalar")
        eq(copy.nested.deep.c, 3, "deeply nested scalar")
        eq(#copy.list, 3, "array length")
    end)

    it("produces an independent structure at every level", function()
        local src  = { nested = { deep = { c = 3 } } }
        local copy = U.DeepCopy(src)
        truthy(copy.nested ~= src.nested, "nested table is a distinct object")
        truthy(copy.nested.deep ~= src.nested.deep, "deep table is a distinct object")
        copy.nested.deep.c = 99
        eq(src.nested.deep.c, 3, "mutating the copy must not touch the source")
    end)
end)

describe("Utils:ClearTable", function()
    it("empties in place, preserving identity", function()
        local t = { a = 1, b = 2, 3, 4 }
        local same = t
        U:ClearTable(t)
        eq(next(t), nil, "table is empty")
        truthy(same == t, "same object")
    end)

    it("tolerates non-tables", function()
        U:ClearTable(nil)
        U:ClearTable("not a table")
    end)
end)

describe("Utils:GetTableHash", function()
    it("reports empty for nil and empty tables", function()
        eq(U:GetTableHash(nil), "empty", "nil")
        eq(U:GetTableHash({}), "empty", "empty table")
    end)

    it("is order-independent for the same content", function()
        -- The whole point: pairs() order is undefined, so the hash sorts before
        -- concatenating. Without that, render caches would miss at random.
        local a, b = {}, {}
        a.zebra, a.apple, a.mango = true, true, true
        b.mango, b.apple, b.zebra = true, true, true
        eq(U:GetTableHash(a), U:GetTableHash(b), "same content, different insertion order")
    end)

    it("distinguishes different content", function()
        truthy(U:GetTableHash({ a = true }) ~= U:GetTableHash({ b = true }), "different keys")
        truthy(U:GetTableHash({ a = true }) ~= U:GetTableHash({ a = false }), "different values")
    end)
end)

describe("Utils:GetPetDuplicateKey", function()
    it("keys on displayID when present", function()
        eq(U:GetPetDuplicateKey({ displayID = 97074, icon = "x" }), "d:97074", "displayID key")
    end)

    it("ignores icon differences for the same model", function()
        -- The documented reason this function exists: the stabled-pet list and
        -- C_StableInfo report different icons for the same model, which was making
        -- real duplicates miss each other.
        local a = { displayID = 500, icon = "Interface\\Icons\\A" }
        local b = { displayID = 500, icon = "Interface\\Icons\\B" }
        eq(U:GetPetDuplicateKey(a), U:GetPetDuplicateKey(b), "same model, different icons")
    end)

    it("falls back to icon only when displayID is unusable", function()
        eq(U:GetPetDuplicateKey({ icon = "Icon1" }), "i:Icon1", "no displayID")
        eq(U:GetPetDuplicateKey({ displayID = 0, icon = "Icon1" }), "i:Icon1", "displayID 0")
    end)

    it("does not collide across the two key spaces", function()
        truthy(U:GetPetDuplicateKey({ displayID = 5 }) ~= U:GetPetDuplicateKey({ icon = 5 }),
            "d: and i: namespaces stay distinct")
    end)
end)

describe("Utils:NormalizeSearchText", function()
    it("trims and lowercases", function()
        eq(U:NormalizeSearchText("  Spirit BEAST  "), "spirit beast", "trimmed + lowered")
    end)

    it("returns empty string for non-strings", function()
        eq(U:NormalizeSearchText(nil), "", "nil")
        eq(U:NormalizeSearchText(42), "", "number")
        eq(U:NormalizeSearchText({}), "", "table")
    end)
end)

-- NOTE: SafeStringFormat currently has zero call sites anywhere in the addon.
-- These tests pin its actual behaviour rather than its apparent intent, so that
-- anyone reviving it knows exactly what they are getting.
describe("Utils:SafeStringFormat", function()
    it("formats normally", function()
        eq(U:SafeStringFormat("%s has %d pets", "Hunter", 5), "Hunter has 5 pets", "basic")
    end)

    it("coerces truthy non-string, non-number arguments", function()
        eq(U:SafeStringFormat("%s", true), "true", "boolean true")
        truthy(U:SafeStringFormat("%s", {}):match("^table: "), "table renders via tostring")
    end)

    it("renders boolean false as 'nil' -- known quirk", function()
        -- `tostring(arg ~= nil and arg or "nil")` is the classic Lua and/or ternary
        -- trap: for arg == false the middle term is falsy, so the expression yields
        -- the "nil" string. Distinguishing false from nil needs a real if/else.
        eq(U:SafeStringFormat("%s", false), "nil", "false is indistinguishable from nil here")
    end)

    it("does NOT coerce nil arguments -- known limitation", function()
        -- The implementation writes `tostring(arg ~= nil and arg or "nil")`, so it
        -- clearly means to render nil as "nil". It cannot: `local args = {...}`
        -- collapses trailing nils and `ipairs` halts at the first hole, so the
        -- coercion loop never sees them. string.format then errors on the missing
        -- value and the pcall fallback returns the raw format string.
        -- Fixing it needs select("#", ...) for the true arity plus
        -- unpack(args, 1, n). Not done here: the function is unused, and changing
        -- dead code is a separate decision from building this harness.
        eq(U:SafeStringFormat("%s", nil), "%s", "trailing nil falls back to format string")
        eq(U:SafeStringFormat("%s-%s", nil, "x"), "%s-%s", "leading nil also falls back")
    end)

    it("returns the format string rather than erroring on bad input", function()
        eq(U:SafeStringFormat(nil), "", "nil format")
        eq(U:SafeStringFormat("%d", "not a number"), "%d", "unconvertible argument")
    end)
end)

describe("Utils:FormatColorText", function()
    it("wraps text in a WoW colour escape", function()
        eq(U:FormatColorText("Rare", { 1, 0.82, 0 }), "|cffffd100Rare|r", "gold")
        eq(U:FormatColorText("x", { 0, 0, 0 }), "|cff000000x|r", "black")
    end)

    it("passes text through when colour is missing", function()
        eq(U:FormatColorText("plain", nil), "plain", "no colour")
        eq(U:FormatColorText(nil, { 1, 1, 1 }), "", "no text")
    end)
end)

describe("Utils.SafeCall", function()
    it("returns the function's result", function()
        eq(U.SafeCall(function(a, b) return a + b end, 2, 3), 5, "sum")
    end)

    it("swallows errors and returns nil", function()
        local realPrint = _G.print
        _G.print = function() end  -- SafeCall reports to chat; keep test output clean
        local result = U.SafeCall(function() error("boom") end)
        _G.print = realPrint
        eq(result, nil, "errored call")
    end)

    it("returns nil for non-functions", function()
        eq(U.SafeCall(nil), nil, "nil")
        eq(U.SafeCall("not a function"), nil, "string")
    end)
end)
