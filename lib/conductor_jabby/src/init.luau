local Jabby = require(script.Parent.Jabby)
local Conductor = require(script.Parent.Conductor)

export type StepFrequency = Enum.StepFrequency | number

export type RunAfter = System | { RunAfter }

export type SystemDefinition = {
	step: StepFrequency,
	step_client: StepFrequency?,
	run_after: RunAfter?,
	system: (dt: number) -> (),
}

export type System = {
	def: SystemDefinition,
	paused: boolean?,
	remove: () -> (),
}

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
	end
	if step == math.huge then
		return `RunOnce`
	elseif step == (1 / math.huge) then
		return `Render`
	end
	return `Hz{string.format("%u", 1 / step :: number)}`
end

local function get_system_name(system_definition: SystemDefinition)
	local name = debug.info(system_definition.system, "n")
	if not name or string.len(name) == 0 then
		local source, line = debug.info(system_definition.system, "s1")
		name = `{source}:{line}`
	end

	return name
end

local ConductorJabby = {}
ConductorJabby.__index = ConductorJabby

function ConductorJabby.new()
	return setmetatable({}, ConductorJabby)
end

function ConductorJabby:attach(scheduler: typeof(Conductor.new()))
	local jabbyScheduler = Jabby.scheduler.create()
	local systemToId = {}

	local oldAdd = scheduler.add
	function scheduler:add(system_definition: SystemDefinition)
		local id = jabbyScheduler:register_system({
			name = get_system_name(system_definition),
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
			phase = get_phase_name(system.step),
		})

		systemToId[system.name] = id

		jabbyScheduler:set_system_data(id, {
			paused = false,
			rate = step_map[system.step],
		})
	end

	local oldRemove = scheduler.remove
	function scheduler:remove(name: string)
		oldRemove(self, name)

		local id = systemToId[name]
		if id then
			jabbyScheduler:remove_system(id)
			systemToId[name] = nil
		end
	end

	local oldPause = scheduler.pause
	function scheduler:pause(name: string)
		oldPause(self, name)

		local id = systemToId[name]
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
