extends Node

const VALID_CONFIG := "res://data/industrial/world_v2_sandbox.json"
const INVALID_CONFIG := "res://data/industrial/world_v2_invalid.json"

var _fault_messages: Array[String] = []

func _ready() -> void:
    print("[WorldV2LifecycleProbe] started")

    # Use a separate Runtime node so this lifecycle test cannot disturb
    # the existing clock/command probe or the project's old industrial scene.
    var runtime := WorldV2RuntimeNode.new()
    runtime.AutoAdvance = false
    runtime.WorldConfigPath = INVALID_CONFIG
    runtime.RuntimeFaulted.connect(_on_runtime_faulted)
    add_child(runtime)

    # D2: malformed configuration must fail cleanly without retaining a session.
    assert(runtime.IsFaulted, "invalid configuration must fault initialization")
    assert(not runtime.IsInitialized, "failed initialization must not retain a world session")
    assert(_fault_messages.size() == 1, "failed initialization must emit RuntimeFaulted")

    # D4: after correcting the configuration, the same node must be recoverable.
    runtime.WorldConfigPath = VALID_CONFIG
    var recovered: bool = runtime.InitializeWorld()
    assert(recovered, "Runtime must initialize after correcting its configuration")
    assert(runtime.IsInitialized, "recovered Runtime must own an initialized world")
    assert(not runtime.IsFaulted, "successful recovery must clear the fault state")

    var before_duplicate: Dictionary = runtime.GetWorldSnapshot()

    # D1: duplicate initialization is a rejected request, not a replacement.
    var duplicate_result: bool = runtime.InitializeWorld()
    assert(not duplicate_result, "duplicate initialization must be rejected")
    assert(runtime.IsInitialized, "duplicate initialization must preserve the current session")
    assert(not runtime.IsFaulted, "duplicate initialization must not fault a healthy Runtime")

    var after_duplicate: Dictionary = runtime.GetWorldSnapshot()
    assert(
        int(after_duplicate.get("worldTimeMilli", -1)) == int(before_duplicate.get("worldTimeMilli", -2)),
        "duplicate initialization must preserve the current world's clock"
    )
    assert(
        int(after_duplicate.get("logicalTimeMilli", -1)) == int(before_duplicate.get("logicalTimeMilli", -2)),
        "duplicate initialization must preserve the current logical clock"
    )

    # D3/D5: leaving the SceneTree must dispose the session and clear ownership.
    remove_child(runtime)
    assert(runtime.IsDisposed, "Runtime must report successful session disposal on exit")
    assert(not runtime.IsInitialized, "exited Runtime must no longer expose an initialized session")

    # D6: exiting the SceneTree is terminal; the detached node cannot be revived.
    var reinitialize_after_exit: bool = runtime.InitializeWorld()
    assert(not reinitialize_after_exit, "disposed Runtime must reject reinitialization")
    assert(runtime.IsDisposed, "rejected reinitialization must preserve disposed state")
    assert(not runtime.IsInitialized, "disposed Runtime must remain without a session")
    runtime.queue_free()

    print(
        "[WorldV2LifecycleProbe] lifecycle probe passed",
        " initialization_faults=", _fault_messages.size(),
        " recovery=true duplicate_rejected=true disposed=true post_exit_rejected=true"
    )

func _on_runtime_faulted(message: String) -> void:
    _fault_messages.append(message)
    print("[WorldV2LifecycleProbe] expected runtime fault: ", message)
