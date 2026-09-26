# The Pale Watcher

[![ContentDB](https://content.luanti.org/packages/SaKeL/pale_watcher/shields/title/)](https://content.luanti.org/packages/SaKeL/pale_watcher/)
[![ContentDB Downloads](https://content.luanti.org/packages/SaKeL/pale_watcher/shields/downloads/)](https://content.luanti.org/packages/SaKeL/pale_watcher/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](license.txt)
[![Media License: CC-BY-SA 4.0](https://img.shields.io/badge/Media-CC_BY--SA_4.0-lightgrey.svg)](license.txt)
![Luanti](https://img.shields.io/badge/Luanti-5.0%2B-5599ff.svg)
[![Luacheck](https://img.shields.io/github/actions/workflow/status/sakel-hub/pale_watcher/luacheck.yml?label=Luacheck&logo=lua)](https://github.com/sakel-hub/pale_watcher/actions)
![AI-Assisted](https://img.shields.io/badge/AI--assisted-gray)

A psychological horror mob mod for Luanti powered by the `x_mob_core` framework.

The Pale Watcher is an ephemeral nightmare entity that stalks players through dark forests. Rather than standard monster chase mechanics, he employs **True Quantum Stalking**: freezing motionless in the player's direct line of sight, and snapping forward through shadows and blind spots the instant eye contact is broken.

---

## Key Features

### 1. True Quantum Stalking & Gaze Mechanics
- **Direct Gaze Freeze**: When looking directly at the Pale Watcher (FOV raycast), he locks in place with a motionless stare.
- **The Gaze Dilemma**: Direct eye contact stops his approach, but drains health and sanity, slows player movement, and dynamically narrows your field of view into claustrophobic tunnel vision.
- **Blind-Spot Step Teleportation**: The moment you turn away or step behind obstacles, the server computes safe positions in your blind spots and snaps him forward in silent strides.
- **Responsive Screen Vignette**: High-resolution horror vignette overlay that scales and crops cleanly across all aspect ratios (16:9, 16:10, 21:9 ultrawide, 4:3).
- **Combat Slip**: The Pale Watcher cannot be felled by standard physical weapons; striking him triggers an immediate dimensional slip retreat into tree cover with void particles.

### 2. The 4 Nightmarish Obstacles to Fleeing
1. **The Intercept Teleport**: Sprinting blindly forward causes the Pale Watcher to predict your forward trajectory vector and snap 15–18 blocks ahead into your path behind trees.
2. **Panic Drag & Claustrophobic Fog**: Leaving the encounter center inflicts panic drag (`speed = 0.8, jump = 0.85`) and triggers dense black domain fog (`fog_distance = 12`).
3. **The Anti-Bunker Curse**: Digging down and sealing yourself in a cramped space ($\le 3$ air blocks) triggers a phase-teleport choke attack directly inside your hideout.
4. **Light Source Failure**: Torches and lanterns within physical reach (5.5m) and unobstructed line of sight (dual raycast) flicker and fail, dropping to the floor. Lights cannot be extinguished through walls, and sanctuary light (level $\ge 14$) is immune. Holding a light source in his direct line of sight causes trembling hands to drop it.

### 3. Vintage Flash Camera (Stun Weapon)
- Craft a **Vintage Flash Camera** (`pale_watcher:flash_camera`) using steel ingots, glass, and a torch.
- Right-clicking triggers a high-intensity xenon flash that illuminates the dark and creates a full-screen whiteout.
- If the Pale Watcher is caught in your line of sight (up to 22m), the flash **stuns him for 3–5 seconds**:
  - He reels backward with hands raised defensively to shield his face (`stun` animation).
  - Teleportation and attacks are interrupted.
  - When the stun window expires, he immediately executes an evasive retreat into the distant fog.

### 4. 8 Cursed Pages & Accessible HUD Plaque
- **Dynamic Surface Placement**: Pages spawn attached to tree trunks or stone walls strictly at eye level (1.0–1.6m) above walkable ground. Never underwater, in lava, or high in tree canopies.
- **Zero-Inventory Encounter Session**: 8 pages placed in a 15–45m radius with subtle audio whispering and ink wisp particles. Collected pages are tracked directly in the encounter session and HUD overlay, keeping player inventories uncluttered.
- **Accessible HUD Plaque**: Features a dedicated gothic plaque background (`pale_watcher_hud_pages_bg.png`) centered horizontally at the top of the screen (`{x = 0.5, y = 0.04}`) with high-contrast text adhering to WCAG contrast standards:
  - Active hunting count: Warm ivory `#FFF8EC` (15.2:1 contrast against dark slate).
  - Ritual ready: Radiant gold `#FFD700` (13.5:1 contrast).
  - Network-efficient packet throttling ensures HUD updates only transmit when the page count changes.
- **Static Geiger-Counter**: Sweeping your crosshair over a tree holding a page subtly increases static crackle.

### 5. Cleansing Flame Banishment & Ritual Pyre
- Once all 8 Cursed Pages are gathered, players craft and place a **Ritual Pyre** (`pale_watcher:ritual_pyre`).
- Right-clicking the pyre channels the 8 bound curses from the active session, igniting the **Cleansing Flame** without requiring any physical inventory items.
- The Pale Watcher is forcibly teleported into the center of the pyre and paralyzed.
- He plays his `death_implode` animation, collapsing inward into black smoke and static shockwaves before dropping rare dimensional loot:
  - **Dimensional Cloth**: Void-woven fabric used to craft the **Shroud of Stalking**.
  - **Static Core**: Condensed quantum radio energy.

### 6. Shroud of Stalking (Blink Ability)
- Crafted from 4 Dimensional Cloths and 1 Static Core.
- Hold Sneak and Right-Click to **Blink** up to 14 meters forward through shadows, accompanied by void slip particles.

---

## Session Lifecycle & Fail-Safe Cleanup

The mod is engineered with crash-resilience and multiplayer disconnect safety:
- **Player Disconnect / Death Cleanup**: Physics modifiers (`speed`, `jump`, `gravity`), visual HUD overlays (vignettes, static, camera flash), FOV narrowing, and domain fog are automatically restored to neutral baseline when a player leaves or dies.
- **Reconnect Protection**: Player join callbacks unconditionally reset any lingering debuffs to prevent persistent speed or FOV penalties in the player database.
- **Server Shutdown & Crash Recovery**:
  - `pale_watcher:purge_transient_lights` LBM cleanses temporary camera flash light nodes on world load.
  - Active cursed pages track session lifetime and expire automatically if their parent session is inactive or if 10 minutes have elapsed without an active encounter.
  - Active ritual pyres automatically burn out after 45 seconds.

---

## Crafting Recipes

### Ritual Pyre
```text
[ Stone ] [ Wood  ] [ Stone ]
[ Wood  ] [ Torch ] [ Wood  ]
[ Stone ] [ Wood  ] [ Stone ]
```

### Vintage Flash Camera
```text
[        ] [  Torch  ] [        ]
[ Steel  ] [  Glass  ] [ Steel  ]
[ Steel  ] [  Steel  ] [ Steel  ]
```

### Shroud of Stalking
```text
[ Cloth ] [ Static Core ] [ Cloth ]
[ Cloth ] [             ] [ Cloth ]
```

---

## How Players Can Survive

If you cannot find all 8 pages, you can survive through three escape conditions:

- **Condition A (The Sanctuary)**: Reach safe ground with light level $\ge 14$ (e.g. campfire or illuminated outpost). The Pale Watcher will stop at the light boundary, stare silently from the tree line for 5 seconds, and dissolve into mist.
- **Condition B (The 70-Node Gauntlet)**: Cross 70 nodes away from where the encounter started. At node 60, he will attempt one final intercept ambush. Dodge past him; once you cross node 70, a deep foghorn drone sounds, the black fog lifts, and the encounter ends cleanly.
- **Condition C (Surviving until Dawn)**: Survive until sunrise (`timeofday > 0.23` and natural light $\ge 14$). The Pale Watcher catches fire, dissolves into static ash, and is banished.

### In-Game Survival Tips
- **Never Run in a Straight Line**: The Pale Watcher predicts forward movement vectors; weaving through dense tree lines disrupts his intercept algorithm.
- **The Glancing Check**: Spin around every 3–4 seconds to lock his position and reset his step timers. Break gaze before static drains your sanity.
- **Head for the Light**: When an encounter starts, immediately locate the nearest high-light outpost.

---

## Development & CI/CD Automation

This mod includes automated workflows and npm developer tooling matching modern Luanti standards:

```bash
# Run static analysis
npm run lint

# Push release tag to ContentDB (requires CONTENT_DB_PALE_WATCHER_TOKEN or CONTENT_DB_TOKEN)
npm run push:ci -- --title="v1.0.0"
```

### Included Tooling Configurations
- **GitHub Actions**:
  - `.github/workflows/luacheck.yml`: Automated static analysis on branches and PRs.
  - `.github/workflows/deploy.yml`: Tagged release deployment to Luanti ContentDB.
- **Editor & Linter Configurations**:
  - `.editorconfig`: Enforces Lua tab indentation and code style.
  - `.luacheckrc`: Pre-configured Luanti globals and mob core variables.
  - `.luarc.json`: LuaLS workspace and auto-completion configuration.
  - `.gitattributes`: Line-ending normalization and git archive export-ignore exclusions for lean release packages.

---

## Requirements & Dependencies

- **Engine**: Luanti 5.0+ (Luanti 5.10+ recommended)
- **Required Mod**: `x_mob_core`
- **Optional Physics Mods**: `player_monoids`, `playerphysics`, `pova`
- **Optional Game Content**: `default` (used for standard crafting ingredients; alternative fallbacks supported)

---

## License & Attribution

- **Source Code**: [MIT License](license.txt) — Copyright (C) 2026 SaKeL
- **Media & Assets**: [CC-BY-SA-4.0](license.txt) — Copyright (C) 2026 SaKeL
  - 3D Model: `models/pale_watcher_mob.glb`
  - Textures: `textures/pale_watcher_*.png`
  - Audio: `sounds/pale_watcher_*.ogg`
