-- NeatPlates - SMILE! :-D

---------------------------------------------------------------------------------------------------------------------
-- Variables and References
---------------------------------------------------------------------------------------------------------------------
local addonName, NeatPlatesInternal = ...
local L = LibStub("AceLocale-3.0"):GetLocale("NeatPlates")
local NeatPlatesCore = CreateFrame("Frame", nil, WorldFrame)
local FrequentHealthUpdate = true
local GetPetOwner = NeatPlatesUtility.GetPetOwner
NeatPlates = {}

-- Local References
local _
local max = math.max
local round = NeatPlatesUtility.round
local fade = NeatPlatesUtility.fade
local select, pairs, tostring  = select, pairs, tostring 			    -- Local function copy
local CreateNeatPlatesStatusbar = CreateNeatPlatesStatusbar			    -- Local function copy
local WorldFrame, UIParent = WorldFrame, UIParent
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local SetNamePlateFriendlySize = C_NamePlate.SetNamePlateFriendlySize
local SetNamePlateEnemySize = C_NamePlate.SetNamePlateEnemySize
local RaidClassColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS

-- Internal Data
local Plates, PlatesVisible, PlatesFading, GUID = {}, {}, {}, {}	         	-- Plate Lists
local PlatesByUnit = {}
local PlatesByGUID = {}
local nameplate, extended, bars, regions, visual, carrier			    					-- Temp/Local References
local unit, unitcache, style, stylename, unitchanged, threatborder				  -- Temp/Local References
local numChildren = -1                                                     	-- Cache the current number of plates
local activetheme = {}                                                    	-- Table Placeholder
local InCombat, HasTarget, HasMouseover = false, false, false					   		-- Player State Data
local EnableFadeIn = true
local ShowCastBars = true
local ShowIntCast = true
local ShowIntWhoCast = true
local ShowServerIndicator = true
local EMPTY_TEXTURE = "Interface\\Addons\\NeatPlates\\Media\\Empty"
local ResetPlates, UpdateAll = false, false
local OverrideFonts = false
local OverrideOutline = 1

-- Raid Icon Reference
local RaidIconCoordinate = {
		["STAR"] = { x = 0, y =0 },
		["CIRCLE"] = { x = 0.25, y = 0 },
		["DIAMOND"] = { x = 0.5, y = 0 },
		["TRIANGLE"] = { x = 0.75, y = 0},
		["MOON"] = { x = 0, y = 0.25},
		["SQUARE"] = { x = .25, y = 0.25},
		["CROSS"] = { x = .5, y = 0.25},
		["SKULL"] = { x = .75, y = 0.25},
}

---------------------------------------------------------------------------------------------------------------------
-- Core Function Declaration
---------------------------------------------------------------------------------------------------------------------
-- Helpers
local function ClearIndices(t) if t then for i,v in pairs(t) do t[i] = nil end return t end end
local function IsPlateShown(plate) return plate and plate:IsShown() end

-- Queueing
local function SetUpdateMe(plate) plate.UpdateMe = true end
local function SetUpdateAll() UpdateAll = true end
local function SetUpdateHealth(source) source.parentPlate.UpdateHealth = true end

-- Overriding
local function BypassFunction() return true end
local ShowBlizzardPlate		-- Holder for later

-- Style
local UpdateStyle, CheckNameplateStyle

-- Indicators
local UpdateIndicator_CustomScaleText, UpdateIndicator_Standard, UpdateIndicator_CustomAlpha
local UpdateIndicator_Level, UpdateIndicator_ThreatGlow, UpdateIndicator_RaidIcon
local UpdateIndicator_EliteIcon, UpdateIndicator_UnitColor, UpdateIndicator_Name
local UpdateIndicator_HealthBar, UpdateIndicator_Highlight, UpdateIndicator_ExtraBar
local OnUpdateCasting, OnStartCasting, OnStopCasting, OnUpdateCastMidway, OnInterruptedCast

-- Event Functions
local OnShowNameplate, OnHideNameplate, OnUpdateNameplate, OnResetNameplate
local OnHealthUpdate, UpdateUnitCondition
local UpdateUnitContext, OnRequestWidgetUpdate, OnRequestDelegateUpdate
local UpdateUnitIdentity

-- Main Loop
local OnUpdate
local OnNewNameplate
local ForEachPlate

-- UpdateNameplateSize
local function UpdateNameplateSize(plate, show, cWidth, cHeight)
	local scaleStandard = activetheme.SetScale()
	local clickableWidth, clickableHeight = NeatPlatesPanel.GetClickableArea()
	local hitbox = {
		width = activetheme.Default.hitbox.width * (cWidth or clickableWidth),
		height = activetheme.Default.hitbox.height * (cHeight or clickableHeight),
		x = (activetheme.Default.hitbox.x*-1) * scaleStandard,
		y = (activetheme.Default.hitbox.y*-1) * scaleStandard,
	}

	if not InCombatLockdown() then
		if IsInInstance() then 
			local zeroBasedScale = tonumber(GetCVar("NamePlateVerticalScale")) - 1.0;
			local horizontalScale = tonumber(GetCVar("NamePlateHorizontalScale"));
			SetNamePlateFriendlySize(110 * horizontalScale, 45 * Lerp(1.0, 1.25, zeroBasedScale))  -- Reset to blizzard nameplate default to avoid issues if we are not allowed to modify the nameplate
		else SetNamePlateFriendlySize(hitbox.width * scaleStandard, hitbox.height * scaleStandard) end -- Clickable area of the nameplate
		SetNamePlateEnemySize(hitbox.width * scaleStandard, hitbox.height * scaleStandard) -- Clickable area of the nameplate
	end

	if plate then 
		plate.carrier:SetPoint("CENTER", plate, "CENTER", hitbox.x, hitbox.y)	-- Offset
		plate.extended.visual.hitbox:SetPoint("CENTER", plate)
		plate.extended.visual.hitbox:SetWidth(hitbox.width)
		plate.extended.visual.hitbox:SetHeight(hitbox.height)

		if show then plate.extended.visual.hitbox:Show() else plate.extended.visual.hitbox:Hide() end
	end
end

-- UpdateReferences
local function UpdateReferences(plate)
	nameplate = plate
	extended = plate.extended

	carrier = plate.carrier
	bars = extended.bars
	regions = extended.regions
	unit = extended.unit
	unitcache = extended.unitcache
	visual = extended.visual
	style = extended.style
	threatborder = visual.threatborder
end

---------------------------------------------------------------------------------------------------------------------
-- Nameplate Detection & Update Loop
---------------------------------------------------------------------------------------------------------------------
do
	-- Local References
	local WorldGetNumChildren, WorldGetChildren = WorldFrame.GetNumChildren, WorldFrame.GetChildren

	-- ForEachPlate
	function ForEachPlate(functionToRun, ...)
		for plate in pairs(PlatesVisible) do
			if plate.extended.Active then
				functionToRun(plate, ...)
			end
		end
	end

        -- OnUpdate; This function is run frequently, on every clock cycle
	function OnUpdate(self, e)
		-- Poll Loop
		local plate, curChildren

        -- Detect when cursor leaves the mouseover unit
		if HasMouseover and not UnitExists("mouseover") then
			HasMouseover = false
			SetUpdateAll()
		end

		for plate in pairs(PlatesVisible) do
			local UpdateMe = UpdateAll or plate.UpdateMe
			local UpdateHealth = plate.UpdateHealth
			local carrier = plate.carrier
			local extended = plate.extended

			if NeatPlatesOptions.BlizzardScaling then carrier:SetScale(plate:GetScale()) end	-- Scale the carrier to allow for certain CVars that control scale to function properly.

			-- Check for an Update Request
			if UpdateMe or UpdateHealth then
				if not UpdateMe then
					OnHealthUpdate(plate)
				else
					OnUpdateNameplate(plate)
				end
				plate.UpdateMe = false
				plate.UpdateHealth = false

				plate:GetChildren():Hide()

			end

			if plate.UnitFrame then plate.UnitFrame:Hide() end

		-- This would be useful for alpha fades
		-- But right now it's just going to get set directly
		-- extended:SetAlpha(extended.requestedAlpha)

		end

		-- Reset Mass-Update Flag
		UpdateAll = false
	end


end

---------------------------------------------------------------------------------------------------------------------
--  Nameplate Extension: Applies scripts, hooks, and adds additional frame variables and regions
---------------------------------------------------------------------------------------------------------------------
do

	local topFrameLevel = 0

	-- ApplyPlateExtesion
	function OnNewNameplate(plate, unitid)

    -- NeatPlates Frame
    --------------------------------
    local bars, regions = {}, {}
		local carrier
		local frameName = "NeatPlatesCarrier"..numChildren

		carrier = CreateFrame("Frame", frameName, WorldFrame)
		local extended = CreateFrame("Frame", nil, carrier)

		plate.carrier = carrier
		plate.extended = extended

    -- Add Graphical Elements
		local visual = {}
		-- Status Bars
		local healthbar = CreateNeatPlatesStatusbar(extended)
		local extrabar = CreateNeatPlatesStatusbar(extended)	-- Currently used for Bodyguard XP in Nazjatar
		local castbar = CreateNeatPlatesStatusbar(extended)
		local textFrame = CreateFrame("Frame", nil, healthbar)
		local widgetParent = CreateFrame("Frame", nil, textFrame)

		textFrame:SetAllPoints()

		extended.widgetParent = widgetParent
		visual.healthbar = healthbar
		visual.extrabar = extrabar
		visual.castbar = castbar
		bars.healthbar = healthbar		-- For Threat Plates Compatibility
		bars.extrabar = extrabar			-- For Threat Plates Compatibility
		bars.castbar = castbar			-- For Threat Plates Compatibility
		-- Parented to Health Bar - Lower Frame
		visual.healthborder = healthbar:CreateTexture(nil, "ARTWORK")
		visual.threatborder = healthbar:CreateTexture(nil, "ARTWORK")
		visual.highlight = healthbar:CreateTexture(nil, "OVERLAY")
		visual.hitbox = healthbar:CreateTexture(nil, "OVERLAY")
		-- Parented to Extended - Middle Frame
		visual.raidicon = textFrame:CreateTexture(nil, "OVERLAY")
		visual.eliteicon = textFrame:CreateTexture(nil, "OVERLAY")
		visual.skullicon = textFrame:CreateTexture(nil, "OVERLAY")
		visual.target = textFrame:CreateTexture(nil, "ARTWORK")
		visual.focus = textFrame:CreateTexture(nil, "ARTWORK")
		visual.mouseover = textFrame:CreateTexture(nil, "ARTWORK")
		-- TextFrame
		visual.customtext = textFrame:CreateFontString(nil, "OVERLAY")
		visual.name  = textFrame:CreateFontString(nil, "OVERLAY")
		visual.subtext = textFrame:CreateFontString(nil, "OVERLAY")
		visual.level = textFrame:CreateFontString(nil, "OVERLAY")
		-- Extra Bar Frame
		visual.extraborder = extrabar:CreateTexture(nil, "ARTWORK")
		visual.extratext = extrabar:CreateFontString(nil, "OVERLAY")
		-- Cast Bar Frame - Highest Frame
		visual.castborder = castbar:CreateTexture(nil, "ARTWORK")
		visual.castnostop = castbar:CreateTexture(nil, "ARTWORK")
		visual.spellicon = castbar:CreateTexture(nil, "OVERLAY")
		visual.spelltext = castbar:CreateFontString(nil, "OVERLAY")
		visual.durationtext = castbar:CreateFontString(nil, "OVERLAY")
		castbar.durationtext = visual.durationtext -- Extra reference for updating castbars duration text
		-- Set Base Properties
		visual.raidicon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		visual.highlight:SetAllPoints(visual.healthborder)
		visual.highlight:SetBlendMode("ADD")
		visual.hitbox:SetBlendMode("ADD")
		visual.hitbox:SetColorTexture(0, 0.6, 0.0, 0.5)

		extended:SetFrameStrata("BACKGROUND")
		healthbar:SetFrameStrata("BACKGROUND")
		extrabar:SetFrameStrata("BACKGROUND")
		castbar:SetFrameStrata("BACKGROUND")
		textFrame:SetFrameStrata("BACKGROUND")
		widgetParent:SetFrameStrata("BACKGROUND")

		widgetParent:SetFrameLevel(textFrame:GetFrameLevel() - 1)

		topFrameLevel = topFrameLevel + 20
		extended.defaultLevel = topFrameLevel
		extended:SetFrameLevel(topFrameLevel)

		extrabar:Hide()
		extrabar:SetStatusBarColor(1,.6,0)

		castbar:Hide()
		castbar:SetStatusBarColor(1,.8,0)
		carrier:SetSize(16, 16)

		-- Default Fonts
		visual.name:SetFontObject("NeatPlatesFontNormal")
		visual.subtext:SetFontObject("NeatPlatesFontSmall")
		visual.level:SetFontObject("NeatPlatesFontSmall")
		visual.extratext:SetFontObject("NeatPlatesFontSmall")
		visual.spelltext:SetFontObject("NeatPlatesFontNormal")
		visual.durationtext:SetFontObject("NeatPlatesFontNormal")
		visual.customtext:SetFontObject("NeatPlatesFontSmall")

		-- NeatPlates Frame References
		extended.regions = regions
		extended.bars = bars
		extended.visual = visual

		-- Allocate Tables
		extended.style,
		extended.unit,
		extended.unitcache,
		extended.stylecache,
		extended.widgets
			= {}, {}, {}, {}, {}

		extended.stylename = ""

		carrier:SetPoint("CENTER", plate, "CENTER")

		UpdateNameplateSize(plate)
	end

end

---------------------------------------------------------------------------------------------------------------------
-- Nameplate Script Handlers
---------------------------------------------------------------------------------------------------------------------
do

	-- UpdateUnitCache
	local function UpdateUnitCache() for key, value in pairs(unit) do unitcache[key] = value end end

	-- CheckNameplateStyle
	function CheckNameplateStyle()
		if activetheme.SetStyle then				-- If the active theme has a style selection function, run it..
			stylename = activetheme.SetStyle(unit)
			extended.style = activetheme[stylename]
		else 										-- If no style function, use the base table
			extended.style = activetheme;
			stylename = tostring(activetheme)
		end

		style = extended.style

		if style and (extended.stylename ~= stylename) then
			UpdateStyle()
			extended.stylename = stylename
			unit.style = stylename

			if(extended.widgets['AuraWidgetHub'] and unit.unitid) then extended.widgets['AuraWidgetHub']:UpdateContext(unit) end
		end

	end

	-- ProcessUnitChanges
	local function ProcessUnitChanges()
			-- Unit Cache: Determine if data has changed
			unitchanged = false

			for key, value in pairs(unit) do
				if unitcache[key] ~= value then
					unitchanged = true
				end
			end

			-- Update Style/Indicators
			if unitchanged or UpdateAll or (not style)then --
				CheckNameplateStyle()
				UpdateIndicator_Standard()
				UpdateIndicator_HealthBar()
				UpdateIndicator_Highlight()
				UpdateIndicator_ExtraBar()
			end

			-- Update Widgets
			if activetheme.OnUpdate then activetheme.OnUpdate(extended, unit) end

			-- Update Delegates
			UpdateIndicator_ThreatGlow()
			UpdateIndicator_CustomAlpha()
			UpdateIndicator_CustomScaleText()

			-- Cache the old unit information
			UpdateUnitCache()
	end

--[[
	local function HideWidgets(plate)
		if plate.extended and plate.extended.widgets then
			local widgetTable = plate.extended.widgets
			for widgetIndex, widget in pairs(widgetTable) do
				widget:Hide()
				--widgetTable[widgetIndex] = nil
			end
		end
	end

--]]

	---------------------------------------------------------------------------------------------------------------------
	-- Create / Hide / Show Event Handlers
	---------------------------------------------------------------------------------------------------------------------

	-- OnShowNameplate
	function OnShowNameplate(plate, unitid)
		local unitGUID = UnitGUID(unitid)
		-- or unitid = plate.namePlateUnitToken
		UpdateReferences(plate)

		carrier:Show()

		PlatesVisible[plate] = unitid
		PlatesByUnit[unitid] = plate
		if unitGUID then PlatesByGUID[unitGUID] = plate end

		unit.frame = extended
		unit.alpha = 0
		unit.isTarget = false
		unit.isMouseover = false
		unit.unitid = unitid
		extended.unitcache = ClearIndices(extended.unitcache)
		extended.stylename = ""
		extended.Active = true

		--visual.highlight:Hide()

		wipe(extended.unit)
		wipe(extended.unitcache)


		-- For Fading In
		PlatesFading[plate] = EnableFadeIn
		extended.requestedAlpha = 0
		--extended.visibleAlpha = 0
		extended:Hide()		-- Yes, it seems counterintuitive, but...
		extended:SetAlpha(0)

		-- Graphics
		unit.isCasting = false
		visual.extrabar:Hide()
		visual.castbar:Hide()
		visual.highlight:Hide()
		visual.hitbox:Hide()
		


		-- Widgets/Extensions
		-- This goes here because a user might change widget settings after nameplates have been created
		if activetheme.OnInitialize then activetheme.OnInitialize(extended, activetheme) end

		-- Skip the initial data gather and let the second cycle do the work.
		plate.UpdateMe = true

	end


	-- OnHideNameplate
	function OnHideNameplate(plate, unitid)
		local unitGUID = UnitGUID(unitid)
		--plate.extended:Hide()
		plate.carrier:Hide()

		UpdateReferences(plate)

		extended.Active = false

		PlatesVisible[plate] = nil
		PlatesByUnit[unitid] = nil
		if unitGUID then PlatesByGUID[unitGUID] = nil end

		visual.extrabar:Hide()
		visual.castbar:Hide()
		visual.castbar:SetScript("OnUpdate", nil)
		unit.isCasting = false

		-- Remove anything from the function queue
		plate.UpdateMe = false

		for widgetname, widget in pairs(extended.widgets) do widget:Hide() end
	end

	-- OnUpdateNameplate
	function OnUpdateNameplate(plate)
		-- And stay down!
		-- plate:GetChildren():Hide()

		-- Gather Information
		local unitid = PlatesVisible[plate]
		UpdateReferences(plate)

		UpdateUnitIdentity(plate, unitid)
		UpdateUnitContext(plate, unitid)
		ProcessUnitChanges()
		OnUpdateCastMidway(plate, unitid)

	end

	-- OnHealthUpdate
	function OnHealthUpdate(plate)
		local unitid = PlatesVisible[plate]

		UpdateUnitCondition(plate, unitid)
		ProcessUnitChanges()
		UpdateIndicator_HealthBar()		-- Just to be on the safe side
	end

     -- OnResetNameplate
	function OnResetNameplate(plate)
		local extended = plate.extended
		plate.UpdateMe = true
		extended.unitcache = ClearIndices(extended.unitcache)
		extended.stylename = ""
		local unitid = PlatesVisible[plate]

		UpdateNameplateSize(plate)
		OnShowNameplate(plate, unitid)
	end

end


---------------------------------------------------------------------------------------------------------------------
--  Unit Updates: Updates Unit Data, Requests indicator updates
---------------------------------------------------------------------------------------------------------------------
do
	local RaidIconList = { "STAR", "CIRCLE", "DIAMOND", "TRIANGLE", "MOON", "SQUARE", "CROSS", "SKULL" }

	-- GetUnitAggroStatus: Determines if a unit is attacking, by looking at aggro glow region
	local function GetUnitAggroStatus( threatRegion )
		if not  threatRegion:IsShown() then return "LOW", 0 end

		local red, green, blue, alpha = threatRegion:GetVertexColor()
		local opacity = threatRegion:GetVertexColor()

		if threatRegion:IsShown() and (alpha < .9 or opacity < .9) then
			-- Unfinished
		end

		if red > 0 then
			if green > 0 then
				if blue > 0 then return "MEDIUM", 1 end
				return "MEDIUM", 2
			end
			return "HIGH", 3
		end
	end

		-- GetUnitReaction: Determines the reaction, and type of unit from the health bar color
	local function GetReactionByColor(red, green, blue)
		if red < .1 then 	-- Friendly
			return "FRIENDLY"
		elseif red > .5 then
			if green > .9 then return "NEUTRAL"
			else return "HOSTILE" end
		end
	end


	local EliteReference = {
		["elite"] = true,
		["rareelite"] = true,
		["worldboss"] = true,
	}

	local RareReference = {
		["rare"] = true,
		["rareelite"] = true,
	}

	local ThreatReference = {
		[0] = "LOW",
		[1] = "MEDIUM",
		[2] = "MEDIUM",
		[3] = "HIGH",
	}

	-- UpdateUnitIdentity: Updates Low-volatility Unit Data
	-- (This is essentially static data)
	--------------------------------------------------------
	function UpdateUnitIdentity(plate, unitid)
		unit.unitid = unitid
		unit.name, unit.realm = UnitName(unitid)
		unit.pvpname = UnitPVPName(unitid)
		unit.rawName = unit.name  -- gsub(unit.name, " %(%*%)", "")

		local classification = UnitClassification(unitid)

		unit.isBoss = UnitLevel(unitid) == -1
		unit.isDangerous = unit.isBoss

		unit.isElite = EliteReference[classification]
		unit.isRare = RareReference[classification]
		unit.isMini = classification == "minus"
		--unit.isPet = UnitIsOtherPlayersPet(unitid)
		unit.isPet = ("Pet" == strsplit("-", UnitGUID(unitid)))

		if UnitIsPlayer(unitid) then
			_, unit.class = UnitClass(unitid)
			unit.type = "PLAYER"
		else
			unit.class = ""
			unit.type = "NPC"
		end
		
	end


        -- UpdateUnitContext: Updates Target/Mouseover
	function UpdateUnitContext(plate, unitid)
		local guid

		UpdateReferences(plate)

		unit.isMouseover = UnitIsUnit("mouseover", unitid)
		unit.isTarget = UnitIsUnit("target", unitid)
		unit.isFocus = UnitIsUnit("focus", unitid)

		unit.guid = UnitGUID(unitid)

		UpdateUnitCondition(plate, unitid)	-- This updates a bunch of properties

		if activetheme.OnContextUpdate then 
			CheckNameplateStyle()
			activetheme.OnContextUpdate(extended, unit)
		end
		if activetheme.OnUpdate then activetheme.OnUpdate(extended, unit) end
	end

	-- UpdateUnitCondition: High volatility data
	function UpdateUnitCondition(plate, unitid)
		UpdateReferences(plate)

		unit.unitid = unit.unitid or unitid -- Just make sure it exists
		unit.level = UnitEffectiveLevel(unitid)

		local c = GetCreatureDifficultyColor(unit.level)
		unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue = c.r, c.g, c.b

		unit.isTrivial = (c.r == 0.5 and c.g == 0.5 and c.b == 0.5)

		unit.red, unit.green, unit.blue = UnitSelectionColor(unitid)
		unit.reaction = GetReactionByColor(unit.red, unit.green, unit.blue) or "HOSTILE"

		unit.health = UnitHealth(unitid) or 0
		unit.healthmax = UnitHealthMax(unitid) or 1

		unit.threatValue = UnitThreatSituation("player", unitid) or 0
		unit.threatSituation = ThreatReference[unit.threatValue]
		unit.isInCombat = UnitAffectingCombat(unitid)

		local raidIconIndex = GetRaidTargetIndex(unitid)

		if raidIconIndex then
			unit.raidIcon = RaidIconList[raidIconIndex]
			unit.isMarked = true
		else
			unit.isMarked = false
		end

		-- Unfinished....
		unit.isTapped = UnitIsTapDenied(unitid)
		--unit.isInCombat = false
		--unit.platetype = 2 -- trivial mini mob

	end

	-- OnRequestWidgetUpdate: Calls Update on just the Widgets
	function OnRequestWidgetUpdate(plate)
		if not IsPlateShown(plate) then return end
		UpdateReferences(plate)
		if activetheme.OnContextUpdate then activetheme.OnContextUpdate(extended, unit) end
		if activetheme.OnUpdate then activetheme.OnUpdate(extended, unit) end
	end

	-- OnRequestDelegateUpdate: Updates just the delegate function indicators
	function OnRequestDelegateUpdate(plate)
			if not IsPlateShown(plate) then return end
			UpdateReferences(plate)
			UpdateIndicator_ThreatGlow()
			UpdateIndicator_CustomAlpha()
			UpdateIndicator_CustomScaleText()
	end


end		-- End of Nameplate/Unit Events


---------------------------------------------------------------------------------------------------------------------
-- Indicators: These functions update the color, texture, strings, and frames within a style.
---------------------------------------------------------------------------------------------------------------------
do
	local color = {}
	local alpha, forcealpha, scale


	-- UpdateIndicator_HealthBar: Updates the value on the health bar
	function UpdateIndicator_HealthBar()
		visual.healthbar:SetMinMaxValues(0, unit.healthmax)
		visual.healthbar:SetValue(unit.health)
	end


	-- UpdateIndicator_Name:
	function UpdateIndicator_Name()
		if ShowServerIndicator and unit.realm then visual.name:SetText(unit.name.." (*)") else visual.name:SetText(unit.name) end
		--unit.pvpname

		-- Name Color
		if activetheme.SetNameColor then
			visual.name:SetTextColor(activetheme.SetNameColor(unit))
		else visual.name:SetTextColor(1,1,1,1) end

		-- Subtext
		if style.subtext.show then
			if activetheme.SetSubText then
				local text, r, g, b, a = activetheme.SetSubText(unit)
				visual.subtext:SetText( text or "")
				visual.subtext:SetTextColor(r or 1, g or 1, b or 1, a or 1)
			else visual.subtext:SetText("") end
		end
	end


	-- UpdateIndicator_Level:
	function UpdateIndicator_Level()
		if unit.isBoss and style.skullicon.show then visual.level:Hide(); visual.skullicon:Show() else visual.skullicon:Hide() end

		if unit.level < 0 then visual.level:SetText("")
		else visual.level:SetText(unit.level) end
		visual.level:SetTextColor(unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue)
	end


	-- UpdateIndicator_ThreatGlow: Updates the aggro glow
	function UpdateIndicator_ThreatGlow()
		if not style.threatborder.show then return end
		threatborder = visual.threatborder
		if activetheme.SetThreatColor then

			threatborder:SetVertexColor(activetheme.SetThreatColor(unit) )
		else
			if InCombat and unit.reaction ~= "FRIENDLY" and unit.type == "NPC" then
				local color = style.threatcolor[unit.threatSituation]
				threatborder:Show()
				threatborder:SetVertexColor(color.r, color.g, color.b, (color.a or 1))
			else threatborder:Hide() end
		end
	end


	-- UpdateIndicator_Highlight
	function UpdateIndicator_Highlight()
		local current = nil
		
		if not current and unit.isTarget and style.target.show then current = 'target'; visual.target:Show() else visual.target:Hide() end
		if not current and unit.isFocus and style.focus.show then current = 'focus'; visual.focus:Show() else visual.focus:Hide() end
		if not current and unit.isMouseover and style.mouseover.show then current = 'mouseover'; visual.mouseover:Show() else visual.mouseover:Hide() end

		if unit.isMouseover and not unit.isTarget then visual.highlight:Show() else visual.highlight:Hide() end

		if current then visual[current]:SetVertexColor(style[current].color.r, style[current].color.g, style[current].color.b, style[current].color.a) end
	end

	-- UpdateIndicator_ExtraBar
	function UpdateIndicator_ExtraBar()
		if not unit or not unit.unitid then return end
		local widgetSetID = UnitWidgetSet(unit.unitid);

		if widgetSetID then
			local widgetID = C_UIWidgetManager.GetAllWidgetsBySetID(widgetSetID)[1].widgetID
			local widget = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(widgetID)
			local rank = widget.overrideBarText
			local barCur = widget.barValue - widget.barMin
			local barMax = widget.barMax - widget.barMin
			local text = rank

			if unit.isMouseover then text = barCur.."/"..barMax end

			visual.extrabar:SetMinMaxValues(0, barMax)
			visual.extrabar:SetValue(barCur)
			visual.extratext:SetText(text)

			visual.extrabar:Show()
		end
	end


	-- UpdateIndicator_RaidIcon
	function UpdateIndicator_RaidIcon()
		if unit.isMarked and style.raidicon.show then
			local iconCoord = RaidIconCoordinate[unit.raidIcon]
			if iconCoord then
				visual.raidicon:Show()
				visual.raidicon:SetTexCoord(iconCoord.x, iconCoord.x + 0.25, iconCoord.y, iconCoord.y + 0.25)
			else visual.raidicon:Hide() end
		else visual.raidicon:Hide() end
	end


	-- UpdateIndicator_EliteIcon: Updates the border overlay art and threat glow to Elite or Non-Elite art
	function UpdateIndicator_EliteIcon()
		threatborder = visual.threatborder
		if (unit.isElite or unit.isRare) and not unit.isBoss and style.eliteicon.show then visual.eliteicon:Show() else visual.eliteicon:Hide() end
		visual.eliteicon:SetDesaturated(unit.isRare) -- Desaturate if rare elite
	end


	-- UpdateIndicator_UnitColor: Update the health bar coloring, if needed
	function UpdateIndicator_UnitColor()
		-- Set Health Bar
		if activetheme.SetHealthbarColor then
			visual.healthbar:SetAllColors(activetheme.SetHealthbarColor(unit))

		else visual.healthbar:SetStatusBarColor(unit.red, unit.green, unit.blue) end

		-- Name Color
		if activetheme.SetNameColor then
			visual.name:SetTextColor(activetheme.SetNameColor(unit))
		else visual.name:SetTextColor(1,1,1,1) end
	end


	-- UpdateIndicator_Standard: Updates Non-Delegate Indicators
	function UpdateIndicator_Standard()
		if IsPlateShown(nameplate) then
			if unitcache.name ~= unit.name then UpdateIndicator_Name() end
			if unitcache.level ~= unit.level or unitcache.isBoss ~= unit.isBoss then UpdateIndicator_Level() end
			UpdateIndicator_RaidIcon()
			if unitcache.isElite ~= unit.isElite or unitcache.isRare ~= unit.isRare then UpdateIndicator_EliteIcon() end
		end
	end


	-- UpdateIndicator_CustomAlpha: Calls the alpha delegate to get the requested alpha
	function UpdateIndicator_CustomAlpha(event)
		if activetheme.SetAlpha then
			--local previousAlpha = extended.requestedAlpha
			extended.requestedAlpha = activetheme.SetAlpha(unit) or previousAlpha or unit.alpha or 1
		else
			extended.requestedAlpha = unit.alpha or 1
		end

		if extended.requestedAlpha > 0 then
			extended:SetAlpha(extended.requestedAlpha)
			if nameplate:IsShown() then extended:Show() end
		else
			extended:Hide()        -- FRAME HIDE TEST
		end

		-- Better Layering
		if unit.isTarget then
			extended:SetFrameLevel(3000)
		elseif unit.isMouseover then
			extended:SetFrameLevel(3200)
		else
			extended:SetFrameLevel(extended.defaultLevel)
		end

	end


	-- UpdateIndicator_CustomScaleText: Updates indicators for custom text and scale
	function UpdateIndicator_CustomScaleText()
		threatborder = visual.threatborder

		if unit.health and (extended.requestedAlpha > 0) then
			-- Scale
			if activetheme.SetScale then
				scale = activetheme.SetScale(unit)
				if scale then extended:SetScale( scale )end
			end

			-- Set Special-Case Regions
			if style.customtext.show then
				if activetheme.SetCustomText then
					local text, r, g, b, a = activetheme.SetCustomText(unit)
					visual.customtext:SetText( text or "")
					visual.customtext:SetTextColor(r or 1, g or 1, b or 1, a or 1)
				else visual.customtext:SetText("") end
			end

			UpdateIndicator_UnitColor()
		end
	end


	local function OnUpdateCastBarForward(self)
		local currentTime = GetTime() * 1000
		local startTime, endTime = self:GetMinMaxValues()
		local text = ""
		if activetheme.SetCastbarDuration then text = activetheme.SetCastbarDuration(currentTime, startTime, endTime) end

		self.durationtext:SetText(text)
		self:SetValue(currentTime)
	end


	local function OnUpdateCastBarReverse(self)
		local currentTime = GetTime() * 1000
		local startTime, endTime = self:GetMinMaxValues()
		local text = ""
		if activetheme.SetCastbarDuration then text = activetheme.SetCastbarDuration(currentTime, startTime, endTime, true) end

		self.durationtext:SetText(text)
		self:SetValue((endTime + startTime) - currentTime)
	end



	-- OnShowCastbar
	function OnStartCasting(plate, unitid, channeled)
		UpdateReferences(plate)
		--if not extended:IsShown() then return end
		if not extended:IsShown() then return end

		local castBar = extended.visual.castbar

		local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible

		if channeled then
			name, text, texture, startTime, endTime, isTradeSkill, notInterruptible = UnitChannelInfo(unitid)
			castBar:SetScript("OnUpdate", OnUpdateCastBarReverse)
		else
			name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible = UnitCastingInfo(unitid)
			castBar:SetScript("OnUpdate", OnUpdateCastBarForward)
		end

		if isTradeSkill then return end

		unit.isCasting = true
		unit.interrupted = false
		unit.interruptLogged = false
		unit.spellIsShielded = notInterruptible
		unit.spellInterruptible = not unit.spellIsShielded

		-- Clear registered events incase they weren't
		castBar:SetScript("OnEvent", nil)
		--castBar:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");

		visual.spelltext:SetText(text)
		visual.durationtext:SetText("")
		visual.spellicon:SetTexture(texture)
		castBar:SetMinMaxValues( startTime, endTime )

		local r, g, b, a = 1, 1, 0, 1

		if activetheme.SetCastbarColor then
			r, g, b, a = activetheme.SetCastbarColor(unit)
			if not (r and g and b and a) then return end
		end

		castBar:SetStatusBarColor( r, g, b)
		castBar:SetAlpha(a or 1)

		if unit.spellIsShielded then
			   visual.castnostop:Show(); visual.castborder:Hide()
		else visual.castnostop:Hide(); visual.castborder:Show() end

		UpdateIndicator_CustomScaleText()
		UpdateIndicator_CustomAlpha()

		castBar:Show()

	end

	-- OnInterruptedCasting
	function OnInterruptedCast(plate, sourceGUID, sourceName, destGUID)
		UpdateReferences(plate)

		local function setSpellText()
			local spellString, color
			local eventText = L["Interrupted"]

			if sourceGUID and sourceGUID ~= "" and ShowIntWhoCast then
				local _, engClass = GetPlayerInfoByGUID(sourceGUID)
				if RaidClassColors[engClass] then color = RaidClassColors[engClass].colorStr end
			end

			if sourceName and color then
				spellString = eventText.." |c"..color.."("..sourceName..")"
			else
				spellString = eventText
			end

			visual.spelltext:SetText(spellString)
			visual.durationtext:SetText("")
		end

		-- Main function
		if unit.interrupted and type and sourceGUID and sourceName and destGUID then
			setSpellText()
		else
			if unit.interrupted or not ShowIntCast then return end --not extended:IsShown() or 

			unit.interrupted = true
			unit.isCasting = false

			local castBar = extended.visual.castbar
			local _unit = unit -- Store this reference as the unit might have change once the fade function uses it.

			castBar:Show()

			local r, g, b, a = 1, 1, 0, 1

			if activetheme.SetCastbarColor then
				r, g, b, a = activetheme.SetCastbarColor(unit)
				if not (r and g and b and a) then return end
			end
			castBar:SetStatusBarColor(r, g, b)
			castBar:SetMinMaxValues(1, 1)

			setSpellText()

			-- Fade out the castbar
			local alpha, ticks, duration, delay = a, 25, 2, 0.8
			local perTick = alpha/(ticks-(delay/(duration/ticks)))
			local stopFade = false
			fade(ticks, duration, delay, function()
				alpha = alpha - perTick
				if not _unit.isCasting and not stopFade then
					castBar:SetAlpha(alpha)
				else
					stopFade = true
				end
			end, function()
				if not _unit.isCasting and not stopFade then
					_unit.interrupted = false
					castBar:Hide()

					--UpdateIndicator_CustomScaleText()
					--UpdateIndicator_CustomAlpha()
				end
			end)

			castBar:SetScript("OnUpdate", nil)
		end
	end

	-- OnHideCastbar
	function OnStopCasting(plate)
		UpdateReferences(plate)

		if not extended:IsShown() or unit.interrupted then return end
		local castBar = extended.visual.castbar

		castBar:Hide()
		castBar:SetScript("OnUpdate", nil)

		unit.isCasting = false
		unit.interrupted = false
		UpdateIndicator_CustomScaleText()
		UpdateIndicator_CustomAlpha()
	end



	function OnUpdateCastMidway(plate, unitid)
		if not ShowCastBars then return end

		local currentTime = GetTime() * 1000

		
		if UnitCastingInfo(unitid) then
			OnStartCasting(plate, unitid, false)	-- Check to see if there's a spell being cast
		elseif UnitChannelInfo(unitid) then
			OnStartCasting(plate, unitid, true)	-- See if one is being channeled...
		end
	end


end -- End Indicator section


--------------------------------------------------------------------------------------------------------------
-- WoW Event Handlers: sends event-driven changes to the appropriate gather/update handler.
--------------------------------------------------------------------------------------------------------------
do


	----------------------------------------
	-- Frequently Used Event-handling Functions
	----------------------------------------
	-- Update individual plate
	local function UnitConditionChanged(...)
		local _, unitid = ...
		local plate = GetNamePlateForUnit(unitid)

		if plate and not UnitIsUnit("player", unitid) then OnHealthUpdate(plate) end
	end

	-- Update everything
	local function WorldConditionChanged()
		SetUpdateAll()
	end

	-- Update spell currently being cast
	local function UnitSpellcastMidway(...)
		local _, unitid = ...
		if UnitIsUnit("player", unitid) or not ShowCastBars then return end

		local plate = GetNamePlateForUnit(unitid);

		if plate then
			OnUpdateCastMidway(plate, unitid)
		end
	 end

	 -- Update spell that was interrupted/cancelled
	 local function UnitSpellcastInterrupted(...)
	 	local event, unitid = ...

	 	if UnitIsUnit("player", unitid) or not ShowCastBars then return end

	 	local plate = GetNamePlateForUnit(unitid)

	 	if plate and not plate.extended.unit.interrupted then OnInterruptedCast(plate) end
	 end


	local CoreEvents = {}

	local function EventHandler(self, event, ...)
		CoreEvents[event](event, ...)
	end

	----------------------------------------
	-- Game Events
	----------------------------------------
	function CoreEvents:PLAYER_ENTERING_WORLD()
		NeatPlatesCore:SetScript("OnUpdate", OnUpdate);
	end

	function CoreEvents:UNIT_NAME_UPDATE(...)
		local unitid = ...
		local plate = GetNamePlateForUnit(unitid);
		
		if plate then
			SetUpdateMe(plate)
		end
	end

	function CoreEvents:NAME_PLATE_CREATED(...)
		local plate = ...
		OnNewNameplate(plate)
	 end

	function CoreEvents:NAME_PLATE_UNIT_ADDED(...)
		local unitid = ...
		local plate = GetNamePlateForUnit(unitid);
		
		-- Ignore if plate is Personal Display
		if plate and not UnitIsUnit("player", unitid) then
			local children = plate:GetChildren()
			if children then children:Hide() end --Avoids errors incase the plate has no children
	 		OnShowNameplate(plate, unitid)
	 	end
	end

	function CoreEvents:NAME_PLATE_UNIT_REMOVED(...)
		local unitid = ...
		local plate = GetNamePlateForUnit(unitid);

		OnHideNameplate(plate, unitid)
	end

	function CoreEvents:PLAYER_TARGET_CHANGED()
		HasTarget = UnitExists("target") == true;
		SetUpdateAll()
	end

	function CoreEvents:UNIT_HEALTH(...)
		if FrequentHealthUpdate then return end
		local unitid = ...
		local plate = PlatesByUnit[unitid]

		if plate then OnHealthUpdate(plate) end
	end

	function CoreEvents:UNIT_HEALTH_FREQUENT(...)
		if not FrequentHealthUpdate then return end
		local unitid = ...
		local plate = PlatesByUnit[unitid]

		if plate then OnHealthUpdate(plate) end
	end

	function CoreEvents:PLAYER_REGEN_ENABLED()
		InCombat = false
		SetUpdateAll()
	end

	function CoreEvents:PLAYER_REGEN_DISABLED()
		InCombat = true
		SetUpdateAll()
	end

	function CoreEvents:DISPLAY_SIZE_CHANGED()
		SetUpdateAll()
	end

	function CoreEvents:UPDATE_MOUSEOVER_UNIT(...)
		if UnitExists("mouseover") then
			HasMouseover = true
			SetUpdateAll()
		end
	end

	function CoreEvents:UNIT_SPELLCAST_START(...)
		local unitid = ...
		if UnitIsUnit("player", unitid) or not ShowCastBars then return end

		local plate = GetNamePlateForUnit(unitid)

		if plate then
			OnStartCasting(plate, unitid, false)
		end
	end


	 function CoreEvents:UNIT_SPELLCAST_STOP(...)
		local unitid = ...
		if UnitIsUnit("player", unitid) or not ShowCastBars then return end

		local plate = GetNamePlateForUnit(unitid)

		if plate then
			OnStopCasting(plate)
		end
	 end

	function CoreEvents:UNIT_SPELLCAST_CHANNEL_START(...)
		local unitid = ...
		if UnitIsUnit("player", unitid) or not ShowCastBars then return end

		local plate = GetNamePlateForUnit(unitid)

		if plate then
			OnStartCasting(plate, unitid, true)
		end
	end

	function CoreEvents:UNIT_SPELLCAST_CHANNEL_STOP(...)
		local unitid = ...
		if UnitIsUnit("player", unitid) or not ShowCastBars then return end

		local plate = GetNamePlateForUnit(unitid)
		if plate then
			OnStopCasting(plate)
		end
	end

	function CoreEvents:COMBAT_LOG_EVENT_UNFILTERED(...)
		local _,event,_,sourceGUID,sourceName,sourceFlags,_,destGUID,destName,_,_,spellID = CombatLogGetCurrentEventInfo()
		spellID = spellID or ""
		local plate = nil
		local ownerGUID

		-- Spell Interrupts
		if ShowIntCast then
			if event == "SPELL_INTERRUPT" or event == "SPELL_AURA_APPLIED" or event == "SPELL_CAST_FAILED" then
				-- With "SPELL_AURA_APPLIED" we are looking for stuns etc. that were applied.
				-- As the "SPELL_INTERRUPT" event doesn't get logged for those types of interrupts, but does trigger a "UNIT_SPELLCAST_INTERRUPTED" event.
				-- "SPELL_CAST_FAILED" is for when the unit themselves interrupt the cast.
				plate = PlatesByGUID[destGUID]

				if plate then
					if (event == "SPELL_AURA_APPLIED" or event == "SPELL_CAST_FAILED") and (not plate.extended.unit.interrupted or plate.extended.unit.interruptLogged) then return end
					local unitType = strsplit("-", sourceGUID)
					-- If a pet interrupted, we need to change the source from the pet to the owner
					if unitType == "Pet" then
							ownerGUID, sourceName = GetPetOwner(sourceName)
					end

					plate.extended.unit.interruptLogged = true
					OnInterruptedCast(plate, ownerGUID or sourceGUID, sourceName, destGUID)
				end
			end
		end

		-- Fixate
		local fixate = {
			[268074] = true,	-- Spawn of G'huun(Uldir)
			[282209] = true,	-- Ravenous Stalker(Dazar'alor)
		}
		if (event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REMOVED") and fixate[spellID] then
			plate = PlatesByGUID[sourceGUID]
			if plate and event == "SPELL_AURA_APPLIED" and UnitIsUnit("player", destName) then
				plate.extended.unit.fixate = true 	-- Fixating player
			elseif plate then
				plate.extended.unit.fixate = false 	-- NOT Fixating player
			end
		end

		-- Aura Base Duration Modifier
		-- Might not be necessary to do it this way, commented for now
		--if true then
		--	local current = {CombatLogGetCurrentEventInfo()}
		--	local _,event,_,sourceGUID,sourceName,sourceFlags,_,destGUID,destName,_,_,spellID = CombatLogGetCurrentEventInfo()
		--	plate = PlatesByGUID[destGUID] or {}
		--	plate.auraBaseMod = plate.auraBaseMod or {}

		--	if event == "SPELL_AURA_APPLIED" then
		--		plate.auraBaseMod[spellID] = 1
		--	elseif event == "SPELL_AURA_REFRESH" then
		--		plate.auraBaseMod[spellID] = 1.3
		--	end
		--	--if event == "SPELL_AURA_APPLIED" and UnitIsUnit("player", sourceName) then print(GetSpellDescription(spellID));for i=1, #current,1 do print(i, current[i]) end elseif event == "SPELL_AURA_REFRESH" and UnitIsUnit("player", sourceName) then print("Spell was resfhred") end
		--end
		
	end

	CoreEvents.UNIT_SPELLCAST_INTERRUPTED = UnitSpellcastInterrupted
	--CoreEvents.UNIT_SPELLCAST_FAILED = UnitSpellcastInterrupted

	CoreEvents.UNIT_SPELLCAST_DELAYED = UnitSpellcastMidway
	CoreEvents.UNIT_SPELLCAST_CHANNEL_UPDATE = UnitSpellcastMidway
	CoreEvents.UNIT_SPELLCAST_INTERRUPTIBLE = UnitSpellcastMidway
	CoreEvents.UNIT_SPELLCAST_NOT_INTERRUPTIBLE = UnitSpellcastMidway

	CoreEvents.UNIT_LEVEL = UnitConditionChanged
	CoreEvents.UNIT_THREAT_SITUATION_UPDATE = UnitConditionChanged
	CoreEvents.UNIT_FACTION = UnitConditionChanged

	CoreEvents.RAID_TARGET_UPDATE = WorldConditionChanged
	CoreEvents.PLAYER_FOCUS_CHANGED = WorldConditionChanged
	CoreEvents.PLAYER_CONTROL_LOST = WorldConditionChanged
	CoreEvents.PLAYER_CONTROL_GAINED = WorldConditionChanged

	-- Registration of Blizzard Events
	NeatPlatesCore:SetFrameStrata("TOOLTIP") 	-- When parented to WorldFrame, causes OnUpdate handler to run close to last
	NeatPlatesCore:SetScript("OnEvent", EventHandler)
	for eventName in pairs(CoreEvents) do NeatPlatesCore:RegisterEvent(eventName) end
end




---------------------------------------------------------------------------------------------------------------------
--  Nameplate Styler: These functions parses the definition table for a nameplate's requested style.
---------------------------------------------------------------------------------------------------------------------
do
	-- Helper Functions
	local function SetObjectShape(object, width, height) object:SetWidth(width); object:SetHeight(height) end
	local function SetObjectJustify(object, horz, vert) object:SetJustifyH(horz); object:SetJustifyV(vert) end
	local function SetObjectAnchor(object, anchor, anchorTo, x, y) object:ClearAllPoints();object:SetPoint(anchor, anchorTo, anchor, x, y) end
	local function SetObjectTexture(object, texture) object:SetTexture(texture) end
	local function SetObjectBartexture(obj, tex, ori, crop) obj:SetStatusBarTexture(tex); obj:SetOrientation(ori); end

	local function SetObjectFont(object,  font, size, flags)
		if OverrideOutline == 2 then flags = "NONE" elseif OverrideOutline == 3 then flags = "OUTLINE" elseif OverrideOutline == 4 then flags = "THICKOUTLINE" end
		if (not OverrideFonts) and font then
			object:SetFont(font, size or 10, flags)
		--else
		--	object:SetFontObject("SpellFont_Small")
		end
	end --FRIZQT__ or ARIALN.ttf  -- object:SetFont("FONTS\\FRIZQT__.TTF", size or 12, flags)


	-- SetObjectShadow:
	local function SetObjectShadow(object, shadow)
		if shadow then
			object:SetShadowColor(0,0,0, 1)
			object:SetShadowOffset(1, -1)
		else object:SetShadowColor(0,0,0,0) end
	end

	-- SetFontGroupObject
	local function SetFontGroupObject(object, objectstyle)
		if objectstyle then
			SetObjectFont(object, objectstyle.typeface, objectstyle.size, objectstyle.flags)
			SetObjectJustify(object, objectstyle.align or "CENTER", objectstyle.vertical or "BOTTOM")
			SetObjectShadow(object, objectstyle.shadow)
		end
	end

	-- SetAnchorGroupObject
	local function SetAnchorGroupObject(object, objectstyle, anchorTo, offset)
		if objectstyle and anchorTo then
			SetObjectShape(object, objectstyle.width or 128, objectstyle.height or 16)
			SetObjectAnchor(object, objectstyle.anchor or "CENTER", anchorTo, objectstyle.x or 0, (objectstyle.y or 0) + (offset or 0))
		end
	end

	-- SetTextureGroupObject
	local function SetTextureGroupObject(object, objectstyle)
		if objectstyle then
			if objectstyle.texture then SetObjectTexture(object, objectstyle.texture or EMPTY_TEXTURE) end
			object:SetTexCoord(objectstyle.left or 0, objectstyle.right or 1, objectstyle.top or 0, objectstyle.bottom or 1)
		end
	end


	-- SetBarGroupObject
	local function SetBarGroupObject(object, objectstyle, anchorTo)
		if objectstyle then
			SetAnchorGroupObject(object, objectstyle, anchorTo)
			SetObjectBartexture(object, objectstyle.texture or EMPTY_TEXTURE, objectstyle.orientation or "HORIZONTAL")
			if objectstyle.backdrop then
				object:SetBackdropTexture(objectstyle.backdrop)
			end
			object:SetTexCoord(objectstyle.left, objectstyle.right, objectstyle.top, objectstyle.bottom)
		end
	end


	-- Style Groups
	local fontgroup = {"name", "subtext", "level", "extratext", "spelltext", "durationtext", "customtext"}

	local anchorgroup = {"healthborder", "threatborder", "castborder", "castnostop",
						"name", "subtext", "extraborder", "extratext", "spelltext", "durationtext", "customtext", "level",
						"spellicon", "raidicon", "skullicon", "eliteicon", "target", "focus", "mouseover"}

	local bargroup = {"castbar", "healthbar", "extrabar"}

	local texturegroup = { "extraborder", "castborder", "castnostop", "healthborder", "threatborder", "eliteicon",
						"skullicon", "highlight", "target", "focus", "mouseover", "spellicon", }


	-- UpdateStyle:
	function UpdateStyle()
		local index, unitSubtext, unitPlateStyle
		local useYOffset = (style.subtext.show and activetheme.SetSubText(unit) and NeatPlatesHubFunctions.SetStyleNamed(unit) == "Default")
		if useYOffset then extended.widgets["AuraWidgetHub"]:UpdateOffset(0, style.subtext.yOffset) end 	-- Update AuraWidget position if 'subtext' is displayed

		-- Frame
		SetAnchorGroupObject(extended, style.frame, carrier)

		-- Anchorgroup
		for index = 1, #anchorgroup do

			local objectname = anchorgroup[index]
			local object, objectstyle = visual[objectname], style[objectname]
			if objectstyle and objectstyle.show then
				local offset
				if useYOffset and (objectname == "name" or objectname == "subtext") then offset = style.subtext.yOffset end -- Subtext offset

				SetAnchorGroupObject(object, objectstyle, extended, offset)
				visual[objectname]:Show()
			else visual[objectname]:Hide() end
		end
		-- Bars
		for index = 1, #bargroup do
			local objectname = bargroup[index]
			local object, objectstyle = visual[objectname], style[objectname]
			if objectstyle then SetBarGroupObject(object, objectstyle, extended) end
		end
		-- Texture
		for index = 1, #texturegroup do
			local objectname = texturegroup[index]
			local object, objectstyle = visual[objectname], style[objectname]
			SetTextureGroupObject(object, objectstyle)
		end
		-- Raid Icon Texture
		if style and style.raidicon and style.raidicon.texture then
			visual.raidicon:SetTexture(style.raidicon.texture)
		end
		if style and style.healthbar.texture == EMPTY_TEXTURE then visual.noHealthbar = true end
		-- Font Group
		for index = 1, #fontgroup do
			local objectname = fontgroup[index]
			local object, objectstyle = visual[objectname], style[objectname]
			SetFontGroupObject(object, objectstyle)
		end
		-- Hide Stuff
		if not unit.isElite and not unit.isRare then visual.eliteicon:Hide() end
		if not unit.isBoss then visual.skullicon:Hide() end

		if not unit.isTarget then visual.target:Hide() end
		if not unit.isFocus then visual.focus:Hide() end
		if not unit.isMouseover then visual.mouseover:Hide() end
		if not unit.isMarked then visual.raidicon:Hide() end

	end

end

--------------------------------------------------------------------------------------------------------------
-- Theme Handling
--------------------------------------------------------------------------------------------------------------
local function UseTheme(theme)
	if theme and type(theme) == 'table' and not theme.IsShown then
		activetheme = theme 						-- Store a local copy
		ResetPlates = true
	end
end

NeatPlatesInternal.UseTheme = UseTheme

local function GetTheme()
	return activetheme
end

local function GetThemeName()
	return NeatPlatesOptions.ActiveTheme
end

NeatPlates.GetTheme = GetTheme
NeatPlates.GetThemeName = GetThemeName


--------------------------------------------------------------------------------------------------------------
-- Misc. Utility
--------------------------------------------------------------------------------------------------------------
local function OnResetWidgets(plate)
	-- At some point, we're going to have to manage the widgets a bit better.

	local extended = plate.extended
	local widgets = extended.widgets

	for widgetName, widgetFrame in pairs(widgets) do
		widgetFrame:Hide()
		--widgets[widgetName] = nil			-- Nilling the frames may cause leakiness.. or at least garbage collection
	end

	plate.UpdateMe = true
end

--------------------------------------------------------------------------------------------------------------
-- External Commands: Allows widgets and themes to request updates to the plates.
-- Useful to make a theme respond to externally-captured data (such as the combat log)
--------------------------------------------------------------------------------------------------------------
function NeatPlates:DisableCastBars() ShowCastBars = false end
function NeatPlates:EnableCastBars() ShowCastBars = true end

function NeatPlates:SetHealthUpdateMethod(useFrequent) FrequentHealthUpdate = useFrequent end
function NeatPlates:SetCoreVariables(LocalVars)
	ShowIntCast = LocalVars.IntCastEnable
	ShowIntWhoCast = LocalVars.IntCastWhoEnable
	ShowServerIndicator = LocalVars.TextShowServerIndicator
end

function NeatPlates:ShowNameplateSize(show, width, height) ForEachPlate(function(plate) UpdateNameplateSize(plate, show, width, height) end) end

function NeatPlates:ForceUpdate() ForEachPlate(OnResetNameplate) end
function NeatPlates:ResetWidgets() ForEachPlate(OnResetWidgets) end
function NeatPlates:Update() SetUpdateAll() end

function NeatPlates:RequestUpdate(plate) if plate then SetUpdateMe(plate) else SetUpdateAll() end end

function NeatPlates:ActivateTheme(theme) if theme and type(theme) == 'table' then NeatPlates.ActiveThemeTable, activetheme = theme, theme; ResetPlates = true; end end
function NeatPlates.OverrideFonts(enable) OverrideFonts = enable; end
function NeatPlates.OverrideOutline(enable) OverrideOutline = enable; end

function NeatPlates.UpdateNameplateSize() UpdateNameplateSize() end

-- Old and needing deleting - Just here to avoid errors
function NeatPlates:EnableFadeIn() EnableFadeIn = true; end
function NeatPlates:DisableFadeIn() EnableFadeIn = nil; end
NeatPlates.RequestWidgetUpdate = NeatPlates.RequestUpdate
NeatPlates.RequestDelegateUpdate = NeatPlates.RequestUpdate







