--!optimize 2
--!native
--!strict

local Jabby = require(script.Parent.Jabby)
local Conductor = require(script.Parent.Conductor)

local step_map = {
	[Enum.StepFrequency.Hz60] = 60,
	[Enum.StepFrequency.Hz30] = 30,
	[Enum.StepFrequency.Hz15] = 15,
	[Enum.StepFrequency.Hz10] = 10,
	[Enum.StepFrequency.Hz5] = 5,
	[Enum.StepFrequency.Hz1] = 1,
	[1 / 20] = 20,
}

local function get_phase_name(step: Enum.StepFrequency | number)
	local found_hz = step_map[step]
	if found_hz then
		return `Hz{found_hz}`
	elseif step == (1 / math.huge) then
		return `Render`
	end
	return `Hz{string.format("%u", 1 / step :: number)}`
end

local function get_system_name(system_definition: Conductor.SystemDefinition)
	if system_definition._name then
		return system_definition._name
	end
	local name = debug.info(system_definition.system, "n")
	if not name or string.len(name) == 0 then
		local source, line = debug.info(system_definition.system, "s"), debug.info(system_definition.system, "l")
		name = `{source}:{line}`
	end

	system_definition._name = name

	return name
end

local ConductorJabby = {}
ConductorJabby.__index = ConductorJabby

function ConductorJabby.new()
	return setmetatable({}, ConductorJabby)
end

function ConductorJabby:attach(scheduler: typeof(Conductor.new()))
	local systemToId = {}
	local systemNameToId = {}
	local jabbyScheduler = Jabby.scheduler.create()

	function scheduler:get_jabby_scheduler()
		return jabbyScheduler
	end

	local oldAdd = scheduler.add
	function scheduler:add(system_definition: Conductor.SystemDefinition)
		local system_name = get_system_name(system_definition)
		local id = jabbyScheduler:register_system({
			name = system_name,
			type = 0,
		})

		local system_fn = system_definition.system
		function system_definition.system(dt: number)
			jabbyScheduler:run(id, function()
				system_fn(dt)
			end)
		end

		local system = oldAdd(self, system_definition)

		jabbyScheduler:set_system_data(id, {
			phase = get_phase_name(system.def.step),
		})

		systemNameToId[system_name] = id
		systemToId[system] = id

		jabbyScheduler:set_system_data(id, {
			paused = false,
			rate = step_map[system.step],
		})

		return system
	end

	local function remove_from_lookups(id: number)
		for i, lookup in systemToId do
			if lookup == id then
				systemToId[i] = nil
				break
			end
		end
		for k, lookup in systemNameToId do
			if lookup == id then
				systemNameToId[k] = nil
				break
			end
		end
	end

	local oldRemove = scheduler.remove
	function scheduler:remove(input: Conductor.SystemInternal | string)
		oldRemove(self, input)

		local id = if typeof(input) == "string" then systemNameToId[input] else systemToId[input]
		if id then
			jabbyScheduler:remove_system(id)
			remove_from_lookups(id)
		end
	end

	local oldPause = scheduler.pause
	function scheduler:pause(input: Conductor.SystemInternal | string)
		oldPause(self, input)

		local id = if typeof(input) == "string" then systemNameToId[input] else systemToId[input]
		if id then
			jabbyScheduler:set_system_data(id, {
				paused = true,
			})
		end
	end

	for name, entry in scheduler.systems do
		local system = entry.def

		local id = jabbyScheduler:register_system({
			name = system.name,
			phase = get_phase_name(system.step),
		})

		systemToId[name] = id

		jabbyScheduler:set_system_data(id, {
			paused = true,
			rate = step_map[system.step],
		})
	end

	return jabbyScheduler
end

return ConductorJabby
