local Recount = _G.Recount

local LibDataBroker = LibStub("LibDataBroker-1.1")

-- ---------------------------------------------------------------------------
-- Stat definitions — what can be shown in the Titan Panel button
-- ---------------------------------------------------------------------------
local STATS = {
	{ key = "dps",         label = "DPS" },
	{ key = "damage",      label = "Damage Done" },
	{ key = "hps",         label = "HPS" },
	{ key = "healing",     label = "Healing Done" },
	{ key = "damageTaken", label = "Damage Taken" },
	{ key = "deaths",      label = "Deaths" },
}

-- Dataset display names (keys match Recount.db.profile.CurDataSet values)
local DATASET_LABELS = {
	OverallData      = "Overall",
	LastFightData    = "Last Fight",
	CurrentFightData = "Current Fight",
}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------
local function GetFightData()
	if not Recount.db or not Recount.db2 then return nil end
	local dataset   = Recount.db.profile.CurDataSet or "OverallData"
	local combatant = Recount.db2.combatants and Recount.db2.combatants[Recount.PlayerName]
	return combatant and combatant.Fights and combatant.Fights[dataset]
end

local function GetStatValue(stat, fd)
	if not fd then return "–" end
	if stat == "dps" then
		local t = fd.TimeDamage or 0
		return t > 0 and string.format("%.0f", (fd.Damage or 0) / t) or "0"
	elseif stat == "damage" then
		return Recount.ShortNumber(fd.Damage or 0)
	elseif stat == "hps" then
		local t = fd.TimeHeal or 0
		return t > 0 and string.format("%.0f", (fd.Healing or 0) / t) or "0"
	elseif stat == "healing" then
		return Recount.ShortNumber(fd.Healing or 0)
	elseif stat == "damageTaken" then
		return Recount.ShortNumber(fd.DamageTaken or 0)
	elseif stat == "deaths" then
		return tostring(fd.DeathCount or 0)
	end
	return "–"
end

local function GetStatLabel(key)
	for _, s in ipairs(STATS) do
		if s.key == key then return s.label end
	end
	return key
end

local function GetDisplayText()
	if not Recount.db then return "Recount" end
	local stat = Recount.db.profile.titanPanel.stat
	return GetStatLabel(stat) .. ": " .. GetStatValue(stat, GetFightData())
end

-- ---------------------------------------------------------------------------
-- Right-click configuration dropdown
-- ---------------------------------------------------------------------------
local dropdownFrame = CreateFrame("Frame", "Recount_TitanDropdown", UIParent, "UIDropDownMenuTemplate")

local function BuildDropdown()
	UIDropDownMenu_Initialize(dropdownFrame, function(_, level)
		if level ~= 1 then return end

		-- ── Stat header ──────────────────────────────────────────────────
		local header = UIDropDownMenu_CreateInfo()
		header.text         = "Display Stat"
		header.isTitle      = true
		header.notCheckable = true
		UIDropDownMenu_AddButton(header, level)

		local currentStat = Recount.db.profile.titanPanel.stat
		for _, s in ipairs(STATS) do
			local info    = UIDropDownMenu_CreateInfo()
			info.text     = s.label
			info.checked  = (currentStat == s.key)
			info.keepShownOnClick = false
			local k = s.key
			info.func = function()
				Recount.db.profile.titanPanel.stat = k
				Recount:UpdateTitanPanel()
			end
			UIDropDownMenu_AddButton(info, level)
		end

		-- ── Separator ────────────────────────────────────────────────────
		local sep        = UIDropDownMenu_CreateInfo()
		sep.text         = ""
		sep.disabled     = true
		sep.notCheckable = true
		UIDropDownMenu_AddButton(sep, level)

		-- ── Dataset header ────────────────────────────────────────────────
		local dh         = UIDropDownMenu_CreateInfo()
		dh.text          = "Dataset"
		dh.isTitle       = true
		dh.notCheckable  = true
		UIDropDownMenu_AddButton(dh, level)

		local currentDataset = Recount.db.profile.CurDataSet or "OverallData"
		local datasets = {
			{ key = "OverallData",      label = "Overall" },
			{ key = "LastFightData",    label = "Last Fight" },
			{ key = "CurrentFightData", label = "Current Fight" },
		}
		for _, d in ipairs(datasets) do
			local info    = UIDropDownMenu_CreateInfo()
			info.text     = d.label
			info.checked  = (currentDataset == d.key)
			info.keepShownOnClick = false
			local k = d.key
			info.func = function()
				Recount.db.profile.CurDataSet = k
				Recount:UpdateTitanPanel()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end, "MENU")
end

-- ---------------------------------------------------------------------------
-- LDB data source object  (distinct name from the minimap launcher "Recount")
-- ---------------------------------------------------------------------------
local titanObject = LibDataBroker:NewDataObject("Recount_Stats", {
	type    = "data source",
	text    = "Recount",
	label   = "Recount Stats",
	tocname = "Recount",
	icon    = "Interface\\AddOns\\Recount\\textures\\Recount_MMB_Icon",

	OnClick = function(self, button)
		if button == "LeftButton" then
			if Recount.MainWindow:IsShown() then
				Recount.MainWindow:Hide()
			else
				Recount.MainWindow:Show()
			end
		elseif button == "RightButton" then
			BuildDropdown()
			ToggleDropDownMenu(1, nil, dropdownFrame, self, 0, 0)
		end
	end,

	OnTooltipShow = function(tooltip)
		if not Recount.db then return end
		local stat    = Recount.db.profile.titanPanel.stat
		local dataset = Recount.db.profile.CurDataSet or "OverallData"
		tooltip:AddLine("Recount", 1, 1, 1)
		tooltip:AddDoubleLine(
			"Showing",
			GetStatLabel(stat) .. " (" .. (DATASET_LABELS[dataset] or dataset) .. ")",
			1, 1, 1, 0.8, 0.8, 0.8
		)
		tooltip:AddLine(" ")
		local fd = GetFightData()
		for _, s in ipairs(STATS) do
			tooltip:AddDoubleLine(s.label, GetStatValue(s.key, fd), 1, 1, 1, 0.8, 0.8, 0.8)
		end
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine("Left-Click",  "Toggle window",    1, 1, 1, 0.8, 0.8, 0.8)
		tooltip:AddDoubleLine("Right-Click", "Configure display", 1, 1, 1, 0.8, 0.8, 0.8)
	end,
})

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Push fresh text to the LDB object so Titan Panel (and any other broker
--- display) picks it up immediately.
function Recount:UpdateTitanPanel()
	if titanObject then
		titanObject.text = GetDisplayText()
	end
end

--- Called at the end of OnInitialize once AceDB is ready.
function Recount:InitTitanPanel()
	Recount.db.profile.titanPanel = Recount.db.profile.titanPanel or { stat = "dps" }
	Recount:UpdateTitanPanel()

	-- Refresh the text every second so live DPS/HPS tracks combat.
	C_Timer.NewTicker(1, function()
		Recount:UpdateTitanPanel()
	end)
end
