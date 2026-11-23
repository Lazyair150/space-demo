extends Node

@onready var runtime: Node = $WorldV2Runtime
var _elapsed := 0.0
var _command_probe_ran := false
var _snapshot_changed_count := 0

func _ready() -> void:
    runtime.RuntimeReady.connect(_on_runtime_ready)
    runtime.RuntimeFaulted.connect(_on_runtime_faulted)
    runtime.SnapshotChanged.connect(_on_snapshot_changed)
    print("[WorldV2Probe] scene ready")

    var ore_parser_probe: Dictionary = SpaceOreParserRuntimeProbe.run()
    assert(bool(ore_parser_probe.get("passed", false)), "ore parser probe failed: " + String(ore_parser_probe.get("reason", "")))
    print("[SpaceOreParserRuntimeProbe] passed percentage=", ore_parser_probe.get("productionPercentage", -1),
        " pending_batches=", ore_parser_probe.get("pendingBatchesBeforeAck", 0))

    # The child Runtime node enters _Ready before this parent probe.
    # Its RuntimeReady signal may already have fired, so inspect its state too.
    if runtime.IsInitialized:
        _print_snapshot()
        _run_command_probe()

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed >= 1.0:
        _elapsed = 0.0
        if runtime.IsInitialized:
            _print_snapshot()

func _on_runtime_ready() -> void:
    print("[WorldV2Probe] runtime ready")
    _print_snapshot()
    _run_command_probe()

func _on_runtime_faulted(message: String) -> void:
    push_error("[WorldV2Probe] runtime fault: " + message)

func _on_snapshot_changed() -> void:
    _snapshot_changed_count += 1

func _run_command_probe() -> void:
    if _command_probe_ran:
        return
    _command_probe_ran = true

    print("[WorldV2Probe] command probe started")

    # Add a deterministic one-requirement demand. Empty liquid means shape-only.
    var demand_id: int = runtime.AddJarDemand(
        "A",
        "Passive",
        0,
        "probe.order.active-demand",
        [{"shape": "圆罐", "liquid": ""}]
    )
    # The ID is opaque to the Godot layer; verify it by reading the snapshot instead.

    var after_add: Dictionary = runtime.GetWorldSnapshot()
    var found_added_demand := false
    for item in after_add.get("demands", []):
        var demand: Dictionary = item
        if int(demand.get("id", -1)) == demand_id:
            found_added_demand = true
            assert(demand.get("area", "") == "Passive", "new demand must enter Passive area")
            assert(demand.get("type", "") == "A", "new demand type must be A")
    assert(found_added_demand, "added demand must appear in detached snapshot")

    # Move the same demand to Active and verify the snapshot reflects the new area.
    var moved: bool = runtime.MoveDemand(demand_id, "Active")
    assert(moved, "existing demand should move to Active")
    var after_move: Dictionary = runtime.GetWorldSnapshot()
    var found_active_demand := false
    for item in after_move.get("demands", []):
        var demand: Dictionary = item
        if int(demand.get("id", -1)) == demand_id:
            found_active_demand = true
            assert(demand.get("area", "") == "Active", "moved demand must be in Active area")
    assert(found_active_demand, "moved demand must remain in snapshot")

    # Starting may succeed or return a domain rejection (for example, insufficient
    # resources). Both are valid command results; the adapter must return a detached result.
    var start_result: Dictionary = runtime.StartActiveDemand(demand_id)
    assert(start_result.has("success"), "start result must contain success")
    assert(start_result.has("reason"), "start result must contain reason")
    assert(not runtime.IsFaulted, "a normal domain rejection must not fault the Runtime")
    var after_domain_rejection: Dictionary = runtime.GetWorldSnapshot()
    assert(not after_domain_rejection.get("runtimeFaulted", true), "domain rejection must remain distinct from runtime fault")

    # Space may update the complete rate table of a configured Jar producer.
    # Jar retains the fractional production accumulator and owns all actual Jar creation.
    runtime.UpdateProducerRates("陶工", {"圆罐": 2.0, "方罐": 0.0})
    assert(not runtime.IsFaulted, "a valid producer-rate update must not fault the Runtime")

    # Space submits completed empty Jars as a discrete, idempotent resource batch.
    var import_result: Dictionary = runtime.ImportProducedJars(
        "runtime-probe-stone-batch-001",
        {"方罐": 2, "圆罐": 1}
    )
    assert(not bool(import_result.get("wasDuplicate", true)), "first Jar batch import must be new")
    assert(int(import_result.get("storedJarCount", 0)) == 3, "all probe Jars should enter the empty warehouse")
    var repeated_import: Dictionary = runtime.ImportProducedJars(
        "runtime-probe-stone-batch-001",
        {"圆罐": 1, "方罐": 2}
    )
    assert(bool(repeated_import.get("wasDuplicate", false)), "repeated Jar batch import must be idempotent")
    assert(runtime.GetWorldSnapshot().get("resourceJars", []).size() == 3, "duplicate import must not create extra Jars")

    # Missing IDs are a normal negative result for MoveDemand, not a runtime fault.
    var missing_move: bool = runtime.MoveDemand(-1, "Passive")
    assert(not missing_move, "moving a missing demand must return false")
    assert(_snapshot_changed_count >= 6, "successful commands must emit SnapshotChanged")

    print(
        "[WorldV2Probe] command probe passed",
        " demand_id=", demand_id,
        " start_success=", start_result.get("success", false),
        " start_reason=", start_result.get("reason", ""),
        " snapshot_signals=", _snapshot_changed_count
    )

    await _run_clock_control_probe()

func _run_clock_control_probe() -> void:
    # Pause must freeze both world and logical time, even though Godot keeps ticking.
    runtime.PauseWorld()
    var paused_before: Dictionary = runtime.GetWorldSnapshot()
    await get_tree().create_timer(0.3, true).timeout
    var paused_after: Dictionary = runtime.GetWorldSnapshot()
    assert(
        int(paused_after.get("worldTimeMilli", -1)) == int(paused_before.get("worldTimeMilli", -2)),
        "world time must not advance while paused"
    )
    assert(
        int(paused_after.get("logicalTimeMilli", -1)) == int(paused_before.get("logicalTimeMilli", -2)),
        "logical time must not advance while paused"
    )

    # At 2x, Godot still submits wall-clock milliseconds unchanged.
    # Core WorldClock alone converts them into twice as much logical time.
    runtime.ResumeWorld()
    runtime.SetWorldSpeedRatio(2.0)
    var fast_before: Dictionary = runtime.GetWorldSnapshot()
    assert(int(fast_before.get("speedRatioMilli", -1)) == 2000, "2x ratio must be visible in snapshot")
    await get_tree().create_timer(0.5, true).timeout
    var fast_after: Dictionary = runtime.GetWorldSnapshot()
    var fast_world_delta := int(fast_after.get("worldTimeMilli", 0)) - int(fast_before.get("worldTimeMilli", 0))
    var fast_logical_delta := int(fast_after.get("logicalTimeMilli", 0)) - int(fast_before.get("logicalTimeMilli", 0))
    assert(fast_world_delta > 0, "world time must advance after resume")
    assert(
        fast_logical_delta == fast_world_delta * 2,
        "2x logical time must be converted exactly once by Core WorldClock"
    )

    # At 0x, world time continues while logical time is held.
    runtime.SetWorldSpeedRatio(0.0)
    var stopped_before: Dictionary = runtime.GetWorldSnapshot()
    assert(int(stopped_before.get("speedRatioMilli", -1)) == 0, "0x ratio must be visible in snapshot")
    await get_tree().create_timer(0.3).timeout
    var stopped_after: Dictionary = runtime.GetWorldSnapshot()
    var stopped_world_delta := int(stopped_after.get("worldTimeMilli", 0)) - int(stopped_before.get("worldTimeMilli", 0))
    var stopped_logical_delta := int(stopped_after.get("logicalTimeMilli", 0)) - int(stopped_before.get("logicalTimeMilli", 0))
    assert(stopped_world_delta > 0, "world time must continue at 0x logical speed")
    assert(stopped_logical_delta == 0, "logical time must remain fixed at 0x speed")

    runtime.SetWorldSpeedRatio(1.0)
    print(
        "[WorldV2Probe] clock control probe passed",
        " paused_world_delta=", int(paused_after.get("worldTimeMilli", 0)) - int(paused_before.get("worldTimeMilli", 0)),
        " 2x_world_delta=", fast_world_delta,
        " 2x_logical_delta=", fast_logical_delta,
        " 0x_world_delta=", stopped_world_delta,
        " 0x_logical_delta=", stopped_logical_delta
    )

func _print_snapshot() -> void:
    var state: Dictionary = runtime.GetWorldSnapshot()
    print(
        "[WorldV2Probe] world=", state.get("worldTimeMilli", -1),
        " logical=", state.get("logicalTimeMilli", -1),
        " paused=", state.get("isPaused", false),
        " master=", state.get("master", {}).get("name", "-"),
        " slave=", state.get("slave", {}).get("name", "-")
    )
