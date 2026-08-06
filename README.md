# LLSPLOIT

Loomian Legacy automation UI (Orion). Modular loader pulls each file from this repo at runtime.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/CZkfKvEXfEGozgGzQQADIOnMAzoKcwsfMbHigwQQPewOcGgH/main/main.lua"))()
```

Compatibility alias (same result):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/CZkfKvEXfEGozgGzQQADIOnMAzoKcwsfMbHigwQQPewOcGgH/main/LLSPLOIT.lua"))()
```

If a fresh push does not show up yet (raw CDN cache), pin a commit SHA:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/CZkfKvEXfEGozgGzQQADIOnMAzoKcwsfMbHigwQQPewOcGgH/<commit>/main.lua"))()
```

Toggle the window with **RightShift** if it is hidden.

## Features (UI tabs)

| Tab | What’s inside |
|-----|----------------|
| **Overview** | Money / Tix / BP + status |
| **Farm** | Wild encounters, capture rules, fishing, Goppie formes, Use Spare / Corrupt Move |
| **Hunts** | Static soft-resets + beast hunts |
| **Battle** | Auto battle, Auto Heal (outdoor), Fast Battle (anim/fillbar hooks), Skip Dialogue hooks, prompt denies, Ignore NPC Battle, End Battle, trainer farming |
| **Rally** | Auto rally keep/release rules |
| **Storage** | Boonary cleanup, repel / PC helpers |
| **Fossil** | Petrolith revive automation |
| **Arcade** | Auto Disc Drop (max score + finish time boxes) |
| **Settings** | Shops, movement utilities, anti-AFK, server hop, config profiles |

## How loading works

`main.lua`:

1. Downloads every file under `modules/` (`HttpGet`)
2. Runs them in order with no yields between executes (avoids `task.defer` races)
3. Exports shared automations onto `_G` / `getgenv()`
4. Builds the Orion window and starts background loops

Repo must stay **public** for raw GitHub URLs to work from an executor.

## Layout

```
main.lua          entry / module loader
LLSPLOIT.lua      thin alias → main.lua
modules/
  boot.lua        boot notifications
  orion.lua       Orion UI library
  globals.lua     services + shared state
  core.lua        core helpers + FishingAutomation
  battle.lua      battle helpers / natural run
  world.lua       UMV, mining, movement
  combat.lua      heal, trainers, prompts, servers
  static.lua      StaticAutomation (soft resets)
  shops.lua       rally / shops / boonary helpers
  catch.lua       CatchAutomation
  arcade.lua      ArcadeAutomation (Disc Drop)
  fossil.lua      fossil revive + config save/load
  ui.lua          window, tabs, background loops
```

## Config

Profiles save under the executor workspace (`LLSPLOIT/`), including autosave `config.json`.

Useful Disc Drop fields (also in the Arcade tab):

- **Max Score** — stop a run at this score (blank = no cap)
- **Finish Time** — submitted time (`90`, `1:30`, or `1m30s`)

## Notes

- Open the arcade / relevant areas once so game modules (e.g. `DiscDropGrid`) are loaded before enabling automation.
- Re-running the loader replaces the UI; wait for notifications to finish if you reload mid-session.
