-- Safe in-game checks only. Offline nameplate simulations remain in tests/.
local PvPTogether = _G.PvPTogether
local LibChev = PvPTogether.LibChev

function PvPTogether:GetInGameTests()
	local cases = LibChev.SelfTests()
	cases[#cases + 1] = {
		name = "PvPTogether: color normalization copies private values",
		run = function()
			local fixture = setmetatable({}, { __index = PvPTogether })
			local input = { r = 2, g = -1, b = 0.5 }
			local color = fixture:NormalizeColorRGB(input, { r = 0, g = 0, b = 0 })
			LibChev.AssertEqual(color.r, 1)
			LibChev.AssertEqual(color.g, 0)
			LibChev.AssertEqual(color.b, 0.5)
			LibChev.AssertEqual(input.r, 2)
			assert(color ~= input)
		end,
	}
	cases[#cases + 1] = {
		name = "PvPTogether: diagnostic counters stay on detached fixtures",
		run = function()
			local fixture = setmetatable(
				{ diagnosticCounterStore = LibChev.NewCounters(), diagnosticLog = LibChev.NewLog() },
				{ __index = PvPTogether }
			)
			fixture:RecordDiagnostic("fixture-reason")
			local snapshot = fixture:GetDiagnosticSnapshot()
			LibChev.AssertEqual(#snapshot, 1)
			LibChev.AssertEqual(snapshot[1].count, 1)
		end,
	}
	return cases
end

-- Compatibility entry point: shared execution stays headless unless requested.
function PvPTogether:RunTests(showReport)
	local success, passed, failed = self:GetDebugController():RunTests(false, showReport == true)
	return success, passed, failed
end
