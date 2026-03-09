# Lab 01 — DJ Loop Station  
**Name:** 
**Project Folder:** Lab_01_DJLoopStation

---

## Core Requirements

### Task 1 — Setup
- 9-pad grid (3×3) spawns in front of `SpawnLocation`
- Each pad uniquely named (`Pad_01` through `Pad_09`) for deterministic sorting
- `Workspace/Music` contains loop sounds:
  - Drums, Bass, Synth, FX, Vocals, Percussion, Ambience
- All loops:
  - `Looped = true`
  - `Playing = true`
  - `Volume = 0`
  - Synced start phase for alignment
- Script respects existing sounds in Music folder (no overwrite)
- Pads 8–9 left empty (dimmed, no interaction)

### Task 2 — Base Test
- Pads toggle loops instantly on touch
- Visual feedback:
  - Smooth color tween to category color (active) or dimmed variant (inactive)
  - Particle burst on activation, cleaned up on deactivation
- HUD displays ON/OFF state per loop via toggle dots
- BPM displayed on HUD
- Dead body detection prevents accidental pad triggers (triple check)

---

## Task 3 — System Tuning

- Master BPM system implemented
  - Default: **120 BPM**
  - Runtime adjustable via `_G.DJ.SetBPM()`
  - BPM exposed via `workspace` attributes
- Crossfade tuning:
  - `FADE_TIME = 0.15s` — snappy, responsive
  - Prevents audio clicks and pops
- Instant toggle system:
  - Replaced bar-quantized queue with immediate apply for responsiveness
- Visual tempo feedback:
  - Active pads pulse transparency in sync with BPM
  - Inactive pads tween back to opaque smoothly

### Observations
- Higher BPM increases perceived energy and visual pulse rate
- Lower BPM produces heavier, slower mixes
- Short fade time (0.15s) gives instant feel without audio artifacts

---

## Task 4 — Added Features

### Audio
- **7-loop system**: Drums, Bass, Synth, FX, Vocals, Percussion, Ambience
- **Per-loop volume sliders**: draggable UI sliders with percentage display
  - Synced to server via `SetLoopVolume` RemoteEvent
  - Real-time volume adjustment while loops are active
- **UI toggle buttons**: clickable dots in HUD to toggle loops without stepping on pads
  - Routed through `ToggleLoopFromUI` RemoteEvent
  - Same backend path as physical pad interaction

### Visual
- **Category-based pad colors**:
  - Drums = Red, Bass = Blue, Synth = Green, FX = Purple
  - Vocals = Yellow, Percussion = Orange, Ambience = Cyan
- **Particle burst** on loop activation (cleaned on deactivation)
- **BPM-synced pad pulse** animation via transparency tween
- **Active/inactive tinting**: smooth Color tween, no stuck states
- **Lighting feedback**:
  - Positive survival: bright green ambient burst
  - Death: fog closes in, lighting fades to near-black
  - Restores to normal after respawn

### Gameplay / Interaction
- **Survival mechanic**: periodic checks (every 16s) based on:
  - Number of active loops (0 or all = instant death)
  - Volume levels (max volume increases risk)
  - Random element for unpredictability
  - Sweet spot: 3–4 loops at moderate volume
- **Death penalty**:
  - All loops forced OFF instantly
  - Dim lighting + ominous audio
  - Character killed after 1.5s delay
  - Respawn after 5s with lighting restored
- **Streak counter**: consecutive survival checks passed, resets on death
- **Scoreboard**:
  - ⏱ Live survival timer (client-side tick every 1s)
  - 🏆 Best survival time (never resets)
  - 🔥 Current streak
  - 👑 Best streak (never resets)

### UX / UI
- **Compact HUD panel** (220×390px, top-left)
- **Semi-transparent** (0.55 background transparency)
- **Rounded corners** with subtle stroke
- **Color-coded loop rows** matching pad categories
- **Divider line** separating loops from scoreboard
- **Per-loop volume slider** with fill bar, knob, and percentage label

---

## System Architecture

| Script | Location | Role |
|--------|----------|------|
| `1_BeatController` | ServerScriptService | Tempo, sound management, volume/toggle API |
| `2_FeedbackSystem` | ServerScriptService | Survival checks, death/reward, lighting effects |
| `3_PadManager` | ServerScriptService | Pad grid, touch detection, visual state |
| `RhythmClient` | StarterPlayerScripts | HUD, sliders, toggle buttons, live timer |

- Load order enforced via numeric prefixes (`1_`, `2_`, `3_`)
- `_G.DJ` shared interface: `RequestToggle`, `ForceAllOff`, `SetBPM`
- `workspace` attributes for cross-script sync:
  - `BPM`, `Loop_*`, `Vol_*` (server → all)
  - `SurvivalStart`, `Alive`, `Streak`, `BestStreak`, `BestSurvivalTime` (server → player)
- `ReplicatedStorage` RemoteEvents:
  - `SetLoopVolume` (client → server)
  - `ToggleLoopFromUI` (client → server)

---

## Task 5 — Testing & Polish

- Verified long-session sync stability
- No desync after repeated toggling
- No audible clicks/pops with 0.15s crossfade
- Instant toggle response (no bar-wait lag)
- Dead body ragdolls cannot trigger pads (triple health/state/attribute check)
- No duplicate loop assignments (unique pad names)
- Particles cleaned up properly (no stacking)
- Pad color never gets stuck (tween-based, no manual flash)
- HUD readable from default camera
- Volume sliders responsive with drag and click support
- Survival timer ticks live on client (not just on server checks)
- Existing sounds in Music folder preserved (not overwritten by script)

---

## Status Checklist

- [x] 7 synced loops working (exceeds 4 minimum)
- [x] Instant toggling with smooth crossfades
- [x] HUD readable with live stats
- [x] 8+ new features added (exceeds 2 minimum)
- [x] Smooth crossfades, no lag
- [x] Per-loop volume control from UI
- [x] UI toggle buttons for loop control
- [x] Survival mechanic with death/reward feedback
- [x] Scoreboard with best time and best streak
- [x] Dead body protection on pads
- [x] No duplicate pad assignments
- [x] Folder correctly named