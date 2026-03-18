# 🌿 Cannabis Idle Game - Roblox

A fully functional idle/incremental game built in Roblox featuring plant growth mechanics, L-system generation, and upgrade systems. This project has been thoroughly tested and verified through a comprehensive 10-task verification system.

## 🎮 Game Features

### Core Gameplay Loop
1. **Plant Seeds** - Click on soil plots to plant different cannabis strains
2. **Water Plants** - Water plants to make them grow through iterations
3. **Harvest Leaves** - Mature plants automatically drop cannabis leaves
4. **Collect Resources** - Walk over dropped leaves to collect cannabis
5. **Purchase Upgrades** - Use cannabis to buy yield boosts, unlock plots, and autopicker

### Plant Types
- **Indica** - Compact growth, moderate leaf production
- **Sativa** - Tall growth, higher leaf yield
- **Hybrid** - Balanced growth and yield
- **Purple Kush** - Premium strain, maximum leaf production
- **Auto Flower** - Fast-growing, quick turnaround

### Upgrade System
- **Yield Boosts** (Levels 1-5) - Increases cannabis collection multiplier
- **Plot Unlocks** (1-6 plots) - Unlock additional farming plots
- **Autopicker** - Automatically collects nearby cannabis leaves

## 🏗️ Technical Implementation

### Architecture
- **Server Script** (`CannabisGame.server.lua`) - Handles all game logic, player data, plant growth
- **Client Script** (`CannabisUI.client.lua`) - Manages GUI, user input, and visual updates
- **Plant Types Module** (`PlantTypes.lua`) - Defines plant characteristics and L-system rules

### Key Systems

#### L-System Plant Generation
Plants grow using Lindenmayer systems (L-systems) with fractal-like branching patterns:
- Each plant type has unique rules, angles, and growth characteristics
- Growth occurs through iterations triggered by watering
- Visual representation built with 3D segments in real-time

#### Remote Event Communication
- `PlantSeed` - Server handles seed planting
- `WaterPlant` - Server processes plant watering
- `PurchaseUpgrade` - Server validates and processes purchases
- `SyncGameState` - Bi-directional state synchronization
- `CannabisCollected` - Server notifies client of collection events

#### Data Persistence
Player data stored server-side includes:
- Cannabis currency (visible as leaderstats)
- Upgrade levels and unlocks
- Individual plot states and plant data
- Growth timers and leaf drop tracking

## 🔧 Installation & Setup

### Prerequisites
- Roblox Studio
- Rojo (for file synchronization)

### Setup Steps
1. Clone this repository
2. Navigate to the `Lab_03` directory
3. Run `rojo serve` to start the development server
4. In Roblox Studio, use the Rojo plugin to connect and sync files
5. Play test in Studio to verify functionality

### File Structure
```
Lab_03/
├── src/
│   ├── ServerScriptService/
│   │   └── CannabisGame.server.lua
│   ├── StarterPlayer/
│   │   └── StarterPlayerScripts/
│   │       └── CannabisUI.client.lua
│   └── ReplicatedStorage/
│       └── PlantTypes.lua
├── default.project.json
└── README.md
```

## 🧪 Verification System

This project includes a comprehensive 10-task verification system to ensure all components work correctly:

### ✅ Completed Verification Tasks

1. **UI Execution Verification** - Confirmed GUI renders properly
2. **Server Player Initialization** - Verified player data setup and leaderstats creation
3. **Client Leaderstats Replication** - Confirmed data synchronizes from server to client
4. **SyncGameState Pipeline** - Validated bi-directional communication flow
5. **Reliable Sync System** - Implemented multiple sync requests to eliminate timing issues
6. **Plot State Validation** - Ensured game logic data structure integrity (6 plots with proper states)
7. **Upgrade System Testing** - Verified purchase mechanics with debug logging
8. **Plant Growth Mechanics** - Tested watering and iteration progression (2 waters per growth)
9. **Leaf Generation System** - Confirmed mature plants drop collectible leaves over time
10. **Final Integration Testing** - Restored balanced values for production gameplay

### Debug Logging System
Extensive debug logging provides real-time verification:
- `[TASK X]` messages for verification checkpoints
- `[DEBUG]` messages for general system operation
- Server and client sync confirmations
- Player action tracking and state changes

## 🎯 Gameplay Guide

### Getting Started
1. **Spawn** in the game world with 100 starting cannabis
2. **Select a plot** by clicking on brown soil squares
3. **Plant a seed** using the "Plant Seed" button or clicking the plot
4. **Water your plant** by clicking it or using the "Water Plant" button
5. **Wait for maturity** (plants need 2 waterings per growth stage, 5 stages total)
6. **Collect leaves** by walking over the cannabis leaves that drop from mature plants

### Advanced Strategies
- **Upgrade yield early** to multiply your collection rates
- **Unlock multiple plots** to scale production
- **Invest in autopicker** for passive collection when you're nearby
- **Different plants have different drop rates** - experiment to find the most profitable

### Game Balance
- **Starting Cannabis**: 100
- **Waters per Growth**: 2 (balanced gameplay)
- **Plant Lifespan**: 30 leaf drops before plant dies and plot resets
- **Upgrade Costs**: Progressive scaling (10→25→50→100→200 for yield boosts)

## 🐛 Troubleshooting

### Common Issues
- **No GUI visible**: Check that Rojo is connected and files are synced properly
- **Plants not growing**: Ensure you're clicking on the plant segments or using action buttons
- **Cannabis not updating**: Verify leaderstats replication in server/client logs
- **Upgrade buttons not working**: Check console for purchase event logs

### Debug Console Messages
Monitor the output console for verification messages:
- Server initialization: `[TASK 2] Player name: YourName`
- Client connection: `[TASK 4] SYNC RECEIVED from server`
- Plant growth: `[TASK 8] Plant grew! Iteration: X → Y`
- Leaf generation: `[TASK 9] Leaf drop #X - Plant: PlantName`

## 📊 Performance Characteristics

### Optimizations
- **Incremental Rendering**: Plants built 50 segments per frame to prevent lag
- **Render Queues**: Large plants queue segment creation to maintain 60 FPS
- **Efficient State Sync**: Only necessary data synced between server/client
- **Automatic Cleanup**: Leaves despawn after 30 seconds, dead plants auto-reset

### Scalability
- Supports up to 6 plots per player
- Handles multiple concurrent plant growth cycles
- Efficient autopicker with proximity detection
- Server-authoritative with client prediction

## 🏆 Project Status

**Status**: ✅ **FULLY VERIFIED AND OPERATIONAL**

All 10 verification tasks completed successfully. The game features:
- Complete plant-to-harvest gameplay loop
- Fully functional upgrade system
- Robust client-server synchronization
- Professional debug logging system
- Balanced gameplay progression
- Optimized performance for multiplayer

## 🔮 Future Enhancements

Potential expansion opportunities:
- **Seasonal Events** - Special plant types during holidays
- **Trading System** - Player-to-player cannabis exchange
- **Prestige System** - Reset progress for permanent bonuses
- **Achievement System** - Unlock rewards for milestones
- **Plot Decorations** - Customize your farming area
- **Breeding System** - Cross-pollinate plants for new strains

---

*Cannabis Idle Game - A comprehensive incremental farming experience built with robust verification and professional development practices.*