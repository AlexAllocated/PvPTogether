-- OFFLINE ONLY: characterization of PvPTogether revision 73e0def.
-- Uses detached fixtures, never a live WoW environment.
local root = arg[1] or "."
local H = assert(loadfile(root .. "/tests/harness.lua"))()(root)
local function setup()
	local addon, state = H.new()
	local base, unit, cast = state:plate("nameplate1")
	addon.isEnabled, addon.db.enemyPlayerStyle, addon.db.enemyPlayerBorderEnabled = true, 2, true
	addon:EnsureNameplateEventFrame()
	assert(addon:ReapplyStyleForNameplateFrame(base))
	assert(cast:GetHeight(true) == 16)
	state:clearMutations()
	return addon, state, base, unit, cast
end
local function report(label, addon, state, base, unit, cast)
	local retained = addon.nameplateStateByFrame[base]
	print(
		string.format(
			"%s: cast=%s journal=%d pending=%s timers=%d border=%s mutations=%d",
			label,
			tostring(cast:GetHeight(true)),
			retained and #retained.journal or 0,
			tostring(addon.pendingNameplateRefreshAfterCombat == true),
			#state.timers,
			tostring(addon.nameplateBorderTintByUnitFrame[unit].visible),
			#state.mutations
		)
	)
end
do
	local addon, state, base, unit, cast = setup()
	state:emit("PLAYER_TARGET_CHANGED")
	state:flushTimers()
	report("ordinary target refresh", addon, state, base, unit, cast)
end
do
	local addon, state, base, unit, cast = setup()
	state.frameData[unit].fields.showOnlyName = nil
	state:emit("PLAYER_TARGET_CHANGED")
	state:flushTimers()
	report("temporary layout flag unavailable", addon, state, base, unit, cast)
	assert(cast:GetHeight(true) == 20 and #state.timers == 0)
	assert(not addon.pendingNameplateRefreshAfterCombat)
	state.frameData[unit].fields.showOnlyName = false
	state:flushTimers()
	report("flag readable again without a new event", addon, state, base, unit, cast)
end
do
	local addon, state, base, unit, cast = setup()
	state.units.nameplate1.isFriend = state:secretValue()
	state:emit("PLAYER_TARGET_CHANGED")
	state:flushTimers()
	report("classification temporarily inaccessible", addon, state, base, unit, cast)
	assert(cast:GetHeight(true) == 20 and not addon.pendingNameplateRefreshAfterCombat)
end
do
	local addon, state, base, unit, cast = setup()
	-- Simulate a native layout pass after restriction begins. Fixture ownership
	-- writes native state; addon calls must still honor the restriction.
	state.combat = true
	for _, object in pairs(state.frameData) do
		object.protected = true
	end
	state.frameData[cast].height = 10
	state:fireHook("SetHeight", cast, 10)
	state:fireHook("UpdateAnchors", unit)
	state:fireHook("ApplyFrameOptions", unit)
	state:flushTimers()
	report("native refresh on restricted plates", addon, state, base, unit, cast)
	assert(cast:GetHeight(true) == 10)
end
