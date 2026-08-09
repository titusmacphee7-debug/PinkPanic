--!strict
-- GunShopService — gun/skin/camo purchases and loadout/cosmetic equips
-- (docs/GUNS_HANDOFF.md §4.3, NOD-108/NOD-109). Prices and ownership are
-- re-derived server-side from the catalogs on every call; the client's
-- opinion is never trusted. All coin math flows through
-- PlayerDataService.update, with the ownership check inside the same update
-- so double-buys have no window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local GunCatalog = require(ReplicatedStorage.Shared.Config.GunCatalog)
local GunSkinCatalog = require(ReplicatedStorage.Shared.Config.GunSkinCatalog)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local RoundService = require(script.Parent.RoundService)
local WeaponService = require(script.Parent.WeaponService)

local GunShopService = {}

type Result = { [string]: any }

local function fail(message: string): Result
	return { ok = false, error = message }
end

local function buyIntoList(
	player: Player,
	listKey: string,
	itemId: string,
	price: number
): Result
	local failReason: string? = nil
	local bought = false
	PlayerDataService.update(player, function(data)
		local list = (data :: any)[listKey] :: { string }
		if table.find(list, itemId) then
			failReason = "Already owned."
			return
		end
		if data.coins < price then
			failReason = `Not enough coins — you need {price - data.coins} more 💗`
			return
		end
		data.coins -= price
		table.insert(list, itemId)
		bought = true
	end)
	if not bought then
		return fail(failReason or "Data still loading — try again.")
	end
	EconomyService.push(player)
	return { ok = true }
end

local function onBuyGun(player: Player, gunId: any): Result
	if not Guard.checkRate(player, "BuyGun", 5, 2) then
		return fail("Too fast!")
	end
	if not Guard.isString(gunId, 50) then
		return fail("Invalid gun.")
	end
	local def = GunCatalog.get(gunId)
	if not def then
		return fail("Unknown gun.")
	end
	if def.price <= 0 then
		return fail("That one's free — it's already yours!")
	end
	return buyIntoList(player, "ownedGuns", gunId, def.price)
end

local function onBuyGunSkin(player: Player, gunId: any, skinId: any): Result
	if not Guard.checkRate(player, "BuyGunSkin", 5, 2) then
		return fail("Too fast!")
	end
	if not Guard.isString(gunId, 50) or not Guard.isString(skinId, 80) then
		return fail("Invalid item.")
	end
	local skins = GunSkinCatalog.perGun[gunId]
	local def = skins and skins[skinId]
	if not def then
		return fail("Unknown skin.")
	end
	local data = PlayerDataService.get(player)
	if not data then
		return fail("Data still loading.")
	end
	if not table.find(data.ownedGuns, gunId) then
		return fail("You don't own that gun yet.")
	end
	return buyIntoList(player, "ownedGunSkins", skinId, def.price)
end

local function onBuyCamo(player: Player, camoId: any): Result
	if not Guard.checkRate(player, "BuyCamo", 5, 2) then
		return fail("Too fast!")
	end
	if not Guard.isString(camoId, 50) then
		return fail("Invalid camo.")
	end
	local def = GunSkinCatalog.universal[camoId]
	if not def then
		return fail("Unknown camo.")
	end
	if def.textureId == "" then
		return fail("Coming soon 💗")
	end
	return buyIntoList(player, "ownedCamos", camoId, def.price)
end

local function onEquipLoadout(player: Player, primary: any, secondary: any): Result
	if not Guard.checkRate(player, "EquipLoadout", 10, 2) then
		return fail("Too fast!")
	end
	-- Loadout changes are a lobby activity — mid-round swaps would refill
	-- ammo and dodge the commitment of a pick.
	if RoundService.getState() == "Active" then
		return fail("Change loadout between rounds!")
	end
	if primary ~= nil and not Guard.isString(primary, 50) then
		return fail("Invalid primary.")
	end
	if not Guard.isString(secondary, 50) then
		return fail("Invalid secondary.")
	end

	local data = PlayerDataService.get(player)
	if not data then
		return fail("Data still loading.")
	end
	if primary ~= nil then
		local def = GunCatalog.get(primary)
		if not def or def.slot ~= "Primary" then
			return fail("That's not a primary weapon.")
		end
		if not table.find(data.ownedGuns, primary) then
			return fail("You don't own that gun.")
		end
	end
	local secondaryDef = GunCatalog.get(secondary)
	if not secondaryDef or secondaryDef.slot ~= "Secondary" then
		return fail("That's not a secondary weapon.")
	end
	if not table.find(data.ownedGuns, secondary) then
		return fail("You don't own that gun.")
	end

	PlayerDataService.update(player, function(profile)
		profile.loadout.primary = primary
		profile.loadout.secondary = secondary
	end)
	EconomyService.push(player)
	WeaponService.refreshLoadout(player)
	return { ok = true }
end

local function onEquipGunCosmetics(player: Player, gunId: any, skinId: any, camoId: any): Result
	if not Guard.checkRate(player, "EquipGunCosmetics", 10, 2) then
		return fail("Too fast!")
	end
	if not Guard.isString(gunId, 50) then
		return fail("Invalid gun.")
	end
	if skinId ~= nil and not Guard.isString(skinId, 80) then
		return fail("Invalid skin.")
	end
	if camoId ~= nil and not Guard.isString(camoId, 50) then
		return fail("Invalid camo.")
	end

	local data = PlayerDataService.get(player)
	if not data then
		return fail("Data still loading.")
	end
	if not GunCatalog.get(gunId) then
		return fail("Unknown gun.")
	end
	if not table.find(data.ownedGuns, gunId) then
		return fail("You don't own that gun.")
	end
	if skinId ~= nil then
		local skins = GunSkinCatalog.perGun[gunId]
		if not skins or not skins[skinId] then
			return fail("That skin doesn't fit this gun.")
		end
		if not table.find(data.ownedGunSkins, skinId) then
			return fail("You don't own that skin.")
		end
	end
	if camoId ~= nil then
		if not GunSkinCatalog.universal[camoId] then
			return fail("Unknown camo.")
		end
		if not table.find(data.ownedCamos, camoId) then
			return fail("You don't own that camo.")
		end
	end

	PlayerDataService.update(player, function(profile)
		profile.gunCosmetics[gunId] = { skinId = skinId, camoId = camoId }
	end)
	EconomyService.push(player)
	WeaponService.refreshCosmetics(player)
	return { ok = true }
end

function GunShopService.init()
	Remotes.func("BuyGun").OnServerInvoke = onBuyGun
	Remotes.func("BuyGunSkin").OnServerInvoke = onBuyGunSkin
	Remotes.func("BuyCamo").OnServerInvoke = onBuyCamo
	Remotes.func("EquipLoadout").OnServerInvoke = onEquipLoadout
	Remotes.func("EquipGunCosmetics").OnServerInvoke = onEquipGunCosmetics
end

return GunShopService
