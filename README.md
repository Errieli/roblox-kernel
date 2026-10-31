# Kernel

A small runtime foundation for Roblox games, installed as one ModuleScript at `ReplicatedFirst.Kernel`. It gives every script the same startup phases, events, task scheduling, cleanup and lazily loaded utilities, without project-specific code.

```luau
local Kernel = require(game.ReplicatedFirst.Kernel)
```

> **Status: `0.2.0-candidate.15` (release candidate).** Used in production games, with no stable release yet. Test it in your own place before adopting it.

## Installation

This repository is the module: `init.luau` is the `Kernel` ModuleScript and each subfolder's `init.luau` is a child ModuleScript with the folder's name (`_Task/init.luau` becomes `ReplicatedFirst.Kernel._Task`). This is the standard `init.luau` layout used by Roblox file-sync tools: point a folder named `Kernel` at a clone of this repository (for example as a git submodule), or create the ModuleScripts by hand with the same names and hierarchy.

Place it in **ReplicatedFirst** so it is available to client scripts as early as possible. Requiring the Kernel never waits for the game to load.

## Startup phases

Scripts coordinate through four ordered phases instead of a central loader:

| Phase | Use it for |
|---|---|
| `Preload` | Declaring exports and configuration before anything runs |
| `Shared` | Shared services that other systems depend on |
| `Runtime` | Gameplay systems |
| `Ready` | Work that needs everything else in place |

```luau
local Kernel = require(game.ReplicatedFirst.Kernel)

Kernel.Yield("Preload")
Kernel{
	name = "Shop",
	value = Shop,
	purpose = "Sells items for coins.",
	dependencies = {"Inventory"},
}

Kernel.Yield("Runtime")
Kernel.Inventory.Add(player, "Sword") -- Exports are read as Kernel.<name>.
```

- `Kernel.Yield(phase)` suspends the script until every earlier phase has completed. It does not wait for other scripts in the same phase. It takes only the phase: code that must not block its script runs in `Kernel.Task.Spawn(function() ... end)`.
- `Kernel{name, value, purpose, dependencies?}` registers a read-only export; it is the only registration form. Duplicate names are rejected, and dependencies still missing when `Ready` finishes fail startup with a clear message.
- `Kernel.Info()` returns diagnostics: each export's purpose and dependencies, phase status and timing, failures, stalled phases and missing dependencies.
- On the client, the first phase starts after `game.Loaded`. An error in a phase stops later phases and is reported.

## Modules

| Export | What it does |
|---|---|
| `Kernel.Task` | `Spawn`, `Defer`, `Delay`, `Wait` (native `task`) and `Cancel(thread)`, which refuses to cancel the running thread |
| `Kernel.Events` | Named local events: `Connect`, `Once`, `Fire` (scheduled), `FireYield` (inline), retained state with `FireState`/`Observe`/`WaitState`, plus `Wait`, `HasState`, `ClearState` |
| `Kernel.Recycle` | `Recycle.new()` collects functions, threads, instances, connections and objects with `Disconnect`/`Destroy`; `:Destroy()` cleans everything once, even if one cleanup fails |
| `Kernel.Beat` | `Heartbeat`, `Stepped`, `PreSimulation`, `PostSimulation`, `PreAnimation` (and `PreRender`, `RenderStepped` on the client). Each returns a disconnect function; pass a number first to throttle: `Beat.Heartbeat(0.5, callback)` |
| `Kernel.Players` | `Added(callback)` and `Removed(callback)` for current and future players; `Online` lists them |
| `Kernel.Class` | Builds a constructor from a table with optional `Constructor` and `Destructor` |
| `Kernel.Multiplier` | Creates multiplier groups that combine named sources per type, with `Set`, `Get`, `GetSource` and `Changed` |
| `Kernel.Configs` | Lazily requires ModuleScripts from `ReplicatedStorage.Configs` (subfolders nest): `Kernel.Configs.Items.Sword` |
| `Kernel.Assets` | Lazily maps instances in `ReplicatedStorage.Assets`: `Kernel.Assets.Effects.Spark` |
| `Kernel.Utils` | Your game's utilities in `ReplicatedStorage.Utils`, loaded on first use |

### Events

```luau
local disconnect = Kernel.Events.Connect("Round Started", function(round)
	print("Round", round)
end)
Kernel.Events.Fire("Round Started", 3)

-- Retained state: late observers still receive the latest value.
Kernel.Events.FireState("Map Ready", workspace.Map)
Kernel.Events.Observe("Map Ready", function(map) end)
```

`Fire` schedules listeners with `task.spawn`; `FireYield` runs them inline. Callbacks receive `nil` arguments intact, and listener completion order is not guaranteed.

### Utilities

`Kernel.Utils.<Name>` requires `ReplicatedStorage.Utils.<Name>` the first time it is used and caches it. Folders nest (`Kernel.Utils.Text.FormatTime`). The Kernel ships no utilities: put the ModuleScripts your game needs in `ReplicatedStorage.Utils`.

```luau
local Utils = require(game.ReplicatedFirst.Kernel).Utils
print(Utils.FormatNumber.Compact(1500)) -- 1.5K
```

A missing `Utils` folder or utility raises an error that names it.

### `_ProfileData`

`Kernel._ProfileData` validates and copies serializable data trees (finite numbers, booleans, strings, dense arrays and string-keyed dictionaries; no cycles) and computes change paths. It supports a separate player-data runtime and is not a public `Kernel` export.

## License

[MIT](LICENSE)
