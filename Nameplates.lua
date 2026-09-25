local PvPTogether = _G.PvPTogether
if not PvPTogether then
	return
end
local LibChev = PvPTogether.LibChev

-- All bookkeeping belongs to the addon. Never call Blizzard's setup/reset mixins:
-- those write shared option tables and frame fields even outside combat.
PvPTogether.nameplateStateByFrame = {}
PvPTogether.nameplateFrameByUnitToken = {}
PvPTogether.nameplateHooksByUnitFrame = LibChev.WeakKeys()
PvPTogether.nameplateBorderTintByUnitFrame = LibChev.WeakKeys()
PvPTogether.nameplateStateByUnitFrame = LibChev.WeakKeys()
PvPTogether.nameplateAnchorRecords = LibChev.WeakKeys()
PvPTogether.nameplateAcquisitionHooks = LibChev.WeakKeys()

local function Field(object, key)
	local value = PvPTogether:SafeGetField(object, key)
	return value
end

local function Method(object, key)
	local value = Field(object, key)
	return type(value) == "function" and value or nil
end

local function Call(object, key, ...)
	local method = Method(object, key)
	if not method then
		return false
	end
	return pcall(method, object, ...)
end

local function BooleanCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, ...)
	if not ok then
		return nil
	end
	return PvPTogether:SafeToBoolean(value)
end

local function SafetyAPI(namespace, name)
	if not PvPTogether:CanAccessValue(namespace) then
		return nil, false
	end
	if namespace == nil then
		return nil, true
	end
	local api, readable = PvPTogether:SafeGetField(namespace, name)
	if not readable or (api ~= nil and type(api) ~= "function") then
		return nil, false
	end
	return api, true
end

local function IsToken(value)
	return PvPTogether:CanAccessValue(value) and type(value) == "string" and value ~= ""
end

function PvPTogether:CanAccessNameplateFrame(frame)
	if not self:CanAccessValue(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then
		return false
	end
	local forbidden = Method(frame, "IsForbidden")
	return forbidden ~= nil and BooleanCall(forbidden, frame) == false
end

function PvPTogether:IsNameplateAugmentationBlockedInCurrentContext()
	if self:IsInCombatLockdown() then
		return true
	end
	local getState, readable = SafetyAPI(C_RestrictedActions, "GetAddOnRestrictionState")
	if not readable then
		return true
	end
	if type(getState) ~= "function" then
		return false
	end
	local restrictionTypes = Field(Enum, "AddOnRestrictionType")
	if not self:CanAccessTable(restrictionTypes) then
		return true
	end
	local inactive = Field(Field(Enum, "AddOnRestrictionState"), "Inactive") or 0
	for _, name in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }) do
		local restrictionType, typeReadable = self:SafeGetField(restrictionTypes, name)
		if not typeReadable then
			return true
		end
		if restrictionType ~= nil then
			local ok, value = pcall(getState, restrictionType)
			local state = ok and self:SafeToNumber(value) or nil
			if state == nil or state ~= inactive then
				return true
			end
		end
	end
	return false
end

function PvPTogether:CanMutateNameplateFrame(frame)
	if not self:CanAccessNameplateFrame(frame) then
		return false, "frame-access"
	end
	local protected, readable = self:SafeGetField(frame, "IsProtected")
	if not readable or (protected ~= nil and type(protected) ~= "function") then
		return false, "protection-query"
	end
	local protection = protected and BooleanCall(protected, frame)
	if protected and protection == nil then
		return false, "protection-result"
	end
	local restricted = self:IsNameplateAugmentationBlockedInCurrentContext()
	if restricted and protection ~= false then
		return false, "protected-context"
	end
	local allow, permissionReadable = SafetyAPI(C_RestrictedActions, "CheckAllowProtectedFunctions")
	if not permissionReadable then
		return false, "permission-query"
	end
	if type(allow) == "function" and BooleanCall(allow, frame, true) ~= true then
		return false, "permission-denied"
	end
	if restricted and type(allow) ~= "function" then
		return false, "permission-unavailable"
	end
	return true
end

function PvPTogether:GetNameplateCapabilities()
	local plates = type(Field(C_NamePlate, "GetNamePlates")) == "function"
		and type(Field(C_NamePlate, "GetNamePlateForUnit")) == "function"
	local setup = self:CanAccessTable(NamePlateSetupOptions)
	local anchor = setup and self:SafeToNumber(Field(NamePlateSetupOptions, "unitNameAnchorStyle"))
	local classic = setup
		and (
			Field(NamePlateSetupOptions, "useClassicHealthBar") ~= false
			or Field(NamePlateSetupOptions, "useClassicCastBar") ~= false
		)
	local styles = plates and setup and anchor ~= nil and not classic
	return {
		styleOverrides = styles == true,
		borderTint = plates,
		reason = not plates and "Nameplate APIs unavailable"
			or not setup and "Blizzard nameplates not loaded"
			or classic and "Global Classic style: native geometry retained"
			or not anchor and "Unsupported nameplate layout"
			or "Modern nameplate layout",
	}
end

-- Unknown classification is never treated as an enemy. Resolve anew on every pass;
-- no GUID or unit-kind cache can leak across recycled tokens or pooled unit frames.
function PvPTogether:ResolveNameplateUnitKind(unitToken)
	if not IsToken(unitToken) then
		return nil
	end
	local player = BooleanCall(UnitIsPlayer, unitToken)
	if player == nil then
		return nil
	end
	if not player then
		return "npc"
	end
	local friend = BooleanCall(UnitIsFriend, "player", unitToken)
	if friend == nil then
		return nil
	end
	if not friend then
		return "enemyPlayer"
	end
	local own = BooleanCall(UnitIsUnit, unitToken, "player")
	if own == nil then
		return nil
	end
	if not own then
		local inParty = BooleanCall(UnitInParty, unitToken, LE_PARTY_CATEGORY_HOME or 1)
		if inParty == nil then
			return nil
		end
		if inParty then
			return "partyMember"
		end
	end
	return "friendlyPlayer"
end

local function LiveUnit(frame)
	if not PvPTogether:CanAccessNameplateFrame(frame) then
		return nil
	end
	local ok, token = Call(frame, "GetUnit")
	if not ok or not IsToken(token) then
		return nil
	end
	local getPlate = Field(C_NamePlate, "GetNamePlateForUnit")
	if type(getPlate) ~= "function" then
		return nil
	end
	local found, current = pcall(getPlate, token, false)
	if not found or not PvPTogether:CanAccessValue(current) or current ~= frame then
		return nil
	end
	return token
end

-- A small reversible journal of native widget properties. Preflight the entire
-- plan, including every anchor target and original value, before its first write.
-- pcall contains a widget error; it is not used as a substitute for access checks.
local anchorPoints = {
	TOPLEFT = true,
	TOP = true,
	TOPRIGHT = true,
	LEFT = true,
	CENTER = true,
	RIGHT = true,
	BOTTOMLEFT = true,
	BOTTOM = true,
	BOTTOMRIGHT = true,
}

local function CopyPoints(points)
	local copy = {}
	for index, point in ipairs(points) do
		copy[index] = { point[1], point[2], point[3], point[4], point[5] }
	end
	return copy
end

local function ObserveAnchors(object)
	if not PvPTogether:CanAccessNameplateFrame(object) or type(hooksecurefunc) ~= "function" then
		return false
	end
	local record = PvPTogether.nameplateAnchorRecords[object]
	if record and record.ready then
		return true
	end
	if not record then
		record = { hooks = {}, partialPoints = {} }
		PvPTogether.nameplateAnchorRecords[object] = record
		-- A newly acquired unanchored widget has an unambiguous empty baseline.
		-- The count is not a screen coordinate; never read existing points here.
		local ok, count = Call(object, "GetNumPoints")
		if ok and PvPTogether:SafeToNumber(count) == 0 then
			record.points = {}
		end
	end
	local function Clear()
		record.partialPoints = {}
		record.points = PvPTogether:CanAccessNameplateFrame(object) and record.partialPoints or nil
	end
	local function Invalidate()
		record.points = nil
		record.partialPoints = {}
	end
	local function Point(_, point, relative, relativePoint, x, y)
		if
			not PvPTogether:CanAccessNameplateFrame(object)
			or not IsToken(point)
			or not anchorPoints[point]
			or not IsToken(relativePoint)
			or not anchorPoints[relativePoint]
			or not PvPTogether:CanAccessNameplateFrame(relative)
		then
			Invalidate()
			return
		end
		x, y = PvPTogether:SafeToNumber(x), PvPTogether:SafeToNumber(y)
		if x == nil or y == nil then
			Invalidate()
			return
		end
		local points = record.points or record.partialPoints
		local index = #points + 1
		for i, existing in ipairs(points) do
			if existing[1] == point then
				index = i
				break
			end
		end
		if index > 16 then
			Invalidate()
			return
		end
		points[index] = { point, relative, relativePoint, x, y }
		-- Native aura rows replace their existing BOTTOM point without first
		-- clearing it. Once every current anchor has been observed, the baseline
		-- is complete. Counts are public metadata, never screen coordinates.
		local ok, count = Call(object, "GetNumPoints")
		count = ok and PvPTogether:SafeToNumber(count) or nil
		if not count or count < #points or count > 16 or count % 1 ~= 0 then
			Invalidate()
			return
		end
		record.partialPoints = points
		record.points = count == #points and points or nil
	end
	-- Observe only public setter arguments; never query positions on a restricted
	-- plate or retain a secret argument. Unknown setters invalidate the baseline.
	local complete = true
	for _, spec in ipairs({
		{ "ClearAllPoints", Clear },
		{ "SetPoint", Point },
		{ "SetAllPoints", Invalidate },
		{ "ClearPoint", Invalidate },
		{ "AdjustPointsOffset", Invalidate },
		{ "SetPointsOffset", Invalidate },
		{ "ClearPointsOffset", Invalidate },
	}) do
		local name, callback = spec[1], spec[2]
		if not record.hooks[name] and Method(object, name) then
			record.hooks[name] = pcall(hooksecurefunc, object, name, callback)
		end
		if Method(object, name) and not record.hooks[name] then
			complete = false
		end
	end
	record.ready = complete
		and record.hooks.ClearAllPoints == true
		and record.hooks.SetPoint == true
		and record.hooks.SetAllPoints == true
	return record.ready
end

local function ReadAnchors(object)
	local predicate, readable = PvPTogether:SafeGetField(object, "IsAnchoringRestricted")
	if not readable then
		return nil, "anchor-restriction-query"
	end
	local restricted = false
	if predicate ~= nil then
		if type(predicate) ~= "function" then
			return nil, "anchor-restriction-query"
		end
		restricted = BooleanCall(predicate, object)
	end
	if predicate and restricted == nil then
		return nil, "anchor-restriction-query"
	end
	if restricted then
		local record = PvPTogether.nameplateAnchorRecords[object]
		if record and record.ready and record.points then
			return CopyPoints(record.points)
		end
		return nil, "anchor-baseline-pending"
	end
	local ok, count = Call(object, "GetNumPoints")
	count = ok and PvPTogether:SafeToNumber(count) or nil
	if not count or count < 0 or count > 16 or count % 1 ~= 0 then
		return nil, "anchor-count"
	end
	local points = {}
	for i = 1, count do
		local got, point, relative, relativePoint, x, y = Call(object, "GetPoint", i)
		if not got or not IsToken(point) or not IsToken(relativePoint) or not PvPTogether:CanAccessValue(relative) then
			return nil, "anchor-values"
		end
		if relative ~= nil and not PvPTogether:CanAccessNameplateFrame(relative) then
			return nil, "anchor-relative"
		end
		x, y = PvPTogether:SafeToNumber(x), PvPTogether:SafeToNumber(y)
		if x == nil or y == nil then
			return nil, "anchor-offsets"
		end
		points[#points + 1] = { point, relative, relativePoint, x, y }
	end
	return points
end

local function Snapshot(op)
	local object = op.object
	local allowed, reason = PvPTogether:CanMutateNameplateFrame(object)
	if not allowed then
		return nil, reason
	end
	if op.kind == "points" then
		return ReadAnchors(object)
	elseif op.kind == "height" then
		local ok, value = Call(object, "GetHeight")
		value = ok and PvPTogether:SafeToNumber(value) or nil
		if value then
			return { value }
		end
	elseif op.kind == "justify" then
		local ok, value = Call(object, "GetJustifyH")
		if ok and IsToken(value) then
			return { value }
		end
	elseif op.kind == "font" then
		local ok, _, height = Call(object, "GetFont")
		height = PvPTogether:SafeToNumber(height)
		local gotFont, font = Call(object, "GetFontObject")
		local gotName, fontName = Call(font, "GetName")
		if ok and gotFont and gotName and IsToken(fontName) and height then
			return { fontName, height }
		end
		return nil, not ok and "font-query" or not height and "font-height" or "font-object-name"
	end
	return nil, "property-query"
end

local setterByKind = { height = "SetHeight", justify = "SetJustifyH" }
local function IsWithinAnchorRoot(object, root)
	if not PvPTogether:CanAccessNameplateFrame(root) then
		return false
	end
	-- Only walk a bounded, access-checked parent chain. A restricted plate may
	-- anchor its own children together, never into another plate or UIParent.
	for _ = 1, 16 do
		if not PvPTogether:CanAccessNameplateFrame(object) then
			return false
		end
		if object == root then
			return true
		end
		local ok, parent = Call(object, "GetParent")
		if not ok or not PvPTogether:CanAccessValue(parent) then
			return false
		end
		object = parent
	end
	return false
end

local function CanAnchor(object, root)
	if not PvPTogether:CanAccessNameplateFrame(object) then
		return false
	end
	for _, name in ipairs({ "IsAnchoringRestricted", "IsAnchoringSecret" }) do
		local predicate, readable = PvPTogether:SafeGetField(object, name)
		if not readable then
			return false
		end
		if predicate ~= nil then
			if type(predicate) ~= "function" then
				return false
			end
			local restricted = BooleanCall(predicate, object)
			if restricted == nil then
				return false
			end
			if restricted and (name == "IsAnchoringSecret" or not IsWithinAnchorRoot(object, root)) then
				return false
			end
		end
	end
	return true
end
local function CanWrite(op, values)
	local allowed, reason = PvPTogether:CanMutateNameplateFrame(op.object)
	if not allowed then
		return false, reason
	end
	if op.kind == "points" then
		if not Method(op.object, "ClearAllPoints") or not Method(op.object, "SetPoint") then
			return false, "anchor-setter"
		end
		if not CanAnchor(op.object, op.anchorRoot) then
			return false, "anchor-source-permission"
		end
		for _, point in ipairs(values) do
			if point[2] ~= nil and not CanAnchor(point[2], op.anchorRoot) then
				return false, "anchor-target-permission"
			end
			-- Every endpoint stays within the same validated unit frame even
			-- when only one endpoint currently exposes the restricted flag.
			if
				op.anchorRoot
				and (
					not IsWithinAnchorRoot(op.object, op.anchorRoot)
					or not IsWithinAnchorRoot(point[2], op.anchorRoot)
				)
			then
				return false, "anchor-family"
			end
		end
		return true
	end
	if op.kind == "font" then
		return Method(op.object, "SetFontObject") ~= nil and Method(op.object, "SetTextHeight") ~= nil
	end
	return Method(op.object, setterByKind[op.kind]) ~= nil
end

local function Write(op, values)
	if not CanWrite(op, values) then
		return false
	end
	if op.kind == "points" then
		if not Call(op.object, "ClearAllPoints") then
			return false
		end
		for _, point in ipairs(values) do
			if not Call(op.object, "SetPoint", point[1], point[2], point[3], point[4], point[5]) then
				return false
			end
		end
		return true
	end
	if op.kind == "font" then
		return Call(op.object, "SetFontObject", values[1]) and Call(op.object, "SetTextHeight", values[2])
	end
	return Call(op.object, setterByKind[op.kind], unpack(values))
end

local function SameTuple(left, right, count)
	for index = 1, count do
		local a, b = left[index], right[index]
		if not PvPTogether:CanAccessValue(a) or not PvPTogether:CanAccessValue(b) then
			return nil
		end
		if a ~= b then
			return false
		end
	end
	return true
end

local function SameProperties(op, current)
	if op.kind ~= "points" then
		return SameTuple(current, op.applied, #current)
	end
	if #current ~= #op.applied then
		return false
	end
	for index = 1, #current do
		local match = SameTuple(current[index], op.applied[index], 5)
		if match ~= true then
			return match
		end
	end
	return true
end

local function Restore(state)
	local remaining = {}
	for i = #state.journal, 1, -1 do
		local op = state.journal[i]
		local current = Snapshot(op)
		-- A different owner changed this property after our last write. Relinquish
		-- it instead of restoring our old baseline over their current presentation.
		local match = true
		if op.applied then
			match = current and SameProperties(op, current)
		end
		if match == nil or (match and not Write(op, op.original)) then
			table.insert(remaining, 1, op)
		end
	end
	state.journal = remaining
	return #remaining == 0
end

local function Execute(state, plan)
	for index, op in ipairs(plan) do
		local reason
		op.original, reason = Snapshot(op)
		local writable, writeReason = false, nil
		if op.original then
			writable, writeReason = CanWrite(op, op.values)
		end
		if not op.original or not writable then
			-- Only addon-authored labels and plan indexes enter diagnostics.
			-- Never retain the widget, its identity, values, or foreign errors.
			PvPTogether.lastLayoutFailure = {
				step = index,
				property = op.kind,
				stage = op.original and "write-permission" or "snapshot",
				reason = reason or writeReason or "setter-unavailable",
			}
			PvPTogether:RecordDiagnostic("layout-preflight")
			return false
		end
	end
	for _, op in ipairs(plan) do
		state.journal[#state.journal + 1] = op -- Retain rollback even for a partial SetPoint failure.
		if not Write(op, op.values) then
			PvPTogether:RecordDiagnostic("layout-write")
			Restore(state)
			return false
		end
		op.applied = Snapshot(op)
	end
	PvPTogether.lastLayoutFailure = nil
	return true
end

local function Add(plan, object, kind, group, values)
	plan[#plan + 1] = { object = object, kind = kind, group = group, values = values }
end

local function Point(point, relative, relativePoint, x, y)
	return { point, relative, relativePoint, x, y }
end

local function Child(frame, key)
	if not PvPTogether:CanAccessNameplateFrame(frame) then
		return nil
	end
	local child = Field(frame, key)
	if PvPTogether:CanAccessNameplateFrame(child) then
		return child
	end
	return nil
end

function PvPTogether:ObserveNameplateAnchors(unitFrame)
	if not self:CanAccessNameplateFrame(unitFrame) then
		return
	end
	local cast = Child(Child(unitFrame, "CastBarsContainer"), "castBar")
	local health = Child(Child(unitFrame, "HealthBarsContainer"), "healthBar")
	-- Explicit widget list, never enumerate a foreign frame or its children.
	for _, spec in ipairs({
		{ unitFrame, "name" },
		{ unitFrame, "PlayerLevelDiffFrame" },
		{ Child(unitFrame, "CastBarsContainer"), "castBar" },
		{ cast, "Icon" },
		{ health, "Text" },
		{ health, "LeftText" },
		{ health, "RightText" },
		{ Child(unitFrame, "AurasFrame"), "DebuffListFrame" },
	}) do
		local child = Child(spec[1], spec[2])
		if child then
			ObserveAnchors(child)
		end
	end
end

function PvPTogether:ObserveNameplateAcquisition(frame)
	if not self:CanAccessNameplateFrame(frame) then
		return false
	end
	if
		not self.nameplateAcquisitionHooks[frame]
		and Method(frame, "AcquireUnitFrame")
		and type(hooksecurefunc) == "function"
	then
		-- This native method finishes before SetUnit applies the initial layout.
		-- The post-hook only installs observers; it does not invoke native setup.
		self.nameplateAcquisitionHooks[frame] = pcall(hooksecurefunc, frame, "AcquireUnitFrame", function()
			PvPTogether:ObserveNameplateAnchors(Child(frame, "UnitFrame"))
		end)
	end
	self:ObserveNameplateAnchors(Child(frame, "UnitFrame"))
	return self.nameplateAcquisitionHooks[frame] == true
end

local function Positive(object, key)
	local value = PvPTogether:SafeToNumber(Field(object, key))
	return value and value > 0 and value or nil
end

local function BuildPlan(unitFrame, style)
	local castContainer = Child(unitFrame, "CastBarsContainer")
	local castBar = Child(castContainer, "castBar")
	local healthContainer = Child(unitFrame, "HealthBarsContainer")
	local healthBar = Child(healthContainer, "healthBar")
	local name = Child(unitFrame, "name")
	local icon = Child(castBar, "Icon")
	local shield = Child(castBar, "BorderShield")
	local text, left, right = Child(healthBar, "Text"), Child(healthBar, "LeftText"), Child(healthBar, "RightText")
	if not castBar or not healthBar or not name or not icon or not shield or not text or not left or not right then
		return nil
	end
	-- Read the cached display flag; calling IsShowOnlyName/ShouldDisplay can populate
	-- Blizzard fields. Unknown flags defer this pass instead of executing that path.
	local showOnlyName = PvPTogether:SafeToBoolean(Field(unitFrame, "showOnlyName"))
	if showOnlyName == nil then
		return nil
	end
	local vertical = Positive(NamePlateSetupOptions, "verticalScale")
	local iconHeight = Positive(NamePlateSetupOptions, "castIconHeight")
	if not vertical or not iconHeight then
		return nil
	end
	local styles = Field(Enum, "NamePlateStyle")
	local modern, block = Field(styles, "Modern"), Field(styles, "Block")
	local insideName = style == modern or style == block
	local insideSpell = style == block or style == Field(styles, "CastFocus")
	local largeHealth = insideName or style == Field(styles, "HealthFocus")
	local healthHeight =
		Positive(NamePlateConstants, largeHealth and "LARGE_HEALTH_BAR_HEIGHT" or "SMALL_HEALTH_BAR_HEIGHT")
	local castHeight = Positive(NamePlateConstants, insideSpell and "LARGE_CAST_BAR_HEIGHT" or "SMALL_CAST_BAR_HEIGHT")
	if not healthHeight or not castHeight then
		return nil
	end
	healthHeight, castHeight = healthHeight * vertical, castHeight * vertical
	local plan = {}
	Add(plan, castContainer, "height", "options", { castHeight + (insideSpell and 0 or iconHeight) })
	Add(plan, castBar, "height", "options", { castHeight })
	if insideSpell then
		Add(plan, castBar, "points", "anchors", {
			Point("TOPLEFT", castContainer, "TOPLEFT", 0, 0),
			Point("BOTTOMRIGHT", castContainer, "BOTTOMRIGHT", 0, 0),
		})
		Add(plan, icon, "points", "anchors", { Point("LEFT", castBar, "LEFT", 0, 0) })
	else
		Add(plan, icon, "points", "anchors", { Point("BOTTOMLEFT", castContainer, "BOTTOMLEFT", 0, 0) })
		Add(plan, castBar, "points", "anchors", {
			Point("BOTTOM", icon, "TOP", 0, 0),
			Point("LEFT", castContainer, "BOTTOMLEFT", 0, 0),
			Point("RIGHT", castContainer, "BOTTOMRIGHT", 0, 0),
		})
	end
	-- The health-container anchors, health textures, level indicators, raid marker,
	-- and CC/LoC anchors remain native. This preserves Forever's level-width offsets.
	Add(plan, healthContainer, "height", "anchors", { healthHeight })
	local outlineAbove = Field(NamePlateSetupOptions, "useOutlinedNameWhenAboveHealthBar") == true
	local fontName = insideName and "SystemFont_NamePlate_Outlined" or "SystemFont_NamePlate"
	local nameFontName = (insideName or outlineAbove) and "SystemFont_NamePlate_Outlined" or "SystemFont_NamePlate"
	local fontHeight = Positive(NamePlateSetupOptions, "healthBarFontHeight")
	if not fontHeight then
		return nil
	end
	for _, target in ipairs({ name, text, left, right }) do
		local selectedFont = target == name and nameFontName or fontName
		if not PvPTogether:CanAccessValue(Field(_G, selectedFont)) or Field(_G, selectedFont) == nil then
			return nil
		end
		Add(plan, target, "font", "options", { selectedFont, fontHeight })
	end
	local justification = Field(NamePlateSetupOptions, "nameJustificationWhenAboveHealthBar")
	if justification ~= "CENTER" and justification ~= "RIGHT" then
		justification = "LEFT"
	end
	Add(
		plan,
		name,
		"justify",
		"anchors",
		{ (showOnlyName or (not insideName and justification == "CENTER")) and "CENTER" or "LEFT" }
	)
	if insideName then
		Add(plan, left, "points", "anchors", { Point("RIGHT", healthBar, "RIGHT", -4, 0) })
		Add(plan, right, "points", "anchors", { Point("RIGHT", left, "LEFT", -2, 0) })
		Add(plan, text, "points", "anchors", { Point("RIGHT", right, "LEFT", 2, 0) })
		Add(plan, name, "points", "anchors", {
			Point("LEFT", healthContainer, "LEFT", 4, 0),
			Point(
				"RIGHT",
				showOnlyName and healthContainer or text,
				showOnlyName and "RIGHT" or "LEFT",
				showOnlyName and -4 or -2,
				0
			),
		})
	else
		Add(plan, left, "points", "anchors", { Point("BOTTOMRIGHT", healthBar, "TOPRIGHT", -4, 2) })
		Add(plan, right, "points", "anchors", { Point("BOTTOMRIGHT", left, "BOTTOMLEFT", -2, 0) })
		Add(plan, text, "points", "anchors", { Point("BOTTOMRIGHT", right, "BOTTOMLEFT", 2, 0) })
		local spacing = PvPTogether:SafeToNumber(Field(NamePlateSetupOptions, "healthBarToNameAboveSpacing")) or 2
		local namePoints = {
			Point("BOTTOMLEFT", healthContainer, "TOPLEFT", outlineAbove and 0 or 4, spacing),
			Point(
				"BOTTOMRIGHT",
				showOnlyName and healthContainer or text,
				showOnlyName and "TOPRIGHT" or "BOTTOMLEFT",
				showOnlyName and -4 or -2,
				showOnlyName and spacing or 0
			),
		}
		-- Forever may place its level indicator to the right of the shortened bar.
		local level = Child(unitFrame, "PlayerLevelDiffFrame")
		if outlineAbove and level then
			local shownOK, shown = Call(level, "IsShown")
			if not shownOK or PvPTogether:SafeToBoolean(shown) == nil then
				return nil
			end
			if shown then
				local points = ReadAnchors(level)
				local relativePoint = points and points[1] and points[1][3]
				if not relativePoint then
					return nil
				end
				if relativePoint == "RIGHT" and not showOnlyName then
					namePoints[2] = Point("RIGHT", level, "RIGHT", 0, 0)
				end
			end
		end
		Add(plan, name, "points", "anchors", namePoints)
	end
	local debuffs = Child(Child(unitFrame, "AurasFrame"), "DebuffListFrame")
	if debuffs then
		local padding = 0
		local getCVar = Field(C_CVar, "GetCVar")
		if type(getCVar) == "function" then
			local ok, raw = pcall(getCVar, "nameplateDebuffPadding")
			padding = ok and PvPTogether:SafeToNumber(raw) or nil
			if padding == nil then
				return nil
			end
		end
		Add(
			plan,
			debuffs,
			"points",
			"anchors",
			{ Point("BOTTOM", insideName and healthBar or name, "TOP", 0, padding) }
		)
	end
	for _, op in ipairs(plan) do
		if op.kind == "points" then
			op.anchorRoot = unitFrame
		end
	end
	return plan
end

function PvPTogether:HideBorderTintForUnitFrame(unitFrame)
	local overlay = self.nameplateBorderTintByUnitFrame[unitFrame]
	if not overlay then
		return true
	end
	if overlay.visible == false then
		return true
	end
	-- This region belongs to us. Harmless Hide on an accessible, unprotected
	-- texture must remain possible during combat, or the unit-frame pool can
	-- display the previous unit's tint on its next occupant. Layout stays blocked.
	if not self:CanAccessNameplateFrame(overlay.Texture) then
		return false
	end
	local protected, readable = self:SafeGetField(overlay.Texture, "IsProtected")
	if not readable or (protected ~= nil and type(protected) ~= "function") then
		return false
	end
	local protection = protected and BooleanCall(protected, overlay.Texture)
	if protected and protection == nil then
		return false
	end
	local allow, permissionReadable = SafetyAPI(C_RestrictedActions, "CheckAllowProtectedFunctions")
	if not permissionReadable then
		return false
	end
	if type(allow) == "function" then
		if BooleanCall(allow, overlay.Texture, true) ~= true then
			return false
		end
	elseif self:IsNameplateAugmentationBlockedInCurrentContext() and protection ~= false then
		return false
	end
	local hidden = Call(overlay.Texture, "Hide")
	if hidden then
		overlay.visible = false
	end
	return hidden
end

function PvPTogether:ApplyBorderTintForUnitFrame(unitFrame, unitKind)
	if not self.isEnabled or not unitKind or not self:IsBorderColorOverrideEnabledForUnitKind(unitKind) then
		return self:HideBorderTintForUnitFrame(unitFrame)
	end
	local healthBar = Child(Child(unitFrame, "HealthBarsContainer"), "healthBar")
	if not self:CanMutateNameplateFrame(healthBar) then
		return false
	end
	local ok, shown = Call(healthBar, "IsShown")
	if not ok or self:SafeToBoolean(shown) ~= true then
		return self:HideBorderTintForUnitFrame(unitFrame)
	end
	local overlay = self.nameplateBorderTintByUnitFrame[unitFrame]
	if overlay and overlay.HealthBar ~= healthBar then
		if not self:HideBorderTintForUnitFrame(unitFrame) then
			return false
		end
		overlay = nil -- A texture never migrates to a replacement Blizzard health bar.
	end
	if not overlay then
		local created, texture = Call(healthBar, "CreateTexture", nil, "OVERLAY", nil, 2)
		if not created or not self:CanMutateNameplateFrame(texture) then
			return false
		end
		overlay = { Texture = texture, HealthBar = healthBar }
		self.nameplateBorderTintByUnitFrame[unitFrame] = overlay
		if not Call(texture, "Hide") then
			return false
		end
		overlay.visible = false
	end
	if not self:CanMutateNameplateFrame(overlay.Texture) then
		return false
	end
	if not overlay.ready then
		if not Call(overlay.Texture, "SetAtlas", "UI-HUD-Nameplates-Selected", true) then
			return false
		end
		overlay.ready = true
	end
	local anchor = Child(healthBar, "bgTexture") or healthBar
	if
		not CanWrite(
			{ object = overlay.Texture, kind = "points", anchorRoot = healthBar },
			{ Point("TOPLEFT", anchor, "TOPLEFT", -1, 1) }
		)
	then
		return false
	end
	local color = self:GetConfiguredBorderColorForUnitKind(unitKind)
	-- Parent alpha already applies to the texture. Reading/multiplying it would
	-- both double-fade the tint and branch on a potentially secret alpha.
	local anchored = Call(overlay.Texture, "ClearAllPoints")
		and Call(overlay.Texture, "SetPoint", "TOPLEFT", anchor, "TOPLEFT", -1, 1)
		and Call(overlay.Texture, "SetPoint", "BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -3, 3)
	if not anchored or not Call(overlay.Texture, "SetVertexColor", color.r, color.g, color.b, 1) then
		return false
	end
	local displayed = Call(overlay.Texture, "Show")
	if displayed then
		overlay.visible = true
	end
	return displayed
end

function PvPTogether:HideAllBorderTintOverrides()
	local complete = true
	for unitFrame in pairs(self.nameplateBorderTintByUnitFrame) do
		if not self:HideBorderTintForUnitFrame(unitFrame) then
			complete = false
		end
	end
	return complete
end

function PvPTogether:OnNativeNameplateLayout(unitFrame, group)
	-- A native pass supersedes only the properties it actually writes. Keep the
	-- remaining journal for disable, removal, or a later unrestricted retry.
	if not self:CanAccessValue(unitFrame) or unitFrame == nil then
		return
	end
	local state = self.nameplateStateByUnitFrame[unitFrame]
	if state then
		local remaining = {}
		for _, op in ipairs(state.journal) do
			if op.group ~= group and op.group ~= "both" then
				remaining[#remaining + 1] = op
			end
		end
		state.journal = remaining
	end
	if self.isEnabled and state then
		self:ScheduleReapplyAllNameplateStyles(0.05, state.frame)
	end
end

function PvPTogether:InstallNameplateFrameHooks(unitFrame)
	if not self:CanAccessNameplateFrame(unitFrame) or type(hooksecurefunc) ~= "function" then
		return false
	end
	local hooks = self.nameplateHooksByUnitFrame[unitFrame] or {}
	self.nameplateHooksByUnitFrame[unitFrame] = hooks
	for _, spec in ipairs({ { "UpdateAnchors", "anchors" }, { "ApplyFrameOptions", "options" } }) do
		local methodName, group = spec[1], spec[2]
		if not hooks[methodName] and Method(unitFrame, methodName) then
			local ok = pcall(hooksecurefunc, unitFrame, methodName, function(frame)
				PvPTogether:OnNativeNameplateLayout(frame, group)
			end)
			hooks[methodName] = ok
		end
	end
	return hooks.UpdateAnchors == true and hooks.ApplyFrameOptions == true
end

function PvPTogether:TrackNameplateFrame(frame)
	if not self:CanAccessNameplateFrame(frame) then
		return false
	end
	self.trackedNamePlateFrames[frame] = true
	return true
end

function PvPTogether:ForEachTrackedNameplateFrame(callback)
	for frame in pairs(self.trackedNamePlateFrames) do
		callback(frame)
	end
end

local function ReleaseState(addon, state)
	if addon.nameplateStateByUnitFrame[state.unitFrame] == state then
		addon.nameplateStateByUnitFrame[state.unitFrame] = nil
	end
	if addon.nameplateStateByFrame[state.frame] == state then
		addon.nameplateStateByFrame[state.frame] = nil
		addon.trackedNamePlateFrames[state.frame] = nil
	end
	if addon.nameplateFrameByUnitToken[state.token] == state.frame then
		addon.nameplateFrameByUnitToken[state.token] = nil
	end
end

function PvPTogether:ReapplyStyleForNameplateFrame(frame)
	if not self.isEnabled then
		return false
	end
	if not self:CanAccessValue(frame) or frame == nil then
		return false
	end
	local state = self.nameplateStateByFrame[frame]
	if state and not self:HideBorderTintForUnitFrame(state.unitFrame) then
		self.pendingNameplateResetAfterCombat = true
		return false
	end
	if not self:CanAccessNameplateFrame(frame) then
		return false
	end
	self:ObserveNameplateAcquisition(frame)
	local token = LiveUnit(frame)
	local unitFrame = Child(frame, "UnitFrame")
	if not token or not unitFrame then
		return false
	end
	local previousOwner = self.nameplateStateByUnitFrame[unitFrame]
	if previousOwner and previousOwner ~= state then
		local hidden = self:HideBorderTintForUnitFrame(unitFrame)
		local restored = Restore(previousOwner)
		if not hidden or not restored then
			self.pendingNameplateResetAfterCombat = true
			return false
		end
		ReleaseState(self, previousOwner)
	end
	if state then
		if not Restore(state) then
			self.pendingNameplateResetAfterCombat = true
			return false
		end
		if state.token ~= token and self.nameplateFrameByUnitToken[state.token] == frame then
			self.nameplateFrameByUnitToken[state.token] = nil
		end
		if state.unitFrame ~= unitFrame then
			self.nameplateStateByUnitFrame[state.unitFrame] = nil
		end
	else
		state = { journal = {} }
		self.nameplateStateByFrame[frame] = state
	end
	state.token, state.unitFrame, state.frame, state.removed = token, unitFrame, frame, false
	self.nameplateStateByUnitFrame[unitFrame] = state
	self.nameplateFrameByUnitToken[token] = frame
	self:TrackNameplateFrame(frame)
	local unitKind = self:ResolveNameplateUnitKind(token)
	if not unitKind or unitKind == "npc" then
		return false
	end
	if not self:InstallNameplateFrameHooks(unitFrame) then
		self:RecordDiagnostic("hooks-unavailable")
		return false
	end
	local tinted = self:ApplyBorderTintForUnitFrame(unitFrame, unitKind)
	local capabilities = self:GetNameplateCapabilities()
	local configured = self:GetOption(unitKind .. "Style")
	if configured == nil or not capabilities.styleOverrides then
		return tinted
	end
	local style = self:GetConfiguredStyleForUnitKind(unitKind)
	if style == self:GetCurrentGlobalNameplateStyle() then
		return tinted
	end
	local plan = BuildPlan(unitFrame, style)
	if not plan then
		self:RecordDiagnostic("layout-unavailable")
		return false
	end
	local applied = Execute(state, plan)
	if not applied then
		self.pendingNameplateRefreshAfterCombat = true
	end
	return applied
end

function PvPTogether:ReapplyStyleForUnitToken(token)
	if not IsToken(token) then
		return false
	end
	local getPlate = Field(C_NamePlate, "GetNamePlateForUnit")
	if type(getPlate) ~= "function" then
		return false
	end
	local ok, frame = pcall(getPlate, token, false)
	return ok and self:CanAccessNameplateFrame(frame) and self:ReapplyStyleForNameplateFrame(frame) or false
end

PvPTogether.ReapplyStyleForAnyUnitToken = PvPTogether.ReapplyStyleForUnitToken
PvPTogether.ApplyPerTypeStyleToNameplateFrame = PvPTogether.ReapplyStyleForNameplateFrame

function PvPTogether:ApplyPerTypeStyleGeometryToUnitFrame(unitFrame)
	if not self:CanAccessNameplateFrame(unitFrame) then
		return false
	end
	local ok, parent = Call(unitFrame, "GetParent")
	return ok and self:ReapplyStyleForNameplateFrame(parent) or false
end

function PvPTogether:HandleNameplateRemoved(token)
	if not IsToken(token) then
		return
	end
	local frame = self.nameplateFrameByUnitToken[token]
	self.nameplateFrameByUnitToken[token] = nil
	if not frame then
		return
	end
	local state = self.nameplateStateByFrame[frame]
	if not state or state.token ~= token then
		return
	end
	state.removed = true
	local hidden = self:HideBorderTintForUnitFrame(state.unitFrame)
	if Restore(state) and hidden then
		ReleaseState(self, state)
	else
		self.pendingNameplateResetAfterCombat = true
	end
end

function PvPTogether:ResetAllNameplateStylesToBlizzard()
	local complete = true
	for frame, state in pairs(self.nameplateStateByFrame) do
		local restored = Restore(state)
		local hidden = self:HideBorderTintForUnitFrame(state.unitFrame)
		if restored and hidden then
			ReleaseState(self, state)
		else
			complete = false
		end
	end
	if not self:HideAllBorderTintOverrides() then
		complete = false
	end
	self.pendingNameplateResetAfterCombat = not complete
	return complete
end

function PvPTogether:ReapplyAllNameplateStyles()
	local stats = { inCombat = self:IsInCombatLockdown(), blocked = false, tracked = 0, tokens = 0, fallback = 0 }
	if not self.isEnabled then
		return stats
	end
	stats.blocked = self:IsNameplateAugmentationBlockedInCurrentContext()
	if self.pendingNameplateResetAfterCombat then
		self:ResetAllNameplateStylesToBlizzard()
	end
	self.pendingNameplateRefreshAfterCombat = false
	local getPlates = Field(C_NamePlate, "GetNamePlates")
	if type(getPlates) ~= "function" then
		return stats
	end
	local ok, frames = pcall(getPlates, false)
	if not ok or not self:CanAccessTable(frames) then
		return stats
	end
	for _, frame in pairs(frames) do
		if self:ReapplyStyleForNameplateFrame(frame) then
			stats.tracked = stats.tracked + 1
		end
	end
	return stats
end
PvPTogether.RefreshVisibleNameplateStyles = PvPTogether.ReapplyAllNameplateStyles

function PvPTogether:ScheduleReapplyAllNameplateStyles(delay, frame)
	if not self.isEnabled then
		return
	end
	if frame then
		self.nameplatePendingFrames = self.nameplatePendingFrames or {}
		self.nameplatePendingFrames[frame] = true
	else
		self.nameplateFullRefreshPending = true
	end
	if self.nameplateRefreshScheduled then
		return
	end
	local after = Field(C_Timer, "After")
	if type(after) ~= "function" then
		self:ReapplyAllNameplateStyles()
		return
	end
	self.nameplateRefreshScheduled = true
	after(
		math.max(0, self:SafeToNumber(delay) or 0),
		LibChev.Fence(self, { "nameplateScheduledReapplyGeneration" }, function()
			PvPTogether.nameplateRefreshScheduled = false
			local frames, full = PvPTogether.nameplatePendingFrames, PvPTogether.nameplateFullRefreshPending
			PvPTogether.nameplatePendingFrames, PvPTogether.nameplateFullRefreshPending = nil, false
			if PvPTogether.isEnabled then
				if full then
					PvPTogether:ReapplyAllNameplateStyles()
				else
					for pending in pairs(frames or {}) do
						PvPTogether:ReapplyStyleForNameplateFrame(pending)
					end
				end
			end
		end)
	)
end

function PvPTogether:TryInstallNameplateHooks()
	-- Mixins were copied into live frames before ADDON_LOADED; hook each actual
	-- unit frame on acquisition, and retry individual missing hooks later.
	self.nameplateHooksInstalled = type(hooksecurefunc) == "function" and self:GetNameplateCapabilities().borderTint
	return self.nameplateHooksInstalled
end

function PvPTogether:HandleNameplateContextChange()
	if self.RefreshOptionsWindow then
		self:RefreshOptionsWindow()
	end
	if self.pendingNameplateResetAfterCombat then
		self:ResetAllNameplateStylesToBlizzard()
	end
	if self.isEnabled then
		self:ScheduleReapplyAllNameplateStyles(0)
	end
end

function PvPTogether:EnsureNameplateEventFrame()
	if self.nameplateEventFrame then
		return self.nameplateEventFrame
	end
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "NAME_PLATE_CREATED" then
			PvPTogether:ObserveNameplateAcquisition(...)
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			PvPTogether:HandleNameplateRemoved(...)
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			if PvPTogether.isEnabled then
				PvPTogether:ReapplyStyleForUnitToken(...)
				PvPTogether:ScheduleReapplyAllNameplateStyles(0)
			end
		elseif event == "CVAR_UPDATE" then
			local name = ...
			if IsToken(name) and name:lower():find("nameplate", 1, true) then
				if PvPTogether.RefreshOptionsWindow then
					PvPTogether:RefreshOptionsWindow()
				end
				PvPTogether:ScheduleReapplyAllNameplateStyles(0)
			end
		elseif event == "ADDON_LOADED" then
			local name = ...
			if IsToken(name) and name == "Blizzard_NamePlates" then
				PvPTogether:TryInstallNameplateHooks()
				PvPTogether:HandleNameplateContextChange()
			end
		else
			PvPTogether:HandleNameplateContextChange()
		end
	end)
	-- Keep lifecycle/restriction events while disabled so deferred cleanup can finish.
	for _, event in ipairs({
		"ADDON_LOADED",
		"NAME_PLATE_CREATED",
		"NAME_PLATE_UNIT_ADDED",
		"NAME_PLATE_UNIT_REMOVED",
		"PLAYER_ENTERING_WORLD",
		"ZONE_CHANGED_NEW_AREA",
		"CVAR_UPDATE",
		"GROUP_ROSTER_UPDATE",
		"UNIT_FACTION",
		"PLAYER_TARGET_CHANGED",
		"PLAYER_REGEN_ENABLED",
		"PLAYER_REGEN_DISABLED",
		"ENCOUNTER_END",
		"CHALLENGE_MODE_COMPLETED",
		"CHALLENGE_MODE_RESET",
	}) do
		pcall(frame.RegisterEvent, frame, event)
	end
	if type(Field(C_RestrictedActions, "GetAddOnRestrictionState")) == "function" then
		pcall(frame.RegisterEvent, frame, "ADDON_RESTRICTION_STATE_CHANGED")
	end
	self.nameplateEventFrame = frame
	return frame
end

local function InvalidateDeferred(addon)
	LibChev.Advance(addon, "nameplateScheduledReapplyGeneration")
	addon.nameplateRefreshScheduled = false
	addon.nameplatePendingFrames, addon.nameplateFullRefreshPending = nil, false
	addon.pendingNameplateRefreshAfterCombat = false
end

function PvPTogether:EnableNameplateModule()
	InvalidateDeferred(self)
	self:EnsureNameplateEventFrame()
	self:TryInstallNameplateHooks()
	self:HandleNameplateContextChange()
end

function PvPTogether:DisableNameplateModule()
	InvalidateDeferred(self)
	self:ResetAllNameplateStylesToBlizzard()
end
