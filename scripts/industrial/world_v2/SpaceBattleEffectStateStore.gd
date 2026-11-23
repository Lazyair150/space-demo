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
    var runtime_checkpoint: Variant = payload.get("runtimeCheckpoint", null)
    return runtime_checkpoint is Dictionary and _valid_runtime_checkpoint(runtime_checkpoint, identity)

func _valid_runtime_checkpoint(runtime_checkpoint: Dictionary, loadout_identity: Dictionary) -> bool:
    if int(runtime_checkpoint.get("schemaVersion", 0)) != 2:
        return false
    if runtime_checkpoint.get("loadoutIdentity", {}) != loadout_identity:
        return false
    var jar_json: Variant = runtime_checkpoint.get("jarExecutionCheckpointJson", null)
    var clock: Variant = runtime_checkpoint.get("spaceClockRemainderMilli", null)
    var parser: Variant = runtime_checkpoint.get("oreParserState", null)
    var run_state: Variant = runtime_checkpoint.get("runState", null)
    if typeof(jar_json) != TYPE_STRING or String(jar_json).is_empty():
        return false
    if not (run_state is Dictionary) or int(run_state.get("schemaVersion", 0)) != 1:
        return false
    if typeof(run_state.get("score", null)) != TYPE_INT or int(run_state.get("score", -1)) < 0:
        return false
    if typeof(run_state.get("wave", null)) != TYPE_INT or int(run_state.get("wave", -1)) < 0:
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
    if typeof(next_pickup_sequence) != TYPE_INT or int(next_pickup_sequence) <= 0:
        return false
    if typeof(drop_rng_state) != TYPE_INT:
        return false
    if not (parser.get("pendingPickups", null) is Array):
        return false
    return true

func _valid_loadout_identity(identity: Variant) -> bool:
    if not (identity is Dictionary):
        return false
    return (
        not String(identity.get("shipWorldId", "")).is_empty()
        and not String(identity.get("loadoutId", "")).is_empty()
        and int(identity.get("loadoutVersion", 0)) > 0
        and String(identity.get("loadoutFingerprint", "")).length() == 64
    )
