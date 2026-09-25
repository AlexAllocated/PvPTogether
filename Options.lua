local PvPTogether = _G.PvPTogether

if not PvPTogether then
	return
end

PvPTogether.optionControls = PvPTogether.optionControls or {}
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

local categories = {
	{ key = "partyMember", title = "Party Members", tooltip = "Custom border for members of your home party." },
	{
		key = "friendlyPlayer",
		title = "Friendly Players",
		tooltip = "Custom border for friendly players outside your home party, including you.",
	},
	{ key = "enemyPlayer", title = "Enemy Players", tooltip = "Custom border for enemy players." },
}

local function ResetKey(kind)
	return "reset" .. kind:sub(1, 1):upper() .. kind:sub(2) .. "BorderColor"
end

function PvPTogether:InvalidateOptionsCallbacks()
	self.optionsCallbackGeneration = (self.optionsCallbackGeneration or 0) + 1
end

function PvPTogether:RefreshOptionsWindow()
	if not self.optionsFrame or not self.optionsFrame:IsShown() then
		return
	end
	local controls = self.optionControls
	local enabled = self:GetOption("enabled") == true
	local capabilities = self:GetNameplateCapabilities()
	local bordersEnabled = enabled and capabilities.borderTint == true
	controls.enabled:SetChecked(enabled)
	local status = capabilities.borderTint and "" or capabilities.reason
	if enabled and self:IsNameplateAugmentationBlockedInCurrentContext() then
		status = "Unavailable nameplates update when restrictions end."
	end
	controls.capabilityStatus:SetText(status)
	for _, category in ipairs(categories) do
		local kind = category.key
		local enabledKey, colorKey = kind .. "BorderEnabled", kind .. "BorderColor"
		local checked = self:GetOption(enabledKey) == true
		local toggle, swatch, reset = controls[enabledKey], controls[colorKey], controls[ResetKey(kind)]
		toggle:SetChecked(checked)
		toggle:SetEnabled(bordersEnabled)
		toggle.Label:SetAlpha(bordersEnabled and 1 or 0.5)
		RefreshColorSwatch(swatch, colorKey, self.DEFAULTS[colorKey])
		SetColorSwatchEnabled(swatch, bordersEnabled and checked)
		reset:SetEnabled(bordersEnabled)
		if IsColorOptionAtDefault(colorKey, self.DEFAULTS[colorKey]) then
			reset:Hide()
		else
			reset:Show()
		end
	end
end

function PvPTogether:OpenBlizzardNameplateSettings()
	if self:IsInCombatLockdown() then
		self:Print("Open Blizzard nameplate settings after combat.")
		return false
	end
	local open = self:SafeGetField(Settings, "OpenToCategory")
	local categoryID = self:SafeGetField(Settings, "NAMEPLATE_OPTIONS_CATEGORY_ID")
	if type(open) ~= "function" or (type(categoryID) ~= "number" and type(categoryID) ~= "string") then
		self:Print("Blizzard nameplate settings are unavailable right now.")
		return false
	end
	local ok = pcall(open, categoryID)
	if not ok then
		self:Print("Blizzard nameplate settings are unavailable right now.")
	end
	return ok
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
	if self.optionsFrame or self:IsInCombatLockdown() then
		return
	end
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		self:Print("Settings API is unavailable; options could not be registered.")
		return
	end
	local panel = CreateFrame("Frame", "PvPTogetherOptionsPanel")
	panel.name = "PvPTogether"
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 0)
	local frame = CreateFrame("Frame", nil, scroll)
	frame:SetSize(640, 475)
	scroll:SetScrollChild(frame)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	title:SetText("PvPTogether")
	local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetText("Custom player nameplate borders. Layout follows Blizzard's global settings.")
	local controls = {}
	controls.enabled = CreateCheckbox(frame, "enabled", "Enable PvPTogether", nil, 12, -48)
	local native = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	native:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -88)
	native:SetSize(280, 26)
	native:SetText("Blizzard Nameplate Settings")
	native:SetScript("OnClick", function()
		PvPTogether:OpenBlizzardNameplateSettings()
	end)
	controls.blizzardNameplateSettings = native
	for index, category in ipairs(categories) do
		local kind, y = category.key, -150 - (index - 1) * 84
		local enabledKey, colorKey = kind .. "BorderEnabled", kind .. "BorderColor"
		local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
		heading:SetText(category.title)
		controls[enabledKey] = CreateCheckbox(frame, enabledKey, "Custom border", category.tooltip, 12, y - 22)
		controls[colorKey] =
			CreateColorSwatch(frame, colorKey, "Color", category.tooltip, self.DEFAULTS[colorKey], 320, y - 26)
		local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		reset:SetPoint("TOPLEFT", frame, "TOPLEFT", 450, y - 26)
		reset:SetSize(70, 22)
		reset:SetText("Reset")
		reset:SetScript("OnClick", function()
			PvPTogether:InvalidateOptionsCallbacks()
			PvPTogether:SetOption(colorKey, PvPTogether.DEFAULTS[colorKey])
		end)
		controls[ResetKey(kind)] = reset
	end
	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -414)
	status:SetWidth(610)
	status:SetJustifyH("LEFT")
	controls.capabilityStatus = status
	self.optionControls = controls
	panel:SetScript("OnShow", function()
		PvPTogether:RefreshOptionsWindow()
	end)
	panel:SetScript("OnHide", function()
		PvPTogether:InvalidateOptionsCallbacks()
	end)
	self.optionsFrame = panel
	local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
	Settings.RegisterAddOnCategory(category)
	self.optionsCategory = category
	self:RefreshOptionsWindow()
end
