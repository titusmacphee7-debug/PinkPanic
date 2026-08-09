--!strict
-- MovementStateService — replicates each player's stance (sliding/crouching)
-- as character attributes so every client's MovementAnimator can pose remote
-- characters correctly. Cosmetic only: no gameplay reads these, so a lying
-- client can only make itself LOOK crouched — hitboxes and damage are
-- untouched. Speed thresholds still drive the sprint/velocity poses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)

local MovementStateService = {}

function MovementStateService.init()
	Remotes.event("MovementState").OnServerEvent:Connect(function(player, sliding, crouching)
		if not Guard.checkRate(player, "MovementState", 12, 1) then
			return
		end
		if type(sliding) ~= "boolean" or type(crouching) ~= "boolean" then
			return
		end
		local character = player.Character
		if character then
			character:SetAttribute("PPSliding", sliding)
			character:SetAttribute("PPCrouching", crouching)
		end
	end)
end

return MovementStateService
