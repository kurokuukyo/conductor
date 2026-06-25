local Jabby = require(script.Parent.Jabby)

local step_map = {
	[Enum.StepFrequency.Hz60] = 60,
	[Enum.StepFrequency.Hz30] = 30,
	[Enum.StepFrequency.Hz15] = 15,
	[Enum.StepFrequency.Hz10] = 10,
	[Enum.StepFrequency.Hz5] = 5,
	[Enum.StepFrequency.Hz1] = 1,
	[1 / 20] = 20,
}

const function get_phase_name(step: Enum.StepFrequency | number)
	const found_hz = step_map[step]
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

local ConductorJabby = {}
ConductorJabby.__index = ConductorJabby

function ConductorJabby.new()
	return setmetatable({}, ConductorJabby)
end

function ConductorJabby:attach(scheduler)
	local jabbyScheduler = Jabby.scheduler.create()
	local systemToId = {}

	function scheduler._wrapSystem(system, originalUpdate)
		local id = jabbyScheduler:register_system({
			name = system.name,
			phase = get_phase_name(system.step), -- replace with real phase if you add one
			type = 0,
		})

		systemToId[system.name] = id

		jabbyScheduler:set_system_data(id, {
			paused = false,
			rate = step_map[system.step],
		})

		return function(dt)
			jabbyScheduler:run(id, function()
				originalUpdate(dt)
			end)
		end
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
