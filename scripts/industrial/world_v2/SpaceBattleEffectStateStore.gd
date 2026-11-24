extends RefCounted
class_name SpaceBattleEffectStateStore
## One replaceable save snapshot for Space effects, dispatcher EventIds, Jar Core checkpoint,
## Space parser/pickups, and the shared simulation clock. A pending file and recoverable
## previous snapshot protect against interrupted replacement; platform durability is separate.

var _path: String

func _init(path: String = "user://battle_effect_state.json") -> void:
    _path = path

## Legacy three-domain save remains supported. Supplying runtime_checkpoint upgrades the
## snapshot to schema v3 and commits all cross-domain state in the same file replacement.
func save(
    effect_state: Dictionary,
    dispatcher_state: Dictionary,
    loadout_identity: Dictionary,
    runtime_checkpoint: Dictionary = {}
) -> bool:
    if not _valid_loadout_identity(loadout_identity):
        push_error("Battle save requires a complete frozen loadout identity")
        return false
    var schema_version := 1
    var payload := {
        "schemaVersion": schema_version,
        "loadoutIdentity": loadout_identity.duplicate(true),
        "effectState": effect_state.duplicate(true),
        "dispatcherState": dispatcher_state.duplicate(true)
    }
    if not runtime_checkpoint.is_empty():
        if not _valid_runtime_checkpoint(runtime_checkpoint, loadout_identity):
            push_error("Battle runtime checkpoint is incomplete or does not match the frozen loadout")
            return false
        payload["schemaVersion"] = 3
        payload["runtimeCheckpoint"] = runtime_checkpoint.duplicate(true)
        if not _valid_snapshot(payload):
            push_error("Battle schema-v3 snapshot failed its complete persistence contract")
            return false
    return _replace_snapshot(payload)

func _replace_snapshot(payload: Dictionary) -> bool:
    var absolute_path := ProjectSettings.globalize_path(_path)
    var temporary_path := absolute_path + ".pending"
    var file := FileAccess.open(temporary_path, FileAccess.WRITE)
    if file == null:
        push_error("Unable to open battle snapshot temporary file: " + temporary_path)
        return false
    file.store_string(JSON.stringify(payload))
    file.flush()
    var write_error := file.get_error()
    file.close()
    if write_error != OK:
        DirAccess.remove_absolute(temporary_path)
        push_error("Unable to flush battle snapshot")
        return false

    if FileAccess.file_exists(absolute_path):
        var backup_path := absolute_path + ".previous"
        if FileAccess.file_exists(backup_path):
            DirAccess.remove_absolute(backup_path)
        var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
        if backup_error != OK:
            DirAccess.remove_absolute(temporary_path)
            push_error("Unable to stage previous battle snapshot")
            return false
        var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
        if replace_error != OK:
            DirAccess.rename_absolute(backup_path, absolute_path)
            push_error("Unable to replace battle snapshot")
            return false
        DirAccess.remove_absolute(backup_path)
        return true

    var rename_error := DirAccess.rename_absolute(temporary_path, absolute_path)
    if rename_error != OK:
        DirAccess.remove_absolute(temporary_path)
        push_error("Unable to commit battle snapshot")
        return false
    return true

func load(expected_loadout_identity: Dictionary = {}) -> Dictionary:
    var absolute_path := ProjectSettings.globalize_path(_path)
    var candidates := [absolute_path, absolute_path + ".previous"]
    for candidate in candidates:
        if not FileAccess.file_exists(candidate):
            continue
        var file := FileAccess.open(candidate, FileAccess.READ)
        if file == null:
            continue
        var parsed: Variant = JSON.parse_string(file.get_as_text())
        file.close()
        if not (parsed is Dictionary) or not _valid_snapshot(parsed):
            continue
        if not expected_loadout_identity.is_empty() and parsed.get("loadoutIdentity", {}) != expected_loadout_identity:
            continue
        return parsed.duplicate(true)
    push_error("No valid matching battle snapshot or recoverable previous snapshot exists")
    return {}

func _valid_snapshot(payload: Dictionary) -> bool:
    var version := int(payload.get("schemaVersion", 0))
    var identity: Variant = payload.get("loadoutIdentity", null)
    var effects: Variant = payload.get("effectState", null)
    var dispatcher: Variant = payload.get("dispatcherState", null)
    if not _valid_loadout_identity(identity) or not (effects is Dictionary) or not (dispatcher is Dictionary):
        return false
    if version == 1:
        return not payload.has("runtimeCheckpoint")
    if version != 3:
        return false
    if int(effects.get("schemaVersion", 0)) != 1 or not (effects.get("instances", null) is Array) or not (effects.get("processedOrderEventIds", null) is Array):
        return false
    if not _valid_dispatcher_state(dispatcher, identity, effects.get("processedOrderEventIds", [])):
        return false
    var runtime_checkpoint: Variant = payload.get("runtimeCheckpoint", null)
    return runtime_checkpoint is Dictionary and _valid_runtime_checkpoint(runtime_checkpoint, identity)

func _valid_dispatcher_state(dispatcher: Dictionary, identity: Dictionary, effect_event_ids: Array) -> bool:
    if int(dispatcher.get("schemaVersion", 0)) != 1:
        return false
    if String(dispatcher.get("shipWorldId", "")) != String(identity.get("shipWorldId", "")):
        return false
    if String(dispatcher.get("loadoutId", "")) != String(identity.get("loadoutId", "")):
        return false
    var dispatcher_version: Variant = dispatcher.get("loadoutVersion", null)
    var dispatcher_version_is_integer := typeof(dispatcher_version) == TYPE_INT
    if typeof(dispatcher_version) == TYPE_FLOAT:
        var dispatcher_version_number := float(dispatcher_version)
        dispatcher_version_is_integer = is_finite(dispatcher_version_number) and absf(dispatcher_version_number) <= 9007199254740991.0 and floor(dispatcher_version_number) == dispatcher_version_number
    if not dispatcher_version_is_integer or int(dispatcher_version) != int(identity.get("loadoutVersion", 0)):
        return false
    if String(dispatcher.get("loadoutFingerprint", "")) != String(identity.get("loadoutFingerprint", "")):
        return false
    var raw_ids: Variant = dispatcher.get("processedEventIds", null)
    if not (raw_ids is Array):
        return false
    var world_instance_id := String(dispatcher.get("jarWorldInstanceId", ""))
    if raw_ids.is_empty():
        if not world_instance_id.is_empty():
            return false
    elif world_instance_id.is_empty():
        return false
    var dispatcher_ids := {}
    for raw_id in raw_ids:
        if typeof(raw_id) != TYPE_STRING:
            return false
        var event_id := String(raw_id)
        if event_id.is_empty() or dispatcher_ids.has(event_id):
            return false
        if not event_id.begins_with(world_instance_id + ":"):
            return false
        var suffix := event_id.trim_prefix(world_instance_id + ":").split(":")
        if suffix.size() != 2 or not suffix[0].is_valid_int() or not suffix[1].is_valid_int():
            return false
        var demand_id := int(suffix[0])
        var cycle_sequence := int(suffix[1])
        if demand_id <= 0 or cycle_sequence <= 0 or str(demand_id) != suffix[0] or str(cycle_sequence) != suffix[1]:
            return false
        dispatcher_ids[event_id] = true
    if effect_event_ids.size() != dispatcher_ids.size():
        return false
    for raw_id in effect_event_ids:
        if typeof(raw_id) != TYPE_STRING or not dispatcher_ids.has(String(raw_id)):
            return false
    return true

func _valid_runtime_checkpoint(runtime_checkpoint: Dictionary, loadout_identity: Dictionary) -> bool:
    var runtime_schema := int(runtime_checkpoint.get("schemaVersion", 0))
    if runtime_schema not in [2, 3]:
        return false
    if runtime_checkpoint.get("loadoutIdentity", {}) != loadout_identity:
        return false
    if runtime_schema == 3:
        var stage_runtime: Variant = runtime_checkpoint.get("stageRuntime", null)
        if not (stage_runtime is Dictionary) or int(stage_runtime.get("schemaVersion", 0)) != 1:
            return false
        if String(stage_runtime.get("stageId", "")).strip_edges().is_empty() or int(stage_runtime.get("definitionVersion", 0)) <= 0:
            return false
        if stage_runtime.get("loadoutIdentity", {}) != loadout_identity:
            return false
        if not (stage_runtime.get("directorState", null) is Dictionary) or not (stage_runtime.get("objectiveState", null) is Dictionary):
            return false
        if typeof(stage_runtime.get("encountersCompleted", null)) != TYPE_BOOL or typeof(stage_runtime.get("completionEmitted", null)) != TYPE_BOOL:
            return false
    var jar_json: Variant = runtime_checkpoint.get("jarExecutionCheckpointJson", null)
    var clock: Variant = runtime_checkpoint.get("spaceClockRemainderMilli", null)
    var parser: Variant = runtime_checkpoint.get("oreParserState", null)
    var run_state: Variant = runtime_checkpoint.get("runState", null)
    if typeof(jar_json) != TYPE_STRING or String(jar_json).is_empty():
        return false
    if not (run_state is Dictionary) or int(run_state.get("schemaVersion", 0)) != 1:
        return false
    var score_value: Variant = run_state.get("score", null)
    var wave_value: Variant = run_state.get("wave", null)
    if not _is_integral_json_number(score_value) or int(score_value) < 0:
        return false
    if not _is_integral_json_number(wave_value) or int(wave_value) < 0:
        return false
    if typeof(run_state.get("segment", null)) != TYPE_STRING or not ["", "热身", "压力", "精英", "喘息"].has(String(run_state.get("segment", ""))):
        return false
    var run_wave := int(run_state.get("wave", 0))
    var run_segment := String(run_state.get("segment", ""))
    if run_wave == 0:
        if not run_segment.is_empty():
            return false
    else:
        var expected_segments := ["热身", "压力", "精英", "喘息"]
        if run_segment != String(expected_segments[(run_wave - 1) % expected_segments.size()]):
            return false
    if (typeof(clock) != TYPE_INT and typeof(clock) != TYPE_FLOAT) or not is_finite(float(clock)) or float(clock) < 0.0 or float(clock) >= 1.0:
        return false
    if not (parser is Dictionary) or int(parser.get("schemaVersion", 0)) != 2:
        return false
    var parser_runtime: Variant = parser.get("parserRuntime", null)
    var next_pickup_sequence: Variant = parser.get("nextPickupSequence", null)
    var drop_rng_state: Variant = parser.get("dropRngState", null)
    if not (parser_runtime is Dictionary) or int(parser_runtime.get("schemaVersion", 0)) != 2:
        return false
    if not _is_integral_json_number(next_pickup_sequence) or int(next_pickup_sequence) <= 0:
        return false
    if not _is_integral_json_number(drop_rng_state):
        return false
    if not (parser.get("pendingPickups", null) is Array):
        return false
    return true

func _valid_loadout_identity(identity: Variant) -> bool:
    if not (identity is Dictionary):
        return false
    var version_value: Variant = identity.get("loadoutVersion", null)
    return (
        not String(identity.get("shipWorldId", "")).is_empty()
        and not String(identity.get("loadoutId", "")).is_empty()
        and _is_integral_json_number(version_value) and int(version_value) > 0
        and String(identity.get("loadoutFingerprint", "")).length() == 64
    )

func _is_integral_json_number(value: Variant) -> bool:
    if typeof(value) == TYPE_INT:
        return true
    if typeof(value) != TYPE_FLOAT:
        return false
    var numeric := float(value)
    # JSON round-trips integral GDScript numbers as floats. Reject imprecise values.
    return is_finite(numeric) and absf(numeric) <= 9007199254740991.0 and floor(numeric) == numeric
