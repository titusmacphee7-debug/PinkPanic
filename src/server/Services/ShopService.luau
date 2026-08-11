--!strict
-- ShopService — purchases and equips, fully server-validated (NOD-32, NOD-33).
-- The server checks price, balance, and ownership inside the single profile
-- update, so there is no window for double-buys or free equips. Free items
-- (price 0) are equippable without purchase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Guard = require(ReplicatedStorage.Shared.Net.Guard)
local CatalogConfig = require(ReplicatedStorage.Shared.Config.CatalogConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)

local ShopService = {}

-- NOTE: this service no longer touches the world gun. It used to re-dress it
-- 1s after every spawn from `equipped.skins.Pistol`, a pre-roster field that
-- is nil for every current profile — and WeaponCosmetics.applySkin falls back
-- to SkinDefault rather than returning, so it repainted the roster gun's Grip
-- and Slide with legacy pistol colours over whatever skin the player actually
-- equipped. Gun cosmetics belong to GunShopService -> GunModelLoader now.
-- The whole service is slated for deletion in NOD-119.

local function onPurchase(player: Player, itemId: any): { [string]: any }
	if not Guard.checkRate(player, "PurchaseItem", 5, 2) then
		return { ok = false, error = "Too fast! Try again." }
	end
	if not Guard.isString(itemId, 50) then
		return { ok = false, error = "Invalid item." }
	end
	local kind, def = CatalogConfig.get(itemId)
	if not kind then
		return { ok = false, error = "Unknown item." }
	end
	if def.price <= 0 then
		return { ok = false, error = "That one's free — just equip it!" }
	end

	local failReason: string? = nil
	local bought = false
	PlayerDataService.update(player, function(data)
		local ownedList = if kind == "skin" then data.ownedSkins else data.ownedCharms
		if table.find(ownedList, itemId) then
			failReason = "Already owned."
			return
		end
		if data.coins < def.price then
			failReason = "Not enough coins!"
			return
		end
		data.coins -= def.price
		table.insert(ownedList, itemId)
		bought = true
	end)

	if not bought then
		return { ok = false, error = failReason or "Data still loading — try again." }
	end
	EconomyService.push(player)
	return { ok = true }
end

local function onEquip(player: Player, kind: any, itemId: any): { [string]: any }
	if not Guard.checkRate(player, "EquipItem", 10, 2) then
		return { ok = false, error = "Too fast!" }
	end
	if kind ~= "skin" and kind ~= "charm" then
		return { ok = false, error = "Invalid slot." }
	end
	-- itemId == nil unequips (charms) / reverts to default (skins).
	if itemId ~= nil then
		if not Guard.isString(itemId, 50) then
			return { ok = false, error = "Invalid item." }
		end
		local foundKind, def = CatalogConfig.get(itemId)
		if foundKind ~= kind then
			return { ok = false, error = "Unknown item." }
		end
		local data = PlayerDataService.get(player)
		if not data then
			return { ok = false, error = "Data still loading." }
		end
		local ownedList = if kind == "skin" then data.ownedSkins else data.ownedCharms
		if def.price > 0 and not table.find(ownedList, itemId) then
			return { ok = false, error = "You don't own that." }
		end
	end

	local changed = PlayerDataService.update(player, function(data)
		if kind == "skin" then
			data.equipped.skins.Pistol = itemId
		else
			data.equipped.charms.Pistol = itemId
		end
	end)
	if not changed then
		return { ok = false, error = "Data still loading." }
	end

	EconomyService.push(player)
	return { ok = true }
end

function ShopService.init()
	Remotes.handleFunction("PurchaseItem", onPurchase)
	Remotes.handleFunction("EquipItem", onEquip)
end

return ShopService
