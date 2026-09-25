return function(H)
	-- The inspected Classic XML uses the same health container and base GetUnit
	-- contract as Retail/Forever. Test the complete border and settings path for
	-- each current family, including old globals being absent.
	for client, version in pairs({
		retail = "12.1.0",
		forever = "1.60.1",
		era = "1.15.9",
		tbc = "2.5.6",
		mists = "5.5.4",
		titan = "3.80.2",
	}) do
		H.test("client " .. client .. " borders, settings and cleanup", function()
			local addon, state, env = H.new({
				options = true,
				configure = function(e)
					e.GetBuildInfo = function()
						return version, "fixture", "", 0
					end
					e.NamePlateSetupOptions, e.NamePlateConstants, e.NameplatesOverrides = nil, nil, nil
					e.Settings.NAMEPLATE_OPTIONS_CATEGORY_ID = 37
				end,
			})
			local base, unit = state:plate("nameplate1", { guid = "Player-1", isPlayer = true, isFriend = true })
			addon.isEnabled, addon.db.friendlyPlayerBorderEnabled = true, true
			addon:EnsureNameplateEventFrame()
			H.truthy(addon:RefreshNameplateFrame(base))
			H.truthy(addon.nameplateBorderTintByUnitFrame[unit].visible)
			H.truthy(addon:OpenBlizzardNameplateSettings())
			H.equal(state.openCategory, 37)
			addon:Disable()
			H.falsy(addon.nameplateBorderTintByUnitFrame[unit].visible)
			H.equal(state.foreignWrites, 0)
			H.equal(state.nativeMutationAttempts, 0)
			H.equal(#state.hooks, 0)
			H.equal(#state.cvarWrites, 0)
		end)
	end
end
