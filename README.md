# Space Demo — World V2 playable prototype

This repository contains the Space game client and the Godot presentation/runtime host for Jar System World V2. The current supported entry path is:

`Main Menu → Hangar → frozen battle loadout → Battle`

The Hangar uses the demo board and catalog resources under `data/hangar/`. The player can select the ship, parser, workshop instances/roles, optional devices and skills, choose free combat or an unlocked finite stage, then launch the battle. The Jar simulation is hosted by `WorldV2ShipHost`; Jar rules and execution remain owned by the sibling `jar-system-dotnet` repository.

> **Prototype status:** this is a locally runnable gameplay prototype, not a finished commercial build. The current catalog/balance and presentation are demo content. Workshop replacement is intentionally not part of the playable path yet. The latest successful cross-repository runtime integration used Space commit `74a93ed281d94823608b0c6803edd78dd9f068cc` with Core commit `b342259fe04363386085dc9a4ca995112954ed43`. Later Space changes in this branch are documentation/status cleanup and the HUD probe's typed-array correction; the latest documentation head has not yet been revalidated by a successful exact-head workflow.

## Requirements

- Git
- .NET 10 SDK (the project targets `net10.0`)
- Godot **4.7.1 .NET** build (not the standard non-.NET build)
- Windows, Linux, or macOS supported by the installed Godot/.NET toolchain

Check the installed tools:

```sh
dotnet --version
godot --version
```

The Godot executable must report a 4.7.1 .NET build. On Windows it is commonly named `Godot_v4.7.1-stable_mono_win64.exe`; on other platforms set `GODOT_BIN` to the installed executable.

## 1. Clone both repositories

The Core repository is a required sibling checkout because `space-demo.csproj` references its World V2 Godot Bridge project. Use the exact Core source revision that passed the integration build:

```sh
mkdir space-workspace
cd space-workspace

git clone --branch world-v2/phase-4.10b-hangar-ui https://github.com/Lazyair150/space-demo.git
git clone --branch world-v2/phase-4.11c-order-template-demand-ingress https://github.com/Lazyair150/jar-system-dotnet.git

cd jar-system-dotnet
git checkout b342259fe04363386085dc9a4ca995112954ed43
cd ../space-demo
```

The expected directory layout is:

```text
space-workspace/
├── space-demo/
└── jar-system-dotnet/
```

If you place the Core checkout elsewhere, pass its Bridge project path explicitly as shown below.

## 2. Build and import

From the `space-demo` directory:

```sh
dotnet build space-demo.csproj -p:JarSystemWorldV2BridgeProject="../jar-system-dotnet/hosts/godot/WorldV2Bridge/JarSystem.WorldV2Bridge.csproj"
godot --headless --editor --path . --build-solutions --quit
```

On Windows PowerShell, use the same commands, but quote the Godot executable if its path contains spaces:

```powershell
dotnet build .\space-demo.csproj -p:JarSystemWorldV2BridgeProject="..\jar-system-dotnet\hosts\godot\WorldV2Bridge\JarSystem.WorldV2Bridge.csproj"
& "C:\Path\To\Godot_v4.7.1-stable_mono_win64.exe" --headless --editor --path . --build-solutions --quit
```

If the Core checkout is not the sibling directory, replace the project path with its absolute path. Do not substitute the Core repository's default branch for the pinned revision above when reproducing this integration state.

## 3. Run the game

From the `space-demo` directory:

```sh
godot --path .
```

Or launch the project from Godot Project Manager by importing this directory and pressing **Run Project**. The project main scene opens the main menu. Select **Start** to enter the Hangar.

### First play session

1. In the Hangar, keep the provided starter ship/parser/workshop selections or choose another owned instance.
2. Keep the optional skill slots empty for the simplest first launch, or equip a skill if you want to exercise the order/effect path.
3. Choose **Free Combat** for an unbounded combat session, or select an unlocked finite stage.
4. Press the build/launch button. The Hangar freezes the selected owned-instance loadout and passes it to the combat scene before the scene enters the tree.
5. In combat, use the current input map:
   - `W` / `A` / `S` / `D`: move
   - Left mouse button: shoot
   - `K`: shield
   - `L`: double shot
   - `P`: pierce

The combat scene mounts a persistent Jar observer HUD: it displays ship/Jar resource information, workshop states, Active/Passive order slots, cooldowns, and snapshot-delta feedback. The Active slot button sends only an explicit demand request to Core. Some advanced systems are intentionally prototype-grade and their catalog/balance values are not final.

## 4. Run the cross-repository verification

The full integration script builds the exact Core Bridge, builds Space, imports/parses the Godot project, and runs the HUD, parser ingress, runtime, lifecycle, fault, disposed/faulted command, and snapshot-isolation probes.

From `space-demo`:

```sh
CORE_REPO_DIR="../jar-system-dotnet" \
CORE_EXPECTED_SHA="b342259fe04363386085dc9a4ca995112954ed43" \
GODOT_BIN="godot" \
bash scripts/ci/verify-world-v2-cross-repo.sh
```

PowerShell users can run the individual build/import commands above; the verification harness is Bash-based and requires Git Bash or WSL on Windows.

## Repository boundaries

- **Space** owns combat, player progression, ship inventory, Hangar composition, production devices, skill/effect meaning, stage progression, presentation, and scene lifecycle.
- **Jar Core** owns Jar resources, workshop rules, order feasibility/admission/execution, reservations, logical time, and its resource ledger.
- Space sends commands and consumes snapshots/events through `WorldV2ShipHost`; it must not duplicate Core solver or resource-conservation rules.
- The manual workshop-replacement module is deliberately isolated and is not required to launch or play the current prototype.

## Current validation boundary

- Successful exact runtime integration: Space `74a93ed281d94823608b0c6803edd78dd9f068cc`, Core `b342259fe04363386085dc9a4ca995112954ed43`, workflow run `45438436612`.
- Core fixed-seed and Core test suite verification is recorded in the Core repository work ledger.
- This README is a setup/run guide; it does not claim that a successful CI run exists for every later documentation-only commit on the current Space branch.
