local Recount = _G.Recount

local AceLocale = LibStub("AceLocale-3.0")
local L = AceLocale:GetLocale("Recount")

local revision = tonumber(string.sub("$Revision: 1472 $", 12, -3))
if Recount.Version < revision then
	Recount.Version = revision
end

local GameTooltip = GameTooltip

local dbCombatants
local srcRetention
-- No dstRetention here: this module records only the resurrector's side, so
-- there is no destination block to gate. That asymmetry is a known gap, raised
-- in docs/AUDIT.md as a self-raised cross-cutting finding, and the remedy is a
-- receiving-side record rather than an unused local kept as a placeholder.

local DetailTitles = { }
DetailTitles.Ressed = {
	TopNames = L["Ressed Who"],
	TopCount = "",
	TopAmount = L["Times"],
	BotNames = L["Ability"],
	BotMin = "",
	BotAvg = "",
	BotMax = "",
	BotAmount = L["Count"]
}

-- Combat-log handlers are dispatched POSITIONALLY, so every one declares the
-- client's full argument list whether or not it reads each name. The unread ones
-- carry a leading underscore: the position keeps its name, so the layout is still
-- documented, and luacheck reads the prefix as "deliberately unused" rather than
-- the exemption being switched off for the whole file.
function Recount:SpellResurrect(_timestamp, _eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName, _spellSchool)
	Recount:AddRes(srcName, dstName, spellName, srcGUID, srcFlags, dstGUID, dstFlags, spellId)
end

function Recount:AddRes(source, victim, ability, srcGUID, srcFlags, dstGUID, dstFlags, _spellId)
	-- DetectPet is called for the NAME it returns: a pet's name comes back as
	-- "Pet <Owner>", which is what the record is keyed on. The owner and owner-id
	-- it also returns are only needed by AddCombatant on a receiving side, and
	-- this module has none -- so they are discarded rather than held in locals
	-- nothing reads.
	source = Recount:DetectPet(source, srcGUID, srcFlags)
	victim = Recount:DetectPet(victim, dstGUID, dstFlags)


	srcRetention = Recount.srcRetention
	if srcRetention then
		if not dbCombatants[source] then
			Recount:AddCombatant(source, nil, srcGUID, srcFlags)
		end


		local sourceData = dbCombatants[source]
		if sourceData then

			Recount:SetActive(sourceData)

			Recount:AddAmount(sourceData, "Ressed", 1)
			Recount:AddTableDataSum(sourceData, "RessedWho", victim,ability, 1)
		end
	end
end

local DataModes = { }

function DataModes:Ressed(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].Ressed or 0)
	end

	return (data.Fights[Recount.db.profile.CurDataSet].Ressed or 0), {{data.Fights[Recount.db.profile.CurDataSet].RessedWho, L["'s Resses"], DetailTitles.Ressed}}
end

local TooltipFuncs = { }

function TooltipFuncs:Ressed(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Ressed"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].RessedWho, 3)
end

Recount:AddModeTooltip(L["Ressers"], DataModes.Ressed, TooltipFuncs.Ressed, nil, nil, nil, nil)

local oldlocalizer = Recount.LocalizeCombatants
function Recount.LocalizeCombatants()
	dbCombatants = Recount.db2.combatants
	oldlocalizer()
end
