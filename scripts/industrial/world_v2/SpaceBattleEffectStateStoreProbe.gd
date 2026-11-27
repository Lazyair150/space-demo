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
    # Use the actual Parser Runtime to create its nested schema-5 checkpoint.
    # A hand-written {"schemaVersion": 2} placeholder previously hid the mismatch
    # between the Space envelope schema and the nested Parser runtime schema.
    var parser_definition := SpaceOreParserDefinition.new()
    parser_definition.parser_id = &"probe-checkpoint-parser"
    parser_definition.definition_version = 1
    parser_definition.production_percentage = 100
    parser_definition.shape_processing_rate_per_second = {"圆罐": 1.0}
    parser_definition.progress_per_jar_by_shape = {"圆罐": 2.0}
    var parser_runtime := SpaceOreParserRuntime.new()
    var parser_initialized := parser_runtime.initialize(parser_definition, "probe-checkpoint-parser-instance", ["圆罐"])
    if not bool(parser_initialized.get("success", false)):
        return _failure("real Parser Runtime fixture initialization failed: " + String(parser_initialized.get("reason", "")))
    if not bool(parser_runtime.ingest_stone("probe-parser-stone", "圆罐", 2.5).get("success", false)):
        return _failure("real Parser Runtime fixture rejected accepted stone volume")
    if not bool(parser_runtime.advance(1000).get("success", false)):
        return _failure("real Parser Runtime fixture could not advance")
    var parser_runtime_state := parser_runtime.capture_state()
    if int(parser_runtime_state.get("schemaVersion", 0)) != SpaceOreParserRuntime.STATE_SCHEMA_VERSION:
        return _failure("Parser Runtime capture did not expose its current schema version")
    var parser_runtime_restore := SpaceOreParserRuntime.new()
    if not bool(parser_runtime_restore.initialize(parser_definition, "probe-checkpoint-parser-instance", ["圆罐"]).get("success", false)):
        return _failure("Parser Runtime restore fixture initialization failed")
    var parser_restore_result := parser_runtime_restore.restore_state(parser_runtime_state)
    if not bool(parser_restore_result.get("success", false)):
        return _failure("Parser Runtime could not restore the exact checkpoint emitted by capture_state: " + String(parser_restore_result.get("reason", "")))

    var runtime_checkpoint := {
        "schemaVersion": 2,
        "loadoutIdentity": identity.duplicate(true),
        "jarExecutionCheckpointJson": "{\"schemaVersion\":2,\"kind\":\"world-v2-execution-checkpoint\"}",
        "spaceClockRemainderMilli": 0.375,
        "runState": {"schemaVersion": 1, "score": 250, "wave": 3, "segment": "精英"},
        "oreParserState": {
            "schemaVersion": 2,
            "parserRuntime": parser_runtime_state,
            "nextPickupSequence": 7,
            "dropRngState": 8817264546339,
            "pendingPickups": [
                {"pickupId": "probe-pickup-6", "stoneType": "圆罐", "volume": 2.0, "positionX": 10.0, "positionY": 20.0}
            ]
        }
    }
    var runtime_validation_error := store._runtime_checkpoint_validation_error(runtime_checkpoint, identity)
    if not runtime_validation_error.is_empty():
        return _failure("store rejected a real current Parser Runtime checkpoint: " + runtime_validation_error)
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

    var unsupported_parser_runtime := runtime_checkpoint.duplicate(true)
    unsupported_parser_runtime["oreParserState"]["parserRuntime"]["schemaVersion"] = SpaceOreParserRuntime.STATE_SCHEMA_VERSION + 1
    var unsupported_reason := store._runtime_checkpoint_validation_error(unsupported_parser_runtime, identity)
    if unsupported_reason.is_empty() or not unsupported_reason.contains("parserRuntime.schemaVersion"):
        _cleanup(absolute_path)
        return _failure("store did not report an explicit unsupported nested Parser Runtime schema")

    # Legacy nested parser schemas remain supported by restore_state and must not
    # be broken by the persistence layer's current-schema correction.
    var legacy_parser_state := parser_runtime_state.duplicate(true)
    legacy_parser_state["schemaVersion"] = 2
    legacy_parser_state.erase("producedJarCountByShape")
    legacy_parser_state.erase("coreImportReceipts")
    legacy_parser_state.erase("coreImportReceiptHistoryComplete")
    var legacy_runtime_checkpoint := runtime_checkpoint.duplicate(true)
    legacy_runtime_checkpoint["oreParserState"]["parserRuntime"] = legacy_parser_state
    var legacy_validation_error := store._runtime_checkpoint_validation_error(legacy_runtime_checkpoint, identity)
    if not legacy_validation_error.is_empty():
        _cleanup(absolute_path)
        return _failure("store rejected a legacy Parser Runtime schema still supported by restore_state: " + legacy_validation_error)

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
    return {"passed": true, "schemaVersion": 3, "domains": 6, "parserRuntimeSchema": SpaceOreParserRuntime.STATE_SCHEMA_VERSION, "legacyParserSchemaAccepted": true}


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
    definition.stack_policy = BuffDefinition.StackPolicy.ADD_STACK
    definition.modifiers = [
        {"stat": &"probe_attack", "stage": StatCalculator.Stage.FLAT, "value": 5.0}
    ]
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

    var source_stats := StatCalculator.new()
    var restored_stats := StatCalculator.new()
    var source := StatusEffectManager.new()
    var restored := StatusEffectManager.new()
    source.bind_stats(source_stats)
    restored.bind_stats(restored_stats)

    var applied := source.apply_order_event("checkpoint-probe-event", frozen_definition)
    if applied == null:
        return _finish_effect_probe("source manager could not apply probe event", source, restored, source_stats, restored_stats)
    var stacked := source.apply_order_event("checkpoint-probe-event-2", frozen_definition)
    if stacked == null or stacked.stacks != 2:
        return _finish_effect_probe("source manager did not apply the declared ADD_STACK policy", source, restored, source_stats, restored_stats)
    applied.remaining = 3.5
    if source_stats.modifier_count(&"probe_attack") != 1 or not is_equal_approx(source_stats.value_of(&"probe_attack", 20.0), 30.0):
        return _finish_effect_probe("source manager did not register the two-stack StatCalculator modifier", source, restored, source_stats, restored_stats)
    var snapshot := source.capture_runtime_state()
    var definition_resolver := func(definition_id: String, version: int) -> BuffDefinition:
        return catalog.resolve_buff(definition_id, version)
    var target_resolver := func(_target_key: String) -> Node:
        return null
    if not restored.restore_runtime_state(snapshot, definition_resolver, target_resolver):
        return _finish_effect_probe("manager rejected a valid exact-version effect snapshot", source, restored, source_stats, restored_stats)
    if restored.count() != 1 or not restored.has_processed_order_event("checkpoint-probe-event") or not restored.has_processed_order_event("checkpoint-probe-event-2"):
        return _finish_effect_probe("restored effect/event identity was lost", source, restored, source_stats, restored_stats)
    if absf(restored.remaining(definition.id) - 3.5) > 0.000001 or restored.stacks(definition.id) != 2:
        return _finish_effect_probe("restored Buff duration or stacks changed", source, restored, source_stats, restored_stats)
    if restored_stats.modifier_count(&"probe_attack") != 1 or not is_equal_approx(restored_stats.value_of(&"probe_attack", 20.0), 30.0):
        return _finish_effect_probe("restored StatCalculator modifier does not match the frozen two-stack Buff", source, restored, source_stats, restored_stats)

    var non_finite_snapshot := snapshot.duplicate(true)
    non_finite_snapshot["instances"][0]["remaining"] = INF
    if restored.restore_runtime_state(non_finite_snapshot, definition_resolver, target_resolver):
        return _finish_effect_probe("non-finite Buff duration was accepted", source, restored, source_stats, restored_stats)
    if restored.count() != 1 or absf(restored.remaining(definition.id) - 3.5) > 0.000001 or restored_stats.modifier_count(&"probe_attack") != 1 or not is_equal_approx(restored_stats.value_of(&"probe_attack", 20.0), 30.0):
        return _finish_effect_probe("rejected non-finite restore partially mutated live Buff or stats", source, restored, source_stats, restored_stats)

    var wrong_version_snapshot := snapshot.duplicate(true)
    wrong_version_snapshot["instances"][0]["definitionVersion"] = 3
    if restored.restore_runtime_state(wrong_version_snapshot, definition_resolver, target_resolver):
        return _finish_effect_probe("wrong exact Buff definition version was accepted", source, restored, source_stats, restored_stats)
    if restored.count() != 1 or absf(restored.remaining(definition.id) - 3.5) > 0.000001 or restored_stats.modifier_count(&"probe_attack") != 1 or not is_equal_approx(restored_stats.value_of(&"probe_attack", 20.0), 30.0):
        return _finish_effect_probe("rejected version mismatch partially mutated live Buff or stats", source, restored, source_stats, restored_stats)

    var unresolved_target_snapshot := snapshot.duplicate(true)
    unresolved_target_snapshot["instances"][0]["targetKey"] = "missing-target"
    if restored.restore_runtime_state(unresolved_target_snapshot, definition_resolver, target_resolver):
        return _finish_effect_probe("unresolved stable Buff target was silently restored", source, restored, source_stats, restored_stats)
    if restored.count() != 1 or absf(restored.remaining(definition.id) - 3.5) > 0.000001 or restored_stats.modifier_count(&"probe_attack") != 1 or not is_equal_approx(restored_stats.value_of(&"probe_attack", 20.0), 30.0):
        return _finish_effect_probe("rejected target restore partially mutated live Buff or stats", source, restored, source_stats, restored_stats)

    restored.apply_order_event("checkpoint-probe-event", frozen_definition)
    if restored.count() != 1 or absf(restored.remaining(definition.id) - 3.5) > 0.000001 or restored.stacks(definition.id) != 2 or restored_stats.modifier_count(&"probe_attack") != 1:
        return _finish_effect_probe("replayed processed event duplicated, refreshed, or re-registered the restored Buff", source, restored, source_stats, restored_stats)
    restored.advance(3.5)
    if restored.count() != 0 or restored_stats.modifier_count(&"probe_attack") != 0 or not is_equal_approx(restored_stats.value_of(&"probe_attack", 20.0), 20.0):
        return _finish_effect_probe("expired restored Buff did not remove its StatCalculator modifier", source, restored, source_stats, restored_stats)
    return _finish_effect_probe("", source, restored, source_stats, restored_stats)


## Release every Node created by the RefCounted probe on both success and failure paths.
static func _finish_effect_probe(
    reason: String,
    source: StatusEffectManager,
    restored: StatusEffectManager,
    source_stats: StatCalculator,
    restored_stats: StatCalculator
) -> Dictionary:
    source.clear_all()
    restored.clear_all()
    source.free()
    restored.free()
    source_stats.clear()
    restored_stats.clear()
    source_stats.free()
    restored_stats.free()
    if reason.is_empty():
        return {"passed": true}
    return {"passed": false, "reason": reason}

static func _cleanup(absolute_path: String) -> void:
    for suffix in ["", ".pending", ".previous"]:
        if FileAccess.file_exists(absolute_path + suffix):
            DirAccess.remove_absolute(absolute_path + suffix)

static func _failure(reason: String) -> Dictionary:
    return {"passed": false, "reason": reason}
