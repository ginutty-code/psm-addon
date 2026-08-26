-- Schema.lua
-- Asserts the generated Data/ tables match what this addon was built against.
-- AbilitiesData.lua's own copy of this check lives in core's Shared/DataSchema.lua --
-- see that file for why.

local EXPECTED_SCHEMA_VERSION = 1

local actual = PSM_DataSchemaVersion
if actual == nil then
    error("PSM_Data: Data/ tables carry no schema version -- run psm-data/sync.py to regenerate them")
elseif actual ~= EXPECTED_SCHEMA_VERSION then
    error(("PSM_Data: schema version mismatch (data is v%d, addon expects v%d) -- run psm-data/sync.py to regenerate"):format(actual, EXPECTED_SCHEMA_VERSION))
end
