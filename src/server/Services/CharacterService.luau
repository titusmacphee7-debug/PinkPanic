--!strict
-- CharacterService — everyone spawns as the same character (NOD-167).
--
-- One R15 rig, one size. The player's own Roblox avatar does not carry over.
-- Players author their look in the character creator (NOD-168), which dresses
-- this rig through the appearance hook below without ever changing its shape.
--
-- This is a combat service. Roblox avatars vary enormously in height and
-- width, and in a shooter that is a live advantage: a tall thin character is a
-- harder target than a wide one, at every range, in every fight. The plan this
-- replaces corrected for that with an invisible normalized hit volume welded
-- over whatever body the player brought — which works, but means the thing you
-- shoot at is not the thing you see, and every animation and scaling edge case
-- is one more way for those two to drift apart with nothing on screen showing
-- it. One rig deletes the problem instead of compensating for it.
--
-- Which is why the rig is MEASURED, not trusted. If character replacement ever
-- silently fails — a Roblox API change, a race with CharacterAdded, a
-- HumanoidDescription field that stops applying — one player quietly becomes a
-- different-sized target and nothing about the game looks wrong. That is the
-- same failure shape as the dead server and the DataStore that reported OK
-- while saving nothing: correct-looking, silent, and only visible in the win
-- rate weeks later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Config = require(ReplicatedStorage.Shared.Config.CharacterConfig)

local SYSTEM = "CharacterService"

local CharacterService = {}

-- The first standardised character measured this session becomes the yardstick
-- every later one is checked against.
--
-- Self-calibrating on purpose. Hardcoding "an R15 rig is 5.7 studs tall" bakes
-- in a number Roblox owns and can change, and a wrong constant would either
-- cry wolf every spawn or quietly never fire. Comparing characters to each
-- other tests the property we actually care about — that everyone is the same
-- size — rather than a number we guessed.
local reference: Vector3? = nil
local deviations = 0

-- Set by the creator (NOD-168) and the cosmetics layer (NOD-146). Runs after
-- the standard rig is applied and before the character is handed back, so a
-- player wears their own look from the first frame instead of appearing as the
-- default and popping into themselves a moment later.
local appearanceHook: ((player: Player, character: Model, description: HumanoidDescription) -> ())? = nil

function CharacterService.setAppearanceHook(
	hook: (player: Player, character: Model, description: HumanoidDescription) -> ()
)
	appearanceHook = hook
end

-- ---------------------------------------------------------------------------
-- The standard description
-- ---------------------------------------------------------------------------

-- Built fresh per character rather than shared. ApplyDescription reads the
-- instance, and the appearance hook writes to it — one shared description
-- would mean the last player to join dressed everyone.
local function standardDescription(): HumanoidDescription
	local description = Instance.new("HumanoidDescription")

	local scale = Config.scale
	description.HeightScale = scale.height
	description.WidthScale = scale.width
	description.DepthScale = scale.depth
	description.HeadScale = scale.head
	description.BodyTypeScale = scale.bodyType
	description.ProportionScale = scale.proportion

	-- Everything the player brought, cleared. A HumanoidDescription with empty
	-- accessory fields removes accessories on apply, which is what makes this
	-- a replacement rather than a partial overwrite.
	description.HatAccessory = ""
	description.HairAccessory = ""
	description.FaceAccessory = ""
	description.NeckAccessory = ""
	description.ShouldersAccessory = ""
	description.FrontAccessory = ""
	description.BackAccessory = ""
	description.WaistAccessory = ""

	-- Layered clothing too. These are separate from the accessory fields
	-- above, and a description that clears one but not the other leaves
	-- players wearing half of whatever they arrived in.
	description.Shirt = Config.default.shirt
	description.Pants = Config.default.pants
	description.GraphicTShirt = 0
	description.Face = Config.default.face

	local skin = Config.default.skin
	description.HeadColor = skin
	description.TorsoColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.LeftLegColor = skin
	description.RightLegColor = skin

	return description
end

-- ---------------------------------------------------------------------------
-- Measurement
-- ---------------------------------------------------------------------------

-- The rig's dimensions, as the SUM of its own parts' sizes.
--
-- Not a world-space bounding box, which was the first version and was wrong in
-- a way worth keeping a note about: a character's bounding box depends on where
-- its arms are. Two measurements of the same player, one taken on spawn and one
-- a second later after the idle animation settled, differed by 0.9 studs in X
-- and Z while the height matched to three decimals. A fairness check that fires
-- on arm position is a check nobody will trust for long.
--
-- Summed part sizes are pose-invariant and scale-sensitive, which is exactly
-- the property being tested: not "what shape is this character standing in"
-- but "is this character built to the same dimensions as everyone else".
--
-- Only direct children, so accessories and a held gun are ignored. They change
-- the silhouette without changing the target, and counting them would report a
-- hat as a fairness problem while missing a real one underneath it.
local function rigSize(character: Model): Vector3?
	local total: Vector3? = nil

	for _, part in character:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		total = if total then total + part.Size else part.Size
	end

	return total
end

local function verify(player: Player, character: Model)
	local size = rigSize(character)
	if not size then
		Diagnostics.warn(SYSTEM, `{player.Name} spawned with no measurable rig parts`)
		return
	end

	local yardstick = reference
	if not yardstick then
		reference = size
		Diagnostics.count(SYSTEM, "standardised")
		return
	end

	local drift = (size - yardstick).Magnitude
	if drift > Config.sizeToleranceStuds then
		deviations += 1
		Diagnostics.warn(
			SYSTEM,
			`{player.Name} is a DIFFERENT SIZE from everyone else — `
				.. `{string.format("%.2f", drift)} studs off ({size} vs {yardstick}). `
				.. "They are a harder or easier target than the rest of the lobby."
		)
		return
	end

	Diagnostics.count(SYSTEM, "standardised")
end

-- ---------------------------------------------------------------------------
-- Application
-- ---------------------------------------------------------------------------

local function standardise(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		Diagnostics.warn(SYSTEM, `{player.Name} spawned without a Humanoid within 10s`)
		return
	end

	-- Rig type is a place setting, not something a script can change. Say so
	-- precisely rather than silently running on a rig the pose solver and the
	-- hit zones cannot use.
	if humanoid.RigType ~= Config.rigType then
		Diagnostics.warn(
			SYSTEM,
			`characters are spawning as {humanoid.RigType.Name}, not R15. `
				.. "Fix in Studio: Game Settings → Avatar → Avatar Type → R15. "
				.. "Code cannot change this."
		)
	end

	local description = standardDescription()

	-- The creator and equipped cosmetics write into the description BEFORE it
	-- is applied, so the player's own look lands in the same single apply.
	-- Guarded because a broken hook must not leave the player as their own
	-- Roblox avatar — the one outcome this service exists to prevent.
	local hook = appearanceHook
	if hook then
		local applied = pcall(hook, player, character, description)
		if not applied then
			Diagnostics.warn(SYSTEM, `appearance hook errored for {player.Name} — spawned as the default look`)
		end
	end

	local ok, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not ok then
		Diagnostics.warn(SYSTEM, `could not standardise {player.Name} — {err}`)
		return
	end

	verify(player, character)
end

function CharacterService.init()
	-- Stops Roblox loading the player's own avatar at all. Applying over it
	-- works either way, but without this every player sees a frame of their
	-- real avatar before it is replaced, which reads as a bug even though the
	-- end state is correct.
	StarterPlayer.LoadCharacterAppearance = Config.loadPlayerAppearance

	local function watch(player: Player)
		-- Every CharacterAdded, not once at join. A respawn builds a fresh
		-- character from the player's account, so standardising only the first
		-- one means everybody is their own avatar again the moment they die.
		player.CharacterAdded:Connect(function(character)
			standardise(player, character)
		end)
		if player.Character then
			standardise(player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		task.spawn(watch, player)
	end
	Players.PlayerAdded:Connect(watch)

	Diagnostics.ok(SYSTEM, `standard R15 rig, scale pinned, player appearance {if Config.loadPlayerAppearance then "loaded" else "off"}`)
end

-- Exposed for tests and for the manifest: how many characters were
-- standardised and how many came out the wrong size.
function CharacterService.stats(): (number, number, Vector3?)
	return Diagnostics.getCount(SYSTEM, "standardised"), deviations, reference
end

return CharacterService
