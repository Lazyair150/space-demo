extends RefCounted
class_name SpaceBattleEffectStateStoreProbe
## Verifies that effect/dispatcher and Jar/Space runtime state share one replaceable save payload.

static func run() -> Dictionary:
    var path := "user://space_battle_runtime_checkpoint_probe.json"
    var absolute_path := ProjectSettings.globalize_path(path)
    var store := SpaceBattleEffectStateStore.new(path)
    var identity := {
        "shipWorldId": "probe-ship-world",
        "loadoutId": "probe-loadout",
        "loadoutVersion": 3,
        "loadoutFingerprint": "a".repeat(64)
    }
    var runtime_checkpoint := {
        "schemaVersion": 1,
        "loadoutIdentity": identity.duplicate(true),
        "jarExecutionCheckpointJson": "{\"schemaVersion\":2,\"kind\":\"world-v2-execution-checkpoint\"}",
        "spaceClockRemainderMilli": 0.375,
        "oreParserState": {
            "schemaVersion": 2,
            "parserRuntime": {"schemaVersion": 2},
            "nextPickupSequence": 7,
            "dropRngState": 88172645463393265,
            "pendingPickups": [
                {"pickupId": "probe-pickup-6", "stoneType": "圆罐", "volume": 2.0, "positionX": 10.0, "positionY": 20.0}
            ]
        }
    }
    var effects := {"activeEffects": [], "processedOrderEventIds": ["event-1"]}
    var dispatcher := {"schemaVersion": 1, "processedEventIds": ["event-1"]}

    if not store.save(effects, dispatcher, identity, runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("unified battle checkpoint save failed")
    var loaded := store.load(identity)
    if int(loaded.get("schemaVersion", 0)) != 2:
        _cleanup(absolute_path)
        return _failure("unified save did not load as schema v2")
    if loaded.get("effectState", {}) != effects or loaded.get("dispatcherState", {}) != dispatcher:
        _cleanup(absolute_path)
        return _failure("effect/dispatcher state was not preserved in the unified snapshot")
    if loaded.get("runtimeCheckpoint", {}) != runtime_checkpoint:
        _cleanup(absolute_path)
        return _failure("Jar/Space runtime checkpoint was not preserved in the unified snapshot")

    var invalid_runtime := runtime_checkpoint.duplicate(true)
    invalid_runtime["jarExecutionCheckpointJson"] = ""
    if store.save(effects, dispatcher, identity, invalid_runtime):
        _cleanup(absolute_path)
        return _failure("store accepted an incomplete Jar/Space checkpoint")
    var after_rejection := store.load(identity)
    if after_rejection.get("runtimeCheckpoint", {}) != runtime_checkpoint:
        _cleanup(absolute_path)
        return _failure("rejected save replaced the previous valid battle checkpoint")

    _cleanup(absolute_path)
    return {"passed": true, "schemaVersion": 2, "domains": 5}

static func _cleanup(absolute_path: String) -> void:
    for suffix in ["", ".pending", ".previous"]:
        if FileAccess.file_exists(absolute_path + suffix):
            DirAccess.remove_absolute(absolute_path + suffix)

static func _failure(reason: String) -> Dictionary:
    return {"passed": false, "reason": reason}
