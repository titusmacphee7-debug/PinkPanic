--!strict
-- CharacterConfig — what every player spawns as (NOD-167). Data only.
--
-- Everyone in Pink Panic is the same character: one R15 rig, one size. The
-- player's own Roblox avatar does not carry over — not the body, not the face,
-- not the clothing, not the accessories. Players author their look through the
-- character creator (NOD-168), which dresses this rig without ever changing
-- its shape.
--
-- This is a combat file wearing an art file's clothes. Roblox avatars vary
-- enormously in height and width, and in a shooter that is a live advantage:
-- a tall thin character is a harder target than a wide one, at every range, in
-- every fight. One rig means what you aim at IS the hitbox, because there is
-- only one shape in the game.

return {
	-- ---------------------------------------------------------------------
	-- Scale — the numbers the fairness guarantee actually rests on
	-- ---------------------------------------------------------------------
	--
	-- All six are pinned. The two easy ones to forget are the last two:
	-- BodyType and Proportion are what Roblox uses to blend a rig toward the
	-- "thin/wide" ends of its range, so leaving them at the player's own value
	-- keeps most of the variation this file exists to remove — while the four
	-- obvious scales all read as correct.
	scale = {
		height = 1,
		width = 1,
		depth = 1,
		head = 1,
		bodyType = 0,
		proportion = 0,
	},

	-- How far a spawned character's summed part sizes may differ from the
	-- reference before it is reported. Tight, because the measurement is
	-- pose-invariant: two identically-scaled rigs sum to the same value
	-- exactly, so anything above float noise is a real difference in build.
	-- A 1.05 height scale — small enough to look normal, big enough to matter
	-- in a fight — moves this by well over a stud.
	sizeToleranceStuds = 0.05,

	-- ---------------------------------------------------------------------
	-- The default look
	-- ---------------------------------------------------------------------
	--
	-- What a player wears before they have been through the creator, and what
	-- they fall back to if their saved appearance fails to load. Deliberately
	-- a real look rather than Roblox default grey: a player whose creator data
	-- is missing should look like a character, not like an error.
	default = {
		-- Cute-pink, per docs/ART_DIRECTION.md.
		skin = Color3.fromRGB(255, 224, 214),

		-- Catalog asset ids. Zero means "leave Roblox's default", which is
		-- correct until Titus has authored the real base outfit — an id
		-- invented here would be a broken asset in every player's character.
		face = 0,
		shirt = 0,
		pants = 0,
	},

	-- ---------------------------------------------------------------------
	-- Rig
	-- ---------------------------------------------------------------------

	-- R15 is required: R6 has no upper/lower limb split, so the layered pose
	-- solver and every hit zone finer than "arm" have nothing to attach to.
	--
	-- Rig type is a PLACE setting, not something a script can change — so this
	-- is the value the service checks against and reports on, not one it can
	-- enforce. Game Settings → Avatar → Avatar Type → R15.
	rigType = Enum.HumanoidRigType.R15,

	-- Stop Roblox loading the player's own avatar at all, rather than loading
	-- it and overwriting it a frame later. The overwrite works either way, but
	-- without this every player sees a flash of their real avatar before it is
	-- replaced, which reads as a bug even though it is not.
	loadPlayerAppearance = false,
}
