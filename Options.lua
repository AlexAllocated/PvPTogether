local PvPTogether = _G.PvPTogether

if not PvPTogether then
	return
end

PvPTogether.optionControls = PvPTogether.optionControls or {}
local INHERIT_STYLE_DROPDOWN_VALUE = "__pvptogether_inherit_style__"
local INHERIT_STYLE_SELECTED_LABEL = "Inherit From Global"
local INHERIT_STYLE_MENU_LABEL = "Inherit From Global Setting"
local STYLE_MODERN = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Modern or 0
local STYLE_THIN = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Thin or 1
local STYLE_BLOCK = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Block or 2
local STYLE_HEALTH_FOCUS = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.HealthFocus or 3
local STYLE_CAST_FOCUS = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.CastFocus or 4
local STYLE_LEGACY = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Legacy or 5
local PREVIEW_LEFT = 360
local PREVIEW_FRAME_WIDTH = 250
local PREVIEW_FRAME_HEIGHT = 92
local PREVIEW_BAR_WIDTH = 170
local PREVIEW_NAME_BLOCK_HEIGHT = 20
local PREVIEW_NAME_TO_BAR_GAP = 2
local PREVIEW_DEFAULT_BORDER_ALPHA = 0.22
local PREVIEW_OVERRIDE_BORDER_ALPHA = 1.0

local PREVIEW_STYLE_LAYOUTS = {
	[STYLE_MODERN] = {
		nameInsideHealthBar = true,
		healthBarHeight = 18,
	},
	[STYLE_THIN] = {
		nameInsideHealthBar = false,
		healthBarHeight = 8,
	},
	[STYLE_BLOCK] = {
		nameInsideHealthBar = true,
		healthBarHeight = 18,
	},
	[STYLE_HEALTH_FOCUS] = {
		nameInsideHealthBar = false,
		healthBarHeight = 18,
	},
	[STYLE_CAST_FOCUS] = {
		nameInsideHealthBar = false,
		healthBarHeight = 8,
	},
	[STYLE_LEGACY] = {
		nameInsideHealthBar = false,
		healthBarHeight = 8,
	},
}

local PREVIEW_NAME_BY_UNIT_KIND = {
	partyMember = "Party Member",
	friendlyPlayer = "Friendly Player",
	enemyPlayer = "Enemy Player",
}
local PREVIEW_FALLBACK_CLASS_COLORS = {
	{ r = 0.78, g = 0.61, b = 0.43, className = "Warrior" },
	{ r = 1.00, g = 0.49, b = 0.04, className = "Druid" },
	{ r = 0.41, g = 0.80, b = 0.94, className = "Mage" },
	{ r = 0.96, g = 0.55, b = 0.73, className = "Paladin" },
	{ r = 0.67, g = 0.83, b = 0.45, className = "Hunter" },
	{ r = 0.00, g = 0.44, b = 0.87, className = "Shaman" },
	{ r = 0.58, g = 0.51, b = 0.79, className = "Warlock" },
	{ r = 1.00, g = 1.00, b = 1.00, className = "Priest" },
	{ r = 1.00, g = 0.96, b = 0.41, className = "Rogue" },
	{ r = 0.77, g = 0.12, b = 0.23, className = "Death Knight" },
	{ r = 0.00, g = 1.00, b = 0.60, className = "Monk" },
	{ r = 0.64, g = 0.19, b = 0.79, className = "Demon Hunter" },
	{ r = 0.20, g = 0.58, b = 0.50, className = "Evoker" },
}

local previewClassColorPool = nil

local function GetLocalizedClassName(classToken, fallback)
	if type(classToken) ~= "string" or not PvPTogether:CanAccessValue(classToken) or classToken == "" then
		return fallback
	end

	local localizedClassName = nil
	localizedClassName = PvPTogether:SafeGetField(LOCALIZED_CLASS_NAMES_MALE, classToken)
	if type(localizedClassName) ~= "string" or localizedClassName == "" then
		localizedClassName = PvPTogether:SafeGetField(LOCALIZED_CLASS_NAMES_FEMALE, classToken)
	end
	if type(localizedClassName) == "string" and localizedClassName ~= "" then
		return localizedClassName
	end
	return fallback
end

local function BuildPreviewClassColorPool()
	local pool = {}

	local function AddColor(red, green, blue, className)
		local r = PvPTogether:SafeToNumber(red)
		local g = PvPTogether:SafeToNumber(green)
		local b = PvPTogether:SafeToNumber(blue)
		if r == nil or g == nil or b == nil then
			return
		end
		if r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then
			return
		end
		pool[#pool + 1] = {
			r = r,
			g = g,
			b = b,
			className = PvPTogether:SafeToString(className, "Player"),
		}
	end

	local function AddClassColorByToken(classToken)
		if type(classToken) ~= "string" or not PvPTogether:CanAccessValue(classToken) or classToken == "" then
			return
		end

		local className = GetLocalizedClassName(classToken, nil)
		if type(className) ~= "string" or className == "" then
			return
		end

		local classColor = PvPTogether:SafeGetField(RAID_CLASS_COLORS, classToken)
		if PvPTogether:CanAccessTable(classColor) then
			AddColor(
				PvPTogether:SafeGetField(classColor, "r"),
				PvPTogether:SafeGetField(classColor, "g"),
				PvPTogether:SafeGetField(classColor, "b"),
				className
			)
			return
		end

		if C_ClassColor and type(C_ClassColor.GetClassColor) == "function" then
			local ok, color = pcall(C_ClassColor.GetClassColor, classToken)
			classColor = ok and color or nil
			if PvPTogether:CanAccessTable(classColor) then
				local red = PvPTogether:SafeGetField(classColor, "r")
				local green = PvPTogether:SafeGetField(classColor, "g")
				local blue = PvPTogether:SafeGetField(classColor, "b")
				local getRGB = PvPTogether:SafeGetField(classColor, "GetRGB")
				if type(getRGB) == "function" then
					local okColor, r, g, b = pcall(getRGB, classColor)
					if okColor then
						red, green, blue = r, g, b
					end
				end
				AddColor(red, green, blue, className)
			end
		end
	end

	if PvPTogether:CanAccessTable(CLASS_SORT_ORDER) then
		for _, classToken in ipairs(CLASS_SORT_ORDER) do
			AddClassColorByToken(classToken)
		end
	end

	if #pool == 0 and PvPTogether:CanAccessTable(RAID_CLASS_COLORS) then
		for classToken in pairs(RAID_CLASS_COLORS) do
			AddClassColorByToken(classToken)
		end
	end

	if #pool == 0 then
		for _, classColor in ipairs(PREVIEW_FALLBACK_CLASS_COLORS) do
			AddColor(classColor.r, classColor.g, classColor.b, classColor.className)
		end
	end

	return pool
end

local function GetRandomPreviewClassInfo()
	if type(previewClassColorPool) ~= "table" or #previewClassColorPool == 0 then
		previewClassColorPool = BuildPreviewClassColorPool()
	end

	if type(previewClassColorPool) ~= "table" or #previewClassColorPool == 0 then
		return {
			r = 0.22,
			g = 0.80,
			b = 0.22,
			className = "Player",
		}
	end

	local randomIndex = math.random(1, #previewClassColorPool)
	local randomInfo = previewClassColorPool[randomIndex]
	return {
		r = randomInfo.r,
		g = randomInfo.g,
		b = randomInfo.b,
		className = randomInfo.className,
	}
end

local function AssignRandomClassInfoToPreview(previewFrame)
	if type(previewFrame) ~= "table" then
		return
	end

	local randomClassInfo = GetRandomPreviewClassInfo()
	previewFrame.HealthColor = {
		r = randomClassInfo.r,
		g = randomClassInfo.g,
		b = randomClassInfo.b,
	}
	previewFrame.HealthClassName = randomClassInfo.className
end

local function IsFrameForbidden(frame)
	local method, readable = PvPTogether:SafeGetField(frame, "IsForbidden")
	if not readable then
		return true
	end
	if type(method) ~= "function" then
		return false
	end

	local ok, isForbidden = pcall(method, frame)
	return not ok or PvPTogether:SafeToBoolean(isForbidden) ~= false
end

local function IsFrameMutable(frame)
	return PvPTogether:CanAccessValue(frame) and frame ~= nil and not IsFrameForbidden(frame)
end

local function SetTextureTint(texture, red, green, blue, alpha)
	if not IsFrameMutable(texture) then
		return
	end

	if texture.SetVertexColor then
		texture:SetVertexColor(red, green, blue, alpha)
	elseif texture.SetColorTexture then
		texture:SetColorTexture(red, green, blue, alpha)
	end
end

local function AnchorPreviewFillTexture(texture, healthBar)
	if not IsFrameMutable(texture) or not IsFrameMutable(healthBar) then
		return
	end

	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 1)
	texture:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, -1)
end

local function GetPreviewLayoutForStyle(styleValue)
	return PREVIEW_STYLE_LAYOUTS[styleValue] or PREVIEW_STYLE_LAYOUTS[STYLE_MODERN]
end

local function SetPreviewAtlas(texture, atlas)
	if type(texture.SetAtlas) ~= "function" or not (C_Texture and type(C_Texture.GetAtlasInfo) == "function") then
		return false
	end
	local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
	if not ok or not PvPTogether:CanAccessTable(info) then
		return false
	end
	texture:SetAtlas(atlas, true)
	return true
end

local function CreateNameplatePreview(parent, x, y)
	local previewFrame = CreateFrame("Frame", nil, parent)
	previewFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	previewFrame:SetSize(PREVIEW_FRAME_WIDTH, PREVIEW_FRAME_HEIGHT)

	local background = previewFrame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.82)
	previewFrame.Background = background

	local outerBorder = previewFrame:CreateTexture(nil, "BORDER")
	outerBorder:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 0, 0)
	outerBorder:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", 0, 0)
	outerBorder:SetColorTexture(0, 0, 0, 0.24)
	previewFrame.OuterBorder = outerBorder

	local plateFrame = CreateFrame("Frame", nil, previewFrame)
	plateFrame:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)
	plateFrame:SetSize(PREVIEW_BAR_WIDTH, 62)
	previewFrame.PlateFrame = plateFrame

	local healthContainer = CreateFrame("Frame", nil, plateFrame)
	healthContainer:SetPoint("CENTER", plateFrame, "CENTER", 0, 0)
	healthContainer:SetSize(PREVIEW_BAR_WIDTH, 18)
	previewFrame.HealthContainer = healthContainer

	local textOverlay = CreateFrame("Frame", nil, plateFrame)
	textOverlay:SetAllPoints(plateFrame)
	textOverlay:SetFrameStrata(plateFrame:GetFrameStrata() or "LOW")
	local overlayBaseLevel = healthContainer.GetFrameLevel and healthContainer:GetFrameLevel() or 0
	if type(overlayBaseLevel) ~= "number" then
		overlayBaseLevel = 0
	end
	textOverlay:SetFrameLevel(overlayBaseLevel + 20)
	previewFrame.TextOverlay = textOverlay

	local healthBar = CreateFrame("StatusBar", nil, healthContainer)
	healthBar:SetAllPoints()
	healthBar:SetMinMaxValues(0, 100)
	healthBar:SetValue(100)
	healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	healthBar:SetStatusBarColor(0, 0, 0, 0)
	previewFrame.HealthBar = healthBar

	local healthBarBackground = healthBar:CreateTexture(nil, "BACKGROUND")
	healthBarBackground:SetPoint("TOPLEFT", healthBar, "TOPLEFT", -2, 3)
	healthBarBackground:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 6, -6)
	if not SetPreviewAtlas(healthBarBackground, "UI-HUD-CoolDownManager-Bar-BG") then
		healthBarBackground:SetColorTexture(0.10, 0.10, 0.10, 0.82)
	end
	previewFrame.HealthBarBackground = healthBarBackground

	local baseFill = healthBar:CreateTexture(nil, "ARTWORK", nil, 0)
	if not SetPreviewAtlas(baseFill, "UI-HUD-CoolDownManager-Bar") then
		baseFill:SetTexture("Interface\\Buttons\\WHITE8X8")
	end
	AnchorPreviewFillTexture(baseFill, healthBar)
	AssignRandomClassInfoToPreview(previewFrame)
	SetTextureTint(baseFill, previewFrame.HealthColor.r, previewFrame.HealthColor.g, previewFrame.HealthColor.b, 1.0)
	previewFrame.HealthFill = baseFill

	local selectedBorder = healthBar:CreateTexture(nil, "OVERLAY", nil, 4)
	if not SetPreviewAtlas(selectedBorder, "UI-HUD-Nameplates-Selected") then
		selectedBorder:SetColorTexture(0.95, 0.95, 0.95, PREVIEW_DEFAULT_BORDER_ALPHA)
	end
	selectedBorder:SetPoint("TOPLEFT", healthBarBackground, "TOPLEFT", -1, 1)
	selectedBorder:SetPoint("BOTTOMRIGHT", healthBarBackground, "BOTTOMRIGHT", -3, 3)
	previewFrame.BorderTexture = selectedBorder

	local nameLabel = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	if nameLabel.SetDrawLayer then
		nameLabel:SetDrawLayer("OVERLAY", 7)
	end
	nameLabel:SetJustifyH("LEFT")
	if nameLabel.SetWordWrap then
		nameLabel:SetWordWrap(false)
	end
	if nameLabel.SetMaxLines then
		nameLabel:SetMaxLines(1)
	end
	nameLabel:SetText("Player")
	previewFrame.NameLabel = nameLabel

	return previewFrame
end

local function RefreshNameplatePreview(previewFrame, unitKind, styleValue, borderEnabled, borderColor, addonEnabled)
	if type(previewFrame) ~= "table" then
		return
	end

	local layout = GetPreviewLayoutForStyle(styleValue)
	local plateFrame = previewFrame.PlateFrame
	local healthContainer = previewFrame.HealthContainer
	local textOverlay = previewFrame.TextOverlay
	local nameLabel = previewFrame.NameLabel
	local healthFill = previewFrame.HealthFill
	local borderTexture = previewFrame.BorderTexture

	if
		not IsFrameMutable(plateFrame)
		or not IsFrameMutable(healthContainer)
		or not IsFrameMutable(textOverlay)
		or not IsFrameMutable(nameLabel)
		or not IsFrameMutable(borderTexture)
	then
		return
	end

	local normalizedColor = borderColor
	if type(normalizedColor) ~= "table" then
		normalizedColor = { r = 1.0, g = 1.0, b = 1.0 }
	end
	local previewHealthColor = previewFrame.HealthColor
	if type(previewHealthColor) ~= "table" then
		local fallbackClassInfo = GetRandomPreviewClassInfo()
		previewHealthColor = {
			r = fallbackClassInfo.r,
			g = fallbackClassInfo.g,
			b = fallbackClassInfo.b,
		}
		previewFrame.HealthColor = previewHealthColor
		previewFrame.HealthClassName = fallbackClassInfo.className
	end
	local previewClassName = previewFrame.HealthClassName
	if type(previewClassName) ~= "string" or previewClassName == "" then
		previewClassName = "Player"
	end
	local previewName = PREVIEW_NAME_BY_UNIT_KIND[unitKind] or "Player"
	if unitKind == "partyMember" then
		previewName = "Party " .. previewClassName
	elseif unitKind == "friendlyPlayer" then
		previewName = "Friendly " .. previewClassName
	elseif unitKind == "enemyPlayer" then
		previewName = "Enemy " .. previewClassName
	end
	nameLabel:SetText(previewName)

	local contentHeight = layout.healthBarHeight
	if not layout.nameInsideHealthBar then
		contentHeight = layout.healthBarHeight + PREVIEW_NAME_TO_BAR_GAP + PREVIEW_NAME_BLOCK_HEIGHT
	end
	plateFrame:ClearAllPoints()
	plateFrame:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)
	plateFrame:SetSize(PREVIEW_BAR_WIDTH, contentHeight)

	healthContainer:ClearAllPoints()
	if layout.nameInsideHealthBar then
		healthContainer:SetPoint("CENTER", plateFrame, "CENTER", 0, 0)
	else
		healthContainer:SetPoint("BOTTOM", plateFrame, "BOTTOM", 0, 0)
	end
	healthContainer:SetSize(PREVIEW_BAR_WIDTH, layout.healthBarHeight)
	if textOverlay.SetFrameLevel and healthContainer.GetFrameLevel then
		local dynamicOverlayBaseLevel = healthContainer:GetFrameLevel()
		if type(dynamicOverlayBaseLevel) == "number" then
			textOverlay:SetFrameLevel(dynamicOverlayBaseLevel + 20)
		end
	end

	nameLabel:ClearAllPoints()

	if layout.nameInsideHealthBar then
		nameLabel:SetPoint("LEFT", healthContainer, "LEFT", 6, 0)
		nameLabel:SetPoint("RIGHT", healthContainer, "RIGHT", -6, 0)
	else
		nameLabel:SetPoint("BOTTOMLEFT", healthContainer, "TOPLEFT", 6, PREVIEW_NAME_TO_BAR_GAP)
		nameLabel:SetPoint("BOTTOMRIGHT", healthContainer, "TOPRIGHT", -6, PREVIEW_NAME_TO_BAR_GAP)
	end

	-- These previews illustrate geometry. Native name coloring is global and
	-- cannot safely become a per-unit-style override.
	if nameLabel.SetTextColor then
		nameLabel:SetTextColor(1, 1, 1, 1)
	end

	if IsFrameMutable(healthFill) then
		SetTextureTint(healthFill, previewHealthColor.r, previewHealthColor.g, previewHealthColor.b, 1.0)
	end

	local borderAlpha = borderEnabled and PREVIEW_OVERRIDE_BORDER_ALPHA or PREVIEW_DEFAULT_BORDER_ALPHA
	SetTextureTint(borderTexture, normalizedColor.r, normalizedColor.g, normalizedColor.b, borderAlpha)

	previewFrame:SetAlpha(addonEnabled and 1 or 0.5)
end

local function GetStyleDropdownLabel(optionKey)
	local configuredStyle = PvPTogether:GetOption(optionKey)
	if PvPTogether:IsNameplateStyle(configuredStyle) then
		return PvPTogether:GetNameplateStyleLabel(configuredStyle), configuredStyle
	end

	return INHERIT_STYLE_SELECTED_LABEL, INHERIT_STYLE_DROPDOWN_VALUE
end

local function CreateCheckbox(parent, optionKey, labelText, tooltipText, x, y)
	local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
	label:SetText(labelText)
	checkbox.Label = label

	if type(tooltipText) == "string" and tooltipText ~= "" then
		checkbox.tooltipText = tooltipText
	end

	checkbox:SetScript("OnClick", function(self)
		PvPTogether:SetOption(optionKey, self:GetChecked() == true)
	end)

	return checkbox
end

local function CreateDropdown(parent, titleText, tooltipText, x, y, width, initializeMenu)
	-- Use the supported menu API instead of the shared legacy dropdown globals.
	if type(DropdownButtonMixin) ~= "table" then
		return nil
	end

	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	title:SetText(titleText)

	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	dropdown.title = title
	dropdown.tooltipText = tooltipText

	dropdown:SetWidth(width or 200)
	dropdown:SetupMenu(initializeMenu)
	return dropdown
end

local function CreateStyleDropdown(parent, titleText, tooltipText, x, y, optionKey)
	return CreateDropdown(parent, titleText, tooltipText, x, y, 220, function(_, rootDescription)
		local function IsSelected(styleValue)
			if styleValue == INHERIT_STYLE_DROPDOWN_VALUE then
				return not PvPTogether:IsNameplateStyle(PvPTogether:GetOption(optionKey))
			end
			return PvPTogether:GetOption(optionKey) == styleValue
		end
		local function SetSelected(styleValue)
			local capabilities = PvPTogether:GetNameplateCapabilities()
			if not PvPTogether.isEnabled or not capabilities.styleOverrides then
				return
			end
			if styleValue == INHERIT_STYLE_DROPDOWN_VALUE then
				PvPTogether:SetOption(optionKey, nil)
			else
				PvPTogether:SetOption(optionKey, styleValue)
			end
		end
		rootDescription:CreateRadio(INHERIT_STYLE_MENU_LABEL, IsSelected, SetSelected, INHERIT_STYLE_DROPDOWN_VALUE)

		for _, styleValue in ipairs(PvPTogether.nameplateStyleOrder) do
			rootDescription:CreateRadio(
				PvPTogether:GetNameplateStyleLabel(styleValue),
				IsSelected,
				SetSelected,
				styleValue
			)
		end
	end)
end

local function ClampColorComponent(value, fallback)
	local numericValue = PvPTogether:SafeToNumber(value)
	if not numericValue then
		return fallback
	end
	if numericValue < 0 then
		return 0
	end
	if numericValue > 1 then
		return 1
	end
	return numericValue
end

local function ColorsNearlyEqual(left, right)
	return math.abs((left or 0) - (right or 0)) < 0.001
end

local function GetColorOption(optionKey, fallbackColor)
	return PvPTogether:NormalizeColorRGB(PvPTogether:GetOption(optionKey), fallbackColor)
end

local function IsColorOptionAtDefault(optionKey, fallbackColor)
	local current = GetColorOption(optionKey, fallbackColor)
	return ColorsNearlyEqual(current.r, fallbackColor.r)
		and ColorsNearlyEqual(current.g, fallbackColor.g)
		and ColorsNearlyEqual(current.b, fallbackColor.b)
end

local function CreateColorSwatch(parent, optionKey, labelText, tooltipText, fallbackColor, x, y)
	local swatchButton = CreateFrame("Button", nil, parent)
	swatchButton:SetSize(22, 22)
	swatchButton:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	local border = swatchButton:CreateTexture(nil, "BORDER")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 1)
	swatchButton.Border = border

	local colorTexture = swatchButton:CreateTexture(nil, "ARTWORK")
	colorTexture:SetPoint("TOPLEFT", swatchButton, "TOPLEFT", 1, -1)
	colorTexture:SetPoint("BOTTOMRIGHT", swatchButton, "BOTTOMRIGHT", -1, 1)
	swatchButton.ColorTexture = colorTexture

	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", swatchButton, "RIGHT", 8, 0)
	label:SetText(labelText)
	swatchButton.Label = label

	if type(tooltipText) == "string" and tooltipText ~= "" then
		swatchButton.tooltipText = tooltipText
	end

	local function SetColorOption(r, g, b)
		PvPTogether:SetOption(optionKey, {
			r = ClampColorComponent(r, fallbackColor.r),
			g = ClampColorComponent(g, fallbackColor.g),
			b = ClampColorComponent(b, fallbackColor.b),
		})
	end

	swatchButton:SetScript("OnClick", function()
		if not PvPTogether.isEnabled or not PvPTogether:GetNameplateCapabilities().borderTint then
			return
		end
		if PvPTogether:IsInCombatLockdown() then
			PvPTogether:Print("Open the color picker after combat.")
			return
		end
		local picker = ColorPickerFrame
		if not IsFrameMutable(picker) then
			PvPTogether:Print("Color picker is unavailable right now.")
			return
		end
		local setup = PvPTogether:SafeGetField(picker, "SetupColorPickerAndShow")
		local readColor = PvPTogether:SafeGetField(picker, "GetColorRGB")
		if type(setup) ~= "function" or type(readColor) ~= "function" then
			PvPTogether:Print("Color picker is unavailable right now.")
			return
		end
		PvPTogether:InvalidateOptionsCallbacks()
		local generation = PvPTogether.optionsCallbackGeneration
		local database = PvPTogether.db
		local function IsCurrentPicker()
			return generation == PvPTogether.optionsCallbackGeneration
				and database == PvPTogether.db
				and PvPTogether.isEnabled
				and PvPTogether:GetNameplateCapabilities().borderTint
		end

		local currentColor = GetColorOption(optionKey, fallbackColor)
		local previousColor = {
			r = currentColor.r,
			g = currentColor.g,
			b = currentColor.b,
		}

		local info = {}
		info.r = currentColor.r
		info.g = currentColor.g
		info.b = currentColor.b
		info.hasOpacity = false
		info.swatchFunc = function()
			if not IsCurrentPicker() or not IsFrameMutable(picker) then
				return
			end
			local ok, r, g, b = pcall(readColor, picker)
			if ok then
				local red = PvPTogether:SafeToNumber(r)
				local green = PvPTogether:SafeToNumber(g)
				local blue = PvPTogether:SafeToNumber(b)
				if red ~= nil and green ~= nil and blue ~= nil then
					SetColorOption(red, green, blue)
				else
					PvPTogether:RecordDiagnostic("picker-color-unavailable")
				end
			end
		end
		info.cancelFunc = function()
			if IsCurrentPicker() then
				SetColorOption(previousColor.r, previousColor.g, previousColor.b)
				PvPTogether:InvalidateOptionsCallbacks()
			end
		end
		if not pcall(setup, picker, info) then
			PvPTogether:InvalidateOptionsCallbacks()
			PvPTogether:Print("Color picker is unavailable right now.")
		end
	end)

	return swatchButton
end

local function RefreshDropdownControl(dropdown, labelText)
	if not dropdown then
		return
	end

	dropdown:OverrideText(labelText)
	dropdown:Update()
end

local function SetDropdownEnabled(dropdown, enabled)
	if not dropdown then
		return
	end

	dropdown:SetEnabled(enabled)
	if not enabled and dropdown.CloseMenu then
		dropdown:CloseMenu()
	end

	dropdown:SetAlpha(enabled and 1 or 0.5)
	if dropdown.title then
		dropdown.title:SetAlpha(enabled and 1 or 0.5)
	end
end

local function RefreshColorSwatch(swatch, optionKey, fallbackColor)
	if not swatch or not swatch.ColorTexture then
		return
	end

	local color = GetColorOption(optionKey, fallbackColor)
	swatch.ColorTexture:SetColorTexture(color.r, color.g, color.b, 1)
end

local function SetColorSwatchEnabled(swatch, enabled)
	if not swatch then
		return
	end

	if swatch.SetEnabled then
		swatch:SetEnabled(enabled)
	end

	swatch:SetAlpha(enabled and 1 or 0.5)
	if swatch.Label then
		swatch.Label:SetAlpha(enabled and 1 or 0.5)
	end
	if swatch.ColorTexture then
		swatch.ColorTexture:SetAlpha(enabled and 1 or 0.5)
	end
end

function PvPTogether:RandomizeOptionsPreviewClasses()
	local controls = self.optionControls
	if type(controls) ~= "table" then
		return
	end

	AssignRandomClassInfoToPreview(controls.partyMemberPreview)
	AssignRandomClassInfoToPreview(controls.friendlyPlayerPreview)
	AssignRandomClassInfoToPreview(controls.enemyPlayerPreview)
end

function PvPTogether:StopOptionsPreviewTicker()
	self.optionsPreviewGeneration = (self.optionsPreviewGeneration or 0) + 1
	local ticker = self.optionsPreviewTicker
	self.optionsPreviewTicker = nil
	if ticker and type(ticker.Cancel) == "function" then
		pcall(ticker.Cancel, ticker)
	end
end

function PvPTogether:InvalidateOptionsCallbacks()
	self.optionsCallbackGeneration = (self.optionsCallbackGeneration or 0) + 1
end

function PvPTogether:StartOptionsPreviewTicker()
	self:StopOptionsPreviewTicker()

	if not self.isEnabled or not (self.optionsFrame and self.optionsFrame.IsShown and self.optionsFrame:IsShown()) then
		return
	end
	if not (C_Timer and type(C_Timer.NewTicker) == "function") then
		return
	end

	local generation = self.optionsPreviewGeneration
	self.optionsPreviewTicker = C_Timer.NewTicker(3, function()
		-- Cancellation does not guarantee an already queued callback is gone.
		if generation ~= PvPTogether.optionsPreviewGeneration or not PvPTogether.isEnabled then
			return
		end
		if
			not (PvPTogether.optionsFrame and PvPTogether.optionsFrame.IsShown and PvPTogether.optionsFrame:IsShown())
		then
			PvPTogether:StopOptionsPreviewTicker()
			return
		end
		PvPTogether:RandomizeOptionsPreviewClasses()
		PvPTogether:RefreshOptionsPreviewsOnly()
	end)
end

function PvPTogether:RefreshOptionsPreviewsOnly()
	local controls = self.optionControls or {}
	local capabilities = self.GetNameplateCapabilities and self:GetNameplateCapabilities() or {}
	local enabled = self:GetOption("enabled") == true and capabilities.styleOverrides == true
	local partyStyleValue = self:GetConfiguredStyleForUnitKind("partyMember")
	local friendlyStyleValue = self:GetConfiguredStyleForUnitKind("friendlyPlayer")
	local enemyStyleValue = self:GetConfiguredStyleForUnitKind("enemyPlayer")
	local partyBorderEnabled = self:GetOption("partyMemberBorderEnabled") == true
	local friendlyBorderEnabled = self:GetOption("friendlyPlayerBorderEnabled") == true
	local enemyBorderEnabled = self:GetOption("enemyPlayerBorderEnabled") == true
	local partyBorderColor = self:GetConfiguredBorderColorForUnitKind("partyMember")
	local friendlyBorderColor = self:GetConfiguredBorderColorForUnitKind("friendlyPlayer")
	local enemyBorderColor = self:GetConfiguredBorderColorForUnitKind("enemyPlayer")

	RefreshNameplatePreview(
		controls.partyMemberPreview,
		"partyMember",
		partyStyleValue,
		partyBorderEnabled,
		partyBorderColor,
		enabled
	)
	RefreshNameplatePreview(
		controls.friendlyPlayerPreview,
		"friendlyPlayer",
		friendlyStyleValue,
		friendlyBorderEnabled,
		friendlyBorderColor,
		enabled
	)
	RefreshNameplatePreview(
		controls.enemyPlayerPreview,
		"enemyPlayer",
		enemyStyleValue,
		enemyBorderEnabled,
		enemyBorderColor,
		enabled
	)
end

function PvPTogether:RefreshOptionsWindow()
	-- Context/CVar events also fire while the settings category is hidden.
	if not self.optionsFrame or not self.optionsFrame:IsShown() then
		return
	end
	local controls = self.optionControls or {}
	local enabled = self:GetOption("enabled") == true
	local capabilities = self.GetNameplateCapabilities and self:GetNameplateCapabilities() or {}
	local stylesEnabled = enabled and capabilities.styleOverrides == true
	local bordersEnabled = enabled and capabilities.borderTint == true
	if controls.capabilityStatus then
		local status = capabilities.reason or ""
		if capabilities.styleOverrides and not controls.partyMemberStyle then
			status = "Style selectors are unavailable on this client build."
		end
		if
			enabled
			and self.IsNameplateAugmentationBlockedInCurrentContext
			and self:IsNameplateAugmentationBlockedInCurrentContext()
		then
			status = "Protected or inaccessible nameplates wait until restrictions end."
		end
		controls.capabilityStatus:SetText(status)
	end

	if controls.enabled then
		controls.enabled:SetChecked(enabled)
	end

	local partyStyleLabel, partySelectedValue = GetStyleDropdownLabel("partyMemberStyle")
	local friendlyStyleLabel, friendlySelectedValue = GetStyleDropdownLabel("friendlyPlayerStyle")
	local enemyStyleLabel, enemySelectedValue = GetStyleDropdownLabel("enemyPlayerStyle")
	local partyBorderEnabled = self:GetOption("partyMemberBorderEnabled") == true
	local friendlyBorderEnabled = self:GetOption("friendlyPlayerBorderEnabled") == true
	local enemyBorderEnabled = self:GetOption("enemyPlayerBorderEnabled") == true

	RefreshDropdownControl(controls.partyMemberStyle, partyStyleLabel, partySelectedValue)
	RefreshDropdownControl(controls.friendlyPlayerStyle, friendlyStyleLabel, friendlySelectedValue)
	RefreshDropdownControl(controls.enemyPlayerStyle, enemyStyleLabel, enemySelectedValue)

	SetDropdownEnabled(controls.partyMemberStyle, stylesEnabled)
	SetDropdownEnabled(controls.friendlyPlayerStyle, stylesEnabled)
	SetDropdownEnabled(controls.enemyPlayerStyle, stylesEnabled)

	if controls.partyMemberBorderEnabled then
		controls.partyMemberBorderEnabled:SetChecked(partyBorderEnabled)
		controls.partyMemberBorderEnabled:SetEnabled(bordersEnabled)
		if controls.partyMemberBorderEnabled.Label then
			controls.partyMemberBorderEnabled.Label:SetAlpha(bordersEnabled and 1 or 0.5)
		end
	end
	if controls.friendlyPlayerBorderEnabled then
		controls.friendlyPlayerBorderEnabled:SetChecked(friendlyBorderEnabled)
		controls.friendlyPlayerBorderEnabled:SetEnabled(bordersEnabled)
		if controls.friendlyPlayerBorderEnabled.Label then
			controls.friendlyPlayerBorderEnabled.Label:SetAlpha(bordersEnabled and 1 or 0.5)
		end
	end
	if controls.enemyPlayerBorderEnabled then
		controls.enemyPlayerBorderEnabled:SetChecked(enemyBorderEnabled)
		controls.enemyPlayerBorderEnabled:SetEnabled(bordersEnabled)
		if controls.enemyPlayerBorderEnabled.Label then
			controls.enemyPlayerBorderEnabled.Label:SetAlpha(bordersEnabled and 1 or 0.5)
		end
	end

	RefreshColorSwatch(controls.partyMemberBorderColor, "partyMemberBorderColor", self.DEFAULTS.partyMemberBorderColor)
	RefreshColorSwatch(
		controls.friendlyPlayerBorderColor,
		"friendlyPlayerBorderColor",
		self.DEFAULTS.friendlyPlayerBorderColor
	)
	RefreshColorSwatch(controls.enemyPlayerBorderColor, "enemyPlayerBorderColor", self.DEFAULTS.enemyPlayerBorderColor)

	if controls.resetPartyMemberBorderColor then
		controls.resetPartyMemberBorderColor:SetEnabled(bordersEnabled)
		if IsColorOptionAtDefault("partyMemberBorderColor", self.DEFAULTS.partyMemberBorderColor) then
			controls.resetPartyMemberBorderColor:Hide()
		else
			controls.resetPartyMemberBorderColor:Show()
		end
	end
	if controls.resetFriendlyPlayerBorderColor then
		controls.resetFriendlyPlayerBorderColor:SetEnabled(bordersEnabled)
		if IsColorOptionAtDefault("friendlyPlayerBorderColor", self.DEFAULTS.friendlyPlayerBorderColor) then
			controls.resetFriendlyPlayerBorderColor:Hide()
		else
			controls.resetFriendlyPlayerBorderColor:Show()
		end
	end
	if controls.resetEnemyPlayerBorderColor then
		controls.resetEnemyPlayerBorderColor:SetEnabled(bordersEnabled)
		if IsColorOptionAtDefault("enemyPlayerBorderColor", self.DEFAULTS.enemyPlayerBorderColor) then
			controls.resetEnemyPlayerBorderColor:Hide()
		else
			controls.resetEnemyPlayerBorderColor:Show()
		end
	end

	SetColorSwatchEnabled(controls.partyMemberBorderColor, bordersEnabled and partyBorderEnabled)
	SetColorSwatchEnabled(controls.friendlyPlayerBorderColor, bordersEnabled and friendlyBorderEnabled)
	SetColorSwatchEnabled(controls.enemyPlayerBorderColor, bordersEnabled and enemyBorderEnabled)

	self:RefreshOptionsPreviewsOnly()
end

function PvPTogether:OpenOptionsWindow()
	if self:IsInCombatLockdown() then
		self:Print("Open PvPTogether settings after combat. Use /pt on or /pt off in combat.")
		return true
	end
	if not self.optionsFrame then
		self:InitializeOptionsWindow()
	end

	if not (Settings and Settings.OpenToCategory and self.optionsCategory and self.optionsCategory.GetID) then
		return false
	end

	Settings.OpenToCategory(self.optionsCategory:GetID())
	return true
end

function PvPTogether:InitializeOptionsWindow()
	if self.optionsFrame then
		return
	end

	if self:IsInCombatLockdown() then
		return
	end
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		-- Leave optionsFrame unset so a later open can retry after Settings loads.
		self:Print("Settings API is unavailable; options could not be registered.")
		return
	end

	local panel = CreateFrame("Frame", "PvPTogetherOptionsPanel")
	panel.name = "PvPTogether"
	local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 0)
	local frame = CreateFrame("Frame", nil, scrollFrame)
	frame:SetSize(640, 570)
	scrollFrame:SetScrollChild(frame)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("PvPTogether")

	local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetText("Per-unit-type Blizzard nameplate geometry and custom border colors.")
	local enabledCheckbox = CreateCheckbox(frame, "enabled", "Enable PvPTogether", nil, 12, -48)

	local sectionTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sectionTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -84)
	sectionTitle:SetText("Style by Unit Type")

	local sectionHelp = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sectionHelp:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -8)
	sectionHelp:SetText("Choose player nameplate geometry from Blizzard's built-in styles.")

	local partyMemberStyle = CreateStyleDropdown(
		frame,
		"Party Members",
		"Style used for actual party member nameplates only.",
		16,
		-120,
		"partyMemberStyle"
	)
	local partyMemberBorderEnabled = CreateCheckbox(
		frame,
		"partyMemberBorderEnabled",
		"Border Color",
		"Enable a custom border tint for actual party member nameplates only.",
		36,
		-188
	)
	local partyMemberBorderColor = CreateColorSwatch(
		frame,
		"partyMemberBorderColor",
		"Color",
		"Border tint color for actual party member nameplates only.",
		self.DEFAULTS.partyMemberBorderColor,
		320,
		-188
	)
	partyMemberBorderColor:ClearAllPoints()
	partyMemberBorderColor:SetPoint("LEFT", partyMemberBorderEnabled.Label, "RIGHT", 24, 0)
	local resetPartyMemberBorderColor = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetPartyMemberBorderColor:SetSize(70, 20)
	resetPartyMemberBorderColor:SetPoint("LEFT", partyMemberBorderColor, "RIGHT", 56, 0)
	resetPartyMemberBorderColor:SetText("Reset")
	resetPartyMemberBorderColor:SetScript("OnClick", function()
		PvPTogether:InvalidateOptionsCallbacks()
		local defaults = PvPTogether.DEFAULTS.partyMemberBorderColor
		PvPTogether:SetOption("partyMemberBorderColor", {
			r = defaults.r,
			g = defaults.g,
			b = defaults.b,
		})
	end)
	local partyMemberPreview = CreateNameplatePreview(frame, PREVIEW_LEFT, -118)

	local friendlyPlayerStyle = CreateStyleDropdown(
		frame,
		"Friendly Players",
		"Style used for friendly player nameplates that are not in your actual party.",
		16,
		-244,
		"friendlyPlayerStyle"
	)
	local friendlyPlayerBorderEnabled = CreateCheckbox(
		frame,
		"friendlyPlayerBorderEnabled",
		"Border Color",
		"Enable a custom border tint for non-group friendly player nameplates.",
		36,
		-312
	)
	local friendlyPlayerBorderColor = CreateColorSwatch(
		frame,
		"friendlyPlayerBorderColor",
		"Color",
		"Border tint color for non-group friendly player nameplates.",
		self.DEFAULTS.friendlyPlayerBorderColor,
		320,
		-312
	)
	friendlyPlayerBorderColor:ClearAllPoints()
	friendlyPlayerBorderColor:SetPoint("LEFT", friendlyPlayerBorderEnabled.Label, "RIGHT", 24, 0)
	local resetFriendlyPlayerBorderColor = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetFriendlyPlayerBorderColor:SetSize(70, 20)
	resetFriendlyPlayerBorderColor:SetPoint("LEFT", friendlyPlayerBorderColor, "RIGHT", 56, 0)
	resetFriendlyPlayerBorderColor:SetText("Reset")
	resetFriendlyPlayerBorderColor:SetScript("OnClick", function()
		PvPTogether:InvalidateOptionsCallbacks()
		local defaults = PvPTogether.DEFAULTS.friendlyPlayerBorderColor
		PvPTogether:SetOption("friendlyPlayerBorderColor", {
			r = defaults.r,
			g = defaults.g,
			b = defaults.b,
		})
	end)
	local friendlyPlayerPreview = CreateNameplatePreview(frame, PREVIEW_LEFT, -242)

	local enemyPlayerStyle = CreateStyleDropdown(
		frame,
		"Enemy Players",
		"Style used for enemy player nameplates.",
		16,
		-368,
		"enemyPlayerStyle"
	)
	local enemyPlayerBorderEnabled = CreateCheckbox(
		frame,
		"enemyPlayerBorderEnabled",
		"Border Color",
		"Enable a custom border tint for enemy player nameplates.",
		36,
		-436
	)
	local enemyPlayerBorderColor = CreateColorSwatch(
		frame,
		"enemyPlayerBorderColor",
		"Color",
		"Border tint color for enemy player nameplates.",
		self.DEFAULTS.enemyPlayerBorderColor,
		320,
		-436
	)
	enemyPlayerBorderColor:ClearAllPoints()
	enemyPlayerBorderColor:SetPoint("LEFT", enemyPlayerBorderEnabled.Label, "RIGHT", 24, 0)
	local resetEnemyPlayerBorderColor = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	resetEnemyPlayerBorderColor:SetSize(70, 20)
	resetEnemyPlayerBorderColor:SetPoint("LEFT", enemyPlayerBorderColor, "RIGHT", 56, 0)
	resetEnemyPlayerBorderColor:SetText("Reset")
	resetEnemyPlayerBorderColor:SetScript("OnClick", function()
		PvPTogether:InvalidateOptionsCallbacks()
		local defaults = PvPTogether.DEFAULTS.enemyPlayerBorderColor
		PvPTogether:SetOption("enemyPlayerBorderColor", {
			r = defaults.r,
			g = defaults.g,
			b = defaults.b,
		})
	end)
	local enemyPlayerPreview = CreateNameplatePreview(frame, PREVIEW_LEFT, -366)

	local capabilityStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	capabilityStatus:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -478)
	capabilityStatus:SetWidth(610)
	capabilityStatus:SetJustifyH("LEFT")
	local scopeHelp = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scopeHelp:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -514)
	scopeHelp:SetWidth(610)
	scopeHelp:SetJustifyH("LEFT")
	scopeHelp:SetText(
		"Name colors, click areas and stacking follow Blizzard's global settings. Global Classic style keeps its native geometry."
	)

	self.optionControls = {
		enabled = enabledCheckbox,
		capabilityStatus = capabilityStatus,
		partyMemberStyle = partyMemberStyle,
		friendlyPlayerStyle = friendlyPlayerStyle,
		enemyPlayerStyle = enemyPlayerStyle,
		partyMemberBorderEnabled = partyMemberBorderEnabled,
		partyMemberBorderColor = partyMemberBorderColor,
		resetPartyMemberBorderColor = resetPartyMemberBorderColor,
		friendlyPlayerBorderEnabled = friendlyPlayerBorderEnabled,
		friendlyPlayerBorderColor = friendlyPlayerBorderColor,
		resetFriendlyPlayerBorderColor = resetFriendlyPlayerBorderColor,
		enemyPlayerBorderEnabled = enemyPlayerBorderEnabled,
		enemyPlayerBorderColor = enemyPlayerBorderColor,
		resetEnemyPlayerBorderColor = resetEnemyPlayerBorderColor,
		partyMemberPreview = partyMemberPreview,
		friendlyPlayerPreview = friendlyPlayerPreview,
		enemyPlayerPreview = enemyPlayerPreview,
	}

	panel:SetScript("OnShow", function()
		PvPTogether:RandomizeOptionsPreviewClasses()
		PvPTogether:RefreshOptionsWindow()
		PvPTogether:StartOptionsPreviewTicker()
	end)
	panel:SetScript("OnHide", function()
		PvPTogether:InvalidateOptionsCallbacks()
		PvPTogether:StopOptionsPreviewTicker()
	end)

	self.optionsFrame = panel

	local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
	Settings.RegisterAddOnCategory(category)
	self.optionsCategory = category
	self:RefreshOptionsWindow()
end
