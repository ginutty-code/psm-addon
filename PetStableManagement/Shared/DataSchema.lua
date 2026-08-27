-- Shared/DataSchema.lua
-- Asserts Data/AbilitiesData.lua matches what this addon was built against.
--
-- Mirrors PetStableManagement_ModelsBrowser/ModelsBrowser/Schema.lua, which does the
-- same check for the four Data/ tables that stay in the Models Browser module.
-- AbilitiesData.lua moved to core's own Data/ so Owned Pets' ability filter has it at
-- login without needing the load-on-demand browser -- which means core needs its own
-- copy of this check too, or a schema mismatch there goes unnoticed until the browser
-- happens to load. Both files' EXPECTED_SCHEMA_VERSION must be bumped together with
-- psm-data's config.SCHEMA_VERSION.

local EXPECTED_SCHEMA_VERSION = 1

local actual = PSM_DataSchemaVersion
if actual == nil then
    error("PSM_Data: Data/AbilitiesData.lua carries no schema version -- run psm-data/sync.py to regenerate it")
elseif actual ~= EXPECTED_SCHEMA_VERSION then
    error(("PSM_Data: schema version mismatch (data is v%d, addon expects v%d) -- run psm-data/sync.py to regenerate"):format(actual, EXPECTED_SCHEMA_VERSION))
end
