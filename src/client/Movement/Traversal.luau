--!strict
-- Traversal — is there a ledge in front of me, and is it safe to go over it
-- (NOD-141).
--
-- Split out of MovementController for one reason: this is the half that is
-- *geometry* rather than input, and geometry can be tested by standing a rig in
-- front of a box and asking, instead of by running around a map and hoping. The
-- controller decides WHEN to mantle; this file answers WHETHER there is anything
-- to mantle onto and WHERE it puts you.
--
-- The subtask that governs the shape of this file is "mantle traversal that does
-- not clip through geometry", and the way to get that is to refuse rather than
-- to correct. Every check below is a reason to return nil. A mantle that
-- half-works — that puts you inside a wall one time in fifty — is worse than one
-- that declines, because the player learns the wrong lesson about which ledges
-- are climbable and blames the ones that do work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)

local Traversal = {}

export type Ledge = {
	-- Where the character ends up standing, as a ROOT position (not a foot
	-- position) — the controller writes CFrames, so this is already in its units.
	target: Vector3,
	-- Top of the ledge, for the overlay and for the height check's own report.
	surfaceY: number,
	-- How far above your feet the ledge is.
	height: number,
	-- The face you are climbing. Kept so a future animation can face it.
	wallNormal: Vector3,
}

local COS_MAX_SLOPE = math.cos(math.rad(Config.mantle.maxSlopeDegrees))
local UP = Vector3.yAxis

-- Where the character's feet are, given a root. HipHeight plus half the root is
-- the standing offset for an R15 rig, and reading it from the rig rather than
-- hardcoding 3 is what keeps this working when NOD-167's standard size changes.
local function footY(root: BasePart, humanoid: Humanoid): number
	return root.Position.Y - (humanoid.HipHeight + root.Size.Y * 0.5)
end

-- Finds a mantleable ledge in `direction`, or nil and the reason it said no.
--
-- The reason is returned rather than logged: at 60 frames a second a rejected
-- mantle would print several hundred lines a minute, and the only place the
-- answer is actually useful is the F3 overlay, where it is one live line.
function Traversal.findLedge(
	root: BasePart,
	humanoid: Humanoid,
	direction: Vector3
): (Ledge?, string)
	local character = root.Parent
	if not character then
		return nil, "no character"
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return nil, "no heading"
	end
	local heading = flat.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local m = Config.mantle
	local feet = footY(root, humanoid)

	-- 1. Is there a wall? Cast at the LOW end of the height band. A ledge you can
	--    mantle always has a face below its lip, and casting low is what tells a
	--    wall apart from a railing you would otherwise be teleported on top of.
	local wallOrigin = Vector3.new(root.Position.X, feet + m.minHeightStuds * 0.5, root.Position.Z)
	local wallHit = workspace:Raycast(wallOrigin, heading * m.reachStuds, params)
	if not wallHit then
		return nil, "nothing in reach"
	end
	-- A near-vertical face. A ramp is something you walk up, and mantling one
	-- looks like the character teleporting through a hill.
	if math.abs(wallHit.Normal.Y) > 0.5 then
		return nil, "surface is not a wall"
	end

	-- 2. Where is its top? Probe down from above the maximum, just past the face.
	local probeAt = Vector3.new(wallHit.Position.X, feet + m.maxHeightStuds + 1, wallHit.Position.Z)
		+ heading * 0.4
	local topHit = workspace:Raycast(probeAt, Vector3.new(0, -(m.maxHeightStuds + 1 - m.minHeightStuds), 0), params)
	if not topHit then
		return nil, "no top within the height band"
	end
	if topHit.Normal.Y < COS_MAX_SLOPE then
		return nil, "top is too steep to stand on"
	end

	local height = topHit.Position.Y - feet
	if height < m.minHeightStuds then
		-- Below the band the Humanoid already steps up. Mantling a kerb would be
		-- the character playing a whole traversal to climb four inches.
		return nil, `only {string.format("%.1f", height)} studs — that is a step`
	end
	if height > m.maxHeightStuds then
		return nil, `{string.format("%.1f", height)} studs — too high`
	end

	-- 3. Is it deep enough to stand on? A second probe one ledge-depth further
	--    in, at the same height. Without this, a fence rail and a rooftop look
	--    identical to step 2 and you mantle onto a line.
	local inset = heading * m.ledgeDepthStuds
	local depthProbe = topHit.Position + inset + UP * 1
	local depthHit = workspace:Raycast(depthProbe, Vector3.new(0, -2, 0), params)
	if not depthHit or math.abs(depthHit.Position.Y - topHit.Position.Y) > 0.6 then
		return nil, "ledge is too thin to stand on"
	end

	-- 4. Headroom, so you do not mantle into a pipe.
	local standFoot = topHit.Position + heading * (m.ledgeDepthStuds * 0.5)
	local headroom = workspace:Raycast(standFoot + UP * 0.1, UP * m.clearanceStuds, params)
	if headroom then
		return nil, "no headroom above the ledge"
	end

	local targetRootY = standFoot.Y + humanoid.HipHeight + root.Size.Y * 0.5
	local target = Vector3.new(standFoot.X, targetRootY, standFoot.Z)

	-- 5. Is the PATH clear? The traversal goes up first and then forward — an L,
	--    not a diagonal — precisely so it does not cut the corner through the
	--    lip of the ledge. Both legs get checked, because a path that is only
	--    checked at its endpoints is a path that clips through everything in
	--    between.
	local rise = targetRootY - root.Position.Y
	if rise > 0 then
		local up = workspace:Raycast(root.Position, UP * (rise + 0.5), params)
		if up then
			return nil, "ceiling in the way of the climb"
		end
	end
	local corner = Vector3.new(root.Position.X, targetRootY, root.Position.Z)
	local across = target - corner
	if across.Magnitude > 0.05 then
		local blocked = workspace:Raycast(corner, across, params)
		if blocked then
			return nil, "something on top of the ledge"
		end
	end

	return {
		target = target,
		surfaceY = topHit.Position.Y,
		height = height,
		wallNormal = wallHit.Normal,
	}, "ok"
end

-- The L path, sampled at `alpha` from 0 to 1: all the way up over the first
-- half, all the way across over the second.
--
-- Two straight legs rather than a curve, because the point of the shape is that
-- the horizontal leg happens entirely ABOVE the ledge. A smooth arc is prettier
-- and puts the character's root inside the lip for the middle third of it.
function Traversal.pathPoint(from: Vector3, target: Vector3, alpha: number): Vector3
	local a = math.clamp(alpha, 0, 1)
	-- Eased, so the traversal starts and ends without a visible jolt. The shape
	-- of the path is the L; this is only how fast you move along it.
	local eased = a * a * (3 - 2 * a)
	local lift = math.min(eased * 2, 1)
	local push = math.max(eased * 2 - 1, 0)

	local y = from.Y + (target.Y - from.Y) * lift
	local x = from.X + (target.X - from.X) * push
	local z = from.Z + (target.Z - from.Z) * push
	return Vector3.new(x, y, z)
end

return Traversal
