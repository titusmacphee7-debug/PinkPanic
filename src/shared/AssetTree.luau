--!strict
-- AssetTree — the canonical Studio folder structure, owned by code (NOD-128).
--
-- Titus asked for Studio to be as organised as the repo, with "a place for
-- everything that's up and coming." So the tree is declared here and **created
-- at boot**, which means the folder for a feature exists before the feature
-- does. You never have to guess where a camo goes: the folder is already there,
-- already named, already carrying a note explaining what belongs in it.
--
-- Two rules this module will not break:
--
--   1. **It only ever creates.** It never deletes, never moves, never renames.
--      The place file is not in git, so anything destroyed here is gone for
--      good. Content that is in the wrong place gets REPORTED, not relocated.
--
--   2. **It never generates game content.** Folders only. Earlier versions of
--      this project built placeholder lobbies and arenas procedurally, it got
--      baked into saved place files, and it kept coming back after Titus built
--      his own. Folders are structure; anything with geometry is content.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Diagnostics = require(ReplicatedStorage.Shared.Diagnostics)

local SYSTEM = "AssetTree"

type Node = {
	path: string,
	note: string,
}

-- Every folder the game has or will have. Adding a feature means adding its
-- folder HERE first — that is what keeps "up and coming" from turning into
-- "dumped wherever there was room".
--
-- Paths are service-relative and slash-separated. Parents are created before
-- children automatically, so intermediate folders need no entry of their own.
local TREE: { Node } = {
	-- ---------------------------------------------------------------------
	-- ReplicatedStorage/Assets — content the CLIENT needs to see.
	--
	-- Note the deliberate split from ReplicatedStorage/Shared/Assets, which
	-- holds the loader CODE. Content here, code there.
	-- ---------------------------------------------------------------------
	{ path = "ReplicatedStorage/Assets", note = "Game content the client renders. Code lives in Shared." },

	{ path = "ReplicatedStorage/Assets/Camos", note = "One texture per camo, named Camo_<Name>. Drop it in; it is in the game." },
	{ path = "ReplicatedStorage/Assets/Outfits", note = "Outfit_<Name>. Layers over the player's own avatar, never replaces it." },
	{ path = "ReplicatedStorage/Assets/Charms", note = "Charm_<Name>. Models welded to the gun's Mount_Charm socket." },
	{ path = "ReplicatedStorage/Assets/KillEffects", note = "KillEffect_<Name>. Plays on YOUR kill. Hearts and sparkles live here." },
	{ path = "ReplicatedStorage/Assets/Tracers", note = "Tracer_<Name>. The cosmetic with the most screen time in the game." },
	{ path = "ReplicatedStorage/Assets/Emotes", note = "Emote_<Name>. Authored gestures and catalog Animation assets." },
	{ path = "ReplicatedStorage/Assets/Titles", note = "Title_<Name>. The TEXT beside a player's name." },
	{ path = "ReplicatedStorage/Assets/NameTags", note = "NameTag_<Name>. The PLATE the name sits on. Different item from a Title." },

	{ path = "ReplicatedStorage/Assets/Guns", note = "Rebuilt gun models, to docs/GUN_MODEL_SPEC.md. Legacy set is still in ReplicatedStorage/GunModels." },
	{ path = "ReplicatedStorage/Assets/Attachments", note = "Optics, muzzles, barrels, grips. Welded to the gun's Mount_* sockets." },
	{ path = "ReplicatedStorage/Assets/Viewmodel", note = "First-person arms and rig." },
	{ path = "ReplicatedStorage/Assets/Effects", note = "Muzzle flashes, impacts, shells, spawn bursts." },

	{ path = "ReplicatedStorage/Assets/Audio", note = "All sound. Everything positional by default." },
	{ path = "ReplicatedStorage/Assets/Audio/Weapons", note = "Per-gun fire, reload, and distant variants." },
	{ path = "ReplicatedStorage/Assets/Audio/Impacts", note = "Per-material hit sounds." },
	{ path = "ReplicatedStorage/Assets/Audio/UI", note = "Cutesy clicks, sparkles, per-rarity crate reveals." },
	{ path = "ReplicatedStorage/Assets/Audio/Music", note = "Lobby, match, victory, defeat." },

	-- ---------------------------------------------------------------------
	-- ServerStorage — content the client must NOT see.
	--
	-- Anything in ReplicatedStorage is readable by a modified client. Anything
	-- whose existence or contents would leak information belongs here.
	-- ---------------------------------------------------------------------
	{ path = "ServerStorage/Streaks", note = "Scorestreak models. Server-only so a client cannot inspect them early." },
	{ path = "ServerStorage/Templates", note = "Server-spawned prefabs: care packages, objective props, hit volumes." },
	{ path = "ServerStorage/Maps", note = "Maps not currently loaded. The live one sits in Workspace." },
}

local AssetTree = {}

local function ensureFolder(parent: Instance, name: string): (Instance, boolean)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing, false
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder, true
end

-- Creates anything missing. Returns how many were new, so the manifest can say
-- "built 4" the first time and stay quiet afterwards.
-- Edit mode is explicitly allowed, and is in fact the important case. At
-- runtime the folders are rebuilt every boot and vanish with the session; run
-- once in Edit and they persist into the saved place, which is what lets Titus
-- actually drag content into them.
function AssetTree.ensure(): number
	assert(not RunService:IsRunning() or RunService:IsServer(), "AssetTree.ensure must not run on a live client")

	local created = 0

	for _, node in TREE do
		local segments = string.split(node.path, "/")
		local serviceName = table.remove(segments, 1) :: string

		local cursor: Instance = game:GetService(serviceName :: any)
		for _, segment in segments do
			local folder, isNew = ensureFolder(cursor, segment)
			if isNew then
				created += 1
			end
			cursor = folder
		end

		-- The note lands on the folder itself, so selecting it in Studio and
		-- looking at Properties tells you what belongs in it. Documentation
		-- nobody has to go and find.
		cursor:SetAttribute("Purpose", node.note)
	end

	return created
end

-- Reports content sitting somewhere that will make it hard to find later.
-- Deliberately advisory: it names things and moves nothing, because the place
-- file is not recoverable and Titus's build is his.
function AssetTree.hygiene(): { string }
	local problems: { string } = {}

	-- Loose parts directly under Workspace. These are almost always leftovers
	-- from importing or testing, and they are the first thing that makes a
	-- place feel unmanaged.
	local looseParts = 0
	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart") and child ~= Workspace.Terrain then
			looseParts += 1
		end
	end
	if looseParts > 0 then
		table.insert(problems, `{looseParts} loose part(s) directly in Workspace — group them or delete them`)
	end

	-- An empty asset folder is fine (it is waiting for content), but an empty
	-- folder that something is ALREADY trying to load from is not. That check
	-- belongs to each registry, which knows what it expected.

	return problems
end

function AssetTree.init()
	local created = AssetTree.ensure()
	local problems = AssetTree.hygiene()

	local built = if created > 0 then `{created} folder(s) created, ` else ""

	if #problems > 0 then
		Diagnostics.warn(SYSTEM, `{built}{#TREE} declared — {table.concat(problems, "; ")}`)
		return
	end

	Diagnostics.ok(SYSTEM, `{built}{#TREE} folders in place`)
end

return AssetTree
