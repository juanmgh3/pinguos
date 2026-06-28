# Turtle reference (CC: Tweaked) — for the PinguOS fleet

Captured so we stop guessing. Source: tweaked.cc/module/turtle.html.

## Full turtle API

- **Move:** `forward`, `back`, `up`, `down`, `turnLeft`, `turnRight`. (All need fuel.)
- **Dig:** `dig`, `digUp`, `digDown` (needs a tool that can break the block).
- **Place:** `place`, `placeUp`, `placeDown` (place selected item/block).
- **Attack:** `attack`, `attackUp`, `attackDown` (hits entities; stronger with a sword).
- **Inventory:** `select`, `getSelectedSlot`, `getItemCount`, `getItemDetail`,
  `getItemSpace`, `transferTo`, `drop`/`dropUp`/`dropDown`, `suck`/`suckUp`/`suckDown`.
- **Inspect:** `inspect`/`inspectUp`/`inspectDown` (returns block name+state),
  `detect`/`detectUp`/`detectDown` (is there a solid block),
  `compare`/`compareUp`/`compareDown` (selected item vs block), `compareTo` (slot vs slot).
- **Fuel:** `getFuelLevel`, `getFuelLimit`, `refuel`.
- **Equipment:** `equipLeft`, `equipRight`, **`getEquippedLeft`**, **`getEquippedRight`**.
- **Craft:** `craft` (only on a crafty turtle = built with a crafting table).

## Tool types -> roles -> capabilities

A turtle's job comes from its **equipped tool** (a diamond tool, by default):

| Tool | Role | Enables | Composed tasks (potential) |
|---|---|---|---|
| Pickaxe | **mineria** | dig stone/ore | tunnel, branch-mine, quarry, dig-down to bedrock |
| Axe | **tala** | break wood/leaves | fell tree, tree farm (chop + replant saplings via `place`) |
| Sword | **ataque** | strong `attack` | mob defense, mob-farm sweeps, clear path of mobs |
| Shovel | **excavacion** | dig dirt/sand/gravel | clear area, dig pit, level ground |
| Hoe | **granja** | till soil | crop loop: harvest (`dig`/`suck`) + replant (`place`) + inspect maturity |
| (none) | **transporte** | move + suck/drop | haul items between chests; restock |
| (any) | **constructor** | `place` from inventory | build a wall/line/blueprint |

Other equippables (upgrades, left/right slot): **wireless/ender modem** (rednet — we
use it for the fleet), **speaker** (sound). A **crafty turtle** can `craft`.

## Auto-detecting the role

`getEquippedLeft()` / `getEquippedRight()` return the equipped upgrade's detail.
We can read the tool name and pick the role automatically instead of prompting —
e.g. name contains "pickaxe" -> mineria, "axe" -> tala, "sword" -> ataque,
"shovel" -> excavacion, "hoe" -> granja. Falls back to a prompt / "generico" if
no tool or unknown. (To verify the exact returned shape in-game before relying on it.)

## Smart behavior building blocks

- `inspect()` returns `{ name, state, ... }` -> detect ore vs stone, crop maturity,
  log vs leaf. Enables "mine only ore", "harvest only ripe crops".
- `compare()` -> "is the block ahead the same as my reference item" (cheap filter).
- `getItemDetail()` -> inventory-aware decisions (out of saplings? full? need fuel?).

## Current state in code (to expand)

- Agent (`bridge/install.js` turtleAgentScript) supports actions: move x6, dig/digUp/
  digDown, attack/attackUp/attackDown, refuel, status, and the `mine N` tunnel task.
- Roles wired in the Fleet app + agent: **mineria, ataque, cava, generico**.
- **Missing roles to add:** tala (axe), excavacion (shovel), granja (hoe), transporte.
- **Missing composed tasks:** fell-tree, tree-farm, crop-loop, dig-down N, haul.
- **Possible upgrade:** auto-detect role from `getEquippedLeft/Right` (drop the prompt).

## Roadmap (build on the `pingufleet` protocol)

Each automation = a composed `cmd` action the agent runs in a loop and reports `done`.
Order by usefulness: tunnel (done) -> fell-tree -> dig-down -> crop-loop -> haul.
