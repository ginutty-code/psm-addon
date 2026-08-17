-- Tests/spec/renderinputs_spec.lua
-- The Owned Pets render selector's dependency set, enforced against the function it caches.
--
-- `UI:_RenderPanelImmediate` memoises `_CalculateRenderData` on `RENDER_SLICES`, with no
-- timeout behind it. So a state field read by that function and absent from the slice list
-- is **permanent staleness** -- the exact failure the 0.1s expiry used to bound, and the
-- reason the plan said not to remove the expiry until the dependency set was provably
-- complete. "Provably" is this file.
--
-- It also pins the claim that justified deleting ten hand-written `ns._renderCache = nil`
-- calls: view mode, pet groups and collapse state are **not** inputs to the computation.
-- They are read in `_ApplyCachedRender` and `UpdateVisibleRows`, which run on every render
-- whether the selector recomputed or not. If someone moves one of them into
-- `_CalculateRenderData`, those deletions become bugs -- and this fails.

local T = ...
local describe, it, eq = T.describe, T.it, T.eq

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local UI_PATH = "PetStableManagement/Shared/UI.lua"

-- The body of `_CalculateRenderData`, from its signature to the next top-level function.
local function CalculateRenderDataBody(src)
    local from = src:find("function ns%.UI:_CalculateRenderData%(%)")
    if not from then return nil end
    local nextFn = src:find("\nfunction ns%.UI[:.]", from + 1)
    return src:sub(from, nextFn and nextFn - 1 or #src)
end

-- Every `ns.state.<field>` the body touches, comments stripped so prose cannot vote.
local function StateFieldsRead(body)
    local seen, list = {}, {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local code = line:gsub("%-%-.*$", "")
        for field in code:gmatch("ns%.state%.([%w_]+)") do
            if not seen[field] then
                seen[field] = true
                list[#list + 1] = field
            end
        end
    end
    table.sort(list)
    return list
end

-- **The audit record.** Each field maps to the slice that reports it changing; adding a row
-- here is the decision a failure asks for, and it is not done without adding the slice.
local COVERED = {
    stablePets           = "ownedPets",
    selectedSpecs        = "ownedSpecs",
    selectedFamilies     = "ownedFamilies",
    selectedTamers       = "ownedTamers",
    exoticFilter         = "ownedExotic",
    duplicatesOnlyFilter = "ownedDuplicates",
    sortBy               = "ownedSort",
    panel                = "ownedSearch",   -- panel.searchBox
    content              = "panelWidth",    -- content:GetWidth()
}

describe("Owned Pets render inputs", function()
    local src = ReadFile(UI_PATH)

    it("finds the function it is about to audit", function()
        eq(src ~= nil, true, "UI.lua is readable")
        eq(CalculateRenderDataBody(src) ~= nil, true, "_CalculateRenderData located")
    end)

    it("reads no state field the render slices do not cover", function()
        local body = CalculateRenderDataBody(src)
        local uncovered = {}
        for _, field in ipairs(StateFieldsRead(body)) do
            if not COVERED[field] then uncovered[#uncovered + 1] = field end
        end
        if #uncovered > 0 then
            error(("_CalculateRenderData reads %d state field(s) with no slice behind them:"
                .. "\n  ns.state.%s\n\nThe render selector has no expiry, so an unmodelled "
                .. "input is permanent staleness rather than a slow refresh. Declare a slice "
                .. "in State/Store.lua, add it to RENDER_SLICES in UI.lua, and record the "
                .. "mapping in COVERED above.")
                :format(#uncovered, table.concat(uncovered, "\n  ns.state.")), 0)
        end
        eq(#uncovered, 0, "uncovered state reads")
    end)

    -- The specific claim that let ten invalidations go. Stated as its own test rather than
    -- left implicit in the allowlist, because the allowlist explains what is covered and
    -- this explains what must never need covering.
    it("does not read view mode, pet groups or collapse state", function()
        local body = CalculateRenderDataBody(src)
        for _, name in ipairs({ "panelViewMode", "PetGroups", "Collapsed", "groupedView" }) do
            eq(body:find(name, 1, true), nil,
                name .. " is applied per render, not baked into the cached data")
        end
    end)

    it("lists every covered field in RENDER_SLICES", function()
        local declared = src:match("local RENDER_SLICES = {(.-)}")
        eq(declared ~= nil, true, "RENDER_SLICES found")
        for field, slice in pairs(COVERED) do
            eq(declared:find('"' .. slice .. '"', 1, true) ~= nil, true,
                slice .. " (for ns.state." .. field .. ") is in RENDER_SLICES")
        end
    end)
end)
