--!strict
-- Diagnostics — the boot manifest (NOD-127).
--
-- This module exists because of one specific week. A single parse error in
-- LobbyService (`(Vector3, Vector3)?`, which Luau does not allow) killed the
-- ENTIRE server from commit a09307c onward: no round loop, no combat, no lobby
-- camera, no cursor release, no pads. Every "separate bug" reported for days was
-- that one dead server, and nothing on screen said so.
--
-- The rule this module enforces: **a system that fails must be loud, and a
-- system that fails must not take the others with it.**
--
-- Two containment layers, and the first one matters more than it looks:
--
--   load()  wraps `require`. A module with a SYNTAX error throws at require
--           time, before any init function exists to guard — so guarding only
--           init would not have caught the bug above. This does.
--   start() wraps init. A runtime error during startup marks that one system
--           DEAD and lets the rest of the game boot.
--
-- Everything declared with expect() and never reported shows as PENDING, which
-- is treated as failure. "Never ran" and "ran and died" are equally bad and the
-- manifest refuses to distinguish them in your favour.

local RunService = game:GetService("RunService")

export type Status = "OK" | "WARN" | "DEAD" | "PENDING"

type Entry = {
	name: string,
	status: Status,
	detail: string?,
	counters: { [string]: number },
	order: number,
}

export type Snapshot = {
	context: string,
	entries: { Entry },
	ok: number,
	warn: number,
	dead: number,
	pending: number,
}

local Diagnostics = {}

local entries: { [string]: Entry } = {}
local order: { string } = {}
local reported = false

local function context(): string
	return if RunService:IsServer() then "SERVER" else "CLIENT"
end

local function entryFor(name: string): Entry
	local existing = entries[name]
	if existing then
		return existing
	end

	table.insert(order, name)
	local entry: Entry = {
		name = name,
		status = "PENDING",
		detail = nil,
		counters = {},
		order = #order,
	}
	entries[name] = entry
	return entry
end

-- Declare a system that SHOULD come online. Call these up front, before any
-- init runs, so a system that never executes at all still appears in the
-- manifest as PENDING rather than simply being absent. An absent system looks
-- like it was never meant to exist; a PENDING one looks like what it is.
function Diagnostics.expect(...: string)
	for _, name in { ... } do
		entryFor(name)
	end
end

function Diagnostics.ok(name: string, detail: string?)
	local entry = entryFor(name)
	entry.status = "OK"
	entry.detail = detail
end

-- Alive, but not fully. Use for "loaded 0 of something we expected some of" —
-- the state that historically looked fine and wasn't.
function Diagnostics.warn(name: string, detail: string)
	local entry = entryFor(name)
	entry.status = "WARN"
	entry.detail = detail
	warn(`[PinkPanic] ⚠️ {name}: {detail}`)
end

function Diagnostics.dead(name: string, reason: string)
	local entry = entryFor(name)
	entry.status = "DEAD"
	entry.detail = reason
	warn(`[PinkPanic] ☠️ {name} is DEAD: {reason}`)
end

-- Counters are how a system proves it is doing something, not merely loaded.
-- The old slide code was present, compiled, and never fired once; nothing in
-- the game could tell the difference. A counter can.
function Diagnostics.count(name: string, counter: string, delta: number?)
	local entry = entryFor(name)
	entry.counters[counter] = (entry.counters[counter] or 0) + (delta or 1)
end

function Diagnostics.getCount(name: string, counter: string): number
	local entry = entries[name]
	if not entry then
		return 0
	end
	return entry.counters[counter] or 0
end

-- Guarded require. Returns nil and marks the system DEAD if the module fails to
-- compile or errors while loading. This is the layer that would have contained
-- the LobbyService parse error instead of letting it kill the whole server.
function Diagnostics.load<T>(name: string, module: ModuleScript): T?
	local success, result = pcall(function()
		return require(module) :: any
	end)

	if not success then
		-- A compile error gives Roblox's generic "Requested module experienced an
		-- error while loading" and prints the real parse error as a SEPARATE line
		-- just above. Say so, because the useful message is the one this string
		-- does not contain.
		local hint = if string.find(result :: string, "experienced an error while loading", 1, true)
			then " (the real error is the line logged directly above this manifest)"
			else ""
		Diagnostics.dead(name, `failed to load — {result}{hint}`)
		return nil
	end

	return result :: T
end

-- Guarded startup. Returns whether the system came up. A system that throws
-- here is marked DEAD and the caller keeps going.
function Diagnostics.start(name: string, fn: () -> ()): boolean
	local success, err = pcall(fn)

	if not success then
		Diagnostics.dead(name, `errored during init — {err}`)
		return false
	end

	-- Only claim OK if the system did not already say something more specific
	-- about itself. A system that called warn() during its own init keeps that.
	local entry = entryFor(name)
	if entry.status == "PENDING" then
		entry.status = "OK"
	end
	return true
end

-- Fetch a required child, or mark the system DEAD naming exactly what was
-- missing. Replaces the pattern of FindFirstChild followed by a silent early
-- return, which is how a system disables itself without telling anyone.
function Diagnostics.requireChild(parent: Instance, childName: string, name: string): Instance?
	local child = parent:FindFirstChild(childName)
	if not child then
		Diagnostics.dead(name, `missing required child "{childName}" under {parent:GetFullName()}`)
		return nil
	end
	return child
end

function Diagnostics.snapshot(): Snapshot
	local list: { Entry } = {}
	local counts = { OK = 0, WARN = 0, DEAD = 0, PENDING = 0 }

	for _, name in order do
		local entry = entries[name]
		table.insert(list, entry)
		counts[entry.status] += 1
	end

	return {
		context = context(),
		entries = list,
		ok = counts.OK,
		warn = counts.WARN,
		dead = counts.DEAD,
		pending = counts.PENDING,
	}
end

local function formatCounters(entry: Entry): string
	local parts: { string } = {}
	for counter, value in entry.counters do
		table.insert(parts, `{counter}={value}`)
	end
	if #parts == 0 then
		return ""
	end
	table.sort(parts)
	return `  [{table.concat(parts, " ")}]`
end

-- Print the manifest. Call once, at the end of boot, after every system has had
-- its chance to report.
function Diagnostics.report(buildTag: string?): Snapshot
	local snap = Diagnostics.snapshot()
	local ctx = snap.context

	local width = 0
	for _, entry in snap.entries do
		width = math.max(width, #entry.name)
	end

	local header = if buildTag then `  build: {buildTag}` else ""
	print(`[PinkPanic] ══════ {ctx} BOOT MANIFEST ══════{header}`)

	-- Status is padded to a fixed width so the name column lines up. This is a
	-- surface you scan for the one bad row among twenty good ones, and ragged
	-- columns are exactly how a DEAD line gets skimmed past.
	for _, entry in snap.entries do
		local icon = if entry.status == "OK"
			then "✅"
			elseif entry.status == "WARN" then "⚠️"
			elseif entry.status == "DEAD" then "☠️"
			else "❓"

		local status = entry.status .. string.rep(" ", 7 - #entry.status)
		local padded = entry.name .. string.rep(" ", width - #entry.name)
		local detail = if entry.detail then `  {entry.detail}` else ""
		print(`[PinkPanic] {icon} {status}{padded}{detail}{formatCounters(entry)}`)
	end

	local broken = snap.dead + snap.pending
	print(
		`[PinkPanic] ────── {snap.ok} OK · {snap.warn} WARN · {snap.dead} DEAD · {snap.pending} NEVER REPORTED ──────`
	)

	-- The whole point. If something is down, this is impossible to scroll past.
	if broken > 0 then
		warn(
			`[PinkPanic] ☠️☠️☠️ {broken} SYSTEM(S) ARE NOT RUNNING. `
				.. `The game is broken in a way that will look like unrelated bugs. `
				.. `Fix these before testing anything else.`
		)
	end

	reported = true
	return snap
end

-- Systems that come online after the manifest prints (a late-joining player's
-- client controller, a map loading mid-session) still get reported, otherwise
-- their failures would land in a manifest nobody is looking at any more.
function Diagnostics.hasReported(): boolean
	return reported
end

return Diagnostics
