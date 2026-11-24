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
if ! command -v git >/dev/null 2>&1; then
  echo "git is required to verify the exact Core revision." >&2
  exit 2
fi
if ! git -C "$CORE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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
dotnet build "$BRIDGE_PROJECT" --configuration Debug

echo "[2/4] Build Space against the exact sibling Bridge project"
dotnet build "$SPACE_ROOT/space-demo.csproj" --configuration Debug \
  -p:JarSystemWorldV2BridgeProject="$BRIDGE_PROJECT"

run_godot_checked() {
  local log_name="$1"
  local expected_marker="$2"
  shift 2
  local log_file="${RUNNER_TEMP:-/tmp}/godot-${log_name}.log"
  local command_status=0

  set +e
  "$GODOT_BIN" "$@" 2>&1 | tee "$log_file"
  command_status=${PIPESTATUS[0]}
  set -e

  if (( command_status != 0 )); then
    echo "Godot command failed (${command_status}); log: $log_file" >&2
    return "$command_status"
  fi

  if grep -Eq 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|Failed to create an autoload|Failed to instantiate|Cannot instantiate C# script|Assertion failed' "$log_file"; then
    echo "Godot reported script, class, or assertion errors despite a zero exit code; log: $log_file" >&2
    return 1
  fi

  if [[ -n "$expected_marker" ]] && ! grep -Fq "$expected_marker" "$log_file"; then
    echo "Expected probe completion marker missing: $expected_marker; log: $log_file" >&2
    return 1
  fi
}

echo "[3/4] Import project and parse GDScript/C# resources"
run_godot_checked "editor-import" "" --headless --path "$SPACE_ROOT" --editor --build-solutions --quit
run_godot_checked "hud-feedback" "=== 18 checks, 0 failures ===" \
  --headless --path "$SPACE_ROOT" --script "res://tests/space_jar_hud_feedback.gd"

echo "[4/4] Run World V2 integration and lifecycle probes"
run_godot_checked "parser-ingress" "[SpaceOreParserJarIngressProbe] passed" \
  --headless --path "$SPACE_ROOT" --scene "res://scenes/industrial/SpaceOreParserJarIngressProbe.tscn" --quit-after 180
run_godot_checked "runtime" "[WorldV2Probe] Host active-demand boundary passed" \
  --headless --path "$SPACE_ROOT" --scene "res://scenes/industrial/WorldV2RuntimeProbe.tscn" --quit-after 180
run_godot_checked "lifecycle" "[WorldV2LifecycleProbe] lifecycle probe passed" \
  --headless --path "$SPACE_ROOT" --scene "res://scenes/industrial/WorldV2LifecycleProbe.tscn" --quit-after 180
run_godot_checked "fault" "[WorldV2FaultProbe] fault boundary passed" \
  --headless --path "$SPACE_ROOT" --scene "res://scenes/industrial/WorldV2FaultProbe.tscn" --quit-after 180
run_godot_checked "disposed-commands" "[WorldV2DisposedCommandsProbe] passed" \
  --headless --path "$SPACE_ROOT" --scene "res://scenes/industrial/WorldV2DisposedCommandsProbe.tscn" --quit-after 180
run_godot_checked "faulted-commands" "[WorldV2FaultedCommandsProbe] passed" \
  --headless --path "$SPACE_ROOT" --scene "res://scenes/industrial/WorldV2FaultedCommandsProbe.tscn" --quit-after 180
run_godot_checked "snapshot-isolation" "[WorldV2SnapshotIsolationProbe] passed" \
  --headless --path "$SPACE_ROOT" --scene "res://scenes/industrial/WorldV2SnapshotIsolationProbe.tscn" --quit-after 180

echo "CROSS-REPO-WORLD-V2-OK core=$ACTUAL_CORE_SHA"
