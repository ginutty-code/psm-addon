-- Log.lua
-- A ring buffer for errors caught at PSM.Utils.SafeCall's boundary, inspected with
-- /psm debug. Before this, a caught error either vanished (a bare pcall whose result
-- was never checked) or printed once to chat and lost its stack the moment the line
-- scrolled away.

local _, ns = ...

ns.Log = {}

local MAX_ENTRIES = 20
local entries = {}

function ns.Log:Record(message, traceback)
    table.insert(entries, {
        time      = date and date("%H:%M:%S") or "",
        message   = tostring(message),
        traceback = traceback,
    })
    if #entries > MAX_ENTRIES then
        table.remove(entries, 1)
    end
end

function ns.Log:Dump()
    if #entries == 0 then
        ns.Utils:Msg("SUCCESS", ns.L("No errors recorded this session."))
        return
    end
    ns.Utils:Msg("ERROR", ns.L("Last %d error(s), oldest first:", #entries))
    for _, entry in ipairs(entries) do
        print(string.format("|cFFFFAA00[%s]|r %s", entry.time, entry.message))
        if entry.traceback then
            print(entry.traceback)
        end
    end
end

function ns.Log:Clear()
    entries = {}
end
