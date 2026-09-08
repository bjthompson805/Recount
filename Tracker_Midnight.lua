-- Tracker_Midnight.lua
--
-- Loaded on the Mainline TOC; only ACTIVE on retail Midnight (Interface >=
-- 120000) and newer. Every entry point is gated on WOW_RETAIL_MIDNIGHT, so on
-- pre-12.0 retail (11.x) and every Classic flavour this file is inert and
-- Recount uses its normal COMBAT_LOG_EVENT_UNFILTERED path unchanged.
--
-- Why this exists: patch 12.0 removed addon access to
-- COMBAT_LOG_EVENT_UNFILTERED. The replacement is C_DamageMeter, whose combat
-- values are "secret" while in combat.
--
-- The secret-value rule (verified in-game): you may PASS a secret value
-- straight into a display sink -- FontString:SetText, StatusBar:SetValue /
-- SetMinMaxValues, AbbreviateNumbers -- and it renders live, mid-fight, with no
-- error and no taint. Those sinks are built to accept secrets. What you must
-- NEVER do is OPERATE on a secret in Lua -- arithmetic, comparison, sort,
-- percentage, total -- or route a secret into a SHARED frame (above all
-- GameTooltip). Either of those silently taints the running execution, and the
-- taint then poisons whatever shared resource it next touches, surfacing as an
-- unrelated error elsewhere (e.g. world-map tooltips). pcall does NOT help: it
-- catches the throw but leaves the taint, so it is never used here to "guard" a
-- secret. We simply pass values through and never compute on them.
--
-- So this renderer: reads the current C_DamageMeter session and writes each
-- source's values straight into the existing bar widgets. It does no sorting
-- (the API returns sources pre-ranked -- we can't compare secrets anyway), no
-- totals, no percentages, and no Total bar, and it strips each bar's hover/click
-- handlers so a secret can never reach the shared GameTooltip.
--
-- Field secrecy on DamageMeterCombatSource (from the API docs in F:): name /
-- totalAmount / amountPerSecond and session maxAmount are secret in combat
-- (fine to pass through, never to compute on); classFilename, specIconID,
-- classification, isLocalPlayer, deathRecapID and sourceGUID are NeverSecret.
--
-- Supported modes: Damage Done, DPS, Damage Taken, Healing Done, Absorbs,
-- Deaths. Modes with no C_DamageMeter source (Friendly Fire, Healing Taken,
-- Overhealing, DOT/HOT Uptime, Activity, Threat) render blank.
--
-- The in-game damage meter must be ENABLED (Options > Gameplay Enhancements >
-- Damage Meter) for C_DamageMeter to collect data; we only read its sessions.

local Recount = _G.Recount

Recount.Version = math.max(Recount.Version or 0, tonumber(string.sub("$Revision: 1608 $", 12, -3)) or 0)

local AceLocale = LibStub("AceLocale-3.0")
local L = AceLocale:GetLocale("Recount")

local C_DamageMeter = C_DamageMeter
local Enum = Enum
local AbbreviateNumbers = AbbreviateNumbers
local FauxScrollFrame_Update = FauxScrollFrame_Update
local FauxScrollFrame_GetOffset = FauxScrollFrame_GetOffset
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local pairs = pairs
local type = type
local select = select
local GetBuildInfo = GetBuildInfo

local WOW_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local WOW_RETAIL_MIDNIGHT = WOW_RETAIL and ((select(4, GetBuildInfo()) or 0) >= 120000)

-- Enum.DamageMeterSessionType.Current: the live, in-progress session, read by
-- type (not by a finished session id) so the bars update during the fight.
local function sessionTypeCurrent()
	return Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current
end

local function metricEnum(name)
	return Enum and Enum.DamageMeterType and Enum.DamageMeterType[name]
end

-- Maps a Recount display mode (matched by its English label) to a C_DamageMeter
-- metric. perSec = true means the right-hand text shows per-second throughput
-- (the bar fill still uses the running total so proportions stay stable). Modes
-- absent from this table have no C_DamageMeter source and render blank.
local MODE_METRIC = {
	["Damage Done"]  = { metric = "DamageDone",  perSec = false },
	["DPS"]          = { metric = "DamageDone",  perSec = true },
	["Damage Taken"] = { metric = "DamageTaken", perSec = false },
	["Healing Done"] = { metric = "HealingDone", perSec = false },
	["Absorbs"]      = { metric = "Absorbs",     perSec = false },
	["Deaths"]       = { metric = "Deaths",      perSec = false },
}

-- Resolve the active mode to (metric enum, perSec). Returns nil for unsupported
-- modes so the renderer knows to clear the bars. Operates only on mode labels
-- (never secret).
local function currentMetric()
	local mwd = Recount.MainWindowData
	local mode = Recount.db and Recount.db.profile and Recount.db.profile.MainWindowMode
	if not mwd or not mode or not mwd[mode] then
		return nil
	end
	local label = mwd[mode][1]
	for engLabel, info in pairs(MODE_METRIC) do
		if label == engLabel or label == L[engLabel] then
			local e = metricEnum(info.metric)
			if e ~= nil then
				return e, info.perSec
			end
			return nil
		end
	end
	return nil
end

-- Fetch the current session for a metric. The returned table holds secret
-- fields, but receiving and holding it is fine -- we only ever pass those fields
-- to display sinks, never compute on them. Blizzard's own UI fetches it the
-- same way.
local function readSession(metric)
	if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
		return nil
	end
	local sType = sessionTypeCurrent()
	if sType == nil then
		return nil
	end
	local session = C_DamageMeter.GetCombatSessionFromType(sType, metric)
	if type(session) ~= "table" then
		return nil
	end
	return session
end

-- Colour a bar from classFilename (NeverSecret -> safe to read; a plain class
-- token, never a secret, so indexing the colour table is fine). Reads colours
-- directly rather than through Recount.Colors:GetColor so a non-class token
-- (creature/pet, or "") can't hit GetColor's nil-class crash path. Honours the
-- user's per-class colour overrides when present.
local function colourBar(statusBar, class)
	local r, g, b = 0.5, 0.5, 0.5
	if class and class ~= "" then
		local override
		local colorsClass = Recount.db and Recount.db.profile and Recount.db.profile.Colors
			and Recount.db.profile.Colors.Class
		if colorsClass then
			override = colorsClass[class]
		end
		local c = override
			or (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class])
			or RAID_CLASS_COLORS[class]
		if c then
			r, g, b = c.r, c.g, c.b
		end
	end
	statusBar:SetStatusBarColor(r, g, b, 1)
end

-- Write one combat source into one Recount bar by passing values straight to the
-- display sinks. No value is computed on; nothing reaches GameTooltip.
local function renderRow(row, src, maxAmount, perSec, metric)
	row:Show()

	-- Stash this source's NeverSecret identity (sourceGUID / sourceCreatureID /
	-- classFilename) plus the current metric enum so a click can re-fetch just
	-- this source's spells from C_DamageMeter. name may be secret, but it is only
	-- ever handed to a display sink (the detail window title).
	row.mnGUID = src.sourceGUID
	row.mnCreatureID = src.sourceCreatureID
	row.mnClass = src.classFilename
	row.mnName = src.name
	row.mnMetric = metric

	-- Recount's hover/click handlers (set in CreateRow) read a combatant entry
	-- from the data model. On Midnight there is no model, and a bar tooltip is
	-- exactly where a secret would leak into the shared GameTooltip -- so HOVER
	-- stays stripped. CLICK is safe: it opens the Midnight detail window, which
	-- reads C_DamageMeter itself and gates every operation on issecretvalue (no
	-- secret ever reaches a shared frame). Wire it once.
	if not row.midnightClickable then
		row:SetScript("OnEnter", nil)
		row:SetScript("OnLeave", nil)
		row:SetScript("OnClick", function(self, button)
			if button ~= "RightButton" and Recount.ShowMidnightSpellDetail then
				Recount:ShowMidnightSpellDetail(self.mnMetric, self.mnGUID, self.mnCreatureID, self.mnName)
			end
		end)
		row.midnightClickable = true
	end

	-- classFilename is NeverSecret.
	colourBar(row.StatusBar, src.classFilename)

	-- Pass-through display. name / amount / maxAmount may be secret in combat;
	-- handing them to SetText / SetValue / SetMinMaxValues / AbbreviateNumbers
	-- renders them live without computing on them.
	row.LeftText:SetText(src.name)

	local amount = perSec and src.amountPerSecond or src.totalAmount
	row.RightText:SetText(AbbreviateNumbers(amount))

	row.StatusBar:SetMinMaxValues(0, maxAmount)
	row.StatusBar:SetValue(src.totalAmount)

	-- Bar text colour (plain config, never secret).
	local barText = Recount.db and Recount.db.profile and Recount.db.profile.Colors
		and Recount.db.profile.Colors.Bar and Recount.db.profile.Colors.Bar["Bar Text"]
	if barText then
		row.LeftText:SetTextColor(barText.r, barText.g, barText.b, barText.a)
		row.RightText:SetTextColor(barText.r, barText.g, barText.b, barText.a)
	end

	row.Name = nil
	row.TooltipData = nil
	row.clickData = nil
	row.clickFunc = nil
end

local function renderMainWindow()
	local MainWindow = Recount.MainWindow
	if not MainWindow or not MainWindow:IsShown() then
		return
	end

	local rows = MainWindow.Rows
	if not rows then
		return
	end
	local curRows = MainWindow.CurRows or 0

	-- No Total bar on Midnight: summing secret values is illegal.
	if rows[0] then
		rows[0]:Hide()
	end

	-- Mode data may not be bound yet during early login; bail until it is.
	local modeData = Recount.MainWindowData and Recount.MainWindowData[Recount.db.profile.MainWindowMode]
	if not modeData then
		return
	end

	if type(modeData[6]) == "function" then
		MainWindow.Title:SetText(modeData[6]())
	end

	local metric, perSec = currentMetric()
	local session = metric and readSession(metric)
	local sources = session and session.combatSources

	if type(sources) ~= "table" then
		-- Unsupported mode, meter disabled, or no data yet: clear all bars.
		for i = 1, curRows do
			if rows[i] then rows[i]:Hide() end
		end
		if MainWindow.ScrollBar then
			FauxScrollFrame_Update(MainWindow.ScrollBar, 0, curRows, 20)
		end
		return
	end

	-- #sources is the entry count (a plain number, not a secret) so it is safe
	-- to use for scrollbar maths and row indexing. The API returns sources
	-- pre-ranked, so we render in array order (we cannot sort by a secret value).
	local count = #sources
	local maxAmount = session and session.maxAmount

	FauxScrollFrame_Update(MainWindow.ScrollBar, count, curRows, 20)
	local offset = FauxScrollFrame_GetOffset(MainWindow.ScrollBar) or 0

	local rowWidth = MainWindow:GetWidth() - 4
	if count > curRows and Recount.db.profile.MainWindow.ShowScrollbar == true then
		rowWidth = MainWindow:GetWidth() - 23
	end

	for i = 1, curRows do
		local row = rows[i]
		local src = sources[i + offset]
		if row and type(src) == "table" then
			renderRow(row, src, maxAmount, perSec, metric)
			row:SetWidth(rowWidth)
		elseif row then
			row:Hide()
		end
	end
end

-- Midnight replacement for RefreshMainWindow. Called from the GUI_Main hook (so
-- the periodic refresh drives it) and directly from the DAMAGE_METER events.
--
-- The detail-window tail is OUTSIDE renderMainWindow on purpose. The Classic
-- renderer ends in me:UpdateDetailData() (GUI_Main.lua:1342), but the body above
-- returns early on the emptied-session path -- which is exactly a meter reset, and
-- exactly when a detail window still showing the last fight is most visible. A tail
-- on the last line would be skipped by the one case it exists for.
function Recount:RefreshMainWindow_Midnight()
	if not WOW_RETAIL_MIDNIGHT then
		return
	end

	renderMainWindow()

	if Recount.RefreshMidnightSpellDetail then
		Recount:RefreshMidnightSpellDetail()
	end
end

-- Midnight has no Recount-owned combat data to clear. Every number on screen is
-- read live from the C_DamageMeter session, so ResetDataUnsafe emptying
-- dbCombatants leaves the bars exactly as they were -- which in game is a Yes
-- button that does nothing at all. ResetAllCombatSessions is the only handle on
-- that data; Blizzard's own session-window menu calls it the same way. It takes
-- no arguments and returns nothing, so no secret value is touched.
--
-- Returns true when the session was actually cleared, so the caller can tell a
-- real reset from "this client has no C_DamageMeter".
function Recount:ResetData_Midnight()
	if not WOW_RETAIL_MIDNIGHT then
		return false
	end
	if not (C_DamageMeter and C_DamageMeter.ResetAllCombatSessions) then
		return false
	end

	C_DamageMeter.ResetAllCombatSessions()
	return true
end

-- C_DamageMeter session events. Each just re-renders from the current session;
-- the event args (damageMeterType, sessionId) are not needed because we always
-- read the live Current session for whichever mode is on screen.
--
-- The three are ALIASES rather than three identical bodies, so that the day one of
-- them has to differ, the divergence is written deliberately instead of discovered.
-- Three byte-identical copies also cannot be told apart by any test.
function Recount:DAMAGE_METER_CURRENT_SESSION_UPDATED()
	Recount:RefreshMainWindow_Midnight()
end

Recount.DAMAGE_METER_COMBAT_SESSION_UPDATED = Recount.DAMAGE_METER_CURRENT_SESSION_UPDATED
Recount.DAMAGE_METER_RESET = Recount.DAMAGE_METER_CURRENT_SESSION_UPDATED

-- Called by Recount:RegisterCombatLogEvent (Recount.lua) when WOW_RETAIL_MIDNIGHT
-- is true. Returns true on success, false if the C_DamageMeter API is missing
-- (addon stays loaded, just with no data source -- no Lua error at login).
function Recount:RegisterCombatLogEvent_Midnight()
	if not C_DamageMeter then
		return false
	end
	-- IsDamageMeterAvailable gates whether the in-game meter is collecting. If
	-- the player hasn't enabled it, the session APIs return nothing -- warn, but
	-- still register so enabling it mid-session starts working without /reload.
	if C_DamageMeter.IsDamageMeterAvailable and not C_DamageMeter.IsDamageMeterAvailable() then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cffff8800Recount:|r The in-game damage meter is disabled. " ..
			"Enable it in |cffffffffOptions > Gameplay Enhancements > Damage Meter|r " ..
			"so Recount can read combat data on retail Midnight.")
	end
	Recount.events:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
	Recount.events:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
	Recount.events:RegisterEvent("DAMAGE_METER_RESET")
	return true
end
