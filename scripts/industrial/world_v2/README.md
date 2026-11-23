# Space / Jar World V2 integration

This directory contains the only supported Jar integration for the Space game. The legacy turn-based IndustrialRuntime, legacy JarCoreBridge, standalone IndustrialMain scene, industrial reward wallet flow, and old industrial test harness have been removed from the project.

## Ownership

- Space owns combat, pickups, energy-stone identity, parser/device selection, player-facing skills, and the effects those skills produce.
- Jar World V2 owns Jar resources, workshop-local rules, Master/Slave relationship rules, order solving/execution, resource settlement, and order cooldowns.
- WorldV2ShipHost owns the lifecycle and the single time/command boundary between the two worlds.
- HUD observes detached Host snapshots and sends only explicitly supported player commands.

## Dependency

The Godot adapter depends on the World V2 Bridge in the sibling `jar-system-dotnet` checkout. The integration branch must use a compatible Bridge revision; the Space project does not fall back to the retired legacy Core bridge.

## Development probes

The World V2 probe scenes under `scenes/industrial/` are development-only fixtures. They are not a second game mode or a production scene entry point. The production Hangar/Combat flow remains the only intended player-facing integration path.

## Validation boundary

Source cleanup and static contract checks do not prove Godot compilation or runtime behavior. Run the project with the required Godot 4.7.1 .NET SDK and the compatible sibling Bridge checkout before marking the integration verified.
