-- Tests/spec/schema_spec.lua
-- Proves Schema.lua actually gates a mismatch, and that it agrees with the
-- version the real generated data carries -- the "A1 schema-compat check"
-- ARCHITECTURE_PLAN.md's A4 anticipated.

local T = ...
local describe, it, eq, raises = T.describe, T.it, T.eq, T.raises

local EXPECTED_VERSION = 1
local SCHEMA_PATH = "PetStableManagement_ModelsBrowser/ModelsBrowser/Schema.lua"

describe("Schema.lua", function()
    it("passes silently when the stamp matches", function()
        _G.PSM_DataSchemaVersion = EXPECTED_VERSION
        dofile(SCHEMA_PATH)
    end)

    it("errors when the stamp is missing", function()
        _G.PSM_DataSchemaVersion = nil
        raises(function() dofile(SCHEMA_PATH) end, "missing schema version")
    end)

    it("errors when the stamp doesn't match", function()
        _G.PSM_DataSchemaVersion = EXPECTED_VERSION + 1
        raises(function() dofile(SCHEMA_PATH) end, "schema version mismatch")
    end)

    it("agrees with the version the real generated data carries", function()
        _G.PSM_DataSchemaVersion = nil
        dofile("PetStableManagement_ModelsBrowser/Data/ModelsData.lua")
        eq(_G.PSM_DataSchemaVersion, EXPECTED_VERSION, "PSM_DataSchemaVersion")
        dofile(SCHEMA_PATH)
    end)
end)
