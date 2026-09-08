-- GUI_Detail_Midnight.lua
--
-- Loaded on the Mainline TOC only; every entry point is gated on
-- WOW_RETAIL_MIDNIGHT (retail, Interface >= 120000). Inert on every other client.
--
-- A Midnight-only spell-breakdown window, modelled on the PieMode half of
-- GUI_Detail.lua's Detail window (top pie + ranked spell list, bottom pie +
-- ranked per-target list) but populated straight from C_DamageMeter instead of
-- Recount's stored data model.
--
-- Why a separate window (learned the hard way, see FEATURE_IMPROVEMENTS.md):
-- Recount's normal Detail/renderer code is saturated with UNGATED arithmetic
-- (sums, sort, percent, string widths). C_DamageMeter's amount fields are secret
-- to a tainted addon, and doing arithmetic on a secret taints the execution and
-- crashes anything downstream. So we cannot feed these values through the normal
-- UI. This window copies the Details! addon's proven approach instead:
--   * read C_DamageMeter on demand (nothing stored into the normal model),
--   * gate EVERY Lua operation on a value with issecretvalue() -- the taint-free
--     "is this a secret?" test -- and simply skip the op when it is secret,
--   * pass raw values to display sinks (SetText / AbbreviateNumbers), which
--     accept secrets and render them without tainting.
-- Out of combat the values are not secret, so the full breakdown (amounts, DPS,
-- percentages, sorting, pie) works. In combat they are secret, so we show a
-- "data is a secret value (available after combat)" placeholder rather than
-- risk any arithmetic.
--
-- Identity keys used to fetch a source are all NeverSecret: sourceGUID,
-- sourceCreatureID, classFilename. spellID on a combatSpell is a plain number,
-- safe to group by. Only the amount fields (totalAmount, amountPerSecond) are
-- secret-when-in-combat.

local Recount = _G.Recount

Recount.Version = math.max(Recount.Version or 0, tonumber(string.sub("$Revision: 1610 $", 12, -3)) or 0)

local Graph = LibStub:GetLibrary("LibGraph-2.0")
local AceLocale = LibStub("AceLocale-3.0")
local L = AceLocale:GetLocale("Recount")

local C_DamageMeter = C_DamageMeter
local C_Spell = C_Spell
local Enum = Enum
local CreateFrame = CreateFrame
local AbbreviateNumbers = AbbreviateNumbers
local UIParent = UIParent
local FauxScrollFrame_GetOffset = FauxScrollFrame_GetOffset
local FauxScrollFrame_Update = FauxScrollFrame_Update
local FauxScrollFrame_OnVerticalScroll = FauxScrollFrame_OnVerticalScroll
local issecretvalue = issecretvalue
local ipairs = ipairs
local type = type
local tsort = table.sort
local tmaxn = table.maxn
local format = string.format
local math_floor = math.floor
local select = select
local GetBuildInfo = GetBuildInfo

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture)

local WOW_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local WOW_RETAIL_MIDNIGHT = WOW_RETAIL and ((select(4, GetBuildInfo()) or 0) >= 120000)

local RowHeight = 14

local me = {}

-- True only for a value we may safely compute on right now (present and not a
-- secret). issecretvalue is taint-free, so asking never taints us.
local function isPlain(v)
	return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- Match the main-window renderer, which reads the live Current session
-- (Tracker_Midnight.lua sessionTypeCurrent), so a bar's breakdown is the same
-- session that bar came from.
local function sessionType()
	return Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current
end

local function spellName(id)
	if id and GetSpellName then
		local n = GetSpellName(id)
		if n then
			return n
		end
	end
	return "spell " .. tostring(id or "?")
end

-- A TOTAL ORDER, and the tiebreak is load-bearing rather than tidiness (audit
-- finding 32). Amount alone leaves two equal spells incomparable -- the
-- comparator answers false both ways -- and Lua 5.1's table.sort is documented
-- as not stable, so tied rows can come back in either order from any call,
-- INCLUDING two calls over identical input.
--
-- That matters more here than in the other two places this fleet has recorded
-- it, where the instability showed up between sessions: RefreshMidnightSpellDetail
-- re-fetches and re-sorts on every damage-meter event while the window is open,
-- so it gets several chances a second in front of a user who is watching. With
-- the selection restored by spellID (finding 31) a reshuffle no longer changes
-- what is selected -- but the rows would still visibly swap places on a tick
-- where nothing happened, which is a change with no cause the user can observe.
--
-- Ties are ordinary rather than exotic: amounts are summed integers and the
-- crowded case is the start of a fight, with several spells landed once each.
-- spellID is a genuine tiebreak because it is unique per group by construction
-- (the grouping at :128 and :139 is keyed on it); `or 0` covers the ungrouped
-- row a nil spellID produces.
local function sortByAmount(a, b)
	local aAmount, bAmount = a.amount or 0, b.amount or 0
	if aAmount ~= bAmount then
		return aAmount > bAmount
	end
	return (a.spellID or 0) < (b.spellID or 0)
end

-- Fetch and shape one source's spells from C_DamageMeter. Returns:
--   rows  = { {spellID, name, icon, amount, dps, percent, targets={...}}, ... }
--   secret = true if at least one spell's amount was secret (so we skipped it)
-- Groups combatSpells by spellID (a plain number); sums only PLAIN amounts, so
-- no arithmetic ever touches a secret. Percent is computed only when the group
-- total is plain and > 0.
-- WHICH ENEMIES THIS SOURCE DAMAGED, KEYED BY SPELL -- and the reason it is a
-- second query rather than a field on the first.
--
-- The damage-done tree has no target axis: under `DamageDone` a spell's
-- `combatSpellDetails` is the default-initialised struct (`unitName = ""`,
-- `amount = 0`), which is why the lower pane rendered a nameless row at 0.
-- Details' own no-CLEU parser does not even read it there -- the reads are
-- commented out at Details/core/parser_nocleu1.lua:1251-1252.
--
-- THE TARGET AXIS LIVES IN A DIFFERENT METRIC, INVERTED. `EnemyDamageTaken`
-- (`Enum.DamageMeterType.EnemyDamageTaken` = 10, DamageMeterConstantsDocumentation
-- .lua:112) lists each ENEMY as a combat source; under each, `combatSpells` are
-- the spells that hit it, and each spell's `combatSpellDetails.unitName` is the
-- PLAYER who dealt it. So "which mobs did I hit" is that table read backwards:
-- walk the enemies, keep the spells whose unitName is us, and the enemy is the
-- target. Details does exactly this inversion at parser_nocleu1.lua:1322-1325.
--
-- MATCHING IS BY NAME AND THAT IS THE LIMIT OF IT. `combatSpellDetails` carries
-- no GUID -- only unitName, unitClassFilename, classification, isPet, isMob,
-- amount, specIconID -- so the only way to attribute a spell to this source is a
-- string compare, and a compare is an OPERATION. When either side is secret we
-- cannot do it, so this returns nothing and the caller keeps whatever the
-- damage-done tree gave. That is an in-combat gap, not a bug to route around.
-- Returns TWO views of the same walk:
--   bySpell[spellID] = { {name, amount}, ... }   per-spell, when the id is usable
--   all              = { {name, amount}, ... }   one row per enemy, summed
--
-- BOTH ARE BUILT BECAUSE THE ENEMY SIDE'S `spellID` IS NOT ALWAYS A SPELL.
-- Measured in a live client 2026-08-25: the one entry under a Juvenile Swiftclaw
-- came back `spellID = 0` with `unitName = "Brickhouse"`. Zero is either melee
-- auto-attack or a per-dealer aggregate -- and the caller cannot tell which, so
-- keying only by spellID silently matched nothing for every real spell, which is
-- exactly the bug this pair replaces.
--
-- `all` is correct under either reading: it is "the enemies this source damaged,
-- and for how much", which is what the Classic pane's "Damaged Who" view shows.
-- The caller prefers `bySpell` when it has the selected id and falls back to
-- `all`, so a usable id gives the precise answer and an unusable one still gives
-- a true one.
local function fetchTargetsBySpell(sourceName)
	local out = {}
	local all = {}
	local allByName = {}
	local enemyMetric = Enum and Enum.DamageMeterType and Enum.DamageMeterType.EnemyDamageTaken
	local sType = sessionType()
	if enemyMetric == nil or sType == nil or not isPlain(sourceName) then
		return out, all
	end
	if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
		and C_DamageMeter.GetCombatSessionSourceFromType) then
		return out, all
	end

	local session = C_DamageMeter.GetCombatSessionFromType(sType, enemyMetric)
	local enemies = session and session.combatSources
	if type(enemies) ~= "table" then
		return out, all
	end

	for i = 1, #enemies do
		local enemy = enemies[i]
		-- The enemy's own name is ConditionalSecret; it is only ever handed to
		-- SetText, never compared or used as a key, so it is kept raw.
		local enemySource = C_DamageMeter.GetCombatSessionSourceFromType(
			sType, enemyMetric, enemy.sourceGUID, enemy.sourceCreatureID)
		local spells = enemySource and enemySource.combatSpells
		if type(spells) == "table" then
			for j = 1, #spells do
				local sp = spells[j]
				local d = sp.combatSpellDetails
				if type(d) == "table" and isPlain(d.unitName) and d.unitName == sourceName then
					local id = sp.spellID
					local list = out[id]
					if not list then
						list = {}
						out[id] = list
					end
					-- THE FIGURE COMES FROM THE SPELL ENTRY, NOT FROM
					-- combatSpellDetails. Measured in a live client 2026-08-25:
					-- `combatSpellDetails.amount` is 0 on the enemy side exactly as
					-- it is on the damage-done side, which is why the row first
					-- appeared correctly NAMED and reading "0 / 0.0%".
					-- `totalAmount` on the enemy-side spell entry is the real
					-- number -- how much this dealer's spell did to this enemy --
					-- and it is what makes this pane reconcile with the Damage
					-- Taken view of the same fight. `d.amount` is kept only as a
					-- fallback for a client that does populate it.
					local amt = sp.totalAmount
					local plain = isPlain(amt) and amt or nil
					if plain == nil and isPlain(d.amount) then
						amt = d.amount
						plain = amt
					end
					list[#list + 1] = {
						name = enemy.name,
						amount = plain,
						rawAmount = amt,
					}

					-- Aggregate view. Keyed on the enemy's name only when that name
					-- is PLAIN -- using a secret as a table key is an operation, so
					-- a secret-named enemy gets its own row instead of being merged.
					-- Over-listing is the safe direction; merging two enemies under
					-- one name would invent a number.
					local eName = enemy.name
					local slot = isPlain(eName) and allByName[eName] or nil
					if slot then
						if plain and slot.amount then
							slot.amount = slot.amount + plain
						elseif plain then
							slot.amount = plain
						end
					else
						slot = { name = eName, amount = plain, rawAmount = amt }
						all[#all + 1] = slot
						if isPlain(eName) then
							allByName[eName] = slot
						end
					end
				end
			end
		end
	end

	return out, all
end

local function fetchSpellRows(metric, sourceGUID, sourceCreatureID, sourceName)
	if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then
		return {}, false
	end
	local sType = sessionType()
	if sType == nil or metric == nil then
		return {}, false
	end

	local source = C_DamageMeter.GetCombatSessionSourceFromType(sType, metric, sourceGUID, sourceCreatureID)
	local spells = source and source.combatSpells
	if type(spells) ~= "table" then
		return {}, false
	end

	local groupsById = {}
	local rows = {}
	local total = 0
	local sawSecret = false
	local targetsBySpell, targetsAll = fetchTargetsBySpell(sourceName)

	for i = 1, #spells do
		local sp = spells[i]
		local id = sp.spellID
		local amt = sp.totalAmount
		if not isPlain(amt) then
			sawSecret = true
		else
			local group = id and groupsById[id]
			if not group then
				group = {
					spellID = id,
					name = spellName(id),
					icon = (id and GetSpellTexture and GetSpellTexture(id)) or nil,
					amount = 0,
					dps = 0,
					targets = {},
				}
				if id then
					groupsById[id] = group
				end
				rows[#rows + 1] = group
			end

			group.amount = group.amount + amt
			total = total + amt

			local ps = sp.amountPerSecond
			if isPlain(ps) then
				group.dps = group.dps + ps
			end

			-- Per-target child. `combatSpellDetails` is ONE struct per spell
			-- (`DamageMeterCombatSpellUnitDetails`, singular), not a list; its
			-- `unitName` may be secret, so it is stored raw for passthrough display
			-- and never computed on. Its amount is gated like the parent.
			--
			-- DO NOT DROP A TARGET WHOSE NAME IS EMPTY. That was tried on
			-- 2026-08-25 and it was WRONG: the row carries a real amount and a real
			-- pie wedge, and skipping it emptied the whole lower pane in a client
			-- where it had been working. The empty name is a display gap in ONE
			-- field, not evidence that there is no target.
			local details = sp.combatSpellDetails
			if type(details) == "table" then
				local tAmt = details.amount
				group.targets[#group.targets + 1] = {
					name = details.unitName,
					amount = isPlain(tAmt) and tAmt or nil,
					rawAmount = tAmt,
				}
			end

		end
	end

	-- ONCE PER GROUP, AFTER THE LOOP -- NOT INSIDE IT. Doing this per spell entry
	-- was wrong twice over: a second entry for the same spellID appended its
	-- damage-done target onto the already-substituted list, and because the
	-- aggregate table is SHARED between groups, that append mutated it for every
	-- other spell too. Caught by the "sums repeats of one enemy" spec, which saw
	-- "Add" arrive in a list that should only have held one enemy.
	--
	-- The enemy-side list REPLACES the damage-done one, never merges with it --
	-- both describe the same hits, so appending would double them.
	--
	-- Per-spell first, aggregate second. The enemy side's spellID was measured as
	-- 0 in a live client, which matches nothing the upper pane can select, so
	-- keying only by spellID left this empty for every real spell. The aggregate
	-- is the honest answer then: it is the enemies this source damaged, which is
	-- what the pane is headed "Player/Mob Name" for. It is never a wrong NAME --
	-- at worst it is broader than the selected spell.
	for i = 1, #rows do
		local group = rows[i]
		local better = group.spellID and targetsBySpell[group.spellID]
		if not (better and #better > 0) then
			better = targetsAll
		end
		if better and #better > 0 then
			group.targets = better
		end
	end

	for i = 1, #rows do
		local r = rows[i]
		r.percent = (total > 0) and (100 * r.amount / total) or 0

		-- TARGET PERCENTAGES ARE RELATIVE TO THE TARGET LIST'S OWN TOTAL, not to
		-- the spell's. This used to divide by `r.amount`, which was right only
		-- while the list was that one spell's targets. It can now be the aggregate
		-- -- every enemy this source damaged, across all its spells -- and against
		-- one spell's total that is not a percentage of anything: it reads past
		-- 100% as soon as the source hit more than one enemy with more than one
		-- spell. Summing the list is also the only figure the column can honestly
		-- be a share OF.
		local tTotal = 0
		for j = 1, #r.targets do
			local t = r.targets[j]
			if t.amount then
				tTotal = tTotal + t.amount
			end
		end
		if tTotal > 0 then
			for j = 1, #r.targets do
				local t = r.targets[j]
				if t.amount then
					t.percent = 100 * t.amount / tTotal
				end
			end
		end
	end

	tsort(rows, sortByAmount)
	return rows, sawSecret
end

--=============================================================================
-- Fill / refresh
--=============================================================================

function me:FillUpper(rows, sawSecret)
	local win = Recount.MidnightDetailWindow
	win.UpperTable = rows or {}
	win.UpperSawSecret = sawSecret
	win.Selected = win.Selected or 1

	local pie = win.TopPie
	pie:ResetPie()

	local n = #win.UpperTable
	for k, v in ipairs(win.UpperTable) do
		local pct = v.percent or 0
		if k ~= n then
			v.color = pie:AddPie(pct)
		else
			v.color = pie:CompletePie()
		end
	end

	me:RefreshUpper()
	-- Auto-select the top spell so the lower (per-target) pane is populated.
	if n > 0 then
		me:SelectUpperIndex(1)
	else
		me:FillLower(nil)
	end
end

function me:RefreshUpper()
	local win = Recount.MidnightDetailWindow
	local UpperTable = win.UpperTable or {}

	if win.NoData then
		win.NoData:SetShown(#UpperTable == 0)
		if #UpperTable == 0 then
			win.NoData:SetText(win.UpperSawSecret
				and L["Data is a secret value (available after combat)."]
				or L["No data available."])
		end
	end

	FauxScrollFrame_Update(win.ScrollBar1, tmaxn(UpperTable), 8, RowHeight)
	local offset = FauxScrollFrame_GetOffset(win.ScrollBar1)

	for i = 1, 8 do
		local entry = UpperTable[i + offset]
		local row = win.TopRows[i]
		if entry then
			local c = entry.color or {0.5, 0.5, 0.5}
			row.Key:SetVertexColor(c[1], c[2], c[3], 1.0)
			row.Background:SetVertexColor((c[1] + 0.5) / 2, (c[2] + 0.5) / 2, (c[3] + 0.5) / 2, 0.3)
			row.Background:SetShown(win.Selected == (i + offset))
			row.Count:SetText(i + offset)
			row.Name:SetText(entry.name)
			-- ROUNDED BEFORE ABBREVIATING. AbbreviateNumbers only abbreviates at
			-- 1000 and above; below that it hands the value straight back, so a
			-- fractional rate printed every digit it had --
			-- "161.82124328613" sitting directly under "5.2K" in the same column,
			-- reported from a live client 2026-08-25. Rounding is safe here
			-- because `dps` is only ever summed from PLAIN values in
			-- fetchSpellRows, so this arithmetic cannot reach a secret; the
			-- isPlain check is belt for a future caller that forgets that.
			local dps = entry.dps or 0
			row.DPS:SetText(AbbreviateNumbers(isPlain(dps) and math_floor(dps + 0.5) or dps))
			row.Amount:SetText(AbbreviateNumbers(entry.amount or 0))
			row.Percent:SetText(format("%.1f%%", entry.percent or 0))
			row:Show()
		else
			row:Hide()
		end
	end
end

-- index is absolute (into the full, unscrolled UpperTable). Row hover converts
-- its visible id with the scroll offset; the pie already passes an absolute slice.
function me:SelectUpperIndex(index)
	local win = Recount.MidnightDetailWindow
	local UpperTable = win.UpperTable or {}
	if not UpperTable[index] then
		return
	end
	win.Selected = index
	me:RefreshUpper()
	me:FillLower(UpperTable[index])
end

function me:FillLower(spellRow)
	local win = Recount.MidnightDetailWindow
	local targets = spellRow and spellRow.targets or {}

	-- Only targets with a plain amount can be ranked; leave the rest for the pie
	-- skip and display them last (unsorted) via passthrough.
	local ranked = {}
	for i = 1, #targets do
		ranked[#ranked + 1] = targets[i]
	end
	tsort(ranked, sortByAmount)
	win.LowerTable = ranked

	local pie = win.BotPie
	pie:ResetPie()
	local n = #ranked
	for k, v in ipairs(ranked) do
		local pct = v.percent or 0
		if k ~= n then
			v.color = pie:AddPie(pct)
		else
			v.color = pie:CompletePie()
		end
	end

	FauxScrollFrame_Update(win.ScrollBar2, tmaxn(ranked), 8, RowHeight)
	local offset = FauxScrollFrame_GetOffset(win.ScrollBar2)

	for i = 1, 8 do
		local entry = ranked[i + offset]
		local row = win.BotRows[i]
		if entry then
			local c = entry.color or {0.5, 0.5, 0.5}
			row.Key:SetVertexColor(c[1], c[2], c[3], 1.0)
			row.Background:SetVertexColor((c[1] + 0.5) / 2, (c[2] + 0.5) / 2, (c[3] + 0.5) / 2, 0.3)
			row.Count:SetText(i + offset)
			row.Name:SetText(entry.name)
			-- amount may be a plain number (AbbreviateNumbers) or, if secret,
			-- passed straight through the display sink.
			row.Amount:SetText(AbbreviateNumbers(entry.amount ~= nil and entry.amount or entry.rawAmount or 0))
			row.Percent:SetText(entry.percent and format("%.1f%%", entry.percent) or "")
			row:Show()
		else
			row:Hide()
		end
	end
end

--=============================================================================
-- Public entry point (called from the Midnight main-window bar click)
--=============================================================================

-- metric: Enum.DamageMeterType for the current mode. guid / creatureID: NeverSecret
-- identity. name: may be secret (passed straight to the title display sink only).
function Recount:ShowMidnightSpellDetail(metric, sourceGUID, sourceCreatureID, name)
	if not WOW_RETAIL_MIDNIGHT then
		return
	end
	if not Recount.MidnightDetailWindow then
		Recount:CreateMidnightDetailWindow()
	end

	local rows, sawSecret = fetchSpellRows(metric, sourceGUID, sourceCreatureID, name)

	-- Title: pass the (possibly secret) name straight to SetText -- a display sink.
	Recount.MidnightDetailWindow.Title:SetText(name)
	Recount.MidnightDetailWindow.Selected = 1
	-- Keep the fetch key so the window can be re-driven from live data later. The
	-- three identity fields are NeverSecret, so storing them computes on nothing.
	-- `name` is stored too, for the enemy-side target lookup on refresh; it may be
	-- secret, and storing a value is not an operation on it.
	Recount.MidnightDetailWindow.Source = {
		metric = metric,
		guid = sourceGUID,
		creatureID = sourceCreatureID,
		name = name,
	}
	me:FillUpper(rows, sawSecret)

	Recount.MidnightDetailWindow:Show()
	Recount:SetWindowTop(Recount.MidnightDetailWindow)
end

-- Re-drive an open detail window from live data. This is the Midnight equivalent
-- of me:UpdateDetailData (GUI_Main.lua:977-991), which the Classic renderer calls
-- as its last act at GUI_Main.lua:1342 -- a line the Midnight branch never reaches,
-- because it returns at GUI_Main.lua:1134. Without this, everything below
-- ShowMidnightSpellDetail is a re-RENDERER of the rows captured at click time:
-- FillUpper takes rows passed in, and RefreshUpper / SelectUpperIndex / FillLower
-- all read win.UpperTable. Scrolling, re-sorting and row clicks therefore re-render
-- the same frozen snapshot, so a fight could end -- emptying the main window -- with
-- this one still listing the dead fight's spells.
--
-- The metric is the one the window was opened with, deliberately: it is what the
-- title describes. Changing the main window's mode with this open leaves it showing
-- its own metric, refreshed, rather than silently switching what it is counting.
function Recount:RefreshMidnightSpellDetail()
	if not WOW_RETAIL_MIDNIGHT then
		return
	end

	local win = Recount.MidnightDetailWindow
	if not win or not win:IsVisible() then
		return
	end

	local src = win.Source
	if not src then
		return
	end

	-- RESTORE BY SPELL, NOT BY ROW NUMBER (audit finding 31). win.Selected is an
	-- absolute index into win.UpperTable, and UpperTable is ranked by amount --
	-- so the number identifies a POSITION IN A RANKING, and the ranking is the
	-- thing a refresh exists to update. Re-selecting the same index put the
	-- highlight on whatever had risen into that slot: the row under the cursor
	-- did not move (RefreshUpper draws the highlight on win.Selected == i +
	-- offset), while the per-target pane below it silently changed to another
	-- spell's targets. The user then reads one spell's name against another
	-- spell's breakdown.
	--
	-- spellID is the identity to key on and it is already in the row: the
	-- grouping is built on it, and it is a plain number by construction, never a
	-- secret. This is the same correction the refresh wrapper makes one level up
	-- -- re-derive from a stored identity rather than from a remembered position.
	--
	-- Both reads happen BEFORE FillUpper, which is required, not incidental:
	-- FillUpper overwrites win.UpperTable and then calls SelectUpperIndex(1),
	-- so afterwards neither the old table nor the old selection still exists.
	local selected = win.Selected or 1
	local selectedSpellID = win.UpperTable and win.UpperTable[selected]
		and win.UpperTable[selected].spellID

	local rows, sawSecret = fetchSpellRows(src.metric, src.guid, src.creatureID, src.name)
	me:FillUpper(rows, sawSecret)

	-- A spell that has dropped out of the list entirely keeps FillUpper's top-row
	-- selection, which is the same fallback the old index clamp gave and the only
	-- honest one: there is no longer a row to return to.
	if selectedSpellID then
		for i = 1, #rows do
			if rows[i].spellID == selectedSpellID then
				me:SelectUpperIndex(i)
				break
			end
		end
	end
end

--=============================================================================
-- Window construction (copied/adapted from GUI_Detail.lua CreateDetailWindow)
--=============================================================================

local function createColumnLabels(parent, yOff, cols)
	local labels = CreateFrame("Frame", nil, parent)
	labels:SetPoint("TOPLEFT", parent, "TOP", -70 - 25, yOff)
	labels:SetWidth(270 + 50)
	labels:SetHeight(RowHeight)
	for _, col in ipairs(cols) do
		local fs = labels:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint(col.point, labels, col.point, col.x, 0)
		fs:SetText(col.text)
		Recount:AddFontString(fs)
	end
	return labels
end

function Recount:CreateMidnightDetailWindow()
	local theFrame = CreateFrame("Frame", "Recount_MidnightDetailWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	Recount.MidnightDetailWindow = theFrame

	theFrame:ClearAllPoints()
	theFrame:SetPoint("CENTER", UIParent, "CENTER")
	theFrame:SetHeight(320 + 26)
	theFrame:SetWidth(450 + 50 + 60)
	theFrame:SetFrameLevel(Recount.MainWindow:GetFrameLevel() + 10)

	theFrame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
		edgeFile = "Interface\\AddOns\\Recount\\textures\\otravi-semi-full-border", edgeSize = 32,
		insets = {left = 1, right = 1, top = 20, bottom = 1},
	})
	theFrame:SetBackdropBorderColor(1.0, 0.0, 0.0)
	theFrame:SetBackdropColor(24 / 255, 24 / 255, 24 / 255)
	Recount.Colors:RegisterBorder("Other Windows", "Title", theFrame)
	Recount.Colors:RegisterBackground("Other Windows", "Background", theFrame)

	theFrame:EnableMouse(true)
	theFrame:SetMovable(true)
	theFrame:SetScript("OnMouseDown", function(this, button)
		if ((not this.isLocked) or (this.isLocked == 0)) and (button == "LeftButton") then
			Recount:SetWindowTop(this)
			this:StartMoving()
			this.isMoving = true
		end
	end)
	theFrame:SetScript("OnMouseUp", function(this)
		if this.isMoving then
			this:StopMovingOrSizing()
			this.isMoving = false
		end
	end)
	theFrame:SetScript("OnShow", function(this)
		Recount:SetWindowTop(this)
	end)
	theFrame:SetScript("OnHide", function(this)
		if this.isMoving then
			this:StopMovingOrSizing()
			this.isMoving = false
		end
	end)

	theFrame.Title = theFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	theFrame.Title:SetPoint("TOPLEFT", theFrame, "TOPLEFT", 6, -15)
	theFrame.Title:SetTextColor(1.0, 1.0, 1.0, 1.0)
	theFrame.Title:SetText(L["Detail Window"])
	Recount:AddFontString(theFrame.Title)
	Recount.Colors:RegisterFont("Other Windows", "Title Text", theFrame.Title)

	theFrame.CloseButton = CreateFrame("Button", nil, theFrame)
	theFrame.CloseButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	theFrame.CloseButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	theFrame.CloseButton:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	theFrame.CloseButton:SetWidth(20)
	theFrame.CloseButton:SetHeight(20)
	theFrame.CloseButton:SetPoint("TOPRIGHT", theFrame, "TOPRIGHT", -4, -12)
	theFrame.CloseButton:SetScript("OnClick", function(this)
		this:GetParent():Hide()
	end)

	-- EVERY PIECE OF CONTENT BELOW HANGS OFF `Content`, NOT OFF `theFrame`, AND
	-- THAT IS THE WHOLE POINT OF THIS FRAME. It is 32px shorter than the window
	-- and bottom-anchored, so its top edge sits exactly below the title strip
	-- (`insets.top = 20` on the backdrop, plus the title's own margin).
	--
	-- This is `PieMode` in the file this window was ported from
	-- (GUI_Detail.lua:1672-1678, same height and width expressions). The port
	-- dropped the container and re-anchored everything to `theFrame` while
	-- keeping the offsets, which are all measured FROM THE CONTAINER -- so the
	-- entire content block rendered 32px too high: the column headers came out
	-- above the window's top border, overlapping the title bar and the close
	-- button, and the rows and pies went up with them. Reported from a live
	-- client 2026-08-25 as "the column header text is outside the window
	-- borders".
	--
	-- So do not anchor anything here to `theFrame` "because it is the window" --
	-- the 32px is not decoration, it is the strip the title lives in.
	theFrame.Content = CreateFrame("Frame", nil, theFrame)
	local Content = theFrame.Content
	Content:ClearAllPoints()
	Content:SetPoint("BOTTOM", theFrame)
	Content:SetHeight(320 - 32 + 26)
	Content:SetWidth(450 + 50 + 60)

	-- Top pie + spell list
	theFrame.TopPie = Graph:CreateGraphPieChart("Recount_MidnightDetail_TopPie", Content, "LEFT", "LEFT", 0, 72.5, 150, 150)
	theFrame.BotPie = Graph:CreateGraphPieChart("Recount_MidnightDetail_BotPie", Content, "LEFT", "LEFT", 0, -72.5, 150, 150)
	theFrame.TopPie:SetSelectionFunc(function(num) me:SelectUpperIndex(num) end)

	theFrame.TopRowLabels = createColumnLabels(Content, -1, {
		{point = "LEFT",  x = 16,       text = "#"},
		{point = "LEFT",  x = 30,       text = L["Name of Ability"]},
		{point = "RIGHT", x = -50 + 30, text = L["Damage"]},
		{point = "RIGHT", x = -120 + 20, text = L["DPS"]},
		{point = "RIGHT", x = 4 + 30,   text = "%"},
	})

	theFrame.TopRows = {}
	for i = 1, 8 do
		local Row = CreateFrame("Frame", nil, Content)
		Row.id = i
		Row:EnableMouse(true)
		Row:SetScript("OnEnter", function(this)
			local w = Recount.MidnightDetailWindow
			me:SelectUpperIndex(this.id + (FauxScrollFrame_GetOffset(w.ScrollBar1) or 0))
		end)
		Row:SetWidth(270 + 50 + 30)
		Row:SetHeight(RowHeight)
		Row:SetPoint("TOPLEFT", Content, "TOP", -70 - 25, -(RowHeight + 2) * i)

		Row.Background = Row:CreateTexture(nil, "BACKGROUND")
		Row.Background:SetAllPoints(Row)
		Row.Background:SetTexture("Interface\\Buttons\\WHITE8X8.blp")
		Row.Background:Hide()

		Row.Key = Row:CreateTexture(nil, "OVERLAY")
		Row.Key:SetPoint("LEFT", Row, "LEFT", 0, 0)
		Row.Key:SetTexture("Interface\\Buttons\\WHITE8X8.blp")
		Row.Key:SetWidth(RowHeight)
		Row.Key:SetHeight(RowHeight)

		Row.Count = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.Count:SetPoint("LEFT", Row.Key, "LEFT", 16, 0)
		Row.Count:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.Count)

		Row.Name = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.Name:SetPoint("LEFT", Row, "LEFT", 30, 0)
		Row.Name:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.Name)

		Row.DPS = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.DPS:SetPoint("RIGHT", Row, "RIGHT", -120 - 10, 0)
		Row.DPS:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.DPS)

		Row.Amount = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.Amount:SetPoint("RIGHT", Row, "RIGHT", -50, 0)
		Row.Amount:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.Amount)

		Row.Percent = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.Percent:SetPoint("RIGHT", Row, "RIGHT", 4, 0)
		Row.Percent:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.Percent)

		theFrame.TopRows[i] = Row
	end

	theFrame.ScrollBar1 = CreateFrame("ScrollFrame", "Recount_MidnightDetail_ScrollBar1", Content, "FauxScrollFrameTemplate")
	-- `scrollFrame`, not `self`: the enclosing function already has a `self` and
	-- this one is the scroll frame, not the window.
	theFrame.ScrollBar1:SetScript("OnVerticalScroll", function(scrollFrame, offset)
		FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, RowHeight, function() me:RefreshUpper() end)
	end)
	theFrame.ScrollBar1:SetPoint("TOPLEFT", theFrame.TopRows[1], "TOPLEFT")
	theFrame.ScrollBar1:SetPoint("BOTTOMRIGHT", theFrame.TopRows[8], "BOTTOMRIGHT")
	Recount:SetupScrollbar("Recount_MidnightDetail_ScrollBar1")

	-- Halfway is measured on the CONTENT, not the window: it is the divider
	-- between the two panes, and both panes are laid out inside Content. Taking
	-- it from theFrame put the line 16px below the gap it is supposed to sit in.
	local Halfway = Content:GetHeight() / 2
	Recount.Colors:RegisterTexture("Other Windows", "Title",
		Graph:DrawLine(Content, 2, Halfway, Content:GetWidth() - 2, Halfway, 24, {0.6, 0.0, 0.0, 1.0}, "ARTWORK"),
		{r = 0.5, g = 0.5, b = 0.5, a = 1})

	-- "No data / secret" placeholder over the list area
	theFrame.NoData = Content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	theFrame.NoData:SetPoint("TOP", Content, "TOP", 55, -(RowHeight + 2) * 4)
	theFrame.NoData:SetWidth(300)
	theFrame.NoData:SetTextColor(1, 0.82, 0, 1)
	theFrame.NoData:Hide()

	-- Bottom pie + per-target list
	theFrame.BotRowLabels = createColumnLabels(Content, -Halfway, {
		{point = "LEFT",  x = 16,       text = "#"},
		{point = "LEFT",  x = 30,       text = L["Player/Mob Name"]},
		{point = "RIGHT", x = -50 + 30, text = L["Damage"]},
		{point = "RIGHT", x = 4 + 30,   text = "%"},
	})

	theFrame.BotRows = {}
	for i = 1, 8 do
		local Row = CreateFrame("Frame", nil, Content)
		Row.id = i
		Row:SetWidth(270 + 50 + 30)
		Row:SetHeight(RowHeight)
		Row:SetPoint("TOPLEFT", Content, "TOP", -70 - 25, -Halfway - (RowHeight + 2) * i)

		Row.Background = Row:CreateTexture(nil, "BACKGROUND")
		Row.Background:SetAllPoints(Row)
		Row.Background:SetTexture("Interface\\Buttons\\WHITE8X8.blp")
		Row.Background:Hide()

		Row.Key = Row:CreateTexture(nil, "OVERLAY")
		Row.Key:SetPoint("LEFT", Row, "LEFT", 0, 0)
		Row.Key:SetTexture("Interface\\Buttons\\WHITE8X8.blp")
		Row.Key:SetWidth(12)
		Row.Key:SetHeight(12)

		Row.Count = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.Count:SetPoint("LEFT", Row.Key, "LEFT", 16, 0)
		Row.Count:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.Count)

		Row.Name = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.Name:SetPoint("LEFT", Row, "LEFT", 30, 0)
		Row.Name:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.Name)

		Row.Amount = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.Amount:SetPoint("RIGHT", Row, "RIGHT", -50, 0)
		Row.Amount:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.Amount)

		Row.Percent = Row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Row.Percent:SetPoint("RIGHT", Row, "RIGHT", 4, 0)
		Row.Percent:SetTextColor(1, 1, 1, 1)
		Recount:AddFontString(Row.Percent)

		theFrame.BotRows[i] = Row
	end

	theFrame.ScrollBar2 = CreateFrame("ScrollFrame", "Recount_MidnightDetail_ScrollBar2", Content, "FauxScrollFrameTemplate")
	theFrame.ScrollBar2:SetScript("OnVerticalScroll", function(scrollFrame, offset)
		FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, RowHeight, function() me:FillLower(Recount.MidnightDetailWindow.UpperTable and Recount.MidnightDetailWindow.UpperTable[Recount.MidnightDetailWindow.Selected]) end)
	end)
	theFrame.ScrollBar2:SetPoint("TOPLEFT", theFrame.BotRows[1], "TOPLEFT")
	theFrame.ScrollBar2:SetPoint("BOTTOMRIGHT", theFrame.BotRows[8], "BOTTOMRIGHT")
	Recount:SetupScrollbar("Recount_MidnightDetail_ScrollBar2")

	-- Join the window-ordering chain like every other Recount window. Its own
	-- OnShow calls SetWindowTop, which walks that chain -- without registering
	-- here the frame has no Above/Below links at all.
	Recount:AddWindow(theFrame)

	theFrame:Hide()
end
