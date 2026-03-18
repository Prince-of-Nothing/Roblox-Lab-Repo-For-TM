# Lab_02 - 3-Lane Endless Runner Implementation Status

**Project**: Simple Endless Runner
**Last Updated**: March 18, 2026
**Status**: FUNCTIONAL

## Project Overview

A 3-lane endless runner game with coin collection, obstacle avoidance, shop islands with purchasable upgrades, and a grace period system. Players run forward automatically while dodging obstacles, collecting coins, and purchasing temporary power-ups from periodic shop islands.

## File Structure

```
Lab_02/src/
├── ServerScriptService/
│   ├── Leaderstats.server.lua      # Player data initialization
│   └── RunnerServer.server.lua     # Core game logic (807 lines)
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── RunnerController.client.lua   # Client movement & UI (489 lines)
```

## Game Systems

### Core Gameplay
| Feature | Status | Details |
|---------|--------|---------|
| 3-Lane Movement | DONE | Lanes at X positions: -8, 0, 8 |
| Constant Forward Motion | DONE | Base speed: 50 studs/sec |
| Segment Generation | DONE | 50-stud segments, 8 ahead buffer |
| Obstacle Spawning | DONE | 0-2 obstacles per segment (always 1 lane clear) |
| Coin Collection | DONE | Distance-based (5 stud range), +1 coin each |
| Death Detection | DONE | Fall below Y=40 or double-hit during grace |

### Lane System
- **Lane Positions**: -8 (left), 0 (center), 8 (right)
- **Strafe Speed**: 40 studs/sec
- **Max X Boundary**: ±12 studs

### Obstacle System
| Pattern | Probability | Description |
|---------|-------------|-------------|
| No obstacles | 30% | Safe segment |
| 1 obstacle | 40% | Single lane blocked |
| 2 obstacles | 30% | Two lanes blocked (always 1 clear) |

- **Obstacle Size**: 4x6x0.1 studs (wall-like)
- **Collision**: Triggers coin loss or death

### Coin System
- **Spawn Chance**: 60% per segment
- **Coin Shape**: Pink/magenta cylinder
- **Collection Range**: 5 studs
- **Sound**: `rbxassetid://135904960416116`

### Grace Period System
| State | Duration | Behavior |
|-------|----------|----------|
| Normal | - | First hit: lose 5 coins, enter grace |
| Grace Period | 10 seconds | Second hit: instant death |
| Shield Grace | 20 seconds | First hit: free (shield consumed), second hit: death |

- **Coin Loss Per Hit**: 5 coins
- **Death if Coins < 0**: Yes

### Speed Boost Zones
- **Spawn Chance**: 13% per segment
- **Appearance**: Green rectangle (3x1x8 studs)
- **Effect**: +30% speed for 5 seconds
- **Visual**: Green particle effect, FOV increase (70→80)
- **Sound**: `rbxassetid://83211426606907`

## Shop System

### Shop Island Spawning
- **First Shop**: After ~16 segments
- **Interval**: Every 40 seconds (~50 segments at base speed)
- **Platform Size**: 30x2x20 studs (green-tinted)

### Available Upgrades
| Upgrade | Cost | Effect | Duration |
|---------|------|--------|----------|
| Speed Boost | 10 coins | +3 permanent forward speed | Run lifetime |
| Shield Grace | 15 coins | 20s shield + 1 free hit | 20 seconds |

### Shop Behavior
- **Detection Range**: 25 studs from shop center
- **Movement Mode**: Free movement (WASD), 30 studs/sec
- **Purchase Method**: Touch the colored sign
- **One-time Purchase**: Each shop item can only be bought once per shop

## Remote Events

| Event Name | Direction | Purpose |
|------------|-----------|---------|
| `RunnerAdvance` | Client→Server | Request next segment |
| `ShopData` | Server→Client | Broadcast shop positions |
| `ObstacleHit` | Server→Client | Notify grace period start |
| `SpeedZoneHit` | Server→Client | Notify speed boost |
| `DebugAddCoins` | Client→Server | Debug: random coin add/remove |

## Client UI Elements

| Element | Position | Purpose |
|---------|----------|---------|
| Coins Label | Top-right | Current coin count |
| Distance Label | Top-right (below coins) | Distance to next shop |
| Speed Label | Top-right (below distance) | Current speed + bonuses |
| Grace Timer | Top-left | Countdown during grace period |
| Shield Timer | Top-left (below grace) | Countdown during shield |
| Shop Mode Label | Top-center | "SHOP MODE" indicator |
| Debug Button | Top-left | "Luck?" random coin gambling |
| Damage Overlay | Full screen | Red flash on obstacle hit |

## Player Data Structure

### leaderstats (Visible)
```lua
leaderstats/
└── Coins (IntValue) = 0
```

### GameState (Hidden)
```lua
GameState/
├── GracePeriodEnd (NumberValue) = 0        -- Timestamp
├── ShieldGracePeriodEnd (NumberValue) = 0  -- Timestamp
├── ShieldGraceHitUsed (BoolValue) = false
├── SpeedBoostActive (BoolValue) = false
├── GraceReducerActive (BoolValue) = false
├── PermanentSpeedBonus (IntValue) = 0      -- From shop purchases
├── TempSpeedBoostEnd (NumberValue) = 0     -- From green zones
└── ShopsPurchased/ (Folder)                -- Track per-shop purchases
    └── Shop_X_Speed/Shop_X_Grace (BoolValue)
```

## Controls

| Input | Action |
|-------|--------|
| A / Left Arrow | Strafe left |
| D / Right Arrow | Strafe right |
| W / Up Arrow | Move forward (shop only) |
| S / Down Arrow | Move backward (shop only) |
| Space | Jump |

## Camera System
- **Type**: Fixed (script-controlled)
- **Position**: 15 studs behind, 8 studs above player
- **Look Target**: Player + 2 studs up
- **FOV**: 70 normal, 80 during speed boost

## Audio
| Event | Sound ID |
|-------|----------|
| Coin Pickup | `rbxassetid://135904960416116` |
| Obstacle Hit | `rbxassetid://138080762` |
| Speed Zone | `rbxassetid://83211426606907` |
| Shop Purchase | `rbxassetid://138273059623491` |
| Shield Break | `rbxassetid://120459258956850` |

## Constants Summary

### Server (RunnerServer)
```lua
SEGMENT_LENGTH = 50
SEGMENT_WIDTH = 30
START_Y = 50
SEGMENTS_AHEAD = 8
COIN_CHANCE = 0.6
OBSTACLE_CHANCE = 0.35  -- (unused, pattern-based instead)
COIN_LOSS_ON_HIT = 5
GRACE_PERIOD = 10
SHOP_SPAWN_INTERVAL = 40
LANES = {-8, 0, 8}
```

### Client (RunnerController)
```lua
FORWARD_SPEED = 50
STRAFE_SPEED = 40
SHOP_MOVE_SPEED = 30
MAX_X = 12
SEGMENT_LENGTH = 50
TRIGGER_MULT = 0.7
```

## Future Improvements
- DataStore persistence for coins/progress
- More shop upgrade types
- Difficulty scaling over time
- Power-up variety (magnet, multiplier, etc.)
- Visual biome changes
- Leaderboard system