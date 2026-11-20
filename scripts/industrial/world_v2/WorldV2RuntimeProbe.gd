extends Node

@onready var runtime: Node = $WorldV2Runtime
var _elapsed := 0.0

func _ready() -> void:
    runtime.RuntimeReady.connect(_on_runtime_ready)
    runtime.RuntimeFaulted.connect(_on_runtime_faulted)
    print("[WorldV2Probe] scene ready")
    # The child Runtime node enters _Ready before this parent probe.
    # Its RuntimeReady signal may already have fired, so inspect its state too.
    if runtime.IsInitialized:
        _print_snapshot()

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed >= 1.0:
        _elapsed = 0.0
        if runtime.IsInitialized:
            _print_snapshot()

func _on_runtime_ready() -> void:
    print("[WorldV2Probe] runtime ready")
    _print_snapshot()

func _on_runtime_faulted(message: String) -> void:
    push_error("[WorldV2Probe] runtime fault: " + message)

func _print_snapshot() -> void:
    var state: Dictionary = runtime.GetWorldSnapshot()
    print(
        "[WorldV2Probe] world=", state.get("worldTimeMilli", -1),
        " logical=", state.get("logicalTimeMilli", -1),
        " paused=", state.get("isPaused", false),
        " master=", state.get("master", {}).get("name", "-"),
        " slave=", state.get("slave", {}).get("name", "-")
    )
