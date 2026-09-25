return function(H)
	local function styled()
		local addon, state, env = H.new()
		local base, unit, cast, health = state:plate("nameplate1")
		addon.isEnabled = true
		addon.db.enemyPlayerStyle = 2
		return addon, state, env, base, unit, cast, health
	end

	-- Forever beta 1.60.1.69977 Camelot constants/overrides and the right-side
	-- level layout are taken from the installed export cited in compatibility.md.
	local function foreverStyled(style)
		local addon, state, env = H.new({
			configure = function(client)
				client.GetBuildInfo = function()
					return "1.60.1", "69977", "Sep 24 2026", 16001
				end
				client.Enum.NamePlateStyle.Classic = 6
				client.NamePlateConstants.SMALL_HEALTH_BAR_HEIGHT = 13
				client.NamePlateConstants.SMALL_CAST_BAR_HEIGHT = 6
				client.NamePlateConstants.HEALTH_BAR_FONT_HEIGHT = 14
				client.NamePlateConstants.CAST_BAR_ICON_HEIGHT = 10
				client.NamePlateConstants.NAME_PLATE_WIDTH = 190
				client.NamePlateSetupOptions.healthBarFontHeight = client.NamePlateConstants.HEALTH_BAR_FONT_HEIGHT
				client.NamePlateSetupOptions.castIconHeight = client.NamePlateConstants.CAST_BAR_ICON_HEIGHT
				client.NamePlateSetupOptions.nameJustificationWhenAboveHealthBar = "CENTER"
				client.NamePlateSetupOptions.useOutlinedNameWhenAboveHealthBar = true
				client.NamePlateSetupOptions.healthBarToNameAboveSpacing = 2
			end,
		})
		local base, unit, cast, health = state:plate("nameplate1")
		state.frameData[base].width = env.NamePlateConstants.NAME_PLATE_WIDTH
		state.frameData[unit.HealthBarsContainer].points = {
			{ "BOTTOMLEFT", unit.CastBarsContainer, "TOPLEFT", 0, 2 },
			{ "BOTTOMRIGHT", unit.CastBarsContainer, "TOPRIGHT", -28, 2 },
		}
		local level = unit.PlayerLevelDiffFrame
		state.frameData[level].width = 28
		state.frameData[level].points = { { "LEFT", unit.HealthBarsContainer, "RIGHT", 0, 0 } }
		state.frameData[level].fields.ShouldDisplay = function()
			error("addon called native level display cache helper")
		end
		for _, fontString in ipairs({ unit.name, health.Text, health.LeftText, health.RightText }) do
			state.frameData[fontString].fontObject = env.SystemFont_NamePlate_Outlined
			state.frameData[fontString].textHeight = 14
		end
		addon.isEnabled, addon.db.enemyPlayerStyle = true, style or env.Enum.NamePlateStyle.Thin
		return addon, state, env, base, unit, cast, health, level
	end

	H.test("modern style changes current cast-container geometry without foreign state writes", function()
		local addon, state, _, base, unit, cast = styled()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(cast:GetHeight(), 16)
		H.equal(unit.CastBarsContainer:GetHeight(), 16)
		H.equal(state.foreignWrites, 0)
		H.equal(state.driverUpdates, 0)
		H.equal(#state.cvarWrites, 0)
		H.truthy(state:countMutations("SetPoint") > 0)
	end)

	H.test("preflight diagnostics distinguish permission failures without retaining foreign values", function()
		local addon, state, _, base, unit = styled()
		state.frameData[unit.CastBarsContainer].results.IsProtected = state:secretValue()
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
		H.equal(addon.lastLayoutFailure.step, 1)
		H.equal(addon.lastLayoutFailure.property, "height")
		H.equal(addon.lastLayoutFailure.stage, "snapshot")
		H.equal(addon.lastLayoutFailure.reason, "protection-result")
		H.equal(H.count(addon.lastLayoutFailure), 4)
		H.truthy(addon:BuildDiagnostics():find("layoutFailure.reason=protection-result", 1, true))
		state.frameData[unit.CastBarsContainer].results.IsProtected = nil
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(addon.lastLayoutFailure, nil)
	end)

	H.test("preflight diagnostics distinguish unnamed fonts from anchor permission failures", function()
		local addon, state, _, base, unit = styled()
		state.frameData[unit.name].fontObject = state:frame({}, true)
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
		H.equal(addon.lastLayoutFailure.property, "font")
		H.equal(addon.lastLayoutFailure.reason, "font-object-name")
		state.frameData[unit.name].fontObject = nil
		state.frameData[unit.CastBarsContainer].fields.IsAnchoringSecret = function()
			return true
		end
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
		H.equal(addon.lastLayoutFailure.property, "points")
		H.equal(addon.lastLayoutFailure.stage, "write-permission")
		H.equal(addon.lastLayoutFailure.reason, "anchor-target-permission")
	end)

	H.test("forbidden frame check precedes all other foreign member reads", function()
		local addon, state, _, base = styled()
		state.frameData[base].forbidden = true
		H.falsy(addon:CanAccessNameplateFrame(base))
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("inaccessible frame check precedes even IsForbidden lookup", function()
		local addon, state, _, base = styled()
		state.inaccessibleTables[base] = true
		H.falsy(addon:CanAccessNameplateFrame(base))
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	for _, mode in ipairs({ "missing", "error", "secret" }) do
		local fault = mode
		H.test("IsForbidden " .. fault .. " result fails closed", function()
			local addon, state, _, base = styled()
			if fault == "missing" then
				state.frameData[base].missing = { IsForbidden = true }
			elseif fault == "error" then
				state.frameData[base].errors.IsForbidden = true
			else
				state.frameData[base].results.IsForbidden = state:secretValue()
			end
			H.falsy(addon:CanAccessNameplateFrame(base))
			H.falsy(addon:ReapplyStyleForNameplateFrame(base))
			H.equal(#state.mutations, 0)
		end)
	end

	H.test("secret and failing IsProtected cannot authorize a mutation", function()
		local addon, state, _, base = styled()
		state.frameData[base].results.IsProtected = state:secretValue()
		H.falsy(addon:CanMutateNameplateFrame(base))
		state.frameData[base].results.IsProtected = nil
		state.frameData[base].errors.IsProtected = true
		H.falsy(addon:CanMutateNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("protected-function authorization is checked and errors fail closed", function()
		local addon, state, _, base = styled()
		state.allowProtectedFunctions = false
		H.falsy(addon:CanMutateNameplateFrame(base))
		state.allowProtectedFunctions = nil
		state.queryErrors.protectedFunctions = true
		H.falsy(addon:CanMutateNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("combat blocks all geometry and texture creation", function()
		local addon, state, _, base = styled()
		addon.db.enemyPlayerBorderEnabled = true
		state.combat = true
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.truthy(addon.pendingNameplateRefreshAfterCombat)
		H.equal(#state.mutations, 0)
		H.equal(#state.timers, 0)
	end)

	for _, restriction in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }) do
		local name = restriction
		H.test(name .. " activating restriction blocks protected geometry before combat starts", function()
			local addon, state, env, base = styled()
			for _, config in pairs(state.frameData) do
				if config.foreign then
					config.protected = true
				end
			end
			state.restricted[env.Enum.AddOnRestrictionType[name]] = env.Enum.AddOnRestrictionState.Activating
			H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
			H.falsy(addon:ReapplyStyleForNameplateFrame(base))
			H.equal(#state.mutations, 0)
		end)
	end

	H.test("restriction-state API errors and secret results fail closed", function()
		local addon, state, env = styled()
		state.queryErrors.restrictions = true
		H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
		state.queryErrors.restrictions = nil
		state.restricted[env.Enum.AddOnRestrictionType.Map] = state:secretValue()
		H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
	end)

	H.test("missing modern restriction API still honors combat lockdown", function()
		local addon, state = H.new({
			configure = function(env)
				env.C_RestrictedActions = nil
			end,
		})
		H.falsy(addon:IsNameplateAugmentationBlockedInCurrentContext())
		state.combat = true
		H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
	end)

	H.test("unit categories preserve party precedence and exclude self", function()
		local addon, state = H.new()
		state.units.party = { isPlayer = true, isFriend = true, inParty = true, isUnit = false }
		state.units.friend = { isPlayer = true, isFriend = true, inParty = false, isUnit = false }
		state.units.enemy = { isPlayer = true, isFriend = false }
		state.units.self = { isPlayer = true, isFriend = true, inParty = true, isUnit = true }
		state.units.npc = { isPlayer = false }
		H.equal(addon:ResolveNameplateUnitKind("party"), "partyMember")
		H.equal(addon:ResolveNameplateUnitKind("friend"), "friendlyPlayer")
		H.equal(addon:ResolveNameplateUnitKind("enemy"), "enemyPlayer")
		H.equal(addon:ResolveNameplateUnitKind("self"), "friendlyPlayer")
		H.equal(addon:ResolveNameplateUnitKind("npc"), "npc")
	end)

	for _, field in ipairs({ "isPlayer", "isFriend", "isUnit", "inParty" }) do
		local name = field
		H.test("secret " .. name .. " never becomes an enemy or party classification", function()
			local addon, state = H.new()
			state.units.nameplate1 = { isPlayer = true, isFriend = true, isUnit = false, inParty = false }
			state.units.nameplate1[name] = state:secretValue()
			H.equal(addon:ResolveNameplateUnitKind("nameplate1"), nil)
		end)
	end

	H.test("failed faction query produces unknown and does not touch geometry", function()
		local addon, state, _, base = styled()
		state.units.nameplate1.errors = { isFriend = true }
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("lookup identity mismatch rejects stale nameplate frame", function()
		local addon, state, _, base = styled()
		local replacement = state:frame({}, true)
		state.plates.nameplate1 = replacement
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("secret GetUnit result is rejected before token lookup", function()
		local addon, state, _, base = styled()
		state.frameData[base].results.GetUnit = state:secretValue()
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("same-token player to NPC recycling restores prior styling", function()
		local addon, state, _, base, _, cast = styled()
		local original = cast:GetHeight()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(cast:GetHeight(), 16)
		state.units.nameplate1 = { guid = "Creature-1-next", isPlayer = false }
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(cast:GetHeight(), original)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("recycled frame removes old token ownership before stale removal", function()
		local addon, state, _, base, unit, cast = styled()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		state.frameData[base].unit, state.frameData[unit].fields.unit = "nameplate2", "nameplate2"
		state.plates.nameplate1, state.plates.nameplate2 = nil, base
		state.units.nameplate2 = { guid = "Player-1-new", isPlayer = true, isFriend = false }
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		state:clearMutations()
		addon:HandleNameplateRemoved("nameplate1")
		H.equal(cast:GetHeight(), 16)
		H.equal(#state.mutations, 0)
		H.equal(addon.nameplateFrameByUnitToken.nameplate2, base)
	end)

	H.test("removal restores offscreen frames and releases tracking", function()
		local addon, state, _, base, _, cast = styled()
		local original = cast:GetHeight()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		state.visible, state.plates.nameplate1 = {}, nil
		addon:HandleNameplateRemoved("nameplate1")
		H.equal(cast:GetHeight(), original)
		H.equal(addon.nameplateStateByFrame[base], nil)
		H.equal(addon.nameplateFrameByUnitToken.nameplate1, nil)
		H.equal(addon.trackedNamePlateFrames[base], nil)
	end)

	H.test("disable restores only addon-owned journal without calling Blizzard reset", function()
		local addon, state, _, base, _, cast = styled()
		local original = cast:GetHeight()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		addon:Disable()
		H.equal(cast:GetHeight(), original)
		H.equal(H.count(addon.nameplateStateByFrame), 0)
		H.equal(state.driverUpdates, 0)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("disable during restrictions retains journal and completes on unlock event", function()
		local addon, state, env, base, _, cast = styled()
		addon:EnsureNameplateEventFrame()
		local original = cast:GetHeight()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		state.restricted[env.Enum.AddOnRestrictionType.Map] = env.Enum.AddOnRestrictionState.Active
		for _, config in pairs(state.frameData) do
			if config.foreign then
				config.protected = true
			end
		end
		state:clearMutations()
		addon:Disable()
		H.truthy(addon.pendingNameplateResetAfterCombat)
		H.equal(#state.mutations, 0)
		H.truthy(addon.nameplateStateByFrame[base])
		state.restricted = {}
		state:emit("ADDON_RESTRICTION_STATE_CHANGED")
		H.equal(cast:GetHeight(), original)
		H.falsy(addon.pendingNameplateResetAfterCombat)
		H.equal(H.count(addon.nameplateStateByFrame), 0)
		H.falsy(addon.isEnabled)
	end)

	H.test("forbidden child during teardown retains cleanup until accessible", function()
		local addon, state, _, base, _, cast = styled()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		state.frameData[cast].forbidden = true
		addon:Disable()
		H.truthy(addon.pendingNameplateResetAfterCombat)
		H.truthy(addon.nameplateStateByFrame[base])
		state.frameData[cast].forbidden = false
		H.truthy(addon:ResetAllNameplateStylesToBlizzard())
		H.equal(H.count(addon.nameplateStateByFrame), 0)
	end)

	H.test("deferred refreshes coalesce a burst into one timer", function()
		local addon, state = H.new()
		addon.hasLoggedIn = true
		addon:Enable()
		for _ = 1, 10 do
			addon:ScheduleReapplyAllNameplateStyles(0)
		end
		H.equal(#state.timers, 1)
		state:flushTimers()
		H.equal(#state.timers, 0)
		H.falsy(addon.nameplateRefreshScheduled)
	end)

	H.test("stale scheduled callback cannot revive after disable and re-enable", function()
		local addon, state = H.new()
		addon.hasLoggedIn = true
		addon:Enable()
		local stale = assert(state.timers[1]).callback
		addon:Disable()
		addon:Enable()
		local passes = 0
		addon.ReapplyAllNameplateStyles = function()
			passes = passes + 1
		end
		stale()
		H.equal(passes, 0)
		H.truthy(addon.nameplateRefreshScheduled)
		state.timers[#state.timers].callback()
		H.equal(passes, 1)
	end)

	H.test("restriction beginning after schedule blocks the queued mutation", function()
		local addon, state, _, base = styled()
		addon:EnableNameplateModule()
		state.combat = true
		state:flushTimers()
		H.equal(#state.mutations, 0)
		H.truthy(addon.pendingNameplateRefreshAfterCombat)
		H.equal(#(addon.nameplateStateByFrame[base] or { journal = {} }).journal, 0)
	end)

	H.test("individual hooks retry and attach to live unit frames", function()
		local addon, state, _, _, unit = styled()
		state.frameData[unit].missing = { ApplyFrameOptions = true }
		H.falsy(addon:InstallNameplateFrameHooks(unit))
		H.equal(#state.hooks, 1)
		H.equal(state.hooks[1].owner, unit)
		state.frameData[unit].missing = nil
		H.truthy(addon:InstallNameplateFrameHooks(unit))
		H.equal(#state.hooks, 2)
		H.truthy(addon:InstallNameplateFrameHooks(unit))
		H.equal(#state.hooks, 2)
	end)

	H.test("global Classic layout preserves native geometry", function()
		local addon, state, env, base = styled()
		env.Enum.NamePlateStyle.Classic = 6
		env.NamePlateSetupOptions.useClassicHealthBar = true
		env.NamePlateSetupOptions.useClassicCastBar = true
		H.falsy(addon:GetNameplateCapabilities().styleOverrides)
		H.truthy(addon:GetNameplateCapabilities().borderTint)
		addon:ReapplyStyleForNameplateFrame(base)
		H.equal(#state.mutations, 0)
	end)

	H.test("missing APIs report unavailable without throwing", function()
		local addon = H.new({
			configure = function(env)
				env.C_NamePlate = nil
			end,
		})
		H.falsy(addon:GetNameplateCapabilities().styleOverrides)
		H.falsy(addon:GetNameplateCapabilities().borderTint)
		addon.isEnabled = true
		H.falsy(addon:ReapplyStyleForUnitToken("nameplate1"))
		addon:ReapplyAllNameplateStyles()
	end)

	H.test("layout preflight rejects secret original geometry before first write", function()
		local addon, state, _, base, _, cast = styled()
		state.frameData[cast].results.GetHeight = state:secretValue()
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("layout preflight rejects forbidden required child before first write", function()
		local addon, state, _, base, unit = styled()
		state.frameData[unit.name].forbidden = true
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("unknown show-only-name flag never calls the Blizzard cache-populating helper", function()
		local addon, state, _, base, unit = styled()
		state.frameData[unit].fields.showOnlyName = nil
		state.frameData[unit].errors.IsShowOnlyName = true
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("native option updates supersede only corresponding journal properties", function()
		local addon, state, _, base, unit, cast = styled()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		state.frameData[cast].height = 31 -- A simulated native option pass, performed by fixture ownership.
		state:fireHook("ApplyFrameOptions", unit)
		addon:Disable()
		H.equal(cast:GetHeight(), 31)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("replacement health bar gets a new overlay and hides old texture", function()
		local addon, state, _, base, unit, _, oldHealth = styled()
		addon.db.enemyPlayerBorderEnabled = true
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		local old = assert(addon.nameplateBorderTintByUnitFrame[unit])
		local replacement = state:frame({}, true)
		state.frameData[unit.HealthBarsContainer].fields.healthBar = replacement
		H.truthy(addon:ApplyBorderTintForUnitFrame(unit, "enemyPlayer"))
		local new = assert(addon.nameplateBorderTintByUnitFrame[unit])
		H.truthy(old.Texture ~= new.Texture)
		H.equal(state.frameData[old.Texture].parent, oldHealth)
		H.equal(state.frameData[new.Texture].parent, replacement)
		H.falsy(old.Texture:IsShown())
		H.truthy(new.Texture:IsShown())
	end)

	H.test("border tint inherits alpha without reading potentially secret health alpha", function()
		local addon, state, _, base, unit, _, health = styled()
		addon.db.enemyPlayerBorderEnabled = true
		state.frameData[health].errors.GetAlpha = true
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		local texture = addon.nameplateBorderTintByUnitFrame[unit].Texture
		local tint
		for _, mutation in ipairs(state.mutations) do
			if mutation.frame == texture and mutation.method == "SetVertexColor" then
				tint = mutation.arguments
			end
		end
		H.equal(assert(tint)[4], 1)
	end)

	H.test("inaccessible enumeration table is never iterated", function()
		local addon, state = H.new()
		state.visible = setmetatable({}, {
			__pairs = function()
				error("inaccessible enumeration iterated")
			end,
		})
		state.inaccessibleTables[state.visible] = true
		addon.isEnabled = true
		addon:ReapplyAllNameplateStyles()
		H.equal(#state.mutations, 0)
	end)

	H.test("visible names beyond the former 80-token polling limit refresh normally", function()
		local addon, state = H.new()
		local _, _, cast = state:plate("nameplate120")
		addon.isEnabled, addon.db.enemyPlayerStyle = true, 2
		addon:ReapplyAllNameplateStyles()
		H.equal(cast:GetHeight(), 16)
	end)

	H.test("combat removal hides permitted addon texture before pooled frame reuse", function()
		local addon, state, _, base, unit = styled()
		addon.db.enemyPlayerBorderEnabled = true
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		local texture = addon.nameplateBorderTintByUnitFrame[unit].Texture
		H.truthy(texture:IsShown())
		state.combat, state.allowProtectedFunctions = true, true
		for _, config in pairs(state.frameData) do
			if config.foreign then
				config.protected = true
			end
		end
		state:clearMutations()
		addon:HandleNameplateRemoved("nameplate1")
		H.falsy(texture:IsShown())
		H.equal(state:countMutations("Hide", texture), 1)
		H.equal(state:countMutations("SetHeight"), 0)
		H.equal(state:countMutations("SetPoint"), 0)
		H.truthy(addon.pendingNameplateResetAfterCombat)
	end)

	H.test("engine-denied texture cleanup remains pending until permission returns", function()
		local addon, state, _, base, unit = styled()
		addon.db.enemyPlayerBorderEnabled = true
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		local texture = addon.nameplateBorderTintByUnitFrame[unit].Texture
		state.combat, state.allowProtectedFunctions = true, false
		state:clearMutations()
		addon:HandleNameplateRemoved("nameplate1")
		H.truthy(texture:IsShown())
		H.equal(#state.mutations, 0)
		H.truthy(addon.pendingNameplateResetAfterCombat)
		state.combat, state.allowProtectedFunctions = false, true
		H.truthy(addon:ResetAllNameplateStylesToBlizzard())
		H.falsy(texture:IsShown())
		H.equal(addon.nameplateStateByFrame[base], nil)
	end)

	for _, predicate in ipairs({ "IsAnchoringRestricted", "IsAnchoringSecret" }) do
		local name = predicate
		H.test(name .. " target respects the local anchor family", function()
			local addon, state, _, base, unit = styled()
			state.frameData[unit.CastBarsContainer].fields[name] = function()
				return true
			end
			if name == "IsAnchoringRestricted" then
				H.truthy(addon:ReapplyStyleForNameplateFrame(base))
			else
				H.falsy(addon:ReapplyStyleForNameplateFrame(base))
				H.equal(#state.mutations, 0)
			end
		end)
		H.test(name .. " secret result prevents all style writes", function()
			local addon, state, _, base, _, cast = styled()
			local secret = state:secretValue()
			state.frameData[cast].fields[name] = function()
				return secret
			end
			H.falsy(addon:ReapplyStyleForNameplateFrame(base))
			H.equal(#state.mutations, 0)
		end)
	end

	H.test("restricted nameplate children permit local geometry and owned border anchors", function()
		local addon, state, _, base, unit, cast = styled()
		addon.db.enemyPlayerBorderEnabled = true
		for _, config in pairs(state.frameData) do
			config.fields.IsAnchoringRestricted = function()
				return true
			end
		end
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(cast:GetHeight(), 16)
		H.truthy(addon.nameplateBorderTintByUnitFrame[unit].Texture:IsShown())
		H.equal(state.foreignWrites, 0)
		H.truthy(addon:ResetAllNameplateStylesToBlizzard())
		H.equal(cast:GetHeight(), 20)
	end)

	local function observedRestrictedPlate(auraWithoutClear)
		local addon, state, env, base, unit, cast, health = styled()
		local debuffs = unit.AurasFrame.DebuffListFrame
		if auraWithoutClear then
			state.frameData[debuffs].points = { { "BOTTOM", unit.name, "TOP", 0, 0 } }
		end
		for _, config in pairs(state.frameData) do
			config.fields.IsAnchoringRestricted = function()
				return true
			end
			config.errors.GetPoint = true
		end
		state.frameData[base].fields.AcquireUnitFrame = function() end
		state.frameData[base].fields.UnitFrame = nil
		addon:EnsureNameplateEventFrame()
		state:emit("NAME_PLATE_CREATED", base)
		state.frameData[base].fields.UnitFrame = unit
		state:fireHook("AcquireUnitFrame", base)
		for object in pairs(addon.nameplateAnchorRecords) do
			if auraWithoutClear and object == debuffs then
				object:SetPoint("BOTTOM", unit.name, "TOP", 0, 0)
			else
				object:ClearAllPoints()
				object:SetPoint("CENTER", state.frameData[object].parent, "CENTER", 0, 0)
			end
		end
		state:clearMutations()
		return addon, state, env, base, unit, cast, health
	end

	H.test("native acquisition captures reversible anchors without querying restricted positions", function()
		local addon, state, _, base, unit, cast = observedRestrictedPlate()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(cast:GetHeight(), 16)
		H.equal(state.frameData[unit.name].points[1][1], "LEFT")
		H.truthy(addon:ResetAllNameplateStylesToBlizzard())
		H.equal(state.frameData[cast].points[1][1], "CENTER")
		H.equal(state.frameData[unit.name].points[1][1], "CENTER")
		H.equal(cast:GetHeight(), 20)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("native aura anchors updated without a clear permit the full bar style", function()
		local addon, state, _, base, unit, cast = observedRestrictedPlate(true)
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(cast:GetHeight(), 16)
		H.equal(state.frameData[unit.name].points[1][1], "LEFT")
		H.truthy(addon:ResetAllNameplateStylesToBlizzard())
		local point = state.frameData[unit.AurasFrame.DebuffListFrame].points[1]
		H.equal(point[1], "BOTTOM")
		H.equal(point[2], unit.name)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("partial anchor observations wait until all current points are known", function()
		local addon, state, _, base, unit = observedRestrictedPlate()
		local debuffs = unit.AurasFrame.DebuffListFrame
		state.frameData[debuffs].points = {
			{ "BOTTOM", unit.name, "TOP", 0, 0 },
			{ "LEFT", unit, "LEFT", 0, 0 },
		}
		state:fireHook("SetAllPoints", debuffs, unit)
		debuffs:SetPoint("BOTTOM", unit.name, "TOP", 0, 0)
		state:clearMutations()
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(addon.lastLayoutFailure.step, 15)
		H.equal(addon.lastLayoutFailure.reason, "anchor-baseline-pending")
		H.equal(#state.mutations, 0)
		debuffs:SetPoint("LEFT", unit, "LEFT", 0, 0)
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
	end)

	H.test("unreadable or invalid anchor counts invalidate observations and recover on a native update", function()
		for _, mode in ipairs({ "secret", "error", "fraction", "too-small", "too-large" }) do
			local addon, state, _, base, unit = observedRestrictedPlate(true)
			local debuffs = unit.AurasFrame.DebuffListFrame
			local config = state.frameData[debuffs]
			if mode == "error" then
				config.errors.GetNumPoints = true
			else
				config.results.GetNumPoints = mode == "secret" and state:secretValue()
					or mode == "fraction" and 1.5
					or mode == "too-small" and 0
					or 17
			end
			debuffs:SetPoint("BOTTOM", unit.name, "TOP", 0, 0)
			state:clearMutations()
			H.falsy(addon:ReapplyStyleForNameplateFrame(base))
			H.equal(addon.lastLayoutFailure.reason, "anchor-baseline-pending")
			H.equal(#state.mutations, 0)
			config.errors.GetNumPoints = nil
			config.results.GetNumPoints = nil
			debuffs:SetPoint("BOTTOM", unit.name, "TOP", 0, 0)
			H.truthy(addon:ReapplyStyleForNameplateFrame(base))
			H.equal(state.foreignWrites, 0)
		end
	end)

	H.test("observed restricted anchors preserve newer third-party changes on teardown", function()
		local addon, state, _, base, unit = observedRestrictedPlate()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		unit.name:ClearAllPoints()
		unit.name:SetPoint("TOP", unit, "TOP", 9, 11)
		H.truthy(addon:ResetAllNameplateStylesToBlizzard())
		H.equal(state.frameData[unit.name].points[1][1], "TOP")
		H.equal(state.frameData[unit.name].points[1][4], 9)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("secret or unobserved anchor changes invalidate the restricted baseline", function()
		for _, mode in ipairs({ "secret", "unobserved" }) do
			local addon, state, _, base, _, cast = observedRestrictedPlate()
			if mode == "secret" then
				state:fireHook("SetPoint", cast, "TOP", state.frameData[cast].parent, "TOP", state:secretValue(), 0)
			else
				state:fireHook("SetAllPoints", cast, state.frameData[cast].parent)
			end
			H.falsy(addon:ReapplyStyleForNameplateFrame(base))
			H.equal(addon.lastLayoutFailure.reason, "anchor-baseline-pending")
			H.equal(#state.mutations, 0)
			cast:ClearAllPoints()
			cast:SetPoint("CENTER", state.frameData[cast].parent, "CENTER", 0, 0)
			H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		end
	end)

	H.test("restricted anchor families never cross into another plate or an unreadable parent", function()
		for _, mode in ipairs({ "other-plate", "secret-parent", "parent-cycle" }) do
			local addon, state, _, base, unit, cast = styled()
			state.frameData[cast].fields.IsAnchoringRestricted = function()
				return true
			end
			if mode == "other-plate" then
				local _, otherUnit = state:plate("nameplate2")
				state.frameData[cast].parent = otherUnit
			elseif mode == "secret-parent" then
				state.frameData[cast].parent = state:secretValue()
			else
				state.frameData[cast].parent = cast
			end
			H.falsy(addon:ReapplyStyleForNameplateFrame(base))
			H.equal(#state.mutations, 0)
		end
	end)

	H.test("font journal preserves native font-object association through disable", function()
		local addon, state, env, base, unit = styled()
		local font = unit.name:GetFontObject()
		local _, height = unit.name:GetFont()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(unit.name:GetFontObject(), env.SystemFont_NamePlate_Outlined)
		H.equal(state:countMutations("SetFont"), 0)
		addon:Disable()
		H.equal(unit.name:GetFontObject(), font)
		local _, restoredHeight = unit.name:GetFont()
		H.equal(restoredHeight, height)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("partial geometry write failure rolls back previous writes and retains failed cleanup", function()
		local addon, state, _, base, unit, cast = styled()
		local original = unit.CastBarsContainer:GetHeight()
		state.frameData[cast].errors.SetHeight = true
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(unit.CastBarsContainer:GetHeight(), original)
		H.truthy(#addon.nameplateStateByFrame[base].journal > 0)
		state.frameData[cast].errors.SetHeight = nil
		addon:Disable()
		H.equal(addon.nameplateStateByFrame[base], nil)
		H.equal(cast:GetHeight(), 20)
	end)

	H.test("font partial failure restores original font object after retry", function()
		local addon, state, _, base, unit = styled()
		local original = unit.name:GetFontObject()
		state.frameData[unit.name].errors.SetTextHeight = true
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(unit.name:GetFontObject(), original)
		state.frameData[unit.name].errors.SetTextHeight = nil
		addon:Disable()
		H.equal(unit.name:GetFontObject(), original)
		H.equal(addon.nameplateStateByFrame[base], nil)
	end)

	H.test("secret protection method is not mistaken for an absent region method", function()
		local addon, state, _, base = styled()
		state.frameData[base].fields.IsProtected = state:secretValue()
		H.falsy(addon:CanMutateNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("PvP permits unprotected public visual regions when native checks allow them", function()
		local addon, state, env, base, _, cast = styled()
		state.combat = true
		state.restricted[env.Enum.AddOnRestrictionType.PvPMatch] = env.Enum.AddOnRestrictionState.Active
		state.allowProtectedFunctions = true
		state.frameData[base].protected = true -- The base is read only; children remain explicitly unprotected.
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(cast:GetHeight(), 16)
		H.equal(state:countMutations(nil, base), 0)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("restricted regions without protection metadata cannot be mutated", function()
		local addon, state, _, base, _, cast = styled()
		state.combat, state.allowProtectedFunctions = true, true
		state.frameData[cast].missing = { IsProtected = true }
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("native layout hook refreshes only the affected plate", function()
		local addon, state, _, base, unit = styled()
		local otherBase, _, otherCast = state:plate("nameplate2")
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.truthy(addon:ReapplyStyleForNameplateFrame(otherBase))
		state:clearMutations()
		addon.nameplateScheduledReapplyGeneration = 0
		state:fireHook("UpdateAnchors", unit)
		H.equal(#state.timers, 1)
		state:flushTimers()
		H.equal(state:countMutations(nil, otherCast), 0)
		H.truthy(#state.mutations > 0)
	end)

	H.test("teardown preserves a newer third-party property change", function()
		local addon, state, _, base, unit, cast = styled()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		state.frameData[unit.CastBarsContainer].height = 31
		addon:Disable()
		H.equal(unit.CastBarsContainer:GetHeight(), 31)
		H.equal(cast:GetHeight(), 20)
		H.equal(H.count(addon.nameplateStateByFrame), 0)
	end)

	H.test("unit frame recycled onto another base cannot be reset by old token removal", function()
		local addon, state, _, oldBase, unit, cast = styled()
		H.truthy(addon:ReapplyStyleForNameplateFrame(oldBase))
		local newBase = state:plate("nameplate2")
		state.frameData[newBase].fields.UnitFrame = unit
		state.frameData[unit].parent, state.frameData[unit].fields.unit = newBase, "nameplate2"
		state.plates.nameplate1 = nil
		H.truthy(addon:ReapplyStyleForNameplateFrame(newBase))
		state:clearMutations()
		addon:HandleNameplateRemoved("nameplate1")
		H.equal(cast:GetHeight(), 16)
		H.equal(#state.mutations, 0)
		H.equal(addon.nameplateStateByUnitFrame[unit], addon.nameplateStateByFrame[newBase])
		addon:Disable()
		H.equal(cast:GetHeight(), 20)
	end)

	H.test("shared Blizzard setup tables and API registries remain read only", function()
		local sharedWrites = 0
		local addon, state = H.new({
			configure = function(env)
				local function readonly(backing)
					return setmetatable({}, {
						__index = backing,
						__newindex = function()
							sharedWrites = sharedWrites + 1
							error("addon wrote shared Blizzard table")
						end,
						__pairs = function()
							return pairs(backing)
						end,
					})
				end
				for _, name in ipairs({
					"NamePlateSetupOptions",
					"NamePlateConstants",
					"NamePlateBaseMixin",
					"NamePlateUnitFrameMixin",
					"NamePlateDriverMixin",
					"C_NamePlate",
					"C_CVar",
					"C_RestrictedActions",
				}) do
					env[name] = readonly(env[name])
				end
			end,
		})
		local base = state:plate("nameplate1")
		addon.isEnabled, addon.db.enemyPlayerStyle = true, 2
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		addon:Disable()
		H.equal(sharedWrites, 0)
		H.equal(state.foreignWrites, 0)
		H.equal(state:countMutations("SetSize", base), 0)
	end)

	H.test("offline harness and regressions are excluded from addon manifest", function()
		local file = assert(io.open(H.root .. "/PvPTogether.toc", "r"))
		local manifest = file:read("*a")
		file:close()
		H.falsy(manifest:find("scripts/", 1, true))
		H.falsy(manifest:find("tests/", 1, true))
		H.falsy(manifest:find("test.lua", 1, true))
	end)

	for _, example in ipairs({
		{ style = 1, label = "Thin", healthHeight = 13, castHeight = 6, containerHeight = 16 },
		{ style = 3, label = "HealthFocus", healthHeight = 20, castHeight = 6, containerHeight = 16 },
		{ style = 4, label = "CastFocus", healthHeight = 13, castHeight = 16, containerHeight = 16 },
		{ style = 5, label = "Legacy", healthHeight = 13, castHeight = 6, containerHeight = 16 },
	}) do
		local expected = example
		H.test("Forever " .. expected.label .. " geometry uses loaded Camelot dimensions", function()
			local addon, _, env, base, unit, cast, health = foreverStyled(expected.style)
			H.truthy(addon:ReapplyStyleForNameplateFrame(base))
			H.equal(unit.HealthBarsContainer:GetHeight(), expected.healthHeight)
			H.equal(cast:GetHeight(), expected.castHeight)
			H.equal(unit.CastBarsContainer:GetHeight(), expected.containerHeight)
			local _, nameHeight = unit.name:GetFont()
			local _, healthTextHeight = health.Text:GetFont()
			H.equal(nameHeight, 14)
			H.equal(healthTextHeight, 14)
			H.equal(unit.name:GetFontObject(), env.SystemFont_NamePlate_Outlined)
			H.equal(health.Text:GetFontObject(), env.SystemFont_NamePlate)
			H.equal(base:GetWidth(), 190)
		end)
	end

	H.test("Forever centered outlined name follows visible right-side level without changing native offsets", function()
		local addon, state, env, base, unit, _, _, level = foreverStyled()
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(unit.name:GetJustifyH(), "CENTER")
		H.equal(unit.name:GetFontObject(), env.SystemFont_NamePlate_Outlined)
		local point, relative, relativePoint, x, y = unit.name:GetPoint(2)
		H.equal(point, "RIGHT")
		H.equal(relative, level)
		H.equal(relativePoint, "RIGHT")
		H.equal(x, 0)
		H.equal(y, 0)
		point, relative, relativePoint, x, y = unit.HealthBarsContainer:GetPoint(2)
		H.equal(point, "BOTTOMRIGHT")
		H.equal(relative, unit.CastBarsContainer)
		H.equal(relativePoint, "TOPRIGHT")
		H.equal(x, -28)
		H.equal(y, 2)
		H.equal(state:countMutations("SetPoint", unit.HealthBarsContainer), 0)
		H.equal(state:countMutations("ClearAllPoints", unit.HealthBarsContainer), 0)
		H.equal(state:countMutations(nil, level), 0)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("Forever hidden level falls back to the health-text boundary", function()
		local addon, state, env, base, unit, _, health, level = foreverStyled()
		state.frameData[level].shown = false
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		local _, relative, _, x = unit.name:GetPoint(2)
		H.equal(relative, health.Text)
		H.equal(x, -2)
		H.equal(unit.name:GetJustifyH(), "CENTER")
		H.equal(unit.name:GetFontObject(), env.SystemFont_NamePlate_Outlined)
		H.equal(state:countMutations(nil, level), 0)
		H.equal(state:countMutations("SetPoint", unit.HealthBarsContainer), 0)
	end)

	H.test("Forever secret level visibility aborts before any partial layout writes", function()
		local addon, state, _, base, _, _, _, level = foreverStyled()
		state.frameData[level].results.IsShown = state:secretValue()
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
		H.equal(#addon.nameplateStateByFrame[base].journal, 0)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("secret restriction API is not treated as an absent legacy capability", function()
		local addon, state, env, base, _, cast = styled()
		state.frameData[cast].protected = true
		state.restricted[env.Enum.AddOnRestrictionType.Encounter] = env.Enum.AddOnRestrictionState.Active
		env.C_RestrictedActions.GetAddOnRestrictionState = state:secretValue()
		H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
		H.falsy(addon:CanMutateNameplateFrame(cast))
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("secret permission API blocks layout and retains owned tint cleanup", function()
		local addon, state, env, base, unit, cast = styled()
		addon.db.enemyPlayerBorderEnabled = true
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		local texture = addon.nameplateBorderTintByUnitFrame[unit].Texture
		local permissionAPI = env.C_RestrictedActions.CheckAllowProtectedFunctions
		env.C_RestrictedActions.CheckAllowProtectedFunctions = state:secretValue()
		state:clearMutations()
		H.falsy(addon:CanMutateNameplateFrame(cast))
		addon:Disable()
		H.truthy(addon.pendingNameplateResetAfterCombat)
		H.truthy(texture:IsShown())
		H.equal(#state.mutations, 0)
		env.C_RestrictedActions.CheckAllowProtectedFunctions = permissionAPI
		H.truthy(addon:ResetAllNameplateStylesToBlizzard())
		H.falsy(texture:IsShown())
	end)

	H.test("unreadable restriction enum entry cannot silently omit a safety check", function()
		local addon, state, env, base, _, cast = styled()
		state.frameData[cast].protected = true
		env.Enum.AddOnRestrictionType.Encounter = state:secretValue()
		H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
		H.falsy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("genuinely absent restriction APIs keep out-of-combat legacy styling available", function()
		local addon, state = H.new({
			configure = function(env)
				env.C_RestrictedActions = nil
			end,
		})
		local base, _, cast = state:plate("nameplate1")
		state.frameData[cast].protected = true
		addon.isEnabled, addon.db.enemyPlayerStyle = true, 2
		H.falsy(addon:IsNameplateAugmentationBlockedInCurrentContext())
		H.truthy(addon:CanMutateNameplateFrame(cast))
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		H.equal(cast:GetHeight(), 16)
		H.equal(state.foreignWrites, 0)
	end)
end
