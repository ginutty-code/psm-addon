-- Tests/spec/encoding_spec.lua
-- Every shipped .lua file must be BOM-free.
--
-- This exists because a BOM got committed and nothing noticed. Two files were rewritten by
-- a PowerShell one-liner, and `Set-Content -Encoding utf8` on Windows PowerShell 5.1 emits
-- a UTF-8 BOM. The result shipped.
--
-- What makes it worth a permanent guard is how quietly it passed:
--
--   * luacheck parses a BOM'd file without complaint -- the warning count did not move;
--   * the WoW client loads it too, so the in-game test came back clean;
--   * `git diff` shows nothing, because the change is three bytes before line 1;
--   * but standard Lua 5.1 `loadfile` rejects it outright -- "'=' expected near '<U+FEFF>'"
--     -- so the headless harness cannot load the file at all.
--
-- So the failure is invisible to every check that was running and fatal to the one thing
-- that would have caught it. It was found only because an unrelated injection test
-- happened to rewrite a file the harness loads.
--
-- Scanning bytes rather than trusting the reader: `io.open` in text mode still hands back
-- the BOM as the first three characters, which is exactly what we want to inspect.

local T = ...
local describe, it, eq, truthy = T.describe, T.it, T.eq, T.truthy

local TOCS = {
    { toc = "PetStableManagement/PetStableManagement.toc",
      dir = "PetStableManagement/" },
    { toc = "PetStableManagement_ModelsBrowser/PetStableManagement_ModelsBrowser.toc",
      dir = "PetStableManagement_ModelsBrowser/" },
}

local BOM = string.char(0xEF, 0xBB, 0xBF)

local function ReadFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

-- The .toc is the shipped file list, so a new file is covered the moment it ships rather
-- than whenever someone remembers to add it here.
local function ShippedFiles()
    local files = {}
    for _, source in ipairs(TOCS) do
        local toc = ReadFile(source.toc)
        if toc then
            for line in toc:gmatch("[^\r\n]+") do
                local trimmed = line:match("^%s*(.-)%s*$")
                if trimmed:match("%.lua$") and not trimmed:match("^#") then
                    files[#files + 1] = source.dir .. trimmed:gsub("\\", "/")
                end
            end
        end
    end
    return files
end

describe("shipped file encoding", function()
    local files = ShippedFiles()

    it("finds the shipped files via both .toc files", function()
        -- Guards the guard: an empty list would pass the check below by inspecting nothing.
        truthy(#files > 20, "shipped .lua files listed (got " .. #files .. ")")
    end)

    it("has no UTF-8 BOM in any shipped file", function()
        local offenders = {}
        for _, path in ipairs(files) do
            local text = ReadFile(path)
            if text and text:sub(1, 3) == BOM then
                offenders[#offenders + 1] = path
            end
        end
        table.sort(offenders)
        if #offenders > 0 then
            error(("%d shipped file(s) start with a UTF-8 BOM:\n  %s\n\n"
                .. "Lua 5.1's loadfile rejects it, so the headless harness cannot load "
                .. "them, even though luacheck and the game client both accept it "
                .. "silently. On Windows PowerShell, `Set-Content -Encoding utf8` writes "
                .. "one; use [System.IO.File]::WriteAllText with UTF8Encoding($false), or "
                .. "edit the file with a tool that preserves encoding.")
                :format(#offenders, table.concat(offenders, "\n  ")), 0)
        end
        eq(#offenders, 0, "files with a BOM")
    end)

    it("can be loaded by the Lua that runs this suite", function()
        -- The consequence, asserted directly rather than inferred from the byte check: a
        -- file that will not compile is a file no spec can ever cover.
        local unloadable = {}
        for _, path in ipairs(files) do
            local chunk, err = loadfile(path)
            if not chunk then
                unloadable[#unloadable + 1] = path .. "  (" .. tostring(err) .. ")"
            end
        end
        if #unloadable > 0 then
            table.sort(unloadable)
            error(("%d shipped file(s) do not compile:\n  %s")
                :format(#unloadable, table.concat(unloadable, "\n  ")), 0)
        end
        eq(#unloadable, 0, "files that fail to compile")
    end)
end)
