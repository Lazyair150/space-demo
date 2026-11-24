extends RefCounted
class_name SpaceBattleEffectStateStoreProbe
## Verifies that effect/dispatcher and Jar/Space runtime state share one replaceable save payload.

static func run() -> Dictionary:
    var effect_restore := _probe_effect_manager_restore()
    if not bool(effect_restore.get("passed", false)):
        return _failure("StatusEffectManager restore probe failed: " + String(effect_restore.get("reason", "")))
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
        "schemaVersion": 2,
        "loadoutIdentity": identity.duplicate(true),
        "jarExecutionCheckpointJson": "{\"schemaVersion\":2,\"kind\":\"world-v2-execution-checkpoint\"}",
        "spaceClockRemainderMilli": 0.375,
        "runState": {"schemaVersion": 1, "score": 250, "wave": 3, "segment": "精英"},
        "oreParserState": {
            "schemaVersion": 2,
            "parserRuntime": {"schemaVersion": 2},
            "nextPickupSequence": 7,
            "dropRngState": 8817264546339,
            "pendingPickups": [
                {"pickupId": "probe-pickup-6", "stoneType": "圆罐", "volume": 2.0, "positionX": 10.0, "positionY": 20.0}
            ]
        }
    }
    var event_id := "probe-jar-world:1:1"
    var effects := {"schemaVersion": 1, "instances": [], "processedOrderEventIds": [event_id]}
    var dispatcher := {
        "schemaVersion": 1,
        "shipWorldId": identity.shipWorldId,
        "loadoutId": identity.loadoutId,
        "loadoutVersion": identity.loadoutVersion,
        "loadoutFingerprint": identity.loadoutFingerprint,
        "jarWorldInstanceId": "probe-jar-world",
        "processedEventIds": [event_id]
    }

    if not store.save(effects, dispatcher, identity, runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("unified battle checkpoint save failed")
    var raw_file := FileAccess.open(absolute_path, FileAccess.READ)
    if raw_file == null:
        _cleanup(absolute_path)
        return _failure("unified checkpoint file is missing immediately after save")
    var raw_snapshot: Variant = JSON.parse_string(raw_file.get_as_text())
    raw_file.close()
    if not (raw_snapshot is Dictionary):
        _cleanup(absolute_path)
        return _failure("unified checkpoint file is not a JSON dictionary after save")
    if not store._valid_snapshot(raw_snapshot):
        _cleanup(absolute_path)
        return _failure("saved checkpoint failed validation after JSON roundtrip: " + JSON.stringify(raw_snapshot))
    var loaded := store.load(identity)
    if int(loaded.get("schemaVersion", 0)) != 3:
        _cleanup(absolute_path)
        return _failure("unified save did not load as schema v3")
    if not _matches_json_value(loaded.get("effectState", {}), effects) or not _matches_json_value(loaded.get("dispatcherState", {}), dispatcher):
        _cleanup(absolute_path)
        return _failure("effect/dispatcher state was not preserved in the unified snapshot")
    if not _matches_json_value(loaded.get("runtimeCheckpoint", {}), runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("Jar/Space runtime checkpoint was not preserved in the unified snapshot")

    var invalid_runtime := runtime_checkpoint.duplicate(true)
    invalid_runtime["jarExecutionCheckpointJson"] = ""
    if store.save(effects, dispatcher, identity, invalid_runtime):
        _cleanup(absolute_path)
        return _failure("store accepted an incomplete Jar/Space checkpoint")
    var after_rejection := store.load(identity)
    if not _matches_json_value(after_rejection.get("runtimeCheckpoint", {}), runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("rejected save replaced the previous valid battle checkpoint")

    var missing_rng_runtime := runtime_checkpoint.duplicate(true)
    missing_rng_runtime.oreParserState.erase("dropRngState")
    if store.save(effects, dispatcher, identity, missing_rng_runtime):
        _cleanup(absolute_path)
        return _failure("store accepted parser checkpoint without deterministic drop RNG state")
    var after_rng_rejection := store.load(identity)
    if not _matches_json_value(after_rng_rejection.get("runtimeCheckpoint", {}), runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("missing RNG rejection replaced the previous valid battle checkpoint")

    var mismatched_dispatcher := dispatcher.duplicate(true)
    mismatched_dispatcher["processedEventIds"] = []
    if store.save(effects, mismatched_dispatcher, identity, runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("store accepted a dispatcher/effect processed-event ledger mismatch")
    var after_dispatcher_rejection := store.load(identity)
    if not _matches_json_value(after_dispatcher_rejection.get("dispatcherState", {}), dispatcher):
        _cleanup(absolute_path)
        return _failure("mismatched dispatcher ledger replaced the previous valid checkpoint")

    var wrong_dispatcher_identity := dispatcher.duplicate(true)
    wrong_dispatcher_identity["loadoutFingerprint"] = "b".repeat(64)
    if store.save(effects, wrong_dispatcher_identity, identity, runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("store accepted a dispatcher from a different frozen loadout")

    var malformed_event_dispatcher := dispatcher.duplicate(true)
    malformed_event_dispatcher["processedEventIds"] = ["probe-jar-world:01:1"]
    var malformed_event_effects := effects.duplicate(true)
    malformed_event_effects["processedOrderEventIds"] = ["probe-jar-world:01:1"]
    if store.save(malformed_event_effects, malformed_event_dispatcher, identity, runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("store accepted a non-canonical Jar event identity")

    var invalid_effect_state := {"activeEffects": [], "processedOrderEventIds": [event_id]}
    if store.save(invalid_effect_state, dispatcher, identity, runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("store accepted an effect payload outside StatusEffectManager schema v1")
    var after_effect_rejection := store.load(identity)
    if not _matches_json_value(after_effect_rejection.get("effectState", {}), effects):
        _cleanup(absolute_path)
        return _failure("invalid effect state replaced the previous valid battle checkpoint")

    var mismatched_wave_runtime := runtime_checkpoint.duplicate(true)
    mismatched_wave_runtime.runState.segment = "压力"
    if store.save(effects, dispatcher, identity, mismatched_wave_runtime):
        _cleanup(absolute_path)
        return _failure("store accepted a wave/segment mismatch")
    var after_wave_rejection := store.load(identity)
    if not _matches_json_value(after_wave_rejection.get("runtimeCheckpoint", {}), runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("wave/segment mismatch replaced the previous valid battle checkpoint")

    var missing_run_state := runtime_checkpoint.duplicate(true)
    missing_run_state.erase("runState")
    if store.save(effects, dispatcher, identity, missing_run_state):
        _cleanup(absolute_path)
        return _failure("store accepted a Jar/Space checkpoint without transient run progression")
    var after_run_state_rejection := store.load(identity)
    if not _matches_json_value(after_run_state_rejection.get("runtimeCheckpoint", {}), runtime_checkpoint):
        _cleanup(absolute_path)
        return _failure("missing run-state rejection replaced the previous valid battle checkpoint")

    _cleanup(absolute_path)
    return {"passed": true, "schemaVersion": 3, "domains": 6}


## Compare values after the same JSON serialization boundary used by the durable store.
## Godot may decode integral JSON numbers as floats, so raw in-memory Variant equality
## is not a valid assertion for persisted snapshots.
static func _matches_json_value(actual: Variant, expected: Variant) -> bool:
    var normalized_expected: Variant = JSON.parse_string(JSON.stringify(expected))
    return actual == normalized_expected

## Exercises real Buff instance reconstruction and processed-event idempotency.
static func _probe_effect_manager_restore() -> Dictionary:
    var definition := BuffDefinition.new()
    definition.id = &"checkpoint_probe_effect"
    definition.definition_version = 2
    definition.duration = 10.0
    definition.max_stacks = 3
    if not definition.is_valid():
        return {"passed": false, "reason": "synthetic exact-version Buff definition is invalid"}

    var catalog := SpaceEffectCatalog.new()
    if not catalog.register_buff(definition):
        return {"passed": false, "reason": "effect catalog rejected the exact-version probe definition"}
    definition.duration = 20.0
    var exposed_definition := catalog.resolve_buff("checkpoint_probe_effect", 2)
    if exposed_definition == null or absf(exposed_definition.duration - 10.0) > 0.000001:
        return {"passed": false, "reason": "catalog registration was not isolated from source Resource mutation"}
    exposed_definition.duration = 1.0
    var frozen_definition := catalog.resolve_buff("checkpoint_probe_effect", 2)
    if frozen_definition == null or absf(frozen_definition.duration - 10.0) > 0.000001:
        return {"passed": false, "reason": "catalog leaked its owned Resource to a caller"}

    var source := StatusEffectManager.new()
    var applied := source.apply_order_event("checkpoint-probe-event", frozen_definition)
    if applied == null:
        return {"passed": false, "reason": "source manager could not apply probe event"}
    applied.remaining = 3.5
    applied.stacks = 2
    var snapshot := source.capture_runtime_state()

    var restored := StatusEffectManager.new()
    var definition_resolver := func(definition_id: String, version: int) -> BuffDefinition:
        return catalog.resolve_buff(definition_id, version)
    var target_resolver := func(_target_key: String) -> Node:
        return null
    if not restored.restore_runtime_state(snapshot, definition_resolver, target_resolver):
        return {"passed": false, "reason": "manager rejected a valid exact-version effect snapshot"}
    if restored.count() != 1 or not restored.has_processed_order_event("checkpoint-probe-event"):
        return {"passed": false, "reason": "restored effect/event identity was lost"}
    if absf(restored.remaining(definition.id) - 3.5) > 0.000001 or restored.stacks(definition.id) != 2:
        return {"passed": false, "reason": "restored Buff duration or stacks changed"}

    var non_finite_snapshot := snapshot.duplicate(true)
    non_finite_snapshot["instances"][0]["remaining"] = INF
    if restored.restore_runtime_state(non_finite_snapshot, definition_resolver, target_resolver):
        return {"passed": false, "reason": "non-finite Buff duration was accepted"}
    if restored.count() != 1 or absf(restored.remaining(definition.id) - 3.5) > 0.000001:
        return {"passed": false, "reason": "rejected non-finite restore partially mutated the live manager"}

    var wrong_version_snapshot := snapshot.duplicate(true)
    wrong_version_snapshot["instances"][0]["definitionVersion"] = 3
    if restored.restore_runtime_state(wrong_version_snapshot, definition_resolver, target_resolver):
        return {"passed": false, "reason": "wrong exact Buff definition version was accepted"}
    if restored.count() != 1 or absf(restored.remaining(definition.id) - 3.5) > 0.000001:
        return {"passed": false, "reason": "rejected version mismatch partially mutated the live manager"}

    var unresolved_target_snapshot := snapshot.duplicate(true)
    unresolved_target_snapshot["instances"][0]["targetKey"] = "missing-target"
    if restored.restore_runtime_state(unresolved_target_snapshot, definition_resolver, target_resolver):
        return {"passed": false, "reason": "unresolved stable Buff target was silently restored"}
    if restored.count() != 1 or absf(restored.remaining(definition.id) - 3.5) > 0.000001:
        return {"passed": false, "reason": "rejected target restore partially mutated the live manager"}

    restored.apply_order_event("checkpoint-probe-event", frozen_definition)
    if restored.count() != 1 or absf(restored.remaining(definition.id) - 3.5) > 0.000001:
        return {"passed": false, "reason": "replayed processed event duplicated or refreshed the restored Buff"}
    return {"passed": true}

static func _cleanup(absolute_path: String) -> void:
    for suffix in ["", ".pending", ".previous"]:
        if FileAccess.file_exists(absolute_path + suffix):
            DirAccess.remove_absolute(absolute_path + suffix)

static func _failure(reason: String) -> Dictionary:
    return {"passed": false, "reason": reason}
