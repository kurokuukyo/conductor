# Conductor

Conductor is an agnostic scheduler for Roblox ECS environments.

## At A Glance

Conductor:
- Is built for BindToSimulation.
- Is extensible through the plugin API.
- Supports [Jabby](https://github.com/alicesaidhi/jabby) through the ConductorJabby plugin.
- Doesn't force you to use any tools you don't need.

## Installation

TODO. This has not been published on wally, which will change once the API matures.

## Yet Another Scheduler?

Conductor is meant to bring systems to [Roblox's BindToSimulation](https://create.roblox.com/docs/reference/engine/classes/RunService#BindToSimulation) method.
Currently, public schedulers do not support this well. This project aims to bridge that gap as more systems rely on this for Server Authority.

## Getting Started

```lua
local Conductor = require("@packages/Conductor")

local scheduler = Conductor.new()

-- To add a system:

local system1 = scheduler:add({
	system = system_fn,
	step = Conductor.StepFrequency.Hz60,
})

-- To ensure a system runs after another system:

local system2 = scheduler:add({
	system = system2_fn,
	step = Conductor.StepFrequency.Hz60,
    run_after = { system1 },
})
```

## Jabby

Jabby can integrate with Conductor by modifying the scheduler a little with the ConductorJabby plugin.

```lua
local Conductor = require("@packages/Conductor")
local ConductorJabby = require("@packages/ConductorJabby")
local Jabby = require("@packages/Jabby")
local world = require("@self/world") -- Not required for Conductor to function.

local scheduler = Conductor.new()
    :register_plugin(ConductorJabby.new())

Jabby.register({
	applet = Jabby.applets.scheduler,
	name = "Scheduler",
	configuration = {
		scheduler = scheduler:get_jabby_scheduler(), -- Only valid with the ConductorJabby plugin.
	},
})

Jabby.register({
	applet = Jabby.applets.world,
	name = "World",
	configuration = {
		world = world
	},
})

-- Client

local client = Jabby.obtain_client()

local function createWidget(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then
		return
	end

	client.spawn_app(client.apps.home, nil)
end

ContextActionService:BindAction("Open Jabby", createWidget, false, Enum.KeyCode.F4)
```