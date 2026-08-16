-- Tests/spec/publicapi_spec.lua
-- The published surface and its trap, exercised against the real file.
--
-- boundary_spec.lua reads the source and proves nobody *writes* a boundary violation.
-- This runs PublicAPI.lua and proves the boundary *behaves*: that publishing copies what
-- it claims to, that a core internal raises instead of returning nil, and -- the case that
-- makes this addon work at all -- that an absent browser member still reads as plain nil.
--
-- That last one is why the trap is selective rather than a blanket "error on any miss".
-- Under LoadOnDemand the browser is legitimately not there, so every
-- `if PSM.ModelsPanel then` gate in core reads a missing key on purpose. A trap that
-- errored on all misses would break precisely the checks that make the module optional --
-- and it would do it at login, on the minimap button, for every user.

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

local Addon = dofile("Tests/wow/addon.lua")

local PUBLIC_FILE = "PetStableManagement/Shared/PublicAPI.lua"

-- Stand-ins for what core's other files would have attached by the time PublicAPI.lua
-- runs last. Values are identifiable tables so "published" can mean *the same table*,
-- not merely "something truthy" -- a publish loop that wrote `true` would pass the
-- weaker check.
local function CoreNamespace()
    local ns = Addon.namespace()
    for _, name in ipairs({
        "Config", "Data", "PanelManager", "PopUpManager", "RowManager",
        "Skin", "Theme", "Tooltip", "Utils", "Widgets", "state",
    }) do
        ns[name] = { __name = name }
    end
    -- Two core members that are deliberately NOT published, standing in for the ~27 real
    -- ones. Teams is a genuine core module; RotationFrame is the ticker RowManager stores
    -- with `ns[key] = f`, which the browser was reaching into before step 2 gave it
    -- RowManager:ReleaseModel instead.
    ns.Teams = { __name = "Teams" }
    ns.RotationFrame = { activeModels = {} }
    return ns
end

local function LoadPublicAPI()
    _G.PSM = {}
    local ns = CoreNamespace()
    Addon.load(PUBLIC_FILE, ns)
    return ns
end

describe("PublicAPI publishing", function()
    it("puts every declared member on the shared global", function()
        local ns = LoadPublicAPI()
        for _, name in ipairs({
            "Config", "Data", "PanelManager", "PopUpManager", "RowManager",
            "Skin", "Theme", "Tooltip", "Utils", "Widgets", "state",
        }) do
            -- Identity, not truthiness: the browser and core must see one table, so a
            -- copy would be a bug that only shows up as state silently diverging.
            eq(rawget(_G.PSM, name), ns[name], "PSM." .. name .. " is core's own table")
        end
    end)

    it("publishes nothing else", function()
        LoadPublicAPI()
        local extra = {}
        for name in pairs(_G.PSM) do
            if name ~= "Config" and name ~= "Data" and name ~= "PanelManager"
                and name ~= "PopUpManager" and name ~= "RowManager" and name ~= "Skin"
                and name ~= "Theme" and name ~= "Tooltip" and name ~= "Utils"
                and name ~= "Widgets" and name ~= "state" then
                extra[#extra + 1] = name
            end
        end
        table.sort(extra)
        eq(#extra, 0, "unexpected published names (" .. table.concat(extra, ", ") .. ")")
    end)
end)

describe("PublicAPI trap", function()
    -- The regression this exists for. Before 3g these reads worked, because `_G.PSM = ns`
    -- made one table of two names; after it they are nil, and every one of them sits
    -- behind a guard that would swallow the nil.
    it("raises on a core member that was not published", function()
        LoadPublicAPI()
        local ok, err = pcall(function() return _G.PSM.Teams end)
        eq(ok, false, "reading PSM.Teams raises")
        truthy(tostring(err):find("Teams", 1, true), "the error names the key")
        truthy(tostring(err):find("PublicAPI", 1, true), "and points at PublicAPI.lua")
    end)

    it("raises for a member stored with bracket syntax too", function()
        -- RowManager writes `ns[key] = f`. A trap built from a hand-written list would
        -- miss these; building it from `pairs(ns)` covers however a member got there.
        LoadPublicAPI()
        eq(pcall(function() return _G.PSM.RotationFrame end), false,
            "reading PSM.RotationFrame raises")
    end)

    -- The case that must NOT raise, and the reason the trap is selective.
    it("returns nil for a browser member that has not loaded", function()
        LoadPublicAPI()
        local ok, value = pcall(function() return _G.PSM.ModelsPanel end)
        eq(ok, true, "reading an absent browser member does not raise")
        eq(value, nil, "it is simply nil")
    end)

    it("lets the browser attach its own members and read them back", function()
        LoadPublicAPI()
        _G.PSM.ModelsPanel = { __name = "ModelsPanel" }
        local ok, value = pcall(function() return _G.PSM.ModelsPanel end)
        eq(ok, true, "reading it back does not raise")
        eq(value.__name, "ModelsPanel", "and gives what the browser stored")
    end)

    -- Core's `ns.Browser` forwards writes as well as reads, because PanelManager clears
    -- four of the browser's caches by hand. Writing through the trapped global has to keep
    -- working, or those assignments would land nowhere and the caches would stop being
    -- cleared -- silently, since nothing reads them back.
    it("allows writes to pass through to the global", function()
        LoadPublicAPI()
        _G.PSM._modelsRenderCache = { 1, 2, 3 }
        eq(pcall(function() return _G.PSM._modelsRenderCache end), true, "read back")
        _G.PSM._modelsRenderCache = nil
        eq(_G.PSM._modelsRenderCache, nil, "and clearing it gives nil, not an error")
    end)
end)
