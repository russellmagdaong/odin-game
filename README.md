# ODIN: Intelligent Tutoring System — Game Client (GDScript)

[![Godot Engine](https://img.shields.io/badge/Godot-4.x-478CBF?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Language](https://img.shields.io/badge/Language-GDScript-478CBF)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Web%20%7C%20Desktop-blue)](https://godotengine.org)

**ODIN (GDScript)** is the standalone, gamified 2D RPG client for the **ODIN Intelligent Tutoring System (ITS)**. Built with **Godot Engine 4**, this repository serves as the dedicated game development workspace for creating, maintaining, and enhancing the interactive learning experience where players learn programming and data structures through retro dungeon-crawling code battles.

---

## 📖 Project Overview

ODIN transforms programming education into an immersive, pixel-art role-playing adventure. Instead of standard quiz forms, students navigate dungeons, interact with NPCs, encounter enemies, and resolve encounters by writing real code inside an embedded code editor. 

The game acts as the frontend interactive layer of the ODIN ITS architecture, communicating with an intelligent backend service that evaluates code correctness, captures keystroke dynamics telemetry, provides automated scaffolding and diagnostic interventions, and tracks student skill mastery in real time.

---

## 🎯 Educational Curriculum & Skills

The game's combat encounters and dungeon progression are designed around core Computer Science concepts:

| Level / Domain | Skill Focus | Learning Objectives |
|---|---|---|
| **Level 0 (Diagnostic)** | *Diagnostic Assessment* | Baseline programming diagnostic and orientation |
| **Level 1** | *Array Initialization & Access* | Declaring arrays, understanding 0-based indexing, element retrieval |
| **Level 2** | *Array Iteration & Loops* | Traversing arrays, bounds checking, loop conditions, transformations |
| **Level 3** | *Multidimensional & Jagged Arrays* | 2D matrices, nested loops, grid traversal, non-rectangular data arrays |
| **Boss Encounters** | *Array Operations & Synthesis* | Complex algorithmic operations, sorting, filtering, and synthesis |

---

## ✨ Key Features

- **🎮 2D Retro RPG Exploration:**
  - Grid-based character movement with walk/run mechanics.
  - Interactive NPCs, dialogue cutscenes, and branch triggers.
  - Multi-tier dungeon levels (`level0` through `level31`) with spawn points and level transitions.
  - Finite State Machine (FSM) AI for enemies (Idle, Alert, Chase).

- **⚔️ Integrated In-Game Code Battle System:**
  - Real-time in-game code editor (`CodeEdit`) with custom styling and problem prompts.
  - Starter code injection and live submission feedback.
  - Instant compiler diagnostic display with targeted line number callouts.

- **🧠 ITS Backend Integration & Pedagogical Interventions:**
  - Automated session tracking and problem fetching via REST API.
  - Scaffolding hints and adaptive NPC dialogues based on student failure modes.
  - Real-time skill mastery probability calculations (Bayesian Knowledge Tracing / Knowledge Modeling).
  - Gamified XP rewards and achievement badge unlocks.

- **⏱️ Keystroke Dynamics & Telemetry:**
  - Built-in `BattleMetrics` engine tracking typing behavior (flight time, dwell time, initial latency, and raw keystroke timing).
  - Provides behavioral data to the tutoring model to detect student struggle, hesitation, or fluency.

- **🌐 Web (HTML5/Wasm) & Desktop Ready:**
  - Runs natively on Desktop or exported to HTML5.
  - Bidirectional communication via `JavaScriptBridge` / `postMessage` for embedded iframe integration in web-based learning management portals.
  - Local save state persistence (`user://player_data.json` / browser `IndexedDB`).

---

## 🏗️ Architecture & Project Structure

```
odin-gdscript/
├── assets/                  # Visual and audio game assets
│   ├── audio/               # Background music (.ogg) and sound effects (.mp3)
│   ├── battle/              # Battle backgrounds and combat sprites
│   ├── characters/          # Player and NPC sprite sheets & animations
│   ├── tiles/               # Tilemaps and environment sprites
│   └── ui/                  # UI textures, dialogue boxes, and icons
│
├── scenes/                  # Godot scene trees (.tscn)
│   ├── characters/          # Player (male/female) and enemy scenes
│   ├── core/                # Core entry points (GameManager, MainMenu, CharacterSelect)
│   ├── gameplay/            # BattleScene, DialogueTrigger, Interactables
│   ├── levels/              # Dungeon level scenes (Level0, Level1, Level2, Level3, etc.)
│   └── ui/                  # Pause menu, confirm dialogs, achievement widgets
│
├── scripts/                 # GDScript logic & controllers
│   ├── core/                # Autoload Singletons & global managers
│   │   ├── api_client.gd    # HTTP communication with ODIN ITS backend
│   │   ├── audio_manager.gd # BGM and SFX player
│   │   ├── dialogue_manager.gd # Dialogue queue and NPC conversation runner
│   │   ├── enums.gd         # Global enums (Skills, Facing, Levels, Logs)
│   │   ├── game_manager.gd  # Primary game lifecycle & state controller
│   │   ├── globals.gd       # Session and gameplay configuration
│   │   ├── logger.gd        # Structured console logger
│   │   ├── player_data_manager.gd # Player profile, save data & achievements
│   │   └── scene_manager.gd # Seamless scene loading & transitions
│   │
│   ├── gameplay/            # Gameplay systems & combat
│   │   ├── battle_metrics.gd # Keystroke latency & dwell-time telemetry
│   │   ├── battle_scene.gd   # Battle UI, code editor & submission logic
│   │   ├── characters/      # Player & Enemy controller scripts and FSM states
│   │   ├── interactables/   # Chests, signs, and world triggers
│   │   └── ui/              # UI components (PauseMenu, Achievements, DialogueBox)
│   │
│   └── utilities/           # Generic helpers (StateMachine, State, etc.)
│
├── resources/               # Shared themes, UI styles, and fonts (Pixy, Dedicool)
├── export_presets.cfg       # Godot export templates (Web/HTML5 configured)
└── project.godot            # Godot 4 engine project configuration
```

---

## 🔌 API & Integration

The game connects to the ODIN backend service via `ApiClient` (`scripts/core/api_client.gd`):

### REST Endpoints Used:
- `POST /api/session`: Initiates a battle/puzzle session for the current player and dungeon level.
- `GET /api/puzzle/:id`: Retrieves problem descriptions and starter code templates.
- `POST /api/submission`: Submits student code and keystroke dynamics metrics for evaluation.
- `PATCH /api/session/:id/end`: Closes active learning sessions.

### Web Embedding (Iframe Communication):
When running in a Web browser, `ApiClient` automatically detects parent frame configurations via `window.parent.__ODIN_GAME_CONFIG` or `window.ODIN_API_URL`. It transmits lifecycle notifications (e.g. `odin_session_started`) back to the parent web host via `postMessage`.

---

## 🚀 Getting Started

### Prerequisites
- **[Godot Engine 4.x](https://godotengine.org/download)** (Recommended: Godot 4.3 or later with **GL Compatibility** renderer).

### Local Setup
1. **Clone the Repository:**
   ```bash
   git clone https://github.com/russellmagdaong/odin-game.git
   cd odin-game
   ```

2. **Open in Godot:**
   - Launch Godot Engine.
   - Click **Import** and browse to the project directory containing `project.godot`.
   - Click **Import & Edit**.

3. **Run the Project:**
   - Press <kbd>F5</kbd> (or the **Play** button in the top-right corner) to launch from the main scene (`res://scenes/core/game_manager.tscn`).

### Local Backend Configuration
By default, standalone local runs connect to `http://localhost:5000` with user ID `local_dev`. To test with a live backend:
- Configure your local ODIN backend service on port 5000, or
- Modify `_get_base_url()` in `scripts/core/api_client.gd`.

---

## 🕹️ Controls

| Action | Primary Key | Secondary Key |
|---|---|---|
| **Move Up** | <kbd>W</kbd> | <kbd>Up Arrow</kbd> |
| **Move Down** | <kbd>S</kbd> | <kbd>Down Arrow</kbd> |
| **Move Left** | <kbd>A</kbd> | <kbd>Left Arrow</kbd> |
| **Move Right** | <kbd>D</kbd> | <kbd>Right Arrow</kbd> |
| **Run / Sprint** | <kbd>Shift</kbd> | — |
| **Interact / Advance** | <kbd>E</kbd> | <kbd>Enter</kbd> / <kbd>Space</kbd> |
| **Pause / Settings** | <kbd>Esc</kbd> | Top-left Gear Icon |

---

## 📦 Building & Exporting

### Web Export (HTML5)
1. Ensure the Web export templates are installed in Godot (`Editor -> Manage Export Templates`).
2. Go to **Project -> Export...**.
3. Select the **Web (ODIN)** preset.
4. Click **Export Project** and select target output directory (e.g. `godot-export-temp/index.html`).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
