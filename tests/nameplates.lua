return function(H)
	local function bordered()
		local addon, state, env = H.new()
		local base, unit, cast, health = state:plate("nameplate1")
		addon.isEnabled, addon.db.enemyPlayerBorderEnabled = true, true
		return addon, state, env, base, unit, cast, health
	end
	local function NativeUntouched(state)
		H.equal(state.foreignWrites, 0)
		H.equal(state.nativeMutationAttempts, 0)
		for _, mutation in ipairs(state.mutations) do
			H.falsy(
				state.frameData[mutation.frame].foreign and mutation.method ~= "CreateTexture",
				"native widget mutated: " .. mutation.method
			)
		end
		H.equal(#state.hooks, 0)
		H.equal(#state.cvarWrites, 0)
	end

	H.test("retired styles never touch native layout even with unreadable geometry", function()
		local addon, state, env, base, unit = bordered()
		addon.db.enemyPlayerStyle = 2
		env.NamePlateSetupOptions, env.NamePlateConstants, env.hooksecurefunc = nil, nil, nil
		for object, config in pairs(state.frameData) do
			if config.foreign then
				config.errors.GetHeight, config.errors.GetPoint, config.errors.GetFont = true, true, true
				config.fields.IsAnchoringRestricted = function()
					return true
				end
			end
		end
		state.frameData[unit].fields.showOnlyName = nil
		H.truthy(addon:RefreshNameplateFrame(base))
		H.truthy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		NativeUntouched(state)
	end)

	H.test("target focus casting native refresh and CVars leave Blizzard geometry intact", function()
		local addon, state, _, base, unit, cast = bordered()
		addon:EnsureNameplateEventFrame()
		H.truthy(addon:RefreshNameplateFrame(base))
		state.frameData[cast].height = 37
		state.frameData[unit.name].points = { { "BOTTOM", unit.HealthBarsContainer, "TOP", 0, 5 } }
		for _, event in ipairs({
			"PLAYER_TARGET_CHANGED",
			"PLAYER_FOCUS_CHANGED",
			"UNIT_SPELLCAST_START",
			"UNIT_SPELLCAST_STOP",
			"UNIT_FACTION",
			"GROUP_ROSTER_UPDATE",
		}) do
			state:emit(event, "nameplate1")
			state:flushTimers()
		end
		state:emit("CVAR_UPDATE", "nameplateStyle")
		state:flushTimers()
		H.equal(cast:GetHeight(), 37)
		H.equal(state.frameData[unit.name].points[1][1], "BOTTOM")
		H.truthy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		addon:Disable()
		H.equal(cast:GetHeight(), 37)
		NativeUntouched(state)
	end)

	H.test("classification becoming unavailable hides only the owned border", function()
		local addon, state, _, base, unit, cast = bordered()
		H.truthy(addon:RefreshNameplateFrame(base))
		local height = cast:GetHeight()
		state.units.nameplate1.isFriend = state:secretValue()
		H.falsy(addon:RefreshNameplateFrame(base))
		H.falsy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		H.truthy(addon.pendingBorderRefresh)
		H.equal(cast:GetHeight(), height)
		state.units.nameplate1.isFriend = false
		addon:RefreshNameplates()
		H.truthy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		H.falsy(addon.pendingBorderRefresh)
		NativeUntouched(state)
	end)

	H.test("recycled token and player-to-NPC changes cannot inherit the old border", function()
		local addon, state, _, base, unit = bordered()
		H.truthy(addon:RefreshNameplateFrame(base))
		state.units.nameplate1.isPlayer = false
		H.truthy(addon:RefreshNameplateFrame(base))
		H.falsy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		state.frameData[base].unit = "nameplate2"
		state.units.nameplate2 = { isPlayer = true, isFriend = false }
		state.plates.nameplate2 = base
		H.truthy(addon:RefreshNameplateFrame(base))
		addon:HandleNameplateRemoved("nameplate1")
		H.truthy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		addon:HandleNameplateRemoved("nameplate2")
		H.falsy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		H.equal(addon.nameplateStateByFrame[base], nil)
		NativeUntouched(state)
	end)

	H.test("pooled unit frames transfer ownership without old removal hiding the new border", function()
		local addon, state, _, oldBase, unit = bordered()
		H.truthy(addon:RefreshNameplateFrame(oldBase))
		local newBase = state:plate("nameplate2")
		state.frameData[newBase].fields.UnitFrame = unit
		state.frameData[unit].parent = newBase
		state.plates.nameplate1 = nil
		H.truthy(addon:RefreshNameplateFrame(newBase))
		addon:HandleNameplateRemoved("nameplate1")
		H.truthy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		H.equal(addon.nameplateStateByFrame[oldBase], nil)
		NativeUntouched(state)
	end)

	H.test("disable retains blocked border cleanup and retries while disabled", function()
		local addon, state, _, base, unit = bordered()
		addon:EnsureNameplateEventFrame()
		H.truthy(addon:RefreshNameplateFrame(base))
		state.allowProtectedFunctions = false
		addon:Disable()
		H.truthy(addon.pendingBorderCleanup)
		H.truthy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		state.allowProtectedFunctions = true
		state:emit("PLAYER_REGEN_ENABLED")
		H.falsy(addon.pendingBorderCleanup)
		H.falsy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		H.equal(H.count(addon.nameplateStateByFrame), 0)
		H.equal(#state.timers, 0)
		NativeUntouched(state)
	end)

	H.test("refresh bursts coalesce and old callbacks cannot revive a disabled lifetime", function()
		local addon, state = bordered()
		addon.hasLoggedIn = true
		addon:ScheduleNameplateRefresh(0)
		addon:ScheduleNameplateRefresh(0)
		H.equal(#state.timers, 1)
		local old = state.timers[1].callback
		addon:Disable()
		addon:Enable()
		state:clearMutations()
		old()
		H.equal(#state.mutations, 0)
		state:flushTimers()
		H.truthy(#state.mutations > 0)
		NativeUntouched(state)
	end)

	H.test("border anchors stay within the health bar family and fail on secret permissions", function()
		for _, mode in ipairs({ "other-root", "secret", "unreadable" }) do
			local addon, state, _, base, _, _, health = bordered()
			local anchor = health.bgTexture
			if mode == "other-root" then
				state.frameData[anchor].parent = state:frame({}, true)
			elseif mode == "secret" then
				state.frameData[anchor].fields.IsAnchoringSecret = function()
					return true
				end
			else
				state.frameData[anchor].fields.IsAnchoringRestricted = function()
					return state:secretValue()
				end
			end
			H.falsy(addon:RefreshNameplateFrame(base))
			H.equal(state:countMutations("SetPoint"), 0)
			NativeUntouched(state)
		end
	end)

	H.test("permitted unprotected PvP borders and Classic global layouts remain supported", function()
		local addon, state, env, base, unit = bordered()
		state.restricted[env.Enum.AddOnRestrictionType.PvPMatch] = env.Enum.AddOnRestrictionState.Active
		state.allowProtectedFunctions = true
		env.NamePlateSetupOptions.useClassicHealthBar = true
		H.truthy(addon:RefreshNameplateFrame(base))
		H.truthy(addon.nameplateBorderTintByUnitFrame[unit].visible)
		NativeUntouched(state)
	end)

	H.test("offline fixtures remain excluded from the addon manifest", function()
		local file = assert(io.open(H.root .. "/PvPTogether.toc"))
		local toc = file:read("*a")
		file:close()
		H.falsy(toc:find("tests/", 1, true))
		H.falsy(toc:find("scripts/", 1, true))
	end)

	H.test("forbidden frame check precedes all other foreign member reads", function()
		local addon, state, _, base = bordered()
		state.frameData[base].forbidden = true
		H.falsy(addon:CanAccessNameplateFrame(base))
		H.falsy(addon:RefreshNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("inaccessible frame check precedes even IsForbidden lookup", function()
		local addon, state, _, base = bordered()
		state.inaccessibleTables[base] = true
		H.falsy(addon:CanAccessNameplateFrame(base))
		H.falsy(addon:RefreshNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	for _, mode in ipairs({ "missing", "error", "secret" }) do
		local fault = mode
		H.test("IsForbidden " .. fault .. " result fails closed", function()
			local addon, state, _, base = bordered()
			if fault == "missing" then
				state.frameData[base].missing = { IsForbidden = true }
			elseif fault == "error" then
				state.frameData[base].errors.IsForbidden = true
			else
				state.frameData[base].results.IsForbidden = state:secretValue()
			end
			H.falsy(addon:CanAccessNameplateFrame(base))
			H.falsy(addon:RefreshNameplateFrame(base))
			H.equal(#state.mutations, 0)
		end)
	end

	H.test("secret and failing IsProtected cannot authorize a mutation", function()
		local addon, state, _, base = bordered()
		state.frameData[base].results.IsProtected = state:secretValue()
		H.falsy(addon:CanMutateNameplateFrame(base))
		state.frameData[base].results.IsProtected = nil
		state.frameData[base].errors.IsProtected = true
		H.falsy(addon:CanMutateNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("protected-function authorization is checked and errors fail closed", function()
		local addon, state, _, base = bordered()
		state.allowProtectedFunctions = false
		H.falsy(addon:CanMutateNameplateFrame(base))
		state.allowProtectedFunctions = nil
		state.queryErrors.protectedFunctions = true
		H.falsy(addon:CanMutateNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("combat without explicit permission blocks texture creation", function()
		local addon, state, _, base = bordered()
		addon.db.enemyPlayerBorderEnabled = true
		state.combat = true
		H.falsy(addon:RefreshNameplateFrame(base))
		H.truthy(addon.pendingBorderRefresh)
		H.equal(#state.mutations, 0)
		H.equal(#state.timers, 0)
	end)

	for _, restriction in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }) do
		local name = restriction
		H.test(name .. " activating restriction blocks protected border creation before combat starts", function()
			local addon, state, env, base = bordered()
			for _, config in pairs(state.frameData) do
				if config.foreign then
					config.protected = true
				end
			end
			state.restricted[env.Enum.AddOnRestrictionType[name]] = env.Enum.AddOnRestrictionState.Activating
			H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
			H.falsy(addon:RefreshNameplateFrame(base))
			H.equal(#state.mutations, 0)
		end)
	end

	H.test("restriction-state API errors and secret results fail closed", function()
		local addon, state, env = bordered()
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

	H.test("failed faction query produces unknown and does not create a border", function()
		local addon, state, _, base = bordered()
		state.units.nameplate1.errors = { isFriend = true }
		H.falsy(addon:RefreshNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("lookup identity mismatch rejects stale nameplate frame", function()
		local addon, state, _, base = bordered()
		local replacement = state:frame({}, true)
		state.plates.nameplate1 = replacement
		H.falsy(addon:RefreshNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("secret GetUnit result is rejected before token lookup", function()
		local addon, state, _, base = bordered()
		state.frameData[base].results.GetUnit = state:secretValue()
		H.falsy(addon:RefreshNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("replacement health bar gets a new overlay and hides old texture", function()
		local addon, state, _, base, unit, _, oldHealth = bordered()
		addon.db.enemyPlayerBorderEnabled = true
		H.truthy(addon:RefreshNameplateFrame(base))
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
		local addon, state, _, base, unit, _, health = bordered()
		addon.db.enemyPlayerBorderEnabled = true
		state.frameData[health].errors.GetAlpha = true
		H.truthy(addon:RefreshNameplateFrame(base))
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
		addon:RefreshNameplates()
		H.equal(#state.mutations, 0)
	end)

	H.test("combat removal hides permitted addon texture before pooled frame reuse", function()
		local addon, state, _, base, unit = bordered()
		addon.db.enemyPlayerBorderEnabled = true
		H.truthy(addon:RefreshNameplateFrame(base))
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
		H.falsy(addon.pendingBorderCleanup)
	end)

	H.test("engine-denied texture cleanup remains pending until permission returns", function()
		local addon, state, _, base, unit = bordered()
		addon.db.enemyPlayerBorderEnabled = true
		H.truthy(addon:RefreshNameplateFrame(base))
		local texture = addon.nameplateBorderTintByUnitFrame[unit].Texture
		state.combat, state.allowProtectedFunctions = true, false
		state:clearMutations()
		addon:HandleNameplateRemoved("nameplate1")
		H.truthy(texture:IsShown())
		H.equal(#state.mutations, 0)
		H.truthy(addon.pendingBorderCleanup)
		state.combat, state.allowProtectedFunctions = false, true
		H.truthy(addon:ClearNameplateBorders())
		H.falsy(texture:IsShown())
		H.equal(addon.nameplateStateByFrame[base], nil)
	end)

	H.test("secret restriction API is not treated as an absent legacy capability", function()
		local addon, state, env, base, _, _, health = bordered()
		state.frameData[health].protected = true
		state.restricted[env.Enum.AddOnRestrictionType.Encounter] = env.Enum.AddOnRestrictionState.Active
		env.C_RestrictedActions.GetAddOnRestrictionState = state:secretValue()
		H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
		H.falsy(addon:CanMutateNameplateFrame(health))
		H.falsy(addon:RefreshNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)

	H.test("secret permission API blocks mutation and retains owned tint cleanup", function()
		local addon, state, env, base, unit, cast = bordered()
		addon.db.enemyPlayerBorderEnabled = true
		H.truthy(addon:RefreshNameplateFrame(base))
		local texture = addon.nameplateBorderTintByUnitFrame[unit].Texture
		local permissionAPI = env.C_RestrictedActions.CheckAllowProtectedFunctions
		env.C_RestrictedActions.CheckAllowProtectedFunctions = state:secretValue()
		state:clearMutations()
		H.falsy(addon:CanMutateNameplateFrame(cast))
		addon:Disable()
		H.truthy(addon.pendingBorderCleanup)
		H.truthy(texture:IsShown())
		H.equal(#state.mutations, 0)
		env.C_RestrictedActions.CheckAllowProtectedFunctions = permissionAPI
		H.truthy(addon:ClearNameplateBorders())
		H.falsy(texture:IsShown())
	end)

	H.test("unreadable restriction enum entry cannot silently omit a safety check", function()
		local addon, state, env, base, _, _, health = bordered()
		state.frameData[health].protected = true
		env.Enum.AddOnRestrictionType.Encounter = state:secretValue()
		H.truthy(addon:IsNameplateAugmentationBlockedInCurrentContext())
		H.falsy(addon:RefreshNameplateFrame(base))
		H.equal(#state.mutations, 0)
	end)
end
