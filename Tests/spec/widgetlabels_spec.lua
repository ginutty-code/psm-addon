-- Tests/spec/widgetlabels_spec.lua
-- Which UI-kit factories constrain the text they put on screen, and which deliberately do
-- not.
--
-- **WoW does not clip child regions.** A FontString wider than the frame it is anchored in
-- is simply drawn past it, over whatever sits alongside. `Widgets.Button` has guarded
-- against that since it was written -- an explicit width, no wrapping, and the overshoot
-- recorded in `Widgets.truncatedLabels` because a chopped word looks exactly like a short
-- word. `Widgets.Tab` did not, for as long as it existed, and its labels sit 10px from the
-- next pill's.
--
-- The reason it went unnoticed is worth pinning: a tab is a plain Frame with a separate
-- `.label` font string, while a button owns one reachable through `GetFontString()`. Same
-- defect, different accessors, so nothing connected them. This file is the connection --
-- every factory that draws text has to appear below with an answer.

local T = ...
local describe, it, eq = T.describe, T.it, T.eq

local WIDGETS_PATH = "PetStableManagement/UI/Widgets.lua"

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- Factory name -> body, each running to the next top-level `function`/`local function`.
local function IndexFactories(src)
    local byName, starts = {}, {}
    for pos in src:gmatch("()\nfunction Widgets%.[%w_]+%s*%(") do starts[#starts + 1] = pos + 1 end
    for pos in src:gmatch("()\nlocal function [%w_]+%s*%(")   do starts[#starts + 1] = pos + 1 end
    table.sort(starts)

    for i = 1, #starts do
        local body = src:sub(starts[i], (starts[i + 1] and starts[i + 1] - 1) or #src)
        local name = body:match("^function Widgets%.([%w_]+)")
        if name then byName[name] = body end
    end
    return byName
end

-- Does this factory put text on screen at all? Four ways it can: build one of ours, create a
-- raw font string, drive a template's own via SetText, or reach one through GetFontString.
local function DrawsText(body)
    return body:find("Widgets%.Label%(")
        or body:find("CreateFontString")
        or body:find(":SetText%(")
        or body:find("GetFontString")
end

local function Clamps(body)
    return body:find("Clamp") ~= nil
end

--------------------------------------------------------------------------------
-- The audit record
--------------------------------------------------------------------------------

-- `true`  -- constrains its text, and the test checks a clamp is actually there.
-- string  -- deliberately does not, and this is why. Checked in that direction too, so an
--            exemption cannot quietly acquire a clamp and keep a stale reason.
local TEXT_FACTORIES = {
    Button = true,
    Tab    = true,

    Label = "the primitive itself. It exists so a caller can build a font string with a "
         .. "width, a justification and a wrap setting of their choosing -- clamping it "
         .. "would clamp every other entry here from underneath.",

    CheckBox = "its label is anchored LEFT-of-box-RIGHT, so it lives *outside* the frame "
            .. "by design and the frame's width is not its bound. Call sites that need a "
            .. "limit pass one (the location rows use width = 126).",

    EditBox = "an edit box owns its text region and scrolls it horizontally; it does not "
           .. "draw outside its own frame.",

    Slider = "the three captions are Blizzard's own $parentLow/High/Text from "
          .. "OptionsSliderTemplate, positioned by the template. What we put in them is a "
          .. "formatted value, not a caller-supplied string.",

    -- **A known gap, recorded rather than fixed.** Same defect Tab had: `.label` is a
    -- separate font string with no width. It differs enough to need its own decision --
    -- left-anchored at a caller-controlled `labelInset` rather than centred, so "available
    -- width" is not the same subtraction -- and guessing at that is how Tab's padding would
    -- have truncated labels that fit today. Listed here so it is a decision someone took,
    -- not a thing nobody noticed.
    SectionHeader = "GAP: unclamped. Left-anchored at a caller-controlled labelInset, so it "
                 .. "needs its own padding rule rather than Tab's.",
}

describe("UI kit label clipping", function()
    local src = ReadFile(WIDGETS_PATH)
    local factories = src and IndexFactories(src)

    it("finds the factories it is about to audit", function()
        eq(src ~= nil, true, WIDGETS_PATH .. " is readable")
        eq(factories ~= nil and factories.Tab ~= nil, true, "Widgets.Tab located")
    end)

    -- The direction that catches a *new* widget: anything drawing text has to be accounted
    -- for, either as clamped or as an exemption with a reason.
    it("accounts for every factory that draws text", function()
        local missing = {}
        for name, body in pairs(factories) do
            if DrawsText(body) and TEXT_FACTORIES[name] == nil then
                missing[#missing + 1] = name
            end
        end
        table.sort(missing)
        if #missing > 0 then
            error(("%d factory(ies) draw text with no entry in TEXT_FACTORIES:\n  %s\n\nWoW "
                .. "does not clip child regions, so an unconstrained font string is drawn "
                .. "over whatever sits next to it. Either clamp it and record `true`, or "
                .. "record the reason it does not need clamping.")
                :format(#missing, table.concat(missing, "\n  ")), 0)
        end
        eq(#missing, 0, "unaccounted text factories")
    end)

    it("clamps the ones recorded as clamping", function()
        for name, answer in pairs(TEXT_FACTORIES) do
            if answer == true then
                eq(factories[name] ~= nil, true, name .. " exists")
                eq(Clamps(factories[name]), true, name .. " constrains its label")
            end
        end
    end)

    -- The reverse, so the reasons above cannot go stale. If someone clamps SectionHeader,
    -- this fails and asks for the "GAP" note to be replaced with `true` -- which is the
    -- point: the record is meant to describe the code, not to have described it once.
    it("keeps the exemption reasons honest", function()
        for name, answer in pairs(TEXT_FACTORIES) do
            if type(answer) == "string" and factories[name] then
                eq(Clamps(factories[name]), false,
                    name .. " is recorded as unclamped but now clamps -- update "
                    .. "TEXT_FACTORIES to `true`")
            end
        end
    end)

    -- Tab specifically, because the clamp is only half of it. Giving a centred font string a
    -- width makes justification observable for the first time: while it had none it was
    -- exactly as wide as its text, so a font object defaulting to LEFT looked centred and
    -- would start shifting every short label the moment a width appeared.
    it("centres the tab label explicitly", function()
        eq(factories.Tab:find('justify%s*=%s*"CENTER"') ~= nil, true,
            "Widgets.Tab sets justify explicitly, now that its label has a width")
    end)
end)
