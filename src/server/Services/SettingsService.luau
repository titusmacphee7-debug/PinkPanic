--!strict
-- SettingsService — persists player preferences (NOD-44) and the starting
-- weapon choice (NOD-28). Partial payloads are fine; each present field is
-- validated independently and junk rejects the whole call.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CameraConfig = require(ReplicatedStorage.Shared.Config.CameraConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)

local SettingsService = {}

local function onUpdateSettings(player: Player, payload: any): { [string]: any }
	if not Guard.checkRate(player, "UpdateSettings", 10, 2) then
		return { ok = false, error = "Too fast!" }
	end
	if type(payload) ~= "table" then
		return { ok = false, error = "Invalid payload." }
	end

	local sensitivity = payload.sensitivity
	local volume = payload.volume
	local fov = payload.fov
	local startingWeapon = payload.startingWeapon
	if sensitivity ~= nil and not Guard.isNumberInRange(sensitivity, 0.1, 4) then
		return { ok = false, error = "Invalid sensitivity." }
	end
	if volume ~= nil and not Guard.isNumberInRange(volume, 0, 1) then
		return { ok = false, error = "Invalid volume." }
	end
	-- The range is CameraConfig's, not a pair of numbers repeated here: the
	-- client's slider and the server's guard have to agree, and the only way
	-- they cannot drift apart is by reading the same table.
	if fov ~= nil and not Guard.isNumberInRange(fov, CameraConfig.fovMin, CameraConfig.fovMax) then
		return { ok = false, error = "Invalid field of view." }
	end
	if startingWeapon ~= nil then
		if not Guard.isString(startingWeapon, 30) or not table.find(GameConfig.loadout, startingWeapon) then
			return { ok = false, error = "Invalid weapon." }
		end
	end

	local changed = PlayerDataService.update(player, function(data)
		if sensitivity ~= nil then
			data.settings.sensitivity = sensitivity
		end
		if volume ~= nil then
			data.settings.volume = volume
		end
		if fov ~= nil then
			data.settings.fov = fov
		end
		if startingWeapon ~= nil then
			data.equipped.weapon = startingWeapon
		end
	end)
	if not changed then
		return { ok = false, error = "Data still loading." }
	end

	EconomyService.push(player)
	return { ok = true }
end

function SettingsService.init()
	Remotes.handleFunction("UpdateSettings", onUpdateSettings)
end

return SettingsService
