# LLSPLOIT

Load in your executor with:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/LLSPLOIT/main/main.lua"))()
```

`main.lua` fetches each file under `modules/` via `HttpGet` + `loadstring`, in order:

| Module | Responsibility |
|--------|----------------|
| `boot` | Boot notifications |
| `orion` | Orion UI library |
| `globals` | Services + shared state |
| `core` | Core helpers + FishingAutomation |
| `battle` | Battle helpers / natural run |
| `world` | Egg rain, UMV, mining, movement |
| `combat` | Heal, trainers, prompts, servers |
| `static` | Soft-reset StaticAutomation |
| `shops` | Rally, shops, boonary |
| `catch` | CatchAutomation |
| `arcade` | ArcadeAutomation |
| `fossil` | Fossil revive + config |
| `ui` | Window, tabs, background loops |

Compatibility alias:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/LLSPLOIT/main/LLSPLOIT.lua"))()
```
