extends Node

var _fault_messages: Array[String] = []

func _ready() -> void:
    print("[WorldV2FaultProbe] started")

    # This fixture uses a real WorldClock checked-arithmetic overflow.
    # Keep the runtime paused from auto-advancing until the extreme but valid
    # speed ratio is installed, then let Godot provide a normal frame delta.
    var runtime := WorldV2RuntimeNode.new()
    runtime.AutoAdvance = false
    runtime.RuntimeFaulted.connect(_on_runtime_faulted)
    add_child(runtime)

    assert(runtime.IsInitialized, "fault fixture must initialize a real World v2 session")
    assert(runtime.CanAcceptCommands, "healthy Runtime must accept commands")

    # 9e15 is finite and its milli-ratio remains below Int64.MaxValue.
    # A normal multi-millisecond frame makes delta * ratio overflow in WorldClock.
    runtime.SetWorldSpeedRatio(9.0e15)
    runtime.AutoAdvance = true

    var fault_observed := false
    for frame_index in range(120):
        await get_tree().process_frame
        if runtime.IsFaulted:
            fault_observed = true
            break

    assert(fault_observed, "Core WorldClock overflow must reach the Godot Runtime")
    assert(runtime.IsInitialized, "a sticky runtime fault must retain its session for diagnosis")
    assert(not runtime.CanAcceptCommands, "faulted Runtime must reject mutating/control commands")
    assert(_fault_messages.size() == 1, "RuntimeFaulted must be emitted exactly once")

    # Diagnostic reads must remain available after the Core fault.
    var snapshot: Dictionary = runtime.GetWorldSnapshot()
    assert(snapshot.get("runtimeFaulted", false), "snapshot must expose the Core runtime fault")
    assert(not str(snapshot.get("faultReason", "")).is_empty(), "snapshot must retain a fault reason")
    assert(int(snapshot.get("worldTimeMilli", -1)) == 0, "overflowing clock advance must not partially commit world time")

    print(
        "[WorldV2FaultProbe] fault boundary passed",
        " core_fault=true signal_count=", _fault_messages.size(),
        " command_gate=", runtime.CanAcceptCommands,
        " snapshot_readable=true",
        " fault_reason=", snapshot.get("faultReason", "")
    )

    # A faulted session remains alive only for diagnosis. Leaving the SceneTree
    # must still release it and permanently dispose this Runtime node.
    remove_child(runtime)
    assert(runtime.IsDisposed, "faulted Runtime must dispose its session on exit")
    assert(not runtime.IsInitialized, "disposed faulted Runtime must release session ownership")
    print("[WorldV2FaultProbe] faulted session disposal passed disposed=true session_released=true")
    runtime.queue_free()

func _on_runtime_faulted(message: String) -> void:
    _fault_messages.append(message)
    print("[WorldV2FaultProbe] runtime fault signal: ", message)
