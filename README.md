# Space Demo — World V2 playable prototype

This repository contains the Space game client and the Godot presentation/runtime host for Jar System World V2. The intended player entry path is:

`Main Menu → Hangar → frozen battle loadout → Battle`

The Hangar uses the demo board and catalog resources under `data/hangar/`. The player can select the ship, parser, workshop instances/roles, optional devices and skills, choose free combat or an unlocked finite stage, then launch the battle. The Jar simulation is hosted by `WorldV2ShipHost`; Jar rules and execution remain owned by the sibling `jar-system-dotnet` repository.

> **Prototype status:** this is a gameplay prototype candidate, not a finished commercial build. The current catalog/balance and presentation are demo content. Workshop replacement is intentionally not part of the playable path yet. A real desktop Hangar launch previously exposed an outer Board Assignment schema 2 incompatibility; Core Board Assignment schema-v2 and non-default liquid-polarity propagation fixes are committed; the latest Space cross-repository script and desktop GUI launch remain pending. Do not treat the intended entry path as accepted until the P0 release gates in the project guide and work record are complete.

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
git clone --branch architecture/core-liquid-identity-consolidation https://github.com/Lazyair150/jar-system-dotnet.git

cd jar-system-dotnet
git checkout 93f050fabb201c37a4bc1601f45e6c0aaff33cdd
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

1. The Hangar initializes a default build from the player's actually owned starter instances. Confirm the ship, parser, two distinct workshop instances, and required board slots in the preview.
2. Optional skill/device slots are filled only when a compatible owned instance and a valid slot are available; the player can still change any selection.
3. Choose **Free Combat** for an unbounded combat session, or select an unlocked finite stage.
4. Press the build/launch button. The Hangar validates and freezes the selected owned-instance loadout, then passes it to the combat scene before the scene enters the tree.
5. In combat, use the current input map:
   - `W` / `A` / `S` / `D`: move
   - Left mouse button: shoot
   - `K`: shield
   - `L`: double shot
   - `P`: pierce

The combat scene mounts a persistent Jar observer HUD: it displays ship/Jar resource information, workshop states, Active/Passive order slots, cooldowns, and snapshot-delta feedback. The Active slot button sends only an explicit demand request to Core. Some advanced systems are intentionally prototype-grade and their catalog/balance values are not final.

## 4. Run the cross-repository verification

The full integration script builds the exact Core Bridge, builds Space, imports/parses the Godot project, and runs the HUD, Hangar catalog/ownership/board contracts, parser ingress, runtime, lifecycle, fault, disposed/faulted command, snapshot-isolation, and battle pause/fault-navigation probes.

From `space-demo`:

```sh
CORE_REPO_DIR="../jar-system-dotnet" \
CORE_EXPECTED_SHA="93f050fabb201c37a4bc1601f45e6c0aaff33cdd" \
GODOT_BIN="godot" \
bash scripts/ci/verify-world-v2-cross-repo.sh
```

PowerShell users can run the individual build/import commands above; the verification harness is Bash-based and requires Git Bash or WSL on Windows.

## Project development and module architecture

- [Project Development Guide](docs/PROJECT_DEVELOPMENT_GUIDE.md): mandatory engineering workflow, cross-repository sync, evidence and documentation rules.
- [System Architecture and Module Map](docs/architecture/00-system-architecture-and-module-map.md): module ownership and dependency direction.
- [Hangar / Board Assignment pipeline](docs/architecture/13-hangar-board-assignment-and-loadout-pipeline.md): frozen Board and cross-language schema/fingerprint contract.
- [World V2 Host / Runtime lifecycle](docs/architecture/14-world-v2-host-runtime-and-failure-boundary.md): startup, time authority, pause, disposal and fault handling.
- [Production / Parser / resource supply](docs/architecture/15-production-parser-and-resource-supply.md).
- [Order / Rule Profile / effect dispatch](docs/architecture/16-order-rule-profile-and-effect-dispatch.md).
- [Progression / Stage / persistence](docs/architecture/17-progression-stage-and-persistence.md).

## Engineering standards

The cross-language coding, architecture, lifecycle, protocol, error-handling, and testing rules are documented in [Space Engineering Standard](docs/architecture/12-space-engineering-standard.md). The standard adapts the structure of Alibaba's Java Development Manual to GDScript, C#, Godot resources, and the Core/Space boundary; it is not an official Alibaba Godot standard.

## Repository boundaries

- **Space** owns combat, player progression, ship inventory, Hangar composition, production devices, skill/effect meaning, stage progression, presentation, and scene lifecycle.
- **Jar Core** owns Jar resources, workshop rules, order feasibility/admission/execution, reservations, logical time, and its resource ledger.
- Space sends commands and consumes snapshots/events through `WorldV2ShipHost`; it must not duplicate Core solver or resource-conservation rules.
- The manual workshop-replacement module is deliberately isolated and is not required to launch or play the current prototype.

## Current validation boundary

- Core integration pin: `93f050fabb201c37a4bc1601f45e6c0aaff33cdd`; Core Verify run `45856292385` passed, including 1044 xUnit tests with 0 failures.
- The cross-repository workflow file currently exists on this PR branch but not base `main`, so GitHub has no PR-triggered run attached to the current Space head. Run `scripts/ci/verify-world-v2-cross-repo.sh` locally with the exact pin above.
- The Space schema 2 golden-vector probe is included in the Hangar Board probe path; it remains pending execution in Godot.
- Headless success does not replace local GUI acceptance on the target OS/GPU. The desktop Hangar-to-Battle fault remains OPEN until that acceptance is recorded.
