<div align="center">

# WAR TYCOON AUTO FARMER

### Client-side Lua automation for Roblox War Tycoon

`CASH COLLECTION` &nbsp; · &nbsp; `PURCHASE SCANNING` &nbsp; · &nbsp; `REBIRTH TARGETS` &nbsp; · &nbsp; `BARREL RECOVERY`

**Source file:** [`war tycoon.lua`](https://github.com/ujjal-saha/Roblox-war-tycoon/blob/main/war%20tycoon.lua)  
**Raw source:** [View the current script](https://raw.githubusercontent.com/ujjal-saha/Roblox-war-tycoon/refs/heads/main/war%20tycoon.lua)

</div>

---

## ◇ Overview

War Tycoon Auto Farmer is a client-side Lua automation script built around the game's visible interface and in-world prompts. Its movable local HUD provides an ON/OFF control, a rebirth target, a completion readout, and a manual airdrop test button.

The main purchase cycle is:

> **Find the Cash Collector** → **Read available money** → **Choose affordable buttons** → **Purchase the least expensive first**

Separate routines monitor completion progress, handle oil barrels and airdrops, recover a dropped barrel after death, and route a pending barrel back through the remembered Cash Collector area to find the physical Oil Exchange.

---

## ◇ Quick Start

The following loader downloads the current `main`-branch script and executes it:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ujjal-saha/Roblox-war-tycoon/refs/heads/main/war%20tycoon.lua"))()
```

1. Join **War Tycoon** and wait for your base and its interface to load.
2. Run the loader only in a compatible client-side environment that supports the functions this script uses.
3. Use the draggable **Auto Buyer** window to configure the rebirth target, then select **ON** to start the automation.
4. Use **Run airdrop now (test)** to request the airdrop-handling routine manually. The routine still searches for the game's floating Oil and Airdrop labels.

> [!CAUTION]
> `loadstring` downloads and executes remote code. Review the source before running it, and remember that the loader follows the mutable `main` branch: the code at that URL can change. This script depends on client/executor-specific APIs and is not a normal Roblox Studio `Script` or `LocalScript`.

---

## ◇ HUD Controls

| Control | Function |
|:--|:--|
| **Top bar** | Drag the window to reposition it. |
| **ON / OFF** | Starts or stops the main automation loop. The completion readout continues updating while OFF, but the automatic completion key press requires ON. |
| **Rebirths** | Enter a target from `0` to `12`. The value is applied when the text box loses focus. `0` disables rebirth purchases. |
| **Run airdrop now (test)** | Requests the oil-barrel/airdrop sequence while the script is ON. |
| **Completion readout and bar** | Shows the percentage read from the local game interface. Completion values are displayed in the HUD, not printed as percentage messages in the console. |
| **Status line** | Reports the current activity, such as scanning, collecting, recovering, or searching for the exchange. |

---

## ◇ How the Logic Works

### 1. Local startup and lifecycle

The script obtains the local player and their `PlayerGui`, then creates a draggable `ScreenGui`. When a new copy is run, it removes the old HUD, disconnects stored connections, and increments a shared run ID. Background loops check that ID so an older run can stop when a replacement is started.

The script begins **OFF**. Its completion display can update while OFF, but the main buying loop and automatic completion action are gated by the ON state.

### 2. Cash Collector and purchase scan

The scanner examines visible `BillboardGui` and `SurfaceGui` text in the loaded workspace and player interface. It resolves each GUI's `Adornee` or parent to a part, then checks ownership information to distinguish the player's base from other bases.

Cash Collector candidates are gathered before one is selected. The script keeps the previously selected collector while it remains available; otherwise it chooses a nearby candidate. Its position is retained as `lastCollectorPos`, which is later used as the return point for barrel delivery and exchange discovery.

Money is read first from likely `leaderstats` values (cash, money, or coins), with visible dollar-formatted interface text as a fallback. Price parsing supports plain numbers and `k`, `m`, `b`, and `t` suffixes. The scanner rejects excluded labels, including exchange-related purchase text, so those signs are not treated as ordinary construction buttons.

Once a readable balance is available, the script:

1. Keeps only buttons whose parsed price is no greater than the current balance.
2. Sorts affordable buttons from lowest price to highest.
3. Visits each candidate and checks whether the sign disappeared or the balance decreased.
4. Retries a failed purchase up to the configured attempt count before continuing.

If money cannot be read or no button is affordable, the status line reports that state and the loop retries later.

### 3. Rebirth targets

The rebirth scanner looks for short interface labels containing a number followed by **Rebirth**. It filters out likely information signs and long purchase instructions, checks that the candidate belongs to the player's base (or is near the remembered collector), and can optionally require a nearby pad.

Eligible targets are ordered from the smallest rebirth number upward. The script remembers off-screen targets, requests streaming around their saved positions, and scans again after the area loads. Failed attempts are temporarily skipped before retrying. The configured ceiling is `12`; a target of `0` means rebirth-button automation is off.

### 4. Completion tracking and the 100% action

A local reader scans text objects in `PlayerGui` for completion information. It can parse a percentage in the same label as the word “Completion,” combine text from a shared interface container, or use a nearby percentage label in the same UI layer as a fallback. The HUD refreshes approximately twice per second.

When completion reaches **100%**, the script arms one action for that completion cycle. It waits until Auto Buyer is ON and the airdrop, recovery, and barrel-delivery routines are idle, then:

1. Holds `E` for **two seconds**.
2. Releases `E`.
3. Increases a positive rebirth target by one, without exceeding `12`.

If the rebirth field is empty or set to `0`, it remains disabled. The completion action rearms after the observed percentage falls below 100%.

### 5. Oil barrel and airdrop detection

The target scanner uses floating `BillboardGui` text that contains **Oil** or **Airdrop** together with a distance in studs. It parses distance suffixes such as `k`, `m`, and `b`, then ranks targets by the distance shown in the label. This label-based approach avoids treating every object named “Oil Barrel” as the live barrel target.

A background check looks for a real Oil/Airdrop distance label at the configured interval. A cooldown prevents repeated automatic triggers. The HUD test button can request the same handling sequence manually.

When the oil pickup is attempted, the script remembers the associated barrel object because its floating label can change after pickup. It treats a tracked or carried barrel as pending delivery and prevents unrelated teleports or target trips until delivery is resolved.

### 6. Oil Exchange discovery and delivery route

When a barrel is pending, the script first returns by flight to the remembered Cash Collector location. That helps stream the player's base back into the client before the exchanger search begins. It then searches around the base for a usable exchanger candidate and flies to the selected prompt or part.

The exchanger finder uses several clues: non-price labels containing “oil” and “exchange,” prompts containing “exchange,” and parts/models named with “exchange.” The screenshot label **`$100,000 PARTS $100,000 OIL EXCHANGE`** is treated as a price-bearing purchase pad—not as the physical exchanger. Purchase cues and price-bearing labels are filtered so the script does not deliberately select that sign as the exchange destination.

The finder is dependent on the exchanger being present, streamed, and recognizable in the current game hierarchy. If it has not been purchased/unlocked or the game changes its labels/prompts, the script may report **Oil Exchange not found**.

### 7. Death and dropped-barrel recovery

A character death watcher checks whether a barrel was being carried or tracked. If so, it records the last known target and sets a recovery-pending flag. After respawn, the recovery routine scans for the floating **Oil … studs** label, prefers a target near the last known position, and attempts to pick it up again.

Recovery and exchange take priority over rebirths, construction buttons, and other target travel. The script does not clear the pending state until it has attempted delivery and the dropped-barrel label is no longer detected.

### 8. Movement and input safeguards

Ordinary target movement uses the script's teleport helper only when there is no pending/carried barrel. While delivering a barrel, the flight routine is limited to the intended Cash Collector and Exchange route. Flight speed is controlled by `FLY_SPEED` and currently defaults to `50`; movement slows near the destination.

The script intentionally does **not** move equipped `Tool` objects into the Backpack. It releases a stuck mouse input when enabled instead, avoiding the reported ACS weapon-reference failure associated with manually reparenting an equipped tool.

---

## ◇ Configuration Reference

| Setting | Default | Meaning |
|:--|:--:|:--|
| `MAX_REBIRTH` | `12` | Maximum rebirth target accepted by the HUD. |
| `FLY_SPEED` | `50` | Flight speed cap; the mover slows as it approaches its destination. |
| `HOLD_TIME` | `3` seconds | Default hold duration for barrel/airdrop/exchange interactions; a prompt with a longer hold requirement can extend it. |
| `MAX_ATTEMPTS` | `4` | Maximum attempts per purchase/rebirth button before continuing; failed rebirths are temporarily skipped before retrying. |
| `SCAN_INTERVAL` | `6` seconds | Interval for automatic Oil/Airdrop label checks. |
| `AIRDROP_COOLDOWN` | `20` seconds | Delay after a completed airdrop routine before another automatic trigger. |
| `DEBUG` | `false` | Enables additional diagnostic warnings when set to `true`. |
| `REBIRTH_REQUIRE_PAD` | `false` | When enabled, only accept a rebirth sign if a nearby pad is found. |

Values are defined near the top of the script or in the airdrop settings section. Adjust cautiously; faster movement may make the game more likely to reset the character or drop a carried barrel.

---

## ◇ Troubleshooting

| Symptom | Checks |
|:--|:--|
| **No “Cash to collect” found** | Make sure the base is loaded and the collector label is visible. The scanner relies on visible in-game GUI text and ownership clues. |
| **Can't read money** | Check that cash appears in `leaderstats` or as a visible dollar-formatted HUD label. |
| **Oil Exchange not found** | Confirm the exchanger is purchased/unlocked and present in the base. Let the base stream in near the remembered Cash Collector; check that an exchanger prompt, name, or non-price label is visible. |
| **Dropped barrel is not recovered** | Wait for the floating Oil distance label to appear after respawn. Recovery uses that label to find the barrel again. |
| **Completion stays at `--%`** | Ensure the game's completion text is visible in the local player interface. The reader searches `PlayerGui`; a server-only value or differently worded display may not be detected. |
| **Controls do not respond** | Confirm the Auto Buyer toggle is ON for automated actions and that the execution environment supports the client APIs used by the script. |

---

## ◇ Compatibility, Permissions & Risk

This is a **client-side, experience-specific automation script**. It relies on Roblox UI structures and APIs commonly exposed by third-party execution environments, including `loadstring`, `game:HttpGet`, `getgenv`, `VirtualInputManager`, and optional input/prompt helpers. These are not standard capabilities for a regular Roblox Studio script, and availability varies by environment.

Automating a Roblox experience may violate Roblox rules or the experience creator's rules and can result in account or access consequences. Use only where explicitly permitted. This project is independent and is not affiliated with, endorsed by, or supported by Roblox or the War Tycoon developers.

---

<div align="center">

**Read the code. Understand the actions. Run only what you trust.**

`LOCAL UI` &nbsp; → &nbsp; `TARGET SCAN` &nbsp; → &nbsp; `SAFE DELIVERY` &nbsp; → &nbsp; `EXCHANGE`

</div>
