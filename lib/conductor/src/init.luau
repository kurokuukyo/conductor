--!optimize 2
--!native
--!strict

local RunService = game:GetService("RunService")
local IS_CLIENT = RunService:IsClient()

local Conductor = {}

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

export type Plugin = {
	attach: (self: Plugin, scheduler: typeof(Conductor.new())) -> unknown,
}

type SystemInternal = System & {
	_name: string?,
	_connection: RBXScriptConnection?,
}

local ERRORS = {
	DESYNCED_DEPENDENCY = "Attempt to depend on system with mismatched step sizes.\n"
		.. '\n\tMain System "%s":'
		.. "\n\t\tStep Size: %s"
		.. '\n\tDepends On System "%s":'
		.. "\n\t\tStep Size: %s"
		.. "\n\nMatch step sizes if you want a system to depend on another.",
	RENDERSTEPPED_ON_SERVER = 'Attempted to set the step frequency of system "%s" to Render. This frequency is only allowed on a client.',
	DEPENDENT_SYSTEM_NOT_REGISTERED = `System \"%s\" did not properly add and was depended on by system \"%s\". Make sure it's declared properly.`,
	SYSTEM_DOES_NOT_EXIST = 'System "%s" does not exist. Was it properly added to the scheduler?',
}

local RUN_AFTER_TIMEOUT = 3

local function get_system_name(system: SystemInternal)
	if system._name then
		return system._name
	end
	local name = debug.info(system.def.system, "n")
	if not name or string.len(name) == 0 then
		local source, line = debug.info(system.def.system, "s1")
		name = `{source}:{line}`
	end

	system._name = name

	return name
end

function Conductor.new()
	local scheduler = {}
	scheduler.systems = {} :: { [string]: System }

	local current_priority = 2000
	local function get_priority()
		current_priority += 1
		return current_priority
	end

	local function bind_on_render(system: SystemInternal, update_fn: (dt: number) -> ())
		if not IS_CLIENT then
			error(ERRORS.RENDERSTEPPED_ON_SERVER:format(get_system_name(system)))
		end
		system._connection = RunService.RenderStepped:Connect(update_fn)
	end

	local function bind_on_arbitrary_hz(system: SystemInternal, update_fn: (dt: number) -> ())
		local current_dt = 0
		local interval = system.def.step :: number

		local function handle_tick(dt: number)
			current_dt += dt
			if current_dt >= interval then
				update_fn(current_dt)
				current_dt -= interval
			end
		end

		system._connection = RunService:BindToSimulation(handle_tick, Enum.StepFrequency.Hz60, get_priority())
	end

	local function bind_on_hz(system: SystemInternal, update_fn: (dt: number) -> ())
		system._connection =
			RunService:BindToSimulation(update_fn, system.def.step :: Enum.StepFrequency, get_priority())
	end

	local function setup_binds(system: SystemInternal, update_fn: (dt: number) -> ())
		local step = system.def.step

		if step == Conductor.StepFrequency.Render then
			bind_on_render(system, update_fn)
		elseif typeof(step) == "number" then
			bind_on_arbitrary_hz(system, update_fn)
		else
			bind_on_hz(system, update_fn)
		end
	end

	local function verify_same_step_size(dependent: SystemInternal, system: SystemInternal)
		if dependent.def.step ~= system.def.step then
			error(
				ERRORS.DESYNCED_DEPENDENCY:format(
					get_system_name(system),
					tostring(system.def.step),
					get_system_name(dependent),
					tostring(dependent.def.step)
				)
			)
		end
	end

	local function find_dependencies_recursive(tbl: RunAfter, system: SystemInternal, result: { System }?): { System }
		if not result then
			result = {}
		end
		if (tbl :: SystemInternal).def then
			verify_same_step_size(tbl :: SystemInternal, system)
			table.insert(result :: { System }, tbl :: SystemInternal)
		else
			for _, potential_dependency: SystemInternal in tbl do
				if potential_dependency.def then
					verify_same_step_size(potential_dependency, system)

					table.insert(result :: { System }, potential_dependency)
					continue
				end
				find_dependencies_recursive(potential_dependency, system, result)
			end
		end
		return result :: { System }
	end

	--[=[
		Adds a system to the scheduler.

		Returns the internal entry associated with the system.

		Usage:

		```lua
		local system = scheduler:add({
			system = system_fn, -- Name of the system is based on this function name.
			step = Conductor.StepFrequency.Hz60
		})
		```

		The update function is passed the delta time and is defined as such:

		```lua
		local function system_fn(dt: number)
			...
		end
		```
	]=]
	function scheduler:add(system_definition: SystemDefinition): System
		if system_definition.step_client and IS_CLIENT then
			system_definition.step = system_definition.step_client
		end

		local system: SystemInternal
		system = {
			def = system_definition,
			remove = function()
				if system._connection then
					system._connection:Disconnect()
				end
			end,
		} :: SystemInternal
		local sys_name = get_system_name(system) -- Get this out of the way.

		local system_fn = system.def.system

		local function update_fn(dt: number)
			if system.paused then
				return
			end

			system_fn(dt)
		end

		if not system_definition.run_after then
			setup_binds(system, update_fn)
		else
			local dependencies = find_dependencies_recursive(system.def.run_after :: RunAfter, system)
			local remaining = #dependencies
			for _, dependency: SystemInternal in dependencies do
				task.spawn(function()
					local timeout_dt = 0

					repeat
						timeout_dt += task.wait()
						if timeout_dt >= RUN_AFTER_TIMEOUT then
							error(
								ERRORS.DEPENDENT_SYSTEM_NOT_REGISTERED:format(
									get_system_name(dependency),
									get_system_name(system)
								)
							)
						end
					until self.systems[get_system_name(dependency)]

					remaining -= 1
					if remaining == 0 then
						setup_binds(system, update_fn)
					end
				end)
			end
		end

		self.systems[sys_name] = system

		return system :: System
	end

	--[=[
		Removes a system from the scheduler.

		Both the string name and the result from `scheduler:add` are valid inputs.

		Usage:

		```lua
		scheduler:remove("viewmodel_system")
		scheduler:remove(viewmodel_system)
		```
	]=]
	function scheduler:remove(input: SystemInternal | string)
		local system: SystemInternal = if typeof(input) == "string" then self.systems[input] else input
		if system then
			local name = get_system_name(system)
			system.remove()
			self.systems[name] = nil
		end
	end

	--[=[
		Pauses a system from execution.

		Both the string name and the result from `scheduler:add` are valid inputs.

		Usage:

		```lua
		scheduler:pause("viewmodel_system")
		scheduler:pause(viewmodel_system)
		```
	]=]
	function scheduler:pause(input: SystemInternal | string)
		local system: SystemInternal = if typeof(input) == "string" then self.systems[input] else input
		if system then
			system.paused = true
		end
	end

	--[=[
		Resumes execution for a system that was paused.

		Both the string name and the result from `scheduler:add` are valid inputs.

		Usage:

		```lua
		scheduler:resume("viewmodel_system")
		scheduler:resume(viewmodel_system)
		```
	]=]
	function scheduler:resume(input: SystemInternal | string)
		local system: SystemInternal = if typeof(input) == "string" then self.systems[input] else input
		if system then
			system.paused = nil
		end
	end

	--[=[
		Hooks plguins that can extend the functionality of Conductor.

		Usage:

		```lua
		local scheduler = Conductor.new():register_plugin(ConductorJabby.new())
		```
	]=]
	function scheduler:register_plugin(plugin: Plugin)
		plugin:attach(self)
		return self
	end

	--[=[
		**Requires ConductorJabby.**

		Gets the jabby scheduler associated with Conductor.
		Usage:

		```lua
		local jabby_scheduler = scheduler:get_jabby_scheduler()
		```
	]=]
	function scheduler:get_jabby_scheduler()
		error("To use this method you need to use the ConductorJabby plugin.")
	end

	return scheduler
end

Conductor.StepFrequency = {
	--- System will run on every frame. Only available on the client.
	Render = 0,

	--- System will run every 60 Hz.
	Hz60 = Enum.StepFrequency.Hz60,

	--- System will run every 30 Hz.
	Hz30 = Enum.StepFrequency.Hz30,

	--- System will run every 15 Hz.
	Hz15 = Enum.StepFrequency.Hz15,

	--- System will run every 10 Hz.
	Hz10 = Enum.StepFrequency.Hz10,

	--- System will run every 5 Hz.
	Hz5 = Enum.StepFrequency.Hz5,

	--- System will run every second.
	Hz1 = Enum.StepFrequency.Hz1,

	-- I've given you the power. Do not make me take it away.

	--[=[
		Takes an arbitrary Hz for use within the scheduler.

		Internally this will use a Hz60 frequency and only call
		the system as appropriate. Use a number that cleanly
		divides 60 for best results.

		Usage:

		```lua
		scheduler:add({
			...
			step = Scheduler.StepFrequency.FromHz(20),
		})
		```
	]=]
	FromHz = function(number: number)
		return 1 / number
	end,
}

return Conductor
