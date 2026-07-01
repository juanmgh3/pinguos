# PinguOS — JARVIS Inc 1: ME stock (first sense)

- **Status:** Approved (design agreed in chat 2026-07-01)
- **Date:** 2026-07-01
- **Slug:** `jarvis-me-stock`
- **Owner:** Juan
- **Depends on:** JARVIS Inc 0 (`jarvis-core`, the wrapped native client + `/os/jarvis/`
  program pattern + `world.md`), Advanced Peripherals **ME Bridge** (`me_bridge`), the
  `fleet_status` pattern.

> Durable record per the SDD flow. If it isn't written here, it isn't agreed.

---

## 1. Summary & vision

JARVIS's **first sense**: query the ME system on demand. *"JARVIS, ¿cuánto hierro tengo?"* →
the brain runs a `me_stock` program (via `run_command`) → real quantities from the ME Bridge.

This establishes the **extension pattern for all future senses**: one PinguOS CLI program per
sense, invoked by the brain, doing the heavy lifting (find peripheral, query, filter, format)
so the brain only narrates. In channel mode we cannot add tools to the brain (the mod defines
them), so we add **programs to its filesystem** — clean and scalable. This slice = ME stock,
**on-demand only** (no watchlist).

## 2. Goals / Non-goals

**Goals (this slice)**
- **`me_stock` program**: finds the ME Bridge; answers *"how much of X"* (fuzzy item match) and
  a no-arg **overview** (item-type count, top items by quantity, ME energy).
- **`world.md`**: teach JARVIS the ME Bridge exists + that `me_stock` is how to read it.
- **Confirm the real ME Bridge API** (method names) before trusting it (versions differ).

**Non-goals**
- Watchlist / low-stock thresholds → later (owner chose on-demand only, YAGNI).
- ME crafting / ordering items → that's action (Inc 2 "Manos"), not a sense.
- Other senses (Create machines, chests, geo scan) → each its own slice.

## 3. Environment & constraints

| Fact | Consequence |
|---|---|
| Advanced Peripherals 0.7.62b exposes a `me_bridge` peripheral; exact method names (`listItems`, `getItem`, energy getters) **vary by version**. | **Step 0: an in-game probe** confirms the real methods; the dependency is isolated in `me_stock.lua` (same discipline as `claudecc`). |
| `peripheral_call` reaches only peripherals wired to the computer or its **wired-modem network**. | `me_stock` uses `peripheral.find("me_bridge")`; if none, it says so. **Physical prereq (owner):** the ME Bridge on JARVIS's network. |
| `listItems()` on a real ME returns **hundreds of item types**. | The program **filters/summarizes** before printing, so the brain gets compact output (not a 500-item dump). |
| CC-bound (peripheral APIs). | `luac -p` + in-game only; no local unit test. Rendered text **ASCII**. |

## 4. Architecture

```
  brain  --run_command "/os/jarvis/me_stock.lua [item]"-->  me_stock.lua
                                                              |
     peripheral.find("me_bridge") -> listItems()/energy -> filter/sort/format -> stdout
                                                              |
  brain reads stdout  <-----------------------------------------
     -> narrates in natural language

  world.md : tells the brain that me_stock exists and when to use it
```

The brain decides to call `me_stock` (guided by `world.md`); the program does the ME work.

## 5. Components

- **`dist/os/jarvis/me_stock.lua`** (new, CC-bound):
  - `local me = peripheral.find("me_bridge")` → if nil, print `"me_stock: no ME Bridge on JARVIS's network"` and return.
  - **With an argument** (`me_stock iron`): fuzzy-match — list items whose `name` or
    `displayName` **contains** the term (case-insensitive); print `name: count` sorted by count
    desc (cap the list, e.g. top 20); no match → say so.
  - **No argument** (`me_stock`): overview — number of item types, **top ~10** by count, and ME
    **energy** (stored / max). 
  - ASCII, compact. `math.floor` before any `%d` formatting (5.1/5.4 safety).
- **`dist/data/jarvis/world.md`** (+ "Almacén ME" section): the base has an ME Bridge; to read
  stock, run `/os/jarvis/me_stock.lua [item]`; never invent quantities.
- **`dist/tests/me_bridge_smoke.lua`** (Step 0 probe, kept for regressions like `claude_smoke`):
  prints the `me_bridge` method names + a sample `listItems`/energy call, so the real API is
  confirmed before `me_stock` trusts it.

## 6. Verification

- **`luac -p`** on `me_stock.lua` and the probe; PinguOS suite stays **90** (CC-bound, no unit
  test added).
- **Step 0 in-game (owner):** run `me_bridge_smoke.lua` → record the real method names →
  adjust `me_stock.lua` if they differ from the reference.
- **First-sense acceptance (in-game):** with the ME Bridge wired, *"¿cuánto hierro tengo?"* →
  brain runs `me_stock iron` → answers the **real** count; no-arg overview shows top items +
  energy; no ME Bridge → the graceful message (brain reports it, doesn't invent).

## 7. Confirmed decisions

1. **Dedicated `me_stock` program** over raw `peripheral_call` — it filters the huge
   `listItems()` so the brain gets usable output (the core value of direction A).
2. **On-demand only** (YAGNI); watchlist/thresholds are a later slice.
3. **Fuzzy name match** — forgiving; the brain maps "hierro" → "iron" and the program matches
   `minecraft:iron_ingot` by substring.
4. **Confirm the ME Bridge API first** (Step 0), isolated in `me_stock.lua`.
5. **Same extension pattern as `fleet_status`** — one program per sense; future senses add
   programs + `world.md`, never touching the mod.
