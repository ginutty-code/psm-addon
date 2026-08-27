-- Tests/wow/addon.lua
-- Load an addon file the way the WoW client loads it.
--
-- The client calls every file listed in a .toc with two arguments: the addon's folder
-- name, and a table private to that addon. A file picks them up with
--
--     local addonName, ns = ...
--
-- `dofile` passes nothing, so under it `...` is empty and both come back nil. That does
-- not matter yet -- core files currently ignore the varargs and hang everything off the
-- `_G.PSM` global -- but it is exactly what A3's `ns` conversion changes, and the moment
-- a converted file is loaded by `dofile` it dies on `ns.Foo = ...` with "attempt to index
-- a nil value" before a single assertion runs.
--
-- So the harness learns the calling convention first, while it is still a no-op. Specs
-- that load addon code go through here; the conversion then needs no test changes beyond
-- reading members off `ns` instead of `_G.PSM`.
--
-- The namespace is per *addon*, not per file: every file of one addon receives the same
-- table. That is the whole reason the two addons here cannot share one, and the reason
-- `_G.PSM` has to survive A3 as the bridge between them.

local A = {}

A.CORE    = "PetStableManagement"
A.BROWSER = "PetStableManagement_ModelsBrowser"

-- A fresh namespace, as the client would hand an addon on login. Specs that want to prove
-- a file builds its own state from nothing should take a new one rather than reusing a
-- namespace another spec has already populated.
--
-- A plain table, with no fallback to `_G.PSM`. It carried one through A3's transition,
-- when the two were the same table anyway; keeping it past 3g would be a lie, because
-- `_G.PSM` is now the cross-addon *bridge* and holds eleven published names rather than
-- core's namespace. A spec needing one file to see another's members loads both into the
-- same namespace -- `A.load(path, ns)` takes one -- which is what the client does too.
function A.namespace()
    return {}
end

-- Load `path`, passing the client's two arguments. Returns the namespace, so a spec can
-- read what the file attached to it:
--
--     local ns = Addon.load("PetStableManagement/Shared/Utils.lua")
--     local U  = ns.Utils            -- after conversion
--     local U  = _G.PSM.Utils        -- before it
--
-- `loadfile` rather than `dofile` because only the former hands back the chunk, and the
-- chunk is what can be called with arguments.
function A.load(path, ns, addonName)
    ns = ns or A.namespace()
    local chunk, err = loadfile(path)
    if not chunk then
        error("could not load " .. path .. ": " .. tostring(err)
              .. "\n(are you running from the psm-addon repo root?)", 0)
    end
    chunk(addonName or A.CORE, ns)
    return ns
end

return A
