--!strict
-- LobbyLights — turns Titus's lamp posts on (NOD-162).
--
-- He builds the lamps; this lights them. The split matters because the place
-- file is not in git: anything this system did by editing the saved place would
-- be unrecoverable if it were wrong, so it does all its work at RUNTIME. Stop
-- the session and the lobby is exactly as he left it.
--
-- **It only ever adds.** Same rule as AssetTree. It creates one PointLight per
-- lantern and writes two properties on the lantern itself; it never creates,
-- moves, renames or destroys a lamp, and it re-uses a light it already made
-- rather than stacking a second one on top.
--
-- Finds lamps two ways — by part name and by attribute — so a lamp model built
-- differently later works by tagging it rather than by editing this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Config = require(ReplicatedStorage.Shared.Config.LightingConfig)

local SYSTEM = "LobbyLights"

local LobbyLights = {}

-- Our light is named, so a second boot finds it instead of adding another. A
-- lamp that gains a light per Play session is four lights deep by the time
-- anybody notices it looks too bright.
local LIGHT_NAME = "PinkPanicLampLight"

local function isLamp(instance: Instance): boolean
	if not instance:IsA("BasePart") then
		return false
	end
	if instance:GetAttribute(Config.lampAttribute) then
		return true
	end
	return instance.Name == Config.lampPartName
end

local function light(part: BasePart)
	local existing = part:FindFirstChild(LIGHT_NAME)
	local pointLight = if existing and existing:IsA("PointLight")
		then existing
		else Instance.new("PointLight")

	pointLight.Name = LIGHT_NAME
	pointLight.Color = Config.lampColor
	pointLight.Brightness = Config.lampBrightness
	pointLight.Range = Config.lampRange
	pointLight.Shadows = Config.lampShadows
	pointLight.Enabled = true
	pointLight.Parent = part

	if Config.lampGlow then
		-- Runtime only. The saved place keeps whatever material Titus chose.
		part.Material = Enum.Material.Neon
		part.Color = Config.lampGlowColor
	end
end

-- Public so it can be re-run from the command bar after adding a lamp, without
-- restarting the server.
function LobbyLights.apply(): number
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return 0
	end

	local lit = 0
	for _, descendant in lobby:GetDescendants() do
		if isLamp(descendant) then
			light(descendant :: BasePart)
			lit += 1
		end
	end
	return lit
end

function LobbyLights.init()
	local lit = LobbyLights.apply()

	if lit == 0 then
		-- Not an error: the lobby may not have replicated yet, and a lobby with
		-- no lamps is a legitimate lobby. Said out loud anyway, because "I added
		-- lamps and they are not lit" and "the system never ran" look identical
		-- from inside the game.
		Diagnostics.warn(
			SYSTEM,
			`no lamps found — looking for parts named "{Config.lampPartName}" or tagged `
				.. `{Config.lampAttribute} anywhere under workspace.Lobby`
		)
		return
	end

	Diagnostics.ok(
		SYSTEM,
		`{lit} lamp(s) lit · pastel pink, brightness {Config.lampBrightness}, `
			.. `range {Config.lampRange} studs`
			.. (if Config.lampGlow then " · lanterns glowing" else "")
	)
end

return LobbyLights
