# Character System & Asset Extraction

How the layered character / equipment system works, and how the colored
preset data was pulled out of the Unity standalone build.

## Files

| File | Purpose |
| --- | --- |
| `layered_character.gd` | `Node2D` driver. Builds 13 stacked `Sprite2D` children, one per equipment layer, all sharing the same `(direction_row, frame_col)` region. Lazy-loads sheets, caches null misses. |
| `items_db.gd` | Builds the full item catalog at runtime from the StreamingAssets folder counts. Slot enum, `WeaponClass` enum, `attack_anim_for(class)`. |
| `loadout.gd` | `user://profile.json` save/load, default loadout, color palettes per slot, preset loader, `apply()` that pushes a loadout onto a `LayeredCharacter`. |
| `inventory.gd` | Gold + items list inside the loadout. `equip()` swaps an item id into the matching layer and returns the previous occupant to inventory. |
| `character_creator.gd` | Modal Control: 15-preset row + per-slot cyclers + per-slot palette swatches + 3D-style preview (`SubViewport`). |
| `inventory_ui.gd` | Modal Control: scrollable item list grouped by slot, detail panel + Equip button. |
| `player_layered.gd` | Drop-in replacement for `player.gd` that drives a `LayeredCharacter`. Auto-attack-set per weapon class, mount speed boost, dodge on Space. |
| `gear_presets.json` | 15 color presets, lifted from the Unity build's `GearPresetDatabase`. |

## Sheet format

```
1920 x 1024  =  15 cols  x  8 rows  of  128x128 frames
rows are CLOCKWISE from facing-right:
  0:E  1:SE  2:S  3:SW  4:W  5:NW  6:N  7:NE
```

Identical layout for every slot, every anim. Source PNGs live in
`assets/charachters/Stand-alone Character creator - 2D Fantasy V1-0-3/Character creator - 2D Fantasy_Data/StreamingAssets/spritesheets/<Slot>/<Anim>.png`
and are referenced in place — no copy needed.

24 anims per slot: Idle / Idle2-4 / Walk / Run / RunBackwards / StrafeLeft /
StrafeRight / CrouchIdle / CrouchRun / Attack1-5 / AttackRun / AttackRun2 /
RideIdle / RideRun / Die / TakeDamage / Taunt / Special1.

## Layer order (back → front)

```
shadow → mount → body → legs → shoes → chest → belt → bag → hands → head → offhand → mainhand → vfx
```

Each layer stores `equip` (sheet folder name, e.g. `"Chest3"`) and `tint`
(modulate Color). Same anim + frame index drives every layer in lockstep, so
layers track movement perfectly.

## Slot inventory (StreamingAssets folder counts)

| Slot | Folders |
| --- | --- |
| Body | NakedBody, NakedBody2, NakedBody3 (skin tones) |
| Head | 24 |
| Hands | 4 |
| Chest | 19 |
| Legs | 9 |
| Shoes | 5 |
| Belt | 2 |
| Bag | 8 |
| Mainhand (Melee) | 25 |
| Mainhand (Ranged) | 7 |
| Mainhand (Magic) | 3 |
| Offhand | 2 |
| Shield | 7 |
| Mount | 5 |
| VFX (Effect) | 5 |
| VFX (Slash / Special / Magic1-3 / Shadow) | misc |

Total ~150 slot folders × 24 anims = **~3,600 PNG sheets** (~430 MB).

## Coloring

The shipped sheets are **greyscale templates**. Color is applied as a
single per-layer `Sprite2D.modulate` multiply. Sprites are pre-separated:
- Body sprite contains skin/face — `bodyColor` tints skin tone.
- Head sprite is just hair/headwear — `headColor` tints hair only.
- Chest/Legs/Shoes/Hands/Belt/Bag are isolated cloth regions.

No region masks needed — each layer is already the right region. This is
confirmed by the shipped `GearPresetDatabase` (see extraction below), which
stores exactly one Color per slot.

`loadout.gd::PALETTE` provides 8–12 swatches per tintable slot, aggregated
from the 15 shipped presets.

## Auto-attack-set per weapon class

`player_layered.gd::_start_attack()` reads `loadout.mainhand_class` and calls
`ItemsDB.attack_anim_for(class)`:

```
WeaponClass.MELEE   -> Attack1
WeaponClass.RANGED  -> Attack2
WeaponClass.MAGIC   -> Special1
WeaponClass.NONE    -> Attack1
```

`Inventory.equip()` writes `mainhand_class` whenever a weapon is equipped.

## Movement / dodge

| State | Anim | Notes |
| --- | --- | --- |
| Idle | `Idle` | |
| Walk (default) | `Walk` @ 12 fps | |
| Sprint (Shift held) | `Run` @ 16 fps | speed × 1.4 |
| Mount equipped | `RideIdle` / `RideRun` | speed × 1.6 |
| Attack | `Attack1/2/Special1` @ 18 fps, looping=false | finished_cb resets state |
| Dodge (Space) | `StrafeLeft/Right` or `RunBackwards` | picked from dodge_dir vs facing |

Dodge constants in `player_layered.gd`: `DODGE_DURATION`, `DODGE_SPEED`,
`DODGE_COOLDOWN`. Anim choice:

```
fwd = facing.dot(dodge_dir)
cross = facing × dodge_dir   (screen-y down: positive cross = right)

fwd < -0.6     -> RunBackwards
cross >= 0     -> StrafeRight
else           -> StrafeLeft
```

(No tumble-roll anim ships — `CrouchRun` is just a crouched jog, not a roll.)

## Walking-on-water ripple

`player_layered.gd` keeps `WATER_RIPPLE_INTERVAL = 0.28`s and on each tick of
movement-while-moving asks `main.is_water_cell(cell)`; if true,
`main.spawn_player_ripple(position)` drops a fading ripple sprite under the
player.

## Persistence

`user://profile.json`:
```json
{
  "name": "Adventurer",
  "body": "NakedBody", "head": "Head1", "hands": "Hands1",
  "chest": "Chest1", "legs": "Legs1", "shoes": "Shoes1",
  "belt": "", "bag": "", "offhand": "",
  "mainhand": "", "mainhand_class": 0,
  "mount": "", "shadow": "Shadow", "vfx": "",
  "tints": { "body": "#e6bc98", "head": "#993f00", ... },
  "inventory": { "gold": 50, "items": ["chest_2", "melee_3", ...] }
}
```

Loaded by `Loadout.load_or_default()` and merged over defaults so missing
keys don't break older saves.

## In-game key bindings (character system)

| Key | Action |
| --- | --- |
| `C` | Open character creator (auto-shown on first run if no profile). |
| `I` | Toggle inventory modal. |
| `G` | Debug: grant a random non-starter item. |
| `Space` | Dodge. |
| `Shift` (held) | Sprint. |
| `RMB` | Attack (anim depends on equipped weapon class). |

---

# Asset extraction process

How the colored gear preset data was pulled out of the Unity standalone build.

## Tool: AssetStudioMod CLI

Third-party fork of Perfare's AssetStudio, actively maintained, has a
non-interactive CLI mode (no GUI required).

### Install

```bash
mkdir -p C:/tools/AssetStudio
curl -L -o C:/tools/AssetStudio/AssetStudioModCLI.zip \
  https://github.com/aelurum/AssetStudio/releases/download/v0.19.0/AssetStudioModCLI_net472_win32_64.zip
cd C:/tools/AssetStudio && unzip -o AssetStudioModCLI.zip
```

The `net472` build uses .NET Framework 4.7.2 which ships with Win10/11 — no
runtime install needed.

Binary path:
`C:/tools/AssetStudio/AssetStudioModCLI_net472_win32_64/AssetStudioModCLI.exe`

### CLI flags used

| Flag | Meaning |
| --- | --- |
| `<path>` | First positional: asset file or folder to load. |
| `-m <mode>` | `info` (count assets), `export` (extract), `dump` (text dump for MonoBehaviours), `extract` (raw bundle decompress). |
| `-t <types>` | Filter by asset type: `tex2d,sprite,monoBehaviour,shader,...`. |
| `-g <opt>` | Group output: `none`, `type`, `container`, `containerFull`, `fileName`, `sceneHierarchy`. |
| `-o <path>` | Output folder. |
| `--filter-by-name <text>` | Substring match on asset names. |
| `--filter-by-pathid <text>` | Match by Unity PathID. |
| `--assembly-folder <path>` | Path to `Managed/` so MonoBehaviour fields decode against `Assembly-CSharp.dll`. |
| `--export-asset-list xml` | Dump an `assets.xml` listing without exporting. |

## What lives where in the build

```
Character creator - 2D Fantasy_Data/
├── StreamingAssets/spritesheets/<Slot>/<Anim>.png   ← raw greyscale sheets (loaded at runtime)
├── sharedassets0.assets + .resS                     ← 5.7 GB bundled Unity assets
├── globalgamemanagers.assets                        ← Unity scene config
├── resources.assets                                 ← built-in Unity resources
└── Managed/Assembly-CSharp.dll                      ← game C# code (needed for MonoBehaviour decoding)
```

`info` pass on `sharedassets0.assets` reports:
- Texture2D: 3,165 (mostly the same greyscale sheets in atlas form)
- Sprite: 371,581 (sprite slices into those textures)
- MonoBehaviour: 17 (UI components + the `GearPresetDatabase`)
- Shader: 0 (handled by Unity built-ins / not exported here)

## Probing for colored sheets (negative result)

```bash
AssetStudioModCLI.exe sharedassets0.assets -t tex2d -m export \
  --filter-by-pathid "10,11,12" -o probe_tex
```

Confirmed: every extracted Texture2D is a greyscale silhouette identical in
content to the StreamingAssets PNGs. The Unity creator does NOT ship
pre-colored sheets — color is applied at runtime.

## Pulling the GearPresetDatabase (the win)

`Managed/Assembly-CSharp.dll` is required so AssetStudio can decode the
custom MonoBehaviour fields (otherwise you only get the asset wrapper, no
data). Dump as text:

```bash
AssetStudioModCLI.exe sharedassets0.assets -t monoBehaviour -m dump \
  --assembly-folder ".../Character creator - 2D Fantasy_Data/Managed" \
  -o probe_dump
```

Result: `probe_dump/GearPresetDatabase.txt` — 1,887 lines, 15 `GearPreset`
entries each with one `Color` field per slot:

```
[0]
GearPreset data
  Color bodyColor   { r 0.902, g 0.737, b 0.596, a 1 }
  Color headColor   { r 0.600, g 0.247, b 0.000, a 1 }
  Color chestColor  { r 0.698, g 0.698, b 0.698, a 1 }
  ... legs / shoes / hands / belt / slash / effect / backpack / shield / mount / weapon
```

This proves the coloring system: **one Color multiply per slot, no masks**.

## Parsing presets to JSON

```python
# parse_presets.py — distilled from the dump above into gear_presets.json
import re, json
text = open("GearPresetDatabase.txt", encoding="utf-8").read()
blocks = re.split(r"\[\d+\]\s*\n\s*GearPreset data", text)[1:]
def hex3(r,g,b):
    return "#%02x%02x%02x" % tuple(int(round(float(c)*255)) for c in (r,g,b))
out = []
for b in blocks:
    p = {}
    for m in re.finditer(
        r"Color\s+(\w+?)Color\s*\n"
        r"\s*float r = ([\d.]+)\s*\n"
        r"\s*float g = ([\d.]+)\s*\n"
        r"\s*float b = ([\d.]+)", b):
        p[m.group(1)] = hex3(*m.group(2,3,4))
    out.append(p)
json.dump(out, open("gear_presets.json", "w"), indent=2)
```

## Wiring presets into Godot

`loadout.gd::presets()` lazy-loads `res://gear_presets.json`.
`loadout.gd::apply_preset(loadout, index)` maps Unity slot keys
(`body / head / chest / legs / shoes / hands / belt / backpack`) onto the
LayeredCharacter layer names and writes the chosen colors into
`loadout.tints`.

`character_creator.gd` shows a "Preset" row of 15 swatches above the per-slot
cyclers; clicking a swatch applies the full preset color set, and per-slot
swatches re-highlight to match.

## What this enables

- 15 ready-made "looks" matching the original Unity creator exactly.
- Per-slot palette overrides (e.g. switch one preset's chest red to blue).
- Default character on first run reproduces Preset 0 (the Unity default).

## What it does NOT extract

- Hair / face region masks — they don't exist; the system is single-color.
- Animator state machines — bundled but referenced by PathID; unnecessary
  since we drive anim playback directly via `LayeredCharacter.play_anim()`.
- Original Unity shader — replaced with `Sprite2D.modulate` (Godot does the
  same multiply natively).

---

## Quick reproduction recipe

```bash
# 1. Tool
mkdir -p C:/tools/AssetStudio
curl -L -o C:/tools/AssetStudio/x.zip \
  https://github.com/aelurum/AssetStudio/releases/download/v0.19.0/AssetStudioModCLI_net472_win32_64.zip
cd C:/tools/AssetStudio && unzip -o x.zip

# 2. Dump MonoBehaviours with assembly support
GAME=".../Stand-alone Character creator - 2D Fantasy V1-0-3/Character creator - 2D Fantasy_Data"
"./AssetStudioModCLI_net472_win32_64/AssetStudioModCLI.exe" \
  "$GAME/sharedassets0.assets" \
  -t monoBehaviour -m dump \
  --assembly-folder "$GAME/Managed" \
  -o ./dumps

# 3. Parse GearPresetDatabase.txt → gear_presets.json (script above)

# 4. Drop gear_presets.json into the Godot project root.
```

That's it — no GUI, fully scriptable, works headless on Windows with curl
+ unzip + python.
