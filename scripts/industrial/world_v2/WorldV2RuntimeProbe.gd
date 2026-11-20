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
    var demand_id: int = runtime.AddSingleRequirementDemand(
        "圆罐",
        "",
        "A",
        "Passive",
        0
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

    # Missing IDs are a normal negative result for MoveDemand, not a runtime fault.
    var missing_move: bool = runtime.MoveDemand(-1, "Passive")
    assert(not missing_move, "moving a missing demand must return false")
    assert(_snapshot_changed_count >= 3, "successful commands must emit SnapshotChanged")

    print(
        "[WorldV2Probe] command probe passed",
        " demand_id=", demand_id,
        " start_success=", start_result.get("success", false),
        " start_reason=", start_result.get("reason", ""),
        " snapshot_signals=", _snapshot_changed_count
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
