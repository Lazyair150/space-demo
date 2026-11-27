extends Node
## Two-process restart probe for the unified battle checkpoint.
##
## Process 1 (-- --mode=write) builds a schema-v3 snapshot from a real Parser Runtime
## and commits it to user://.
## Process 2 (-- --mode=restore) is a fresh engine process: it loads the committed
## snapshot, restores a Parser Runtime from the JSON-decoded checkpoint, and fails if
## any persisted domain no longer matches what the writer committed.
##
## The in-process contract probe never feeds the decoded checkpoint back into the
## Parser Runtime, so it cannot catch a snapshot that is structurally valid but
## unloadable after a restart.

const SNAPSHOT_PATH := "user://battle_checkpoint_restart_probe.json"
const PARSER_INSTANCE_ID := "restart-probe-parser-instance"
const PARSER_SHAPE := "圆罐"
const SHIP_WORLD_ID := "restart-probe-ship-world"
const LOADOUT_ID := "restart-probe-loadout"
const LOADOUT_VERSION := 3
const LOADOUT_FINGERPRINT := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
const JAR_WORLD_INSTANCE_ID := "restart-probe-jar-world"
const PROCESSED_EVENT_ID := "restart-probe-jar-world:1:7"
const FIRST_STONE_PICKUP_ID := "restart-probe-stone-a"
const PENDING_PICKUP_ID := "restart-probe-pickup-6"
const DROP_RNG_STATE := 8817264546339

func _ready() -> void:
	# Deferred so every Autoload is ready before the probe touches resources.
	call_deferred("_run")

func _run() -> void:
	var mode := _requested_mode()
	var result: Dictionary
	match mode:
		"write":
			result = _write_snapshot()
		"restore":
			result = _restore_snapshot()
		_:
			result = _failure("pass -- --mode=write or -- --mode=restore")
	if bool(result.get("passed", false)):
		print("[BattleCheckpointRestart] %s=%s" % [mode, String(result.get("marker", "passed"))])
		get_tree().quit(0)
		return
	push_error("[BattleCheckpointRestart] %s failed: %s" % [mode, String(result.get("reason", "unknown"))])
	get_tree().quit(1)

func _requested_mode() -> String:
	for argument in OS.get_cmdline_user_args():
		if String(argument).begins_with("--mode="):
			return String(argument).trim_prefix("--mode=")
	return ""

func _failure(reason: String) -> Dictionary:
	_remove_snapshot()
	return {"passed": false, "reason": reason}

func _remove_snapshot() -> void:
	var absolute_path := ProjectSettings.globalize_path(SNAPSHOT_PATH)
	for candidate in [absolute_path, absolute_path + ".pending", absolute_path + ".previous"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)

func _snapshot_exists() -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(SNAPSHOT_PATH))

func _loadout_identity() -> Dictionary:
	return {
		"shipWorldId": SHIP_WORLD_ID,
		"loadoutId": LOADOUT_ID,
		"loadoutVersion": LOADOUT_VERSION,
		"loadoutFingerprint": LOADOUT_FINGERPRINT
	}

func _new_parser_definition() -> SpaceOreParserDefinition:
	var definition := SpaceOreParserDefinition.new()
	definition.parser_id = &"restart-probe-parser"
	definition.definition_version = 1
	definition.production_percentage = 100
	definition.shape_processing_rate_per_second = {PARSER_SHAPE: 1.0}
	definition.progress_per_jar_by_shape = {PARSER_SHAPE: 2.0}
	return definition

func _new_parser_runtime() -> SpaceOreParserRuntime:
	var runtime := SpaceOreParserRuntime.new()
	runtime.initialize(_new_parser_definition(), PARSER_INSTANCE_ID, [PARSER_SHAPE])
	return runtime

func _effect_state() -> Dictionary:
	return {"schemaVersion": 1, "instances": [], "processedOrderEventIds": [PROCESSED_EVENT_ID]}

func _dispatcher_state() -> Dictionary:
	return {
		"schemaVersion": 1,
		"shipWorldId": SHIP_WORLD_ID,
		"loadoutId": LOADOUT_ID,
		"loadoutVersion": LOADOUT_VERSION,
		"loadoutFingerprint": LOADOUT_FINGERPRINT,
		"jarWorldInstanceId": JAR_WORLD_INSTANCE_ID,
		"processedEventIds": [PROCESSED_EVENT_ID]
	}

func _runtime_checkpoint(parser_runtime_state: Dictionary) -> Dictionary:
	return {
		"schemaVersion": 2,
		"loadoutIdentity": _loadout_identity(),
		"jarExecutionCheckpointJson": "{\"schemaVersion\":2,\"kind\":\"restart-probe-execution-checkpoint\"}",
		"spaceClockRemainderMilli": 0.375,
		"runState": {"schemaVersion": 1, "score": 250, "wave": 3, "segment": "精英"},
		"oreParserState": {
			"schemaVersion": 2,
			"parserRuntime": parser_runtime_state,
			"nextPickupSequence": 7,
			"dropRngState": DROP_RNG_STATE,
			"pendingPickups": [
				{
					"pickupId": PENDING_PICKUP_ID,
					"stoneType": PARSER_SHAPE,
					"volume": 2.0,
					"positionX": 10.0,
					"positionY": 20.0
				}
			]
		}
	}

func _write_snapshot() -> Dictionary:
	_remove_snapshot()
	var parser := _new_parser_runtime()
	var first_ingest := parser.ingest_stone(FIRST_STONE_PICKUP_ID, PARSER_SHAPE, 2.5)
	if not bool(first_ingest.get("success", false)) or bool(first_ingest.get("duplicate", false)):
		return _failure("writer could not ingest a fresh stone into the real Parser Runtime")
	if not bool(parser.advance(1000).get("success", false)):
		return _failure("writer could not advance the real Parser Runtime")
	var parser_runtime_state := parser.capture_state()
	if parser_runtime_state.is_empty():
		return _failure("real Parser Runtime did not expose a checkpoint state")
	var store := SpaceBattleEffectStateStore.new(SNAPSHOT_PATH)
	if not store.save(_effect_state(), _dispatcher_state(), _loadout_identity(), _runtime_checkpoint(parser_runtime_state)):
		return _failure("unified checkpoint save failed")
	if not _snapshot_exists():
		return _failure("checkpoint file is absent immediately after a successful save")
	return {"passed": true, "marker": "checkpoint-written"}

func _restore_snapshot() -> Dictionary:
	if not _snapshot_exists():
		return _failure("no checkpoint file exists; the writer process did not persist one")
	var identity := _loadout_identity()
	var store := SpaceBattleEffectStateStore.new(SNAPSHOT_PATH)
	var snapshot := store.load(identity)
	if snapshot.is_empty():
		return _failure("a freshly started process could not load the committed checkpoint")
	if int(snapshot.get("schemaVersion", 0)) != 3:
		return _failure("restored snapshot is not schema v3")

	var checkpoint: Variant = snapshot.get("runtimeCheckpoint", null)
	if not (checkpoint is Dictionary):
		return _failure("restored snapshot has no runtime checkpoint")
	var parser_envelope: Variant = checkpoint.get("oreParserState", null)
	if not (parser_envelope is Dictionary):
		return _failure("restored checkpoint has no ore parser envelope")
	var parser_runtime_state: Variant = parser_envelope.get("parserRuntime", null)
	if not (parser_runtime_state is Dictionary):
		return _failure("restored checkpoint has no parser runtime state")

	# The persistence boundary must hand back the integer contract the checkpoint declares.
	# A float here means the validators downstream would reject a real restart.
	if typeof(parser_envelope.get("nextPickupSequence", null)) != TYPE_INT:
		return _failure("a loaded checkpoint lost the integer type of the parser pickup sequence")
	var run_state_check: Variant = checkpoint.get("runState", null)
	if not (run_state_check is Dictionary) or typeof((run_state_check as Dictionary).get("score", null)) != TYPE_INT:
		return _failure("a loaded checkpoint lost the integer type of the run score")

	var parser := _new_parser_runtime()
	var restore_result := parser.restore_state(parser_runtime_state)
	if not bool(restore_result.get("success", false)):
		return _failure(
			"the real Parser Runtime rejected a JSON-decoded checkpoint: " + String(restore_result.get("reason", ""))
			+ " | persistedProfile=" + JSON.stringify(parser_runtime_state.get("parserProfile", {}))
			+ " | fixtureProfile=" + JSON.stringify(_new_parser_definition().build_runtime_profile())
		)

	# The persisted copy went through JSON, where every number became a float, while the
	# recaptured copy still carries the definition's float rates. Canonicalise both sides to
	# the runtime's integer form so this assertion fails on a real state difference only.
	var recaptured: Variant = SpaceJsonNumberCanonicalizer.canonicalize(parser.capture_state())
	var persisted: Variant = SpaceJsonNumberCanonicalizer.canonicalize(parser_runtime_state)
	if recaptured != persisted:
		return _failure(
			"Parser Runtime state changed across save/restart/restore; restored=%s persisted=%s"
			% [JSON.stringify(recaptured), JSON.stringify(persisted)]
		)

	# A restart must not replay already-accepted pickups into fresh production.
	var replay := parser.ingest_stone(FIRST_STONE_PICKUP_ID, PARSER_SHAPE, 2.5)
	if not bool(replay.get("success", false)) or not bool(replay.get("duplicate", false)) or not is_zero_approx(float(replay.get("acceptedVolume", -1.0))):
		return _failure("a restored Parser Runtime re-accepted an already processed pickup")
	var outputs: Variant = parser.pending_output_batches()
	if (outputs is Array) and not (outputs as Array).is_empty():
		return _failure("a restored Parser Runtime re-emitted %d output batch(es) after a restart" % (outputs as Array).size())

	if int(parser_envelope.get("nextPickupSequence", 0)) != 7:
		return _failure("restored nextPickupSequence is not the committed value")
	if int(parser_envelope.get("dropRngState", 0)) != DROP_RNG_STATE:
		return _failure("restored drop RNG state is not the committed value")
	var pending: Variant = parser_envelope.get("pendingPickups", null)
	if not (pending is Array) or (pending as Array).size() != 1 or String((pending as Array)[0].get("pickupId", "")) != PENDING_PICKUP_ID:
		return _failure("restored pending pickups are not the committed set")

	# Processed order events must survive so a restart cannot re-apply an effect.
	var effects: Variant = snapshot.get("effectState", null)
	var dispatcher: Variant = snapshot.get("dispatcherState", null)
	if not (effects is Dictionary) or not (dispatcher is Dictionary):
		return _failure("restored snapshot is missing an effect or dispatcher domain")
	if not (effects.get("processedOrderEventIds", []) as Array).has(PROCESSED_EVENT_ID):
		return _failure("restored effect ledger lost the processed order event")
	if not (dispatcher.get("processedEventIds", []) as Array).has(PROCESSED_EVENT_ID):
		return _failure("restored dispatcher ledger lost the processed order event")
	if String(dispatcher.get("loadoutFingerprint", "")) != LOADOUT_FINGERPRINT:
		return _failure("restored dispatcher belongs to a different frozen loadout")

	var run_state: Variant = checkpoint.get("runState", null)
	if not (run_state is Dictionary) or int(run_state.get("wave", 0)) != 3 or String(run_state.get("segment", "")) != "精英":
		return _failure("restored run progression is not the committed value")

	_remove_snapshot()
	return {"passed": true, "marker": "checkpoint-restored-after-process-restart"}
