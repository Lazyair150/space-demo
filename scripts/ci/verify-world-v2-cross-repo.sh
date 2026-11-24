#!/usr/bin/env bash
set -euo pipefail

SPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE_ROOT="${CORE_REPO_DIR:-$(dirname "$SPACE_ROOT")/jar-system-dotnet}"
EXPECTED_CORE_SHA="${CORE_EXPECTED_SHA:-}"
GODOT_BIN="${GODOT_BIN:-godot}"

if [[ -z "$EXPECTED_CORE_SHA" ]]; then
  echo "CORE_EXPECTED_SHA must be set to the exact Jar Core PR commit used for integration." >&2
  exit 2
fi
if [[ ! -d "$CORE_ROOT/.git" ]]; then
  echo "Jar Core checkout not found: $CORE_ROOT" >&2
  exit 2
fi
if ! command -v dotnet >/dev/null 2>&1; then
  echo "dotnet SDK is required for the cross-repository build." >&2
  exit 2
fi
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "Godot .NET executable not found: $GODOT_BIN" >&2
  exit 2
fi

ACTUAL_CORE_SHA="$(git -C "$CORE_ROOT" rev-parse HEAD)"
if [[ "$ACTUAL_CORE_SHA" != "$EXPECTED_CORE_SHA" ]]; then
  echo "Wrong Jar Core revision: expected $EXPECTED_CORE_SHA, got $ACTUAL_CORE_SHA" >&2
  exit 3
fi

BRIDGE_PROJECT="$CORE_ROOT/hosts/godot/WorldV2Bridge/JarSystem.WorldV2Bridge.csproj"
if [[ ! -f "$BRIDGE_PROJECT" ]]; then
  echo "World V2 Bridge project not found: $BRIDGE_PROJECT" >&2
  exit 2
fi

echo "[1/4] Build exact Core World V2 Bridge: $ACTUAL_CORE_SHA"
dotnet build "$BRIDGE_PROJECT" --configuration Release

echo "[2/4] Build Space against the exact sibling Bridge project"
dotnet build "$SPACE_ROOT/space-demo.csproj" --configuration Release \
  -p:JarSystemWorldV2BridgeProject="$BRIDGE_PROJECT"

echo "[3/4] Import project and parse GDScript/C# resources"
"$GODOT_BIN" --headless --path "$SPACE_ROOT" --editor --quit

echo "[4/4] Run World V2 integration and lifecycle probes"
PROBES=(
  "res://scenes/industrial/SpaceOreParserJarIngressProbe.tscn"
  "res://scenes/industrial/WorldV2RuntimeProbe.tscn"
  "res://scenes/industrial/WorldV2LifecycleProbe.tscn"
  "res://scenes/industrial/WorldV2FaultProbe.tscn"
  "res://scenes/industrial/WorldV2DisposedCommandsProbe.tscn"
  "res://scenes/industrial/WorldV2FaultedCommandsProbe.tscn"
  "res://scenes/industrial/WorldV2SnapshotIsolationProbe.tscn"
)
for scene in "${PROBES[@]}"; do
  echo "Running $scene"
  "$GODOT_BIN" --headless --path "$SPACE_ROOT" --scene "$scene" --quit-after 3
done

echo "CROSS-REPO-WORLD-V2-OK core=$ACTUAL_CORE_SHA"
