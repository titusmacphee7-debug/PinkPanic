--!strict
-- Movement — the movement state machine, and the one answer to "how fast may
-- this player be going" (NOD-139).
--
-- **Shared, not client-only.** The issue named a client path, and rule 2 wins:
-- the server's plausibility check needs the same speed ceiling the client is
-- driving toward, and two implementations of that number is two numbers. The
-- ACTUATOR is client-only — it writes a LinearVelocity, which is a thing only
-- the owner does — and it lives in client/Movement.
--
-- Transitions are declared as DATA. Two reasons, and the second is the one that
-- matters. A table of legal edges can be read, so "can you slide out of a
-- dive?" is answered by looking rather than by tracing branches. And an illegal
-- transition is DETECTED — logged, named, counted — instead of silently doing
-- nothing, which is how a movement bug becomes "sometimes crouch doesn't work"
-- and stays that way for a month.
--
-- Nothing here touches an Instance. It is a pure state machine over a table, so
-- a test drives it in a loop instead of by running around a map.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Diagnostics = require(ReplicatedStorage.Shared.Systems.Diagnostics)
local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)

local SYSTEM = "Movement"

local Movement = {}

export type State =
	"Idle"
	| "Walk"
	| "Sprint"
	| "TacSprint"
	| "Crouch"
	| "Prone"
	| "Slide"
	| "Dive"
	| "Air"
	| "Mantle"
	| "Stun"

local STATES: { State } = {
	"Idle",
	"Walk",
	"Sprint",
	"TacSprint",
	"Crouch",
	"Prone",
	"Slide",
	"Dive",
	"Air",
	"Mantle",
	"Stun",
}
Movement.STATES = STATES

-- ---------------------------------------------------------------------------
-- The transition table
--
-- Read as: from the row, you may enter any column marked true. Every state can
-- enter Air (you can always be knocked off something) and Stun (M8 can always
-- interrupt you), so those two are added to every row below rather than typed
-- eleven times.
-- ---------------------------------------------------------------------------

local EDGES: { [State]: { State } } = {
	Idle = { "Walk", "Sprint", "Crouch", "Prone", "Mantle" },
	Walk = { "Idle", "Sprint", "Crouch", "Prone", "Mantle" },
	-- Sprint into a slide, or into a tactical sprint. NOT straight to prone:
	-- that is a dive, and a dive is its own state with its own arc.
	Sprint = { "Idle", "Walk", "TacSprint", "Crouch", "Slide", "Dive", "Mantle" },
	-- Tactical sprint has your gun down, so it cannot go anywhere that shoots
	-- without passing through Sprint first.
	TacSprint = { "Sprint", "Walk", "Idle", "Slide", "Dive", "Mantle" },
	Crouch = { "Idle", "Walk", "Sprint", "Prone", "Mantle" },
	Prone = { "Crouch", "Idle" },
	-- A slide ends standing, crouched or prone; you cannot re-enter a slide
	-- from a slide, which is what makes slide-cancelling a technique instead of
	-- a hold-the-key exploit.
	Slide = { "Idle", "Walk", "Sprint", "Crouch", "Prone" },
	Dive = { "Prone", "Crouch", "Idle" },
	Air = { "Idle", "Walk", "Sprint", "TacSprint", "Crouch", "Dive", "Mantle" },
	Mantle = { "Idle", "Walk", "Sprint", "Crouch" },
	-- Stun releases to standing, whatever you were doing when it landed.
	Stun = { "Idle", "Walk", "Crouch" },
}

local allowed: { [State]: { [State]: boolean } } = {}
for _, from in STATES do
	local row: { [State]: boolean } = {}
	for _, to in EDGES[from] or {} do
		row[to] = true
	end
	-- Universal edges. Gravity and stuns do not ask permission.
	row.Air = true
	row.Stun = true
	-- A state may always re-enter itself; that is a no-op, not a violation.
	row[from] = true
	allowed[from] = row
end

function Movement.canTransition(from: State, to: State): boolean
	local row = allowed[from]
	return row ~= nil and row[to] == true
end

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

function Movement.profileAllows(profile: Config.ProfileName, state: State): boolean
	local def = Config.profiles[profile]
	if not def then
		return true
	end
	return def.allowed[state] == true
end

-- ---------------------------------------------------------------------------
-- Speed
-- ---------------------------------------------------------------------------

-- The one answer. `weight` is the held gun's `moveSpeedMult` from CombatStats,
-- which is how a light SMG and an LMG stop being the same character.
--
-- Deliberately does NOT take the whole resolved stats table: this is called
-- from the server audit, where there may be no weapon at all, and a function
-- that needs one would have to invent a default — which is a second answer.
function Movement.speedFor(state: State, weight: number?): number
	local base = Config.speed[state] or Config.speed.Walk
	if state == "Idle" or state == "Stun" then
		return 0
	end
	return base * (weight or 1)
end

-- The fastest any legal state could have this player going, for the server's
-- plausibility check. Reads the table rather than hardcoding "Dive is fastest",
-- so re-tuning a speed cannot quietly outrun the check that watches it.
function Movement.maxSpeed(weight: number?): number
	local best = 0
	for _, state in STATES do
		local speed = Movement.speedFor(state, weight)
		if speed > best then
			best = speed
		end
	end
	return best
end

-- ---------------------------------------------------------------------------
-- Machine
-- ---------------------------------------------------------------------------

export type Machine = {
	state: State,
	previous: State,
	profile: Config.ProfileName,
	-- Simulation time in the current state. Slide duration, stun duration and
	-- the sprint-to-fire delay all read this rather than each keeping a clock.
	elapsed: number,
	-- Counted rather than merely refused, so "crouch does nothing sometimes"
	-- has a number attached to it.
	refused: number,
}

function Movement.create(profile: Config.ProfileName?): Machine
	return {
		state = "Idle",
		previous = "Idle",
		profile = profile or "combat",
		elapsed = 0,
		refused = 0,
	}
end

-- How loud a refusal is. The first few of any given kind are worth a line; the
-- thousandth is noise, and a warning people scroll past is not a warning.
local REPORT_LIMIT = 3
local reported: { [string]: number } = {}

-- Returns whether the transition happened.
--
-- A refusal is NOT silent. That is the entire design: `machine.state` staying
-- put with no explanation is indistinguishable from an input that never
-- arrived, and those two bugs live in completely different files.
function Movement.transition(machine: Machine, to: State): boolean
	local from = machine.state

	if not Movement.profileAllows(machine.profile, to) then
		-- Not a bug. The lobby genuinely does not have slides, and asking for
		-- one there is the input layer doing its job in the wrong room.
		Diagnostics.count(SYSTEM, `blocked:{machine.profile}:{to}`)
		machine.refused += 1
		return false
	end

	if not Movement.canTransition(from, to) then
		machine.refused += 1
		Diagnostics.count(SYSTEM, `illegal:{from}->{to}`)

		local key = `{from}->{to}`
		local seen = (reported[key] or 0) + 1
		reported[key] = seen
		if seen <= REPORT_LIMIT then
			Diagnostics.warn(
				SYSTEM,
				`illegal transition {from} → {to} (x{seen}) — the edge is not in the table, so either the `
					.. `input layer asked for something impossible or the table is missing a real move.`
			)
		end
		return false
	end

	if to == from then
		return true -- re-entering the same state is a no-op, not a change
	end

	machine.previous = from
	machine.state = to
	machine.elapsed = 0
	Diagnostics.count(SYSTEM, `enter:{to}`)
	return true
end

function Movement.step(machine: Machine, deltaTime: number)
	machine.elapsed += deltaTime
end

function Movement.setProfile(machine: Machine, profile: Config.ProfileName)
	if machine.profile == profile then
		return
	end
	machine.profile = profile
	-- Leaving a state the new profile does not have. Walking out of a slide
	-- into the lobby has to land somewhere, and Idle is the only state every
	-- profile is guaranteed to allow.
	if not Movement.profileAllows(profile, machine.state) then
		machine.previous = machine.state
		machine.state = "Idle"
		machine.elapsed = 0
	end
end

-- ---------------------------------------------------------------------------
-- Validation
--
-- Every edge names a real state, and every state is reachable from Idle. An
-- unreachable state is a feature nobody can ever get to, which is exactly the
-- kind of thing that is invisible until someone asks why sliding does not work.
-- ---------------------------------------------------------------------------

function Movement.validate()
	local known: { [string]: boolean } = {}
	for _, state in STATES do
		known[state] = true
	end

	local problems: { string } = {}
	for from, row in EDGES do
		if not known[from] then
			table.insert(problems, `EDGES has a row for "{from}", which is not a state`)
		end
		for _, to in row do
			if not known[to] then
				table.insert(problems, `{from} → "{to}", which is not a state`)
			end
		end
	end

	-- Breadth-first from Idle.
	local reachable: { [State]: boolean } = { Idle = true }
	local frontier: { State } = { "Idle" }
	while #frontier > 0 do
		local current = table.remove(frontier) :: State
		for to, ok in allowed[current] do
			if ok and not reachable[to] then
				reachable[to] = true
				table.insert(frontier, to)
			end
		end
	end
	for _, state in STATES do
		if not reachable[state] then
			table.insert(problems, `{state} is unreachable from Idle`)
		end
	end

	if #problems > 0 then
		Diagnostics.warn(SYSTEM, `state graph: {table.concat(problems, " · ")}`)
		return
	end

	local edges = 0
	for _, row in allowed do
		for _, ok in row do
			if ok then
				edges += 1
			end
		end
	end
	Diagnostics.ok(
		SYSTEM,
		`{#STATES} states, {edges} legal transitions, all reachable · `
			.. `walk {Config.speed.Walk} sprint {Config.speed.Sprint} · no math.huge anywhere`
	)
end

return Movement
