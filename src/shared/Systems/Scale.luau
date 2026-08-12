--!strict
-- Scale — studs to real units, derived from the character (NOD-169).
--
-- Titus: *"lets make a measurement system that can convert studs into feet in
-- our game so stuff is to a realistic scale."*
--
-- The conversion is not a constant anybody typed. It is the ratio between the
-- height the standard character is DECLARED to be (ScaleConfig, in inches) and
-- the height that same character MEASURES in studs. Change the rig and the
-- conversion follows, because `calibrate` is fed by the thing that builds it.
--
-- Why not Roblox's own 1 stud = 0.28m: that would make the standard rig 4'10",
-- and every range in the game would be quietly a sixth shorter than it reads.
-- The rig is the ground truth here, not the engine's nominal figure.
--
-- Dependency direction: this is a System and reads only Config (rule 3).
-- CharacterService pushes the measurement in rather than being required —
-- a System never requires a Service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local ScaleConfig = require(ReplicatedStorage.Shared.Config.ScaleConfig)

local SYSTEM = "Scale"

local Scale = {}

-- The live measurement, seeded from the config fallback so every conversion
-- below works in Edit mode and before the first spawn.
local rigStuds = ScaleConfig.referenceRigStuds

-- A drift this size means the rig changed, not that the measurement is noisy.
-- Height is pose-invariant, so anything above a rounding error is real.
local DRIFT_STUDS = 0.05

local function feetPerStud(): number
	return (ScaleConfig.characterHeightInches / 12) / rigStuds
end

-- ---------------------------------------------------------------------------
-- Conversions
-- ---------------------------------------------------------------------------

function Scale.feetPerStud(): number
	return feetPerStud()
end

function Scale.toFeet(studs: number): number
	return studs * feetPerStud()
end

function Scale.toStuds(feet: number): number
	return feet / feetPerStud()
end

function Scale.toMetres(studs: number): number
	return Scale.toFeet(studs) * 0.3048
end

function Scale.toInches(studs: number): number
	return Scale.toFeet(studs) * 12
end

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------

-- Feet, rounded honestly: to the foot up close, to five feet past the point
-- where a single foot stops being a distinction anybody can perceive.
function Scale.feetText(studs: number): string
	local feet = Scale.toFeet(studs)
	if feet >= ScaleConfig.coarseAboveFeet then
		return `{math.floor(feet / 5 + 0.5) * 5} ft`
	end
	return `{math.floor(feet + 0.5)} ft`
end

-- "40 studs (43 ft)" — the form every range in a report should be quoted in,
-- so the stud figure stays authoritative and the foot figure stays checkable.
function Scale.describe(studs: number): string
	return `{string.format("%.4g", studs)} studs ({Scale.feetText(studs)})`
end

-- ---------------------------------------------------------------------------
-- Calibration
-- ---------------------------------------------------------------------------

-- Fed by whatever builds the standard character. Returns true if the number
-- moved, so the caller can decide whether that is news.
--
-- Warns rather than silently accepting: the conversion moving means every
-- range in the game just changed meaning, which is worth one line in the
-- manifest and is invisible otherwise.
function Scale.calibrate(measuredStuds: number): boolean
	if measuredStuds <= 0 then
		return false
	end
	local drift = math.abs(measuredStuds - rigStuds)
	if drift < DRIFT_STUDS then
		rigStuds = measuredStuds
		return false
	end

	local was = rigStuds
	rigStuds = measuredStuds
	Diagnostics.warn(
		SYSTEM,
		`standard rig measured {string.format("%.4f", measuredStuds)} studs, not `
			.. `{string.format("%.4f", was)} — every range in the game just changed `
			.. `meaning by {string.format("%.1f", (measuredStuds / was - 1) * 100)}%. `
			.. `Update ScaleConfig.referenceRigStuds`
	)
	return true
end

function Scale.rigStuds(): number
	return rigStuds
end

function Scale.init()
	local inches = ScaleConfig.characterHeightInches
	Diagnostics.ok(
		SYSTEM,
		`1 stud = {string.format("%.3f", feetPerStud())} ft · character {math.floor(inches / 12)}'`
			.. `{inches % 12}" over {string.format("%.4f", rigStuds)} studs · `
			.. `100 studs = {Scale.feetText(100)}`
	)
end

return Scale
