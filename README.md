# Conductor

Conductor is an agnostic scheduler for Roblox ECS environments.

## At A Glance

Conductor:
- Is built for BindToSimulation.
- Is extensible through the plugin API.
- Supports [Jabby](https://github.com/alicesaidhi/jabby) through the ConductorJabby plugin.
- Doesn't force you to use any tools you don't need.

## Installation

This project is only available on GitHub right now due to the potential for huge API changes. There be dragons!

To install the project right now, you can use pesde. Your pesde.toml should look like this once you're done:

```toml
conductor = { repo = "kurokuukyo/conductor", rev = "<insert commit you want to target>", path = "lib/conductor" }

# Optional
conductorjabby = { repo = "kurokuukyo/conductor", rev = "<insert commit you want to target>", path = "lib/conductorjabby" }

[overrides]
"conductorjabby>Conductor" = "conductor" # ConductorJabby won't always have the latest commit during this part of development in its dependencies.
```

If you want to patch Jabby to allow BindToSimulation to play nice, you can use the following:

```toml
jabby = { repo = "kurokuukyo/jabby", rev = "538ffd1" }

...
[overrides]
"conductorjabby>Jabby" = "jabby"
```

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

Jabby unfortunately does not play well with BindToSimulation events out of the gate. [This fork aims to fix that.](https://github.com/kurokuukyo/jabby/tree/0.2)

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