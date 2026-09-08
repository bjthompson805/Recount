local Recount = _G.Recount

local revision = tonumber(string.sub("$Revision: 1441 $", 12, -3))
if Recount.Version < revision then
	Recount.Version = revision
end

local pairs = pairs
local string = string
local table = table
local type = type

local GetScreenWidth = GetScreenWidth
local PlaySound = PlaySound

local ColorPickerFrame = ColorPickerFrame
-- No OpacitySliderFrame capture: alpha comes from ColorPickerFrame:GetColorAlpha() on every
-- flavour, and the global does not exist at all in the retail client source.

local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local Colors = {}
Recount.Colors = Colors

local ItemsToUpdate = {}
local TypeToUpdate = {}
local ColorMultiplier = {}


local TYPE_TEXTURE = 1
local TYPE_BORDER = 2
local TYPE_BACKGROUND = 3
local TYPE_FUNC = 4
local TYPE_FONT = 5

local Cur_Branch
local Cur_Name
local TempColor = {}
local PreviousColor = {}

-- `SetupColorPickerAndShow` is the canonical setup method on EVERY flavour, and the OkayButton's
-- OnClick reads swatchFunc only from the info table the picker captures at setup time -- assigning
-- swatchFunc directly on the frame is silently dropped.
--
-- There used to be a `usesNewColorPicker()` predicate here, testing for that method's presence and
-- selecting a "pre-Dragonflight" path when it was absent. It is deleted, not merely unused: the
-- method is defined on Classic Era as well (Blizzard_FrameXML/Classic/ColorPickerFrame.lua:3), so
-- the predicate was ALWAYS TRUE in game and the path behind it was unreachable on every shipped
-- client. Keeping a dead discriminator around invites someone to branch on it again.
--
-- The real flavour difference is which object is the ColorSelect, and `GetColorAlpha` already
-- hides it -- Classic Era returns OpacitySliderFrame:GetValue(), Mainline delegates to
-- Content.ColorPicker. Feature-detect that if you ever need to, never the setup method.

local function Color_Change()
	local r, g, b = ColorPickerFrame:GetColorRGB()

	TempColor.r = r
	TempColor.g = g
	TempColor.b = b
	if not ColorPickerFrame.hasOpacity then
		TempColor.a = nil
	else
		-- ColorPickerFrame:GetColorAlpha() is the public method on EVERY
		-- flavour, so there is no branch to make here. Classic Era's is
		-- `return OpacitySliderFrame:GetValue()`
		-- (Blizzard_FrameXML/Classic/ColorPickerFrame.lua:19-20); retail's
		-- delegates to Content.ColorPicker (Mainline/ColorPickerFrame.lua:105-107).
		--
		-- This used to read
		--   usesNewColorPicker() and ColorPickerFrame:GetColorAlpha()
		--     or 1.0 - OpacitySliderFrame:GetValue()
		-- with a comment claiming the pre-modern picker inverts the slider.
		-- The client source says otherwise -- Classic Era returns the value
		-- straight -- so the two halves disagreed by `1 - a` for one picker
		-- state, and GUI_Realtime.lua read the same slider uninverted. The
		-- else half was also unreachable: SetupColorPickerAndShow exists on
		-- Classic Era too, so usesNewColorPicker() is always true in game.
		TempColor.a = ColorPickerFrame:GetColorAlpha()
	end

	Colors:SetColor(Cur_Branch, Cur_Name, TempColor)
end

local function Opacity_Change()
	local r, g, b = ColorPickerFrame:GetColorRGB()
	-- Same single call as Color_Change above; see the comment there for why
	-- there is no flavour branch and no inversion.
	local a = ColorPickerFrame:GetColorAlpha()

	TempColor.r = r
	TempColor.g = g
	TempColor.b = b
	TempColor.a = a

	Colors:SetColor(Cur_Branch, Cur_Name, TempColor)
end

local function Color_Cancel()
	-- Restoring the visible color is what matters; SetColor below calls
	-- UpdateColor which re-paints the registered visual elements. The
	-- picker frame itself is closing, no need to manually rewind its
	-- internal sliders.
	Colors:SetColor(Cur_Branch, Cur_Name, PreviousColor)
end

function Colors:GetColor(Branch, Name)
	if Branch == "Class" then
		if not Recount.db.profile.Colors[Branch][Name] then
			local classcol
			if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[Name] then
				classcol = CUSTOM_CLASS_COLORS[Name]
			else
				classcol = RAID_CLASS_COLORS[Name]
			end
			-- Copy: RAID_CLASS_COLORS / CUSTOM_CLASS_COLORS belong to the client
			-- and to every other addon reading them. Stamping our alpha onto the
			-- shared table leaks Recount's state into the default UI.
			return { r = classcol.r, g = classcol.g, b = classcol.b, a = 1 }
		end
	elseif Branch == "Realtime" then
		if not Recount.db.profile.Colors[Branch][Name] then
			if string.find(Name,"Top$") then
				return {r = 1.0, g = 0.0, b = 0.0, a = 1.0}
			else
				return {r = 0.2, g = 0.0, b = 0.0, a = 0.4}
			end
		end
	end
	if Recount.db.profile.Colors[Branch][Name] and not Recount.db.profile.Colors[Branch][Name].a then
		Recount.db.profile.Colors[Branch][Name].a = 1
	end

	return Recount.db.profile.Colors[Branch][Name]
end

local LastSet

function Colors:SetColor(Branch, Name, c)
	if type(Recount.db.profile.Colors[Branch][Name]) ~= "table" then
		Recount.db.profile.Colors[Branch][Name] = {}
	end
	Recount.db.profile.Colors[Branch][Name].r = c.r
	Recount.db.profile.Colors[Branch][Name].g = c.g
	Recount.db.profile.Colors[Branch][Name].b = c.b

	--[[if c.a and Branch ~= "Class" then
		Recount.db.profile.Colors[Branch][Name].a = c.a
	elseif c.a and Branch == "Class" then
		Recount.db.profile.Colors[Branch][Name].a = nil
	end]]
	Recount.db.profile.Colors[Branch][Name].a = c.a

	Colors:UpdateColor(Branch, Name)
end

function Colors:UpdateAllColors()
	local c
	for k1, Branch in pairs(ItemsToUpdate) do
		for k2 in pairs(Branch) do
			c = Recount.db.profile.Colors[k1][k2]
			if c then
				Colors:SetColor(k1, k2, c)
			end
		end
	end
end

function Colors:UpdateColor(Branch, Name)

	local c = Colors:GetColor(Branch, Name)

	local Items = ItemsToUpdate[Branch][Name]

	if LastSet ~= Name then
		LastSet = Name
	end

	for k, v in pairs(TypeToUpdate[Branch][Name]) do
		if v == TYPE_TEXTURE then
			local Multi = ColorMultiplier[Branch][Name][k]
			if c.a then
				if Multi then
					Items[k]:SetVertexColor(c.r * Multi.r, c.g * Multi.g, c.b * Multi.b, c.a * Multi.a)
				else
					Items[k]:SetVertexColor(c.r, c.g, c.b, c.a)
				end
			else
				if Multi then
					Items[k]:SetVertexColor(c.r * Multi.r, c.g * Multi.g, c.b * Multi.b)
				else
					Items[k]:SetVertexColor(c.r, c.g, c.b)
				end
			end
		elseif v == TYPE_BORDER then
			if c.a then
				Items[k]:SetBackdropBorderColor(c.r, c.g, c.b, c.a)
			else
				Items[k]:SetBackdropBorderColor(c.r, c.g, c.b)
			end
		elseif v == TYPE_BACKGROUND then
			if c.a then
				Items[k]:SetBackdropColor(c.r, c.g, c.b, c.a)
			else
				Items[k]:SetBackdropColor(c.r, c.g, c.b)
			end
		elseif v == TYPE_FUNC then
			Items[k][1](Items[k][2],{c.r, c.g, c.b, c.a})
		elseif v == TYPE_FONT then
			if c.a then
				Items[k]:SetTextColor(c.r, c.g, c.b, c.a)
			else
				Items[k]:SetTextColor(c.r, c.g, c.b)
			end
		end
	end
end


function Colors:UnregisterItem(Item)
	for k1, Branch in pairs(ItemsToUpdate) do
		for k2, Name in pairs(Branch) do
			for k, v in pairs(Name) do
				if v == Item then
					Name[k] = nil
					TypeToUpdate[k1][k2][k] = nil
					ColorMultiplier[k1][k2][k] = nil
				end
			end
		end
	end
end

function Colors:RegisterFunction(Branch, Name, Func, Pass)
	local c = Colors:GetColor(Branch, Name)
	if c.a then
		Func(Pass,{c.r, c.g, c.b, c.a})
	else
		Func(Pass,{c.r, c.g, c.b})
	end

	if type(ItemsToUpdate[Branch]) ~= "table" then
		ItemsToUpdate[Branch] = {}
		TypeToUpdate[Branch] = {}
		ColorMultiplier[Branch] = {}
	end

	if type(ItemsToUpdate[Branch][Name]) ~= "table" then
		ItemsToUpdate[Branch][Name] = {}
		TypeToUpdate[Branch][Name] = {}
		ColorMultiplier[Branch][Name] = {}
	end

	table.insert(ItemsToUpdate[Branch][Name],{Func, Pass})
	table.insert(TypeToUpdate[Branch][Name],TYPE_FUNC)
end

function Colors:RegisterTexture(Branch, Name, Texture, Multi)
	local c = Colors:GetColor(Branch, Name)

	if not Texture.SetVertexColor then
		Texture.SetVertexColor = Texture.SetStatusBarColor
	end

	if c.a then
		if Multi then
			Texture:SetVertexColor(c.r * Multi.r, c.g * Multi.g, c.b * Multi.b, c.a * Multi.a)
		else
			Texture:SetVertexColor(c.r, c.g, c.b, c.a)
		end
	else
		if Multi then
			Texture:SetVertexColor(c.r * Multi.r, c.g * Multi.g, c.b * Multi.b)
		else
			Texture:SetVertexColor(c.r, c.g, c.b)
		end
	end

	if type(ItemsToUpdate[Branch]) ~= "table" then
		ItemsToUpdate[Branch] = {}
		TypeToUpdate[Branch] = {}
		ColorMultiplier[Branch] = {}
	end

	if type(ItemsToUpdate[Branch][Name]) ~= "table" then
		ItemsToUpdate[Branch][Name] = {}
		TypeToUpdate[Branch][Name] = {}
		ColorMultiplier[Branch][Name] = {}
	end

	local entry = #ItemsToUpdate[Branch][Name] + 1
	table.insert(ItemsToUpdate[Branch][Name],Texture)
	table.insert(TypeToUpdate[Branch][Name],TYPE_TEXTURE)

	if Multi then
		ColorMultiplier[Branch][Name][entry] = Multi
	end
end

function Colors:RegisterBorder(Branch, Name, frame)
	local c = Colors:GetColor(Branch, Name)
	if c.a then
		frame:SetBackdropBorderColor(c.r, c.g, c.b, c.a)
	else
		frame:SetBackdropBorderColor(c.r, c.g, c.b)
	end

	if type(ItemsToUpdate[Branch]) ~= "table" then
		ItemsToUpdate[Branch] = {}
		TypeToUpdate[Branch] = {}
		ColorMultiplier[Branch] = {}
	end

	if type(ItemsToUpdate[Branch][Name]) ~= "table" then
		ItemsToUpdate[Branch][Name] = {}
		TypeToUpdate[Branch][Name] = {}
		ColorMultiplier[Branch][Name] = {}
	end

	table.insert(ItemsToUpdate[Branch][Name],frame)
	table.insert(TypeToUpdate[Branch][Name],TYPE_BORDER)
end

function Colors:RegisterBackground(Branch, Name, frame)
	local c = Colors:GetColor(Branch, Name)
	if c.a then
		frame:SetBackdropColor(c.r, c.g, c.b, c.a)
	else
		frame:SetBackdropColor(c.r, c.g, c.b)
	end

	if type(ItemsToUpdate[Branch]) ~= "table" then
		ItemsToUpdate[Branch] = {}
		TypeToUpdate[Branch] = {}
		ColorMultiplier[Branch] = {}
	end

	if type(ItemsToUpdate[Branch][Name]) ~= "table" then
		ItemsToUpdate[Branch][Name] = {}
		TypeToUpdate[Branch][Name] = {}
		ColorMultiplier[Branch][Name] = {}
	end

	table.insert(ItemsToUpdate[Branch][Name],frame)
	table.insert(TypeToUpdate[Branch][Name],TYPE_BACKGROUND)
end

function Colors:RegisterFont(Branch, Name, frame)
	local c = Colors:GetColor(Branch, Name)
	if c.a then
		frame:SetTextColor(c.r, c.g, c.b, c.a)
	else
		frame:SetTextColor(c.r, c.g, c.b)
	end

	if type(ItemsToUpdate[Branch]) ~= "table" then
		ItemsToUpdate[Branch] = {}
		TypeToUpdate[Branch] = {}
		ColorMultiplier[Branch] = {}
	end

	if type(ItemsToUpdate[Branch][Name]) ~= "table" then
		ItemsToUpdate[Branch][Name] = {}
		TypeToUpdate[Branch][Name] = {}
		ColorMultiplier[Branch][Name] = {}
	end

	table.insert(ItemsToUpdate[Branch][Name],frame)
	table.insert(TypeToUpdate[Branch][Name],TYPE_FONT)
end

function Colors:EditColor(Branch, Name, Attach)
	Cur_Branch = Branch
	Cur_Name = Name

	ColorPickerFrame:Hide()
	PlaySound(856)

	local c = Colors:GetColor(Branch, Name)

	PreviousColor.r, PreviousColor.g, PreviousColor.b, PreviousColor.a = c.r, c.g, c.b, c.a

	-- Every callback must be in the info table passed to SetupColorPickerAndShow.
	-- Setting swatchFunc / opacityFunc / cancelFunc on the frame and then calling
	-- Show is silently dropped: the OkayButton's OnClick reads the info table the
	-- picker captured at setup time, not the frame's fields. That was the bug that
	-- shipped a broken colour picker to Classic.
	--
	-- There is NO flavour branch here any more. This used to be
	-- `if usesNewColorPicker() then ... else <assign fields, then Show> end`, and
	-- the else half could not run on any shipped client:
	-- `ColorPickerFrameMixin:SetupColorPickerAndShow` is defined on Classic Era too
	-- (Blizzard_FrameXML/Classic/ColorPickerFrame.lua:3, with ten Blizzard call
	-- sites in that same tree), so the predicate was unconditionally true in game.
	-- The dead half also carried `opacity = 1.0 - c.a`, an inversion the client
	-- contradicts, and two specs drove it -- passing tests defending dead, wrong
	-- code. Removed rather than left as a decoy.
	--
	-- The method's PRESENCE is therefore not a flavour discriminator and must not
	-- be reintroduced as one. What actually differs between flavours is which
	-- object is the ColorSelect, and GetColorAlpha already hides that.
	ColorPickerFrame:SetupColorPickerAndShow({
		r = c.r, g = c.g, b = c.b,
		opacity = c.a, hasOpacity = c.a ~= nil,
		swatchFunc = Color_Change,
		opacityFunc = Opacity_Change,
		cancelFunc = Color_Cancel,
	})

	-- Position next to the caller. Done after Setup/Show so the picker's
	-- own setup logic doesn't blow away our anchors. A faint visual
	-- "appear-then-snap" is acceptable; matches how the picker behaves
	-- in retail addons that use this same pattern.
	if Attach then
		local leftPos = Attach:GetLeft() or 0 -- Elsia: Side code adapted from Mirror
		local rightPos = Attach:GetRight() or 0
		local rightDist = GetScreenWidth() - rightPos
		local side, oside
		if rightDist < leftPos then
			side, oside = "LEFT", "RIGHT"
		else
			side, oside = "RIGHT", "LEFT"
		end
		ColorPickerFrame:ClearAllPoints()
		ColorPickerFrame:SetPoint(oside, Attach, side, 0, 0)
	end
end

--[[function Colors:Debug()
	for k1, Branch in pairs(ItemsToUpdate) do
		for k2, Name in pairs(Branch) do
			Recount:Print(getn(Name).." "..k1.." "..k2)

			local Items = ItemsToUpdate[k1][k2]

			for k, v in pairs(TypeToUpdate[k1][k2]) do
				if v == TYPE_TEXTURE then
					Recount:Print("Texture:" .. getn(Items[k]))
				elseif v == TYPE_BORDER then
					Recount:Print("Border:" .. getn(Items[k]))
				elseif v == TYPE_BACKGROUND then
					Recount:Print("Background:" .. getn(Items[k]))
				elseif v == TYPE_FUNC then
					Recount:Print("Func:" .. getn(Items[k]))
				elseif v == TYPE_FONT then
					Recount:Print("Font:" .. getn(Items[k]))
				end
			end
		end
	end
end]]
