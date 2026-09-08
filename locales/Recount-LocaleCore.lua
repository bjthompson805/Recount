-- Recount locale-system bootstrap.
--
-- Loaded FIRST in the locale block (before the per-language files) and defines
-- ns.NewLocale(code, isDefault, silent), used by EVERY Recount locale file so
-- that every translation stays in memory and can be picked from the "Addon
-- Language" dropdown -- not just the one matching the client. Paired with the
-- load-time override overlay at the top of Recount.lua.
--
-- Why this layer exists: AceLocale-3.0 only keeps the locale table that matches
-- the client's GetLocale() (plus the enUS default). Non-matching locale files
-- exit early via `if not L then return end`, so their strings never reach
-- memory. That is fine for auto-detect, but it blocks a UI-language override --
-- to force Recount into, say, Dutch on an enUS client we need the Dutch strings
-- IN memory, not just on disk. This helper records every L[key] = value into
-- BOTH:
--   * ns.Locales[code]  -- always, so the override path has every locale ready
--   * AceLocale's table  -- only when the locale matches the client / isDefault,
--                           so the normal auto-detect path is unchanged
--
-- Uses the WoW per-addon namespace (the second vararg) rather than the global
-- Recount table, because the locale files load before Recount.lua creates that
-- global.
--
-- Usage in each override-capable locale file:
--   local _, ns = ...
--   local L = ns.NewLocale("nlNL")
--   L["Damage Done"] = "Schade Gedaan"

local _, ns = ...
ns.Locales = ns.Locales or {}

function ns.NewLocale(code, isDefault, silent)
	ns.Locales[code] = ns.Locales[code] or {}
	local store = ns.Locales[code]

	-- Returns the AceLocale-managed table only when this is the current client
	-- locale OR isDefault is true; otherwise nil. silent is forwarded so enUS can
	-- keep its debug/strict-missing flag.
	local AceL = LibStub("AceLocale-3.0"):NewLocale("Recount", code, isDefault, silent)

	-- Proxy: the locale file writes L["key"] = "value" and never reads back, so
	-- only __newindex is needed. Writes land in ns.Locales[code] always, and in
	-- the AceLocale table when AceL is non-nil.
	return setmetatable({}, {
		__newindex = function(_, k, v)
			-- enUS uses AceLocale's `L[key] = true` convention, where the value
			-- IS the key. AceLocale understands `true` natively, but the override
			-- overlay copies ns.Locales values straight onto the live L table --
			-- where `true` is not expanded -- so store the key string itself here.
			store[k] = (v == true) and k or v
			if AceL then
				AceL[k] = v
			end
		end,
	})
end
