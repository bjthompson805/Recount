local Recount = _G.Recount

local AceLocale = LibStub("AceLocale-3.0")
local L = AceLocale:GetLocale( "Recount" )

local revision = tonumber(string.sub("$Revision: 1454 $", 12, -3))
if Recount.Version < revision then
	Recount.Version = revision
end

local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local GetSpellInfo = GetSpellInfo
local UnitGUID = UnitGUID
local UnitName = UnitName
local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local ipairs = ipairs
local next = next
local pairs = pairs
local wipe = wipe
local math_floor = math.floor

local dbCombatants

-- ---------------------------------------------------------------------------
-- What this module does, and why it is arithmetic rather than an estimate
-- ---------------------------------------------------------------------------
-- Flat and percentage damage reduction is INVISIBLE in the combat log. The
-- server applies it before the event is written, so a swing that would have hit
-- for 530 arrives as 500 and is byte-identical to one that was always 500. The
-- log carries `resisted`, `blocked` and `absorbed` and nothing else -- there is
-- no field for mitigation.
--
-- That does NOT make the prevented amount unknowable, because for these auras
-- the reduction is a KNOWN CONSTANT and so the pre-reduction number is never
-- needed:
--
--   FLAT    a hit that lands for >0 had exactly `value` prevented. The only
--           ambiguity is a hit whose raw damage was below `value`, which floors
--           at 0 -- and those are vanishingly rare at level.
--   PERCENT raw = amount / (1 - R), so prevented = amount * R / (1 - R).
--
-- ARMOUR IS DELIBERATELY NOT MODELLED HERE and must not be added: its reduction
-- varies with attacker level and armour value, so it is not a constant and the
-- arithmetic above does not hold for it.

-- The combat log's school mask for physical damage. Tracker.lua declares the
-- same constant as a file-local at :434; it is not a global, so it cannot be
-- shared, but the MASK is the only thing duplicated here -- the mask-to-name
-- conversion below goes through Recount.SpellSchoolName so the two cannot
-- disagree about what the name is.
local SPELLSCHOOL_PHYSICAL = 1

-- ---------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------
-- Keyed on the AURA's spellId, which is NOT the id of the spell that applies it.
-- Measured in a live Classic Era client 2026-08-18: a shaman's Stoneskin Totem
-- puts a buff literally named "Stoneskin" on party members, id 10405, and that
-- is the id that arrives in UNIT_AURA. The totem-summoning spell has a
-- different id entirely and never appears here.
--
-- EVERY ENTRY MUST BE VERIFIED BEFORE IT IS ADDED. A wrong value here produces a
-- confident, plausible, wrong number in the UI -- which is worse than showing
-- nothing, because nobody can tell by looking. An aura that is not in this table
-- is simply not counted; that is the correct failure mode and is why the table
-- starts nearly empty rather than being filled in from memory.
--
--   kind        "FLAT" (points removed per hit) or "PERCENT" (fraction, 0..1)
--   value       the constant, per rank
--   melee       true if it only reduces melee swings (Stoneskin does)
--   schoolMask  combat-log school MASK it applies to, or nil for all schools.
--               Converted through Recount.SpellSchoolName at credit time --
--               never compared against `element` directly, because `element`
--               is that table's output (a name), not a mask.
--   fallback    the aura's English name, used only when the client cannot
--               resolve the spellId to a name yet.
local MITIGATION = {
	-- Stoneskin, rank as observed in game on 2026-08-18. Wowhead's spell data
	-- for this id reads "Apply Area Aura: Mod Melee Damage Taken, Value: -30",
	-- radius 20 yards -- which is also why walking out of the totem's radius
	-- drops the aura and gives us a clean window.
	[10405] = { kind = "FLAT", value = 30, melee = true, schoolMask = SPELLSCHOOL_PHYSICAL, fallback = "Stoneskin" },

	-- TODO: the remaining Stoneskin ranks, and the other constant-reduction
	-- auras (Blessing of Sanctuary, Defensive Stance, ...). Each needs its aura
	-- id and value verified -- from the spell data or from a client -- before it
	-- goes in. Do not populate this from memory.
}

-- The aura's display name. Read from the CLIENT rather than from Recount's own
-- locale files, because the registry is keyed on a spellId and the client
-- already holds that spell's name in the player's language. `fallback` covers
-- the case where the id is not in the client's cache yet; it is English, which
-- is wrong-but-legible, and better than an empty bar label.
local function labelFor(spellId, entry)
	local name
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellId)
		name = info and info.name
	elseif GetSpellInfo then
		name = GetSpellInfo(spellId)
	end
	return name or entry.fallback
end

-- ---------------------------------------------------------------------------
-- Which damage events can be credited
-- ---------------------------------------------------------------------------
-- Mitigation applies to a swing exactly once, but AddDamageData is reached more
-- than once for some swings. With MergeDamageAbsorbs on, Tracker.lua:593-599
-- files a SECOND, synthetic row for the absorbed portion with hittype "Absorb",
-- and SWING_MISSED (:654) files the absorb as damage too. Crediting on those
-- would count one swing's mitigation twice.
--
-- So this is an ALLOW-list of hit types that represent damage which actually
-- landed, not a deny-list of the ones seen to be wrong: a hit type added to
-- Tracker.lua later is then excluded until someone decides it belongs, which is
-- the safe direction. The names are Tracker.lua's unlocalised literals
-- (:559-577) and must not be localised.
local CREDITABLE_HITS = {
	Hit = true,
	Crit = true,
	Crushing = true,
	Glancing = true,
	Tick = true,
	Split = true,
}

-- ---------------------------------------------------------------------------
-- Live aura tracking
-- ---------------------------------------------------------------------------
-- active[destGUID] = { [auraInstanceID] = spellId }
--
-- KEYED ON auraInstanceID, NOT ON spellId, AND NOT A BOOLEAN. This is not
-- fussiness; the naive version is wrong and fails silently.
--
-- Measured with a shaman refreshing totems: UNIT_AURA delivers an ADD AND A
-- REMOVE IN THE SAME EVENT when a totem is replaced, and drops several auras at
-- once when they expire together. A boolean "does this player have Stoneskin",
-- updated by processing removes before adds, therefore reads FALSE for the
-- instant of a refresh -- and any swing landing in that window is counted as
-- unmitigated. It undercounts, quietly, with nothing to notice.
--
-- Tracking instances removes the problem by construction: the replacement is
-- added in the same pass that removes the old one, so the set is never empty in
-- between.
local active = {}

-- ---------------------------------------------------------------------------
-- Secret values
-- ---------------------------------------------------------------------------
-- Retail 12.0 made the UNIT_AURA payload SECRET to a tainted execution, and
-- every addon is tainted. Reported in game 2026-08-25, 27 times in one session:
--
--   TrackerModule_Mitigation.lua:198: attempt to perform boolean test on field
--   'isFullUpdate' (a secret boolean value, while execution tainted by 'Recount')
--
-- isFullUpdate is not the only field exposed. UnitConstantsDocumentation.lua in
-- the live client marks UnitAuraUpdateInfo.addedAuras ConditionalSecretContents,
-- so its AuraData entries' spellId and auraInstanceID are secret on the same
-- clients -- and both are used as TABLE KEYS below. Indexing BY a secret is an
-- operation and taints exactly as the boolean test does; it just happens not to
-- have been the first line reached. removedAuraInstanceIDs is NeverSecretContents
-- and needs no guard.
--
-- pcall is NOT a guard here: it catches the throw and leaves the taint, which
-- then surfaces as an unrelated error somewhere else in the UI. The only correct
-- handling is to not perform the operation.
--
-- issecretvalue is itself taint-free, so asking costs nothing, and it is simply
-- nil on Classic, where none of this applies.
local issecretvalue = issecretvalue

local function isPlain(v)
	return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- Which unit tokens we care about. Recount only has aura visibility for units
-- the client exposes, which is the player and the party/raid -- there is no way
-- to read auras on someone outside the group, so mitigation on them is not
-- countable and is not guessed at.
local function trackedUnits()
	local units = { "player" }
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	return units
end

local UNITS = trackedUnits()

local function rescanUnit(unit)
	local guid = UnitGUID(unit)
	if not guid then
		return
	end

	local live = {}
	for i = 1, 40 do
		local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
		if not aura then
			break
		end
		-- Skipped rather than latched off, because secrecy can be conditional:
		-- an aura unreadable inside an encounter is readable again outside one,
		-- and disabling permanently on the first secret would kill tracking for
		-- the rest of the session. Skipping undercounts, which is the safe
		-- direction to be wrong in and the same one the amount <= 0 case takes.
		if isPlain(aura.spellId) and isPlain(aura.auraInstanceID) and MITIGATION[aura.spellId] then
			live[aura.auraInstanceID] = aura.spellId
		end
	end

	if next(live) then
		active[guid] = live
	else
		active[guid] = nil
	end
end

function Recount:MitigationUnitAura(unit, updateInfo)
	-- Bail before doing any work at all for units we cannot act on. UNIT_AURA is
	-- one of the noisiest events in the game -- measured, three of every five
	-- fires carried neither an add nor a remove, they were refresh traffic -- so
	-- this early exit is the whole performance story.
	local guid = UnitGUID(unit)
	if not guid then
		return
	end

	-- An unreadable isFullUpdate means this client will not let us read the aura
	-- fields either, so the unit's tracking is dropped and we return WITHOUT
	-- rescanning. A rescan there would cost 40 API calls per UNIT_AURA to learn
	-- nothing, and UNIT_AURA is the noisiest event in the game. Dropping the
	-- entry is also the honest state: with no visibility we do not know what is
	-- live, and a stale set would credit mitigation that may have expired.
	-- Tested for SECRECY, not with isPlain: an absent isFullUpdate is a plain
	-- falsy value meaning "this is a delta", and isPlain(nil) is false, so
	-- isPlain here would throw away every delta payload that omits the field.
	if updateInfo and issecretvalue and issecretvalue(updateInfo.isFullUpdate) then
		active[guid] = nil
		return
	end

	if not updateInfo or updateInfo.isFullUpdate then
		rescanUnit(unit)
		return
	end

	local live = active[guid]

	-- Removals and additions are applied in the SAME pass, in that order,
	-- because both lists can be populated on one event.
	if updateInfo.removedAuraInstanceIDs and live then
		for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
			live[instanceID] = nil
		end
	end

	if updateInfo.addedAuras then
		for _, aura in ipairs(updateInfo.addedAuras) do
			-- addedAuras is ConditionalSecretContents; see the note above
			-- `isPlain`. Both fields are table keys, so both are guarded.
			if isPlain(aura.spellId) and isPlain(aura.auraInstanceID) and MITIGATION[aura.spellId] then
				live = live or {}
				live[aura.auraInstanceID] = aura.spellId
			end
		end
	end

	if live and next(live) then
		active[guid] = live
	else
		active[guid] = nil
	end
end

-- Who cast each live aura. Read lazily rather than cached at add time: the
-- addedAuras payload carries sourceUnit, but an aura can outlive the group slot
-- its caster occupied, so resolving at credit time is the honest reading.
local function sourceOf(unit, instanceID)
	local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
		and C_UnitAuras.GetAuraDataByAuraInstanceID(unit, instanceID)
	-- sourceUnit is guarded for the same reason the ids are: passing a secret
	-- into UnitName is an operation on it, and the name that came back would be
	-- secret too, which then taints the combatant lookup it feeds.
	if not aura or not isPlain(aura.sourceUnit) then
		return nil
	end
	return UnitName(aura.sourceUnit)
end

-- Map a GUID back to a unit token so the aura can be re-read. Rebuilt on roster
-- change rather than scanned per damage event.
local guidToUnit = {}

function Recount:MitigationUnitFor(guid)
	return guidToUnit[guid]
end

function Recount:MitigationRosterUpdate()
	wipe(guidToUnit)
	for _, unit in ipairs(UNITS) do
		local guid = UnitGUID(unit)
		if guid then
			guidToUnit[guid] = unit
		end
	end
end

-- ---------------------------------------------------------------------------
-- Crediting
-- ---------------------------------------------------------------------------
-- Called from AddDamageData for every damage event, BEFORE it mutates `element`
-- to "Melee" for swings (Tracker.lua:1959), so `element` here is always a
-- Recount.SpellSchoolName value. `amount` is what actually landed, AFTER
-- mitigation.
function Recount:CreditMitigation(victim, ability, element, hittype, amount, dstGUID)
	local live = dstGUID and active[dstGUID]
	if not live or not amount or amount <= 0 then
		-- amount <= 0 is the floored case: the hit was reduced to nothing, so
		-- the prevented amount is somewhere between 0 and the constant and is
		-- genuinely unknowable. Counting it as the full value would overstate,
		-- so it is skipped rather than guessed.
		return
	end

	if not CREDITABLE_HITS[hittype] then
		return
	end

	local unit = guidToUnit[dstGUID]
	local schoolName = Recount.SpellSchoolName

	-- MULTIPLE SHAMANS: the game resolves this for us and we must not second-guess
	-- it. Totem auras of the same type do not stack -- the player ends up holding
	-- exactly ONE Stoneskin aura, and its sourceUnit names the shaman whose totem
	-- actually won. Reading the applied aura therefore credits the right one
	-- automatically, and the other shaman correctly gets nothing, because their
	-- totem is not mitigating anything for this player. It also splits correctly
	-- across a raid: a player standing in A's totem and another in B's each carry
	-- their own sourceUnit.
	--
	-- The guard below is for the case that reasoning is wrong. If two live
	-- instances of the SAME spellId ever coexist, the loop would credit both and
	-- double the number. Counting each spellId once per hit is the conservative
	-- reading -- it cannot inflate, and if these genuinely do stack somewhere the
	-- result is an undercount, which is the safer direction to be wrong in.
	local counted = {}

	for instanceID, spellId in pairs(live) do
		local entry = MITIGATION[spellId]
		if entry
			and not counted[spellId]
			and (not entry.melee or ability == L["Melee"])
			and (not entry.schoolMask or (schoolName and schoolName[entry.schoolMask] == element))
		then
			counted[spellId] = true
			local prevented
			if entry.kind == "FLAT" then
				prevented = entry.value
			else
				-- Rounded because it feeds the same bars and per-second figures
				-- as damage, which are whole numbers everywhere else.
				prevented = math_floor(amount * entry.value / (1 - entry.value) + 0.5)
			end

			local caster = unit and sourceOf(unit, instanceID)
			-- Only an EXISTING combatant is credited. The aura tells us the
			-- caster's name but not the GUID and flags AddCombatant needs, and
			-- inventing those would file a malformed combatant. In practice a
			-- grouped shaman becomes a combatant on their first cast, so this
			-- drops only mitigation landing before they have done anything at
			-- all; that is a known undercount, not a silent wrong number.
			--
			-- WHERE THAT CORRECTNESS ACTUALLY LIVES, because this comment used to
			-- credit the wrong line (audit finding 22). The condition below is an
			-- EARLY EXIT: it saves a labelFor call and three no-op frames, and it
			-- keeps the intent legible. It is NOT what stops a malformed record
			-- being written. Each of the three writers below refuses a nil `who`
			-- on its own -- SetActive at Tracker.lua:1229, AddAmount at :1375,
			-- AddTableDataSum at :1637 -- so with an unregistered caster the
			-- guarded and unguarded paths produce IDENTICAL state.
			--
			-- MEASURED, not reasoned: replacing this condition with `if true then`
			-- leaves all 30 tests in Tests/mitigation_spec.lua green, and no test
			-- can catch it, because there is nothing observable to attach an
			-- assertion to.
			--
			-- SO IF YOU TIGHTEN THOSE WRITERS, OR ADD A FOURTH RECORDER HERE, the
			-- nil check is the thing to keep. Removing one because "the guard
			-- above handles it" would take the protection away and leave the guard
			-- standing, and nothing would go red.
			if caster and dbCombatants and dbCombatants[caster] then
				local casterData = dbCombatants[caster]
				local label = labelFor(spellId, entry)
				-- SetActive stamps LastActive and nothing else; the per-second
				-- denominator is ActiveTime, written only by AddTimeEvent, which
				-- this module never calls. This comment used to say the stamp was
				-- omitted deliberately to keep a shaman from reading as active,
				-- citing the Mana Given side -- and that reason was wrong in both
				-- places. LastActive's one reader is the idle sweep at
				-- Recount.lua:1607, which deletes an idler's WHOLE record 30
				-- seconds after its last stamp, Mitigated included.
				Recount:SetActive(casterData)
				Recount:AddAmount(casterData, "Mitigated", prevented)
				Recount:AddTableDataSum(casterData, "MitigatedBy", label, victim, prevented)
				Recount:AddTableDataSum(casterData, "MitigatedWho", victim, label, prevented)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
-- Its own frame, following TrackerModule_Threat.lua:131. These are not combat
-- log events, so Recount's CLEU dispatcher in Tracker.lua cannot carry them.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "UNIT_AURA" then
		Recount:MitigationUnitAura(arg1, arg2)
		return
	end

	-- A roster change can retire the unit token an aura was being read through,
	-- so the GUID map is rebuilt and every tracked unit rescanned. PLAYER_ENTERING_WORLD
	-- is here because auras already on the player at load never arrive as a delta.
	Recount:MitigationRosterUpdate()
	for _, unit in ipairs(UNITS) do
		if UnitGUID(unit) then
			rescanUnit(unit)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
local DetailTitles = { }
DetailTitles.Mitigated = {
	TopNames = L["Ability"],
	TopCount = "",
	TopAmount = L["Prevented"],
	BotNames = L["To"],
	BotMin = "",
	BotAvg = "",
	BotMax = "",
	BotAmount = L["Prevented"]
}

DetailTitles.MitigatedWho = {
	TopNames = L["To"],
	TopCount = "",
	TopAmount = L["Prevented"],
	BotNames = L["Ability"],
	BotMin = "",
	BotAvg = "",
	BotMax = "",
	BotAmount = L["Prevented"]
}

local DataModes = { }

function DataModes:Mitigated(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].Mitigated or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].Mitigated or 0), {{data.Fights[Recount.db.profile.CurDataSet].MitigatedBy, L["'s Damage Prevented"], DetailTitles.Mitigated}, {data.Fights[Recount.db.profile.CurDataSet].MitigatedWho, L["'s Damage Prevented For"], DetailTitles.MitigatedWho}}
end

local TooltipFuncs = { }

function TooltipFuncs:Mitigated(name, data)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Prevention Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].MitigatedBy, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Prevented For"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].MitigatedWho, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

Recount:AddModeTooltip(L["Damage Prevented"], DataModes.Mitigated, TooltipFuncs.Mitigated)

local oldlocalizer = Recount.LocalizeCombatants
function Recount.LocalizeCombatants()
	dbCombatants = Recount.db2.combatants
	oldlocalizer()
end

-- Exposed for the spec suite, which needs to assert what the registry claims
-- rather than re-declaring the values and drifting from them.
Recount.MitigationRegistry = MITIGATION
Recount.MitigationActive = active
-- The frame too, so the spec can drive the DISPATCHER rather than only the
-- functions it calls. The crash this module's secret-value guards answer came in
-- through here, and a spec that calls MitigationUnitAura directly cannot see a
-- dispatcher that stops forwarding the payload.
Recount.MitigationEventFrame = eventFrame
