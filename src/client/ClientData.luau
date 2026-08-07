--!strict
-- ClientData — the client's mirror of its profile snapshot (DataChanged) plus
-- small bits of shared UI state. Controllers read from here instead of each
-- subscribing to the remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local changedEvent = Instance.new("BindableEvent")
local UNLOCK_BIND = "PinkPanicMouseUnlock"
local unlockBound = false

local ClientData = {}

ClientData.snapshot = nil :: any
ClientData.changed = changedEvent.Event
ClientData.shopOpen = false
ClientData.settingsOpen = false

-- True while any modal menu should block gameplay input.
function ClientData.menuOpen(): boolean
	return ClientData.shopOpen or ClientData.settingsOpen
end

-- Call after toggling shopOpen/settingsOpen. The first-person camera scripts
-- re-lock the mouse every render step, so while a menu is open we bind AFTER
-- them (RenderPriority.Last) and force the cursor free each frame — the only
-- approach that reliably wins that fight.
function ClientData.updateMouseUnlock()
	local shouldUnlock = ClientData.menuOpen()
	if shouldUnlock and not unlockBound then
		unlockBound = true
		RunService:BindToRenderStep(UNLOCK_BIND, Enum.RenderPriority.Last.Value, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	elseif not shouldUnlock and unlockBound then
		unlockBound = false
		RunService:UnbindFromRenderStep(UNLOCK_BIND)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end

function ClientData.equippedSkin(): string?
	local snap = ClientData.snapshot
	local skins = snap and snap.equipped and snap.equipped.skins
	return if type(skins) == "table" then skins.Pistol else nil
end

function ClientData.equippedCharm(): string?
	local snap = ClientData.snapshot
	local charms = snap and snap.equipped and snap.equipped.charms
	return if type(charms) == "table" then charms.Pistol else nil
end

function ClientData.owns(kind: string, itemId: string): boolean
	local snap = ClientData.snapshot
	local list = if kind == "skin" then snap and snap.ownedSkins else snap and snap.ownedCharms
	return type(list) == "table" and table.find(list, itemId) ~= nil
end

function ClientData.init()
	Remotes.event("DataChanged").OnClientEvent:Connect(function(data)
		if type(data) == "table" then
			ClientData.snapshot = data
			changedEvent:Fire(data)
		end
	end)
end

return ClientData
