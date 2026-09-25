-- Shared welcome formatting, session state and copy UI live in private libchev.
local Addon = _G.PvPTogether
local LibChev = Addon.LibChev

-- Register only our own link type through Blizzard's public dispatcher. The
-- handler consumes the primitive link string, never foreign context tables.
function Addon:RegisterWelcomeLink(linkType, callback)
	if not self:CanAccessTable(LinkUtil) then
		return false
	end
	local exists, register = LinkUtil.IsLinkHandlerRegistered, LinkUtil.RegisterLinkHandler
	if
		not self:CanAccessValue(exists)
		or not self:CanAccessValue(register)
		or type(exists) ~= "function"
		or type(register) ~= "function"
	then
		return false
	end
	local ok, registered = pcall(exists, linkType)
	if not ok or not self:CanAccessValue(registered) or registered ~= false then
		return false
	end
	return pcall(register, linkType, callback)
end

function Addon:GetWelcomeUIPolicy()
	return {
		parent = UIParent,
		createFrame = CreateFrame,
		restricted = function()
			return not self.IsNameplateAugmentationBlockedInCurrentContext
				or self:IsNameplateAugmentationBlockedInCurrentContext()
		end,
		canMutate = LibChev.CanMutateOwnedRegion,
	}
end

function Addon:GetWelcomeController()
	local controller = rawget(self, "welcomeController")
	if not controller then
		controller = LibChev.NewWelcomeController({
			addonName = "PvPTogether",
			linkType = "pvptogetherfeedback",
			curseforgeURL = "https://www.curseforge.com/wow/addons/pvptogether",
			githubURL = "https://github.com/AlexAllocated/PvPTogether",
			command = "/pt",
			clients = "Retail, WoW Forever, Classic Era, Hardcore, Season of Discovery, TBC Anniversary, Mists Classic, and Titan Reforged",
			getVersion = function()
				return self:GetDiagnosticVersion()
			end,
			registerLink = function(linkType, callback)
				return self:RegisterWelcomeLink(linkType, callback)
			end,
			print = function(text)
				self:Print(text)
			end,
			ui = self:GetWelcomeUIPolicy(),
		})
		self.welcomeController = controller
	end
	return controller
end

function Addon:PrintWelcomeMessage()
	-- A partially updated installation must never prevent normal addon startup.
	if type(LibChev.NewWelcomeController) ~= "function" then
		return false
	end
	local ok, controller = pcall(self.GetWelcomeController, self)
	if not ok then
		return false
	end
	local announced, result = pcall(controller.Announce, controller)
	return announced and result == true
end
