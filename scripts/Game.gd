extends Node2D

signal stage_completed(result: Dictionary)
signal stage_faulted(reason: String)

const ENERGY_STONE_PICKUP_SCENE: PackedScene = preload("res://scenes/industrial/SpaceEnergyStonePickup.tscn")

const ARENA_RECT:=Rect2(80,80,1120,560)
const ASTEROID_COUNT:=10

@onready var arena: Node2D = $Arena
@onready var camera_2d: Camera2D = %Camera2D
@onready var player: CharacterBody2D = %Player

@export var asteroid_scene:PackedScene

var _camera_home:Vector2
var _shake_time:float
var _shake_strength:float
var _battle_loadout: SpaceBattleLoadoutSnapshot
var _stage_director: SpaceStageEncounterDirector
var _selected_stage: SpaceStageDefinition
var _stage_objective_runtime: SpaceStageObjectiveRuntime
var _stage_encounters_completed: bool = false
var _stage_completion_emitted: bool = false
var _stage_protected_target: Node
var _order_effect_dispatcher: SpaceOrderEffectDispatcher
var _order_effect_commit_callback: Callable
var _persisted_order_dispatcher_state: Dictionary = {}
var _ore_parser_runtime: SpaceOreParserRuntime
var _persisted_ore_parser_state: Dictionary = {}
var _next_energy_stone_pickup_sequence: int = 1
var _persisted_jar_execution_checkpoint_json: String = ""
var _persisted_space_clock_remainder_milli: float = -1.0
var _persisted_run_state: Dictionary = {}
var _persisted_effect_state: Dictionary = {}
var _effect_catalog: SpaceEffectCatalog
var _effect_target_resolver: Callable
var _battle_shutdown_started: bool = false
var _last_completed_world_time_milli: int = -1
var _last_completed_logical_time_milli: int = -1

@export var allow_sandbox_world_for_development: bool = true

## Hangar must call this before adding the combat scene to the SceneTree.
func configure_battle_loadout(
	loadout: SpaceBattleLoadoutSnapshot,
	persisted_dispatcher_state: Dictionary = {},
	persisted_ore_parser_state: Dictionary = {},
	persisted_jar_execution_checkpoint_json: String = "",
	persisted_space_clock_remainder_milli: float = -1.0
) -> bool:
	if is_inside_tree() or loadout == null or loadout.to_dictionary().is_empty():
		return false
	_battle_loadout = loadout
	_persisted_order_dispatcher_state = persisted_dispatcher_state.duplicate(true)
	_persisted_ore_parser_state = persisted_ore_parser_state.duplicate(true)
	_persisted_jar_execution_checkpoint_json = persisted_jar_execution_checkpoint_json
	_persisted_space_clock_remainder_milli = persisted_space_clock_remainder_milli
	return true

## A finite stage must be frozen with the same owned-instance snapshots as the battle loadout.
## Call before adding the combat scene to the SceneTree.
func configure_battle_stage(stage: SpaceStageDefinition, protected_target: Node = null) -> bool:
	if is_inside_tree() or stage == null or not stage.is_valid() or _battle_loadout == null or not _persisted_jar_execution_checkpoint_json.is_empty():
		return false
	var objective_runtime := SpaceStageObjectiveRuntime.new()
	if not objective_runtime.configure(stage, protected_target):
		return false
	var director := SpaceStageEncounterDirector.new()
	if not director.configure(stage, _battle_loadout.to_dictionary()):
		return false
	_selected_stage = stage
	_stage_director = director
	_stage_objective_runtime = objective_runtime
	_stage_protected_target = protected_target
	return true

## Read by the child Spawner during its _ready; configuration is pre-tree only.
func get_stage_director_for_spawner() -> SpaceStageEncounterDirector:
	return _stage_director

## The callback must atomically persist Space effect state and dispatcher state before returning true.
func configure_order_effect_commit_callback(callback: Callable) -> bool:
	if is_inside_tree() or not callback.is_valid():
		return false
	_order_effect_commit_callback = callback
	return true

## Configure a resumed battle from one atomic effect/dispatcher/Jar/Space snapshot.
## The exact effect catalog and target resolver are required to reconstruct saved Buff instances.
func configure_battle_loadout_from_checkpoint(
	loadout: SpaceBattleLoadoutSnapshot,
	saved_snapshot: Dictionary,
	commit_callback: Callable = Callable(),
	effect_catalog: SpaceEffectCatalog = null,
	effect_target_resolver: Callable = Callable(),
	stage: SpaceStageDefinition = null,
	protected_target: Node = null
) -> bool:
	if loadout == null or int(saved_snapshot.get("schemaVersion", 0)) != 3:
		return false
	if not loadout.order_definition_keys().is_empty() and not commit_callback.is_valid():
		return false
	var expected_identity := {
		"shipWorldId": loadout.ship_world_id(),
		"loadoutId": loadout.loadout_id(),
		"loadoutVersion": loadout.loadout_version(),
		"loadoutFingerprint": loadout.loadout_fingerprint()
	}
	if saved_snapshot.get("loadoutIdentity", {}) != expected_identity:
		return false
	var runtime_checkpoint: Variant = saved_snapshot.get("runtimeCheckpoint", null)
	var dispatcher_state: Variant = saved_snapshot.get("dispatcherState", null)
	var effect_state: Variant = saved_snapshot.get("effectState", null)
	if not (runtime_checkpoint is Dictionary) or int(runtime_checkpoint.get("schemaVersion", 0)) not in [2, 3] or not (dispatcher_state is Dictionary) or not (effect_state is Dictionary):
		return false
	var runtime_schema := int(runtime_checkpoint.get("schemaVersion", 0))
	if (runtime_schema == 2 and stage != null) or (runtime_schema == 3 and stage == null):
		return false
	var stage_runtime: Variant = runtime_checkpoint.get("stageRuntime", {})
	if runtime_schema == 3 and not (stage_runtime is Dictionary):
		return false
	if int(effect_state.get("schemaVersion", 0)) != 1 or not (effect_state.get("instances", null) is Array) or not (effect_state.get("processedOrderEventIds", null) is Array):
		return false
	if not _checkpoint_event_ledgers_match(effect_state, dispatcher_state, expected_identity):
		push_error("[Game] Saved effect and dispatcher event ledgers do not match")
		return false
	if effect_catalog == null or not effect_target_resolver.is_valid():
		push_error("[Game] Resuming a battle requires the exact effect catalog and target resolver")
		return false
	if runtime_checkpoint.get("loadoutIdentity", {}) != expected_identity:
		return false
	var jar_checkpoint: Variant = runtime_checkpoint.get("jarExecutionCheckpointJson", null)
	var clock_remainder: Variant = runtime_checkpoint.get("spaceClockRemainderMilli", null)
	var parser_state: Variant = runtime_checkpoint.get("oreParserState", null)
	var run_state: Variant = runtime_checkpoint.get("runState", null)
	if typeof(jar_checkpoint) != TYPE_STRING or String(jar_checkpoint).is_empty() or (typeof(clock_remainder) != TYPE_INT and typeof(clock_remainder) != TYPE_FLOAT) or not is_finite(float(clock_remainder)) or float(clock_remainder) < 0.0 or float(clock_remainder) >= 1.0 or not (parser_state is Dictionary) or not (run_state is Dictionary):
		return false
	if int(run_state.get("schemaVersion", 0)) != 1 or typeof(run_state.get("score", null)) != TYPE_INT or int(run_state.get("score", -1)) < 0 or typeof(run_state.get("wave", null)) != TYPE_INT or int(run_state.get("wave", -1)) < 0 or typeof(run_state.get("segment", null)) != TYPE_STRING:
		return false
	if not configure_battle_loadout(
		loadout,
		dispatcher_state,
		parser_state,
		String(jar_checkpoint),
		float(clock_remainder)
	):
		return false
	_persisted_run_state = run_state.duplicate(true)
	_persisted_effect_state = effect_state.duplicate(true)
	if runtime_schema == 3 and not restore_battle_stage_from_checkpoint(stage, stage_runtime, protected_target):
		push_error("[Game] Finite-stage checkpoint identity/state restore failed")
		return false
	_effect_catalog = effect_catalog
	_effect_target_resolver = effect_target_resolver
	if commit_callback.is_valid() and not configure_order_effect_commit_callback(commit_callback):
		return false
	return true

func _checkpoint_event_ledgers_match(effect_state: Dictionary, dispatcher_state: Dictionary, expected_identity: Dictionary) -> bool:
	if int(dispatcher_state.get("schemaVersion", 0)) != 1:
		return false
	if String(dispatcher_state.get("shipWorldId", "")) != String(expected_identity.get("shipWorldId", "")) or String(dispatcher_state.get("loadoutId", "")) != String(expected_identity.get("loadoutId", "")) or int(dispatcher_state.get("loadoutVersion", 0)) != int(expected_identity.get("loadoutVersion", 0)) or String(dispatcher_state.get("loadoutFingerprint", "")) != String(expected_identity.get("loadoutFingerprint", "")):
		return false
	var effect_ids: Variant = effect_state.get("processedOrderEventIds", null)
	var dispatcher_ids: Variant = dispatcher_state.get("processedEventIds", null)
	if not (effect_ids is Array) or not (dispatcher_ids is Array) or effect_ids.size() != dispatcher_ids.size():
		return false
	var world_instance_id := String(dispatcher_state.get("jarWorldInstanceId", ""))
	if effect_ids.is_empty():
		if not world_instance_id.is_empty():
			return false
	elif world_instance_id.is_empty():
		return false
	var expected := {}
	for raw_id in effect_ids:
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty() or expected.has(String(raw_id)):
			return false
		var event_id := String(raw_id)
		if not event_id.begins_with(world_instance_id + ":"):
			return false
		var suffix := event_id.trim_prefix(world_instance_id + ":").split(":")
		if suffix.size() != 2 or not suffix[0].is_valid_int() or not suffix[1].is_valid_int() or int(suffix[0]) <= 0 or int(suffix[1]) <= 0 or str(int(suffix[0])) != suffix[0] or str(int(suffix[1])) != suffix[1]:
			return false
		expected[event_id] = true
	var actual := {}
	for raw_id in dispatcher_ids:
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty() or actual.has(String(raw_id)):
			return false
		actual[String(raw_id)] = true
	return expected == actual

func _ready() -> void:
	if not GameFlow.begin_battle_preparation():
		push_error("[Game] Application flow rejected battle scene entry")
		# This instance never acquired the battle lifecycle or Host ownership.
		# Its teardown must not fault/dispose another active battle.
		_battle_shutdown_started = true
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	if not _persisted_jar_execution_checkpoint_json.is_empty() and not GameFlow.begin_battle_resuming():
		push_error("[Game] Application flow rejected checkpoint resume phase")
		_shutdown_battle(true, "battle initialization failed")
		return
	if not _persisted_run_state.is_empty():
		if not GameState.restore_run_state(_persisted_run_state):
			push_error("[Game] Saved transient run state is invalid")
			_shutdown_battle(true, "battle initialization failed")
			return
	elif _persisted_jar_execution_checkpoint_json.is_empty():
		GameState.reset_run()
	# A resumed Jar checkpoint must not reset score/wave/segment before continuing.
	# Buff durations consume the same combat simulation delta as Jar and actors.
	if player != null and player.effects != null:
		player.effects.external_time_authority = true
	if not _restore_saved_effect_state():
		push_error("[Game] Saved Space effect state could not be restored")
		_shutdown_battle(true, "battle initialization failed")
		return
	if not _begin_ship_world():
		push_error("[Game] Ship world initialization failed; combat build is not allowed to proceed")
		var initialization_reason := "battle initialization failed"
		var failed_host := get_node_or_null("/root/WorldV2ShipHost")
		if failed_host != null and failed_host.IsFaulted and not String(failed_host.FaultReason).is_empty():
			initialization_reason = "World V2 Host fault: " + String(failed_host.FaultReason)
		_shutdown_battle(true, initialization_reason)
		return
	var active_jar_host := get_node_or_null("/root/WorldV2ShipHost")
	if active_jar_host != null and not active_jar_host.ShipWorldFaulted.is_connected(_on_ship_world_faulted):
		active_jar_host.ShipWorldFaulted.connect(_on_ship_world_faulted)
	_refresh_last_completed_simulation_position(active_jar_host)
	if not _persisted_jar_execution_checkpoint_json.is_empty():
		if not GameFlow.mark_battle_resume_ready():
			push_error("[Game] Application flow could not enter resume-ready state")
			_shutdown_battle(true, "battle initialization failed")
			return
		var pause_controller := get_node_or_null("PauseController")
		if pause_controller == null or not pause_controller.has_method("enter_resume_ready") or not bool(pause_controller.call("enter_resume_ready")):
			push_error("[Game] Restored battle could not acquire the mandatory resume-ready pause gates")
			_shutdown_battle(true, "battle initialization failed")
			return
	else:
		if not GameFlow.mark_battle_running():
			push_error("[Game] Application flow could not enter the running battle phase")
			_shutdown_battle(true, "battle initialization failed")
			return
	_camera_home = camera_2d.position
	_scatter_asteroids()
	var spawner := get_node_or_null("Spawner")
	if spawner != null:
		if spawner.has_signal("encounters_completed") and not spawner.encounters_completed.is_connected(_on_stage_encounters_completed):
			spawner.encounters_completed.connect(_on_stage_encounters_completed)
		if spawner.has_signal("stage_faulted") and not spawner.stage_faulted.is_connected(_on_stage_faulted):
			spawner.stage_faulted.connect(_on_stage_faulted)
	if player:
		if not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)
		if not player.damaged.is_connected(_on_player_damaged):
			player.damaged.connect(_on_player_damaged)

## Encounter completion is not objective completion or reward settlement.
func _on_stage_encounters_completed(result: Dictionary) -> void:
	if _selected_stage == null or _stage_objective_runtime == null or _battle_shutdown_started:
		return
	var identity: Variant = result.get("stageIdentity", null)
	if not (identity is Dictionary) or String(identity.get("stageId", "")) != String(_selected_stage.stage_id) or int(identity.get("definitionVersion", 0)) != _selected_stage.definition_version:
		_shutdown_battle(true, "finite stage encounter identity mismatch")
		return
	_stage_encounters_completed = true
	_stage_objective_runtime.mark_encounters_completed()
	_try_complete_stage()

func _try_complete_stage() -> void:
	if _selected_stage == null or _stage_objective_runtime == null or _battle_shutdown_started or _stage_completion_emitted or not _stage_encounters_completed or not _stage_objective_runtime.is_complete():
		return
	_stage_completion_emitted = true
	stage_completed.emit({
		"stageIdentity": {"stageId": String(_selected_stage.stage_id), "definitionVersion": _selected_stage.definition_version},
		"objectiveProgress": _stage_objective_runtime.progress(),
		"status": "objective_complete"
	})

func record_stage_boss_defeated(definition_id: String) -> bool:
	if _stage_objective_runtime == null or not _stage_objective_runtime.record_boss_defeated(definition_id):
		return false
	_try_complete_stage()
	return true

func get_stage_objective_progress() -> Dictionary:
	return _stage_objective_runtime.progress() if _stage_objective_runtime != null else {}



func _on_stage_faulted(reason: String) -> void:
	stage_faulted.emit(reason)
	_shutdown_battle(true, "finite stage runtime fault: " + reason)

func _restore_saved_effect_state() -> bool:
	if _persisted_effect_state.is_empty():
		return true
	if player == null or player.effects == null or _effect_catalog == null or not _effect_target_resolver.is_valid():
		push_error("[Game] Saved effect state has no StatusEffectManager/catalog/target resolver")
		return false
	var definition_resolver := func(definition_id: String, version: int) -> BuffDefinition:
		return _effect_catalog.resolve_buff(definition_id, version)
	return player.effects.restore_runtime_state(
		_persisted_effect_state,
		definition_resolver,
		_effect_target_resolver
	)

func _begin_ship_world() -> bool:
	if not _persisted_jar_execution_checkpoint_json.is_empty() and _persisted_run_state.is_empty():
		push_error("[Game] Resuming Jar execution requires the matching transient GameState checkpoint")
		return false
	var jar_host := get_node_or_null("/root/WorldV2ShipHost")
	if jar_host == null:
		push_error("[Game] WorldV2ShipHost autoload is unavailable")
		return false

	if _battle_loadout == null:
		if not allow_sandbox_world_for_development:
			push_error("[Game] Combat requires a frozen pre-battle loadout")
			return false
		return jar_host.BeginShipWorld()

	_order_effect_dispatcher = SpaceOrderEffectDispatcher.new()
	if not _order_effect_dispatcher.configure(_battle_loadout, _persisted_order_dispatcher_state):
		return false
	if not _battle_loadout.order_definition_keys().is_empty() and not _order_effect_commit_callback.is_valid():
		push_error("[Game] Selected orders require a durable Space effect commit callback")
		return false

	if not jar_host.BeginShipWorldFromJson(_battle_loadout.jar_world_options_json()):
		push_error("[Game] Jar rejected the frozen battle loadout configuration")
		return false

	if not _persisted_jar_execution_checkpoint_json.is_empty():
		# The checkpoint already contains selected demands, sessions, resources and
		# ledger receipts. Never materialize the frozen orders a second time.
		if not jar_host.RestoreExecutionCheckpointJson(_persisted_jar_execution_checkpoint_json):
			push_error("[Game] Jar execution checkpoint restore failed")
			return false
	else:
		var materialized: Dictionary = jar_host.MaterializeSelectedOrders(
			_battle_loadout.selected_order_bindings()
		)
		if not bool(materialized.get("success", false)):
			push_error("[Game] Selected order materialization failed: " + str(materialized.get("error", "")))
			return false

	if _persisted_space_clock_remainder_milli >= 0.0:
		if not jar_host.RestoreSpaceClockRemainderMilli(_persisted_space_clock_remainder_milli):
			push_error("[Game] Saved Space clock remainder is invalid or was restored too late")
			return false

	if not _initialize_ore_parser():
		return false
	return true

func _initialize_ore_parser() -> bool:
	if _battle_loadout == null:
		return true
	var parser_profile := _battle_loadout.ore_parser_profile()
	if parser_profile.is_empty():
		push_error("[Game] Frozen battle loadout has no selected ore parser profile")
		return false
	var definition := SpaceOreParserDefinition.from_runtime_profile(parser_profile)
	var shape_names: Variant = _battle_loadout.jar_world_options().get("shapes", [])
	if not (shape_names is Array):
		push_error("[Game] Frozen Jar world has no shape vocabulary for the ore parser")
		return false
	_ore_parser_runtime = SpaceOreParserRuntime.new()
	var parser_instance_id := _battle_loadout.ship_world_id() + ":" + String(definition.parser_id)
	var initialized := _ore_parser_runtime.initialize(definition, parser_instance_id, shape_names)
	if not bool(initialized.get("success", false)):
		push_error("[Game] Ore parser initialization failed: " + String(initialized.get("reason", "")))
		_ore_parser_runtime = null
		return false
	if not _persisted_ore_parser_state.is_empty():
		if int(_persisted_ore_parser_state.get("schemaVersion", 0)) != 2:
			push_error("[Game] Unsupported Space ore parser envelope schema")
			return false
		var parser_state: Variant = _persisted_ore_parser_state.get("parserRuntime", null)
		if not (parser_state is Dictionary):
			push_error("[Game] Saved ore parser state is malformed")
			return false
		var raw_next_pickup_sequence: Variant = _persisted_ore_parser_state.get("nextPickupSequence", 1)
		if typeof(raw_next_pickup_sequence) != TYPE_INT or int(raw_next_pickup_sequence) <= 0:
			push_error("[Game] Saved energy-stone pickup sequence is malformed")
			return false
		var raw_drop_rng_state: Variant = _persisted_ore_parser_state.get("dropRngState", null)
		var spawner := get_node_or_null("Spawner")
		if typeof(raw_drop_rng_state) != TYPE_INT or spawner == null or not spawner.has_method("restore_energy_stone_drop_rng_state"):
			push_error("[Game] Saved energy-stone drop RNG state or Spawner owner is invalid")
			return false
		_next_energy_stone_pickup_sequence = int(raw_next_pickup_sequence)
		if not _validate_energy_stone_pickup_sequence(_persisted_ore_parser_state, parser_state):
			return false
		var restored := _ore_parser_runtime.restore_state(parser_state)
		if not bool(restored.get("success", false)):
			push_error("[Game] Ore parser state restore failed: " + String(restored.get("reason", "")))
			return false
		if not bool(spawner.call("restore_energy_stone_drop_rng_state", int(raw_drop_rng_state))):
			push_error("[Game] Energy-stone drop RNG state restore failed")
			return false
		if not _restore_pending_energy_stone_pickups(_persisted_ore_parser_state, shape_names, parser_state):
			return false
	elif not _persisted_jar_execution_checkpoint_json.is_empty():
		push_error("[Game] Jar checkpoint cannot be restored without its matching Space ore parser state")
		return false
	return true


func _validate_energy_stone_pickup_sequence(parser_envelope: Dictionary, parser_state: Dictionary) -> bool:
	var ship_world_id := _battle_loadout.ship_world_id() if _battle_loadout != null else ""
	var prefix := "space-stone:" + ship_world_id + ":"
	var seen: Variant = parser_state.get("seenPickups", {})
	var pending: Variant = parser_envelope.get("pendingPickups", [])
	if not (seen is Dictionary) or not (pending is Array):
		push_error("[Game] Saved pickup identity sources are malformed")
		return false
	var maximum_issued_sequence := 0
	for pickup_id_value in seen.keys():
		var pickup_id := String(pickup_id_value)
		if not pickup_id.begins_with(prefix):
			continue
		var suffix := pickup_id.trim_prefix(prefix)
		if not suffix.is_valid_int():
			push_error("[Game] Saved parser contains a malformed battle pickup ID")
			return false
		var sequence := int(suffix)
		if sequence <= 0 or str(sequence) != suffix:
			push_error("[Game] Saved parser contains a non-canonical battle pickup ID")
			return false
		maximum_issued_sequence = maxi(maximum_issued_sequence, sequence)
	for raw_record in pending:
		if not (raw_record is Dictionary):
			continue
		var pickup_id := String(raw_record.get("pickupId", ""))
		if not pickup_id.begins_with(prefix):
			continue
		var suffix := pickup_id.trim_prefix(prefix)
		if not suffix.is_valid_int():
			push_error("[Game] Saved pending pickup has a malformed battle identity")
			return false
		var sequence := int(suffix)
		if sequence <= 0 or str(sequence) != suffix:
			push_error("[Game] Saved pending pickup has a non-canonical battle identity")
			return false
		maximum_issued_sequence = maxi(maximum_issued_sequence, sequence)
	if _next_energy_stone_pickup_sequence <= maximum_issued_sequence:
		push_error("[Game] Saved next pickup sequence would reuse an issued identity")
		return false
	return true

func _restore_pending_energy_stone_pickups(
	parser_envelope: Dictionary,
	shape_names: Array,
	parser_state: Dictionary
) -> bool:
	var raw_pickups: Variant = parser_envelope.get("pendingPickups", [])
	if not (raw_pickups is Array):
		push_error("[Game] Saved pending energy-stone pickup list is malformed")
		return false
	var seen_pickups: Variant = parser_state.get("seenPickups", {})
	if not (seen_pickups is Dictionary):
		push_error("[Game] Saved parser pickup identity ledger is malformed")
		return false

	var staged_nodes: Array[SpaceEnergyStonePickup] = []
	var staged_ids := {}
	for raw_record in raw_pickups:
		if not (raw_record is Dictionary):
			push_error("[Game] Saved energy-stone pickup record is malformed")
			for staged in staged_nodes:
				staged.free()
			return false
		var pickup_id := String(raw_record.get("pickupId", ""))
		var stone_type := String(raw_record.get("stoneType", ""))
		var raw_volume: Variant = raw_record.get("volume", null)
		var raw_x: Variant = raw_record.get("positionX", null)
		var raw_y: Variant = raw_record.get("positionY", null)
		if pickup_id.strip_edges().is_empty() or pickup_id.length() > 128 or staged_ids.has(pickup_id):
			push_error("[Game] Saved energy-stone pickup identity is empty or duplicated")
			for staged in staged_nodes:
				staged.free()
			return false
		staged_ids[pickup_id] = true
		if seen_pickups.has(pickup_id):
			# The parser already accepted this pickup before the save boundary; never
			# resurrect a world object whose resource has entered parser inventory.
			continue
		if not shape_names.has(stone_type) or (typeof(raw_volume) != TYPE_INT and typeof(raw_volume) != TYPE_FLOAT) or not is_finite(float(raw_volume)) or float(raw_volume) <= 0.0 or float(raw_volume) > 1000000000.0:
			push_error("[Game] Saved energy-stone pickup type/volume is invalid")
			for staged in staged_nodes:
				staged.free()
			return false
		if (typeof(raw_x) != TYPE_INT and typeof(raw_x) != TYPE_FLOAT) or (typeof(raw_y) != TYPE_INT and typeof(raw_y) != TYPE_FLOAT) or not is_finite(float(raw_x)) or not is_finite(float(raw_y)):
			push_error("[Game] Saved energy-stone pickup position is invalid")
			for staged in staged_nodes:
				staged.free()
			return false
		var pickup := ENERGY_STONE_PICKUP_SCENE.instantiate() as SpaceEnergyStonePickup
		if pickup == null or not pickup.configure(pickup_id, stone_type, float(raw_volume)):
			if pickup != null:
				pickup.free()
			push_error("[Game] Saved energy-stone pickup could not be reconstructed")
			for staged in staged_nodes:
				staged.free()
			return false
		pickup.global_position = Vector2(float(raw_x), float(raw_y))
		staged_nodes.append(pickup)

	for pickup in staged_nodes:
		add_child(pickup)
	return true

## Space pickup systems call this after the ship has acquired an energy stone.
func ingest_energy_stone(pickup_id: String, stone_type: String, volume: float) -> Dictionary:
	if _ore_parser_runtime == null:
		return {"success": false, "reason": "no frozen ore parser is active"}
	var receipt := _ore_parser_runtime.ingest_stone(pickup_id, stone_type, volume)
	if bool(receipt.get("success", false)) and _stage_objective_runtime != null:
		_stage_objective_runtime.record_resource("energy_stone", volume)
		_try_complete_stage()
	return receipt

## Spawner reads the frozen Jar vocabulary; an enemy drop cannot invent a new stone type.
func get_ore_parser_shape_vocabulary() -> Array:
	if _battle_loadout == null:
		return []
	var raw_shapes: Variant = _battle_loadout.jar_world_options().get("shapes", [])
	return raw_shapes.duplicate(true) if raw_shapes is Array else []

## Allocate pickup identity before it enters the SceneTree. The counter is persisted
## beside parser state so restored battles never reuse an already-issued identity.
func allocate_energy_stone_pickup_id() -> String:
	if _battle_loadout == null or _ore_parser_runtime == null:
		return ""
	if _next_energy_stone_pickup_sequence >= 9223372036854775807:
		return ""
	var pickup_id := "space-stone:" + _battle_loadout.ship_world_id() + ":" + str(_next_energy_stone_pickup_sequence)
	if pickup_id.length() > 128:
		return ""
	_next_energy_stone_pickup_sequence += 1
	return pickup_id

## Enemy/encounter drop adapter. The profile chooses type and volume; the battle owns
## stable pickup identity, and the parser owns acceptance/consumption after collection.
func spawn_energy_stone_drop(
	profile: SpaceEnergyStoneDropProfile,
	world_position: Vector2,
	rng: RandomNumberGenerator
) -> Dictionary:
	if profile == null or _ore_parser_runtime == null or _battle_loadout == null:
		return {"success": false, "reason": "frozen battle parser/loadout is not active"}
	var frozen_profile := SpaceEnergyStoneDropProfile.from_runtime_profile(profile.build_runtime_profile())
	var shape_names := get_ore_parser_shape_vocabulary()
	var roll := frozen_profile.roll_drop(rng, shape_names)
	if not bool(roll.get("success", false)):
		return {"success": false, "reason": String(roll.get("reason", "invalid energy-stone drop profile"))}
	if not bool(roll.get("dropped", false)):
		return {"success": true, "dropped": false}

	var pickup_id := allocate_energy_stone_pickup_id()
	if pickup_id.is_empty():
		return {"success": false, "reason": "could not allocate a stable energy-stone pickup ID"}
	var pickup := ENERGY_STONE_PICKUP_SCENE.instantiate() as SpaceEnergyStonePickup
	if pickup == null:
		return {"success": false, "reason": "energy-stone pickup scene could not be instantiated"}
	if not pickup.configure(pickup_id, String(roll.stoneType), float(roll.volume)):
		pickup.free()
		return {"success": false, "reason": "rolled energy-stone data failed pickup validation"}

	add_child(pickup)
	pickup.global_position = world_position
	return {
		"success": true,
		"dropped": true,
		"pickupId": pickup_id,
		"stoneType": String(roll.stoneType),
		"volume": float(roll.volume),
		"profileId": String(roll.profileId),
		"profileVersion": int(roll.profileVersion)
	}

## Persist this beside the frozen loadout and Jar execution checkpoint.
func capture_ore_parser_state() -> Dictionary:
	if _ore_parser_runtime == null:
		return {}
	var pending_pickups: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("space_energy_stone_pickups"):
		if not (node is SpaceEnergyStonePickup) or node.is_queued_for_deletion():
			continue
		pending_pickups.append({
			"pickupId": node.pickup_id,
			"stoneType": node.stone_type,
			"volume": node.volume,
			"positionX": node.global_position.x,
			"positionY": node.global_position.y
		})
	pending_pickups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.pickupId) < String(b.pickupId)
	)
	var spawner := get_node_or_null("Spawner")
	if spawner == null or not spawner.has_method("capture_energy_stone_drop_rng_state"):
		push_error("[Game] Cannot capture parser checkpoint without the enemy drop RNG owner")
		return {}
	return {
		"schemaVersion": 2,
		"parserRuntime": _ore_parser_runtime.capture_state(),
		"nextPickupSequence": _next_energy_stone_pickup_sequence,
		"dropRngState": int(spawner.call("capture_energy_stone_drop_rng_state")),
		"pendingPickups": pending_pickups
	}

## Capture Jar Core state, the Host-owned fractional clock, and Space parser state at one
## completed step boundary. The caller must persist this object as one save transaction.
func capture_jar_space_runtime_checkpoint() -> Dictionary:
	var jar_host := get_node_or_null("/root/WorldV2ShipHost")
	if jar_host == null or not jar_host.IsShipWorldActive or _battle_loadout == null:
		return {}
	var identity := {
		"shipWorldId": _battle_loadout.ship_world_id(),
		"loadoutId": _battle_loadout.loadout_id(),
		"loadoutVersion": _battle_loadout.loadout_version(),
		"loadoutFingerprint": _battle_loadout.loadout_fingerprint()
	}
	var jar_checkpoint := String(jar_host.CaptureExecutionCheckpointJson())
	var parser_checkpoint := capture_ore_parser_state()
	var stage_checkpoint := _capture_stage_runtime_checkpoint()
	if (_selected_stage != null and stage_checkpoint.is_empty()) or jar_checkpoint.is_empty() or int(parser_checkpoint.get("schemaVersion", 0)) != 2:
		push_error("[Game] Coordinated checkpoint is incomplete: Jar or ore-parser state is missing")
		return {}
	return {
		"schemaVersion": 3 if _selected_stage != null else 2,
		"loadoutIdentity": identity,
		"jarExecutionCheckpointJson": jar_checkpoint,
		"spaceClockRemainderMilli": jar_host.CaptureSpaceClockRemainderMilli(),
		"oreParserState": parser_checkpoint,
		"runState": GameState.capture_run_state(),
		"stageRuntime": stage_checkpoint
	}

func _capture_stage_runtime_checkpoint() -> Dictionary:
	if _selected_stage == null:
		return {}
	if _stage_director == null or _stage_objective_runtime == null or _battle_loadout == null:
		return {}
	var director_state := _stage_director.capture_state()
	var objective_state := _stage_objective_runtime.capture_state()
	if director_state.is_empty() or objective_state.is_empty():
		return {}
	return {
		"schemaVersion": 1,
		"stageId": String(_selected_stage.stage_id),
		"definitionVersion": _selected_stage.definition_version,
		"loadoutIdentity": {
			"shipWorldId": _battle_loadout.ship_world_id(),
			"loadoutId": _battle_loadout.loadout_id(),
			"loadoutVersion": _battle_loadout.loadout_version(),
			"loadoutFingerprint": _battle_loadout.loadout_fingerprint()
		},
		"directorState": director_state,
		"objectiveState": objective_state,
		"encountersCompleted": _stage_encounters_completed,
		"completionEmitted": _stage_completion_emitted
	}

## Restore only against the exact stage and frozen loadout identities.
func restore_battle_stage_from_checkpoint(stage: SpaceStageDefinition, source: Dictionary, protected_target: Node = null) -> bool:
	if is_inside_tree() or _battle_loadout == null or stage == null or not stage.is_valid() or _selected_stage != null:
		return false
	if int(source.get("schemaVersion", 0)) != 1 or String(source.get("stageId", "")) != String(stage.stage_id) or int(source.get("definitionVersion", 0)) != stage.definition_version:
		return false
	var expected_loadout := {
		"shipWorldId": _battle_loadout.ship_world_id(),
		"loadoutId": _battle_loadout.loadout_id(),
		"loadoutVersion": _battle_loadout.loadout_version(),
		"loadoutFingerprint": _battle_loadout.loadout_fingerprint()
	}
	if source.get("loadoutIdentity", {}) != expected_loadout:
		return false
	var director_state: Variant = source.get("directorState", null)
	var objective_state: Variant = source.get("objectiveState", null)
	if not (director_state is Dictionary) or not (objective_state is Dictionary):
		return false
	var director := SpaceStageEncounterDirector.new()
	if not director.restore_state(stage, _battle_loadout.to_dictionary(), director_state):
		return false
	var objective := SpaceStageObjectiveRuntime.new()
	if not objective.restore_state(stage, objective_state, protected_target):
		return false
	var encounters_completed := bool(source.get("encountersCompleted", false))
	if encounters_completed != (director.state() == SpaceStageEncounterDirector.State.COMPLETE):
		return false
	var completion_emitted := bool(source.get("completionEmitted", false))
	if completion_emitted and not objective.is_complete():
		return false
	_selected_stage = stage
	_stage_director = director
	_stage_objective_runtime = objective
	_stage_protected_target = protected_target
	_stage_encounters_completed = encounters_completed
	_stage_completion_emitted = completion_emitted
	return true
func _refresh_last_completed_simulation_position(jar_host: Node) -> void:
	if jar_host == null or not jar_host.has_method("GetWorldSnapshot"):
		return
	var snapshot: Variant = jar_host.call("GetWorldSnapshot")
	if not (snapshot is Dictionary) or not bool(snapshot.get("available", false)):
		return
	var world_time: Variant = snapshot.get("worldTimeMilli", null)
	var logical_time: Variant = snapshot.get("logicalTimeMilli", null)
	if typeof(world_time) == TYPE_INT and int(world_time) >= 0 and typeof(logical_time) == TYPE_INT and int(logical_time) >= 0:
		_last_completed_world_time_milli = int(world_time)
		_last_completed_logical_time_milli = int(logical_time)

func _fail_ore_parser(jar_host: WorldV2ShipHost, reason: String) -> void:
	push_error("[Game] Ore parser/ingress failed closed: " + reason)
	_shutdown_battle(true, "ore parser/ingress failure")

## Idempotent terminal boundary for every failed, ended, or externally removed battle.
## Host disposal and the SceneTree pause release happen before any scene transition.
func _shutdown_battle(faulted: bool, reason: String) -> void:
	if _battle_shutdown_started:
		return
	_battle_shutdown_started = true
	if not reason.is_empty():
		print("[Game] Battle shutdown: " + reason)
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	var jar_host := get_node_or_null("/root/WorldV2ShipHost")
	if jar_host != null:
		jar_host.EndShipWorld()
	if faulted:
		GameFlow.fault_battle(reason, _last_completed_world_time_milli, _last_completed_logical_time_milli)
		var pause_controller := get_node_or_null("PauseController")
		if pause_controller != null and pause_controller.has_method("show_fault"):
			var fault_presentation := reason
			if _last_completed_world_time_milli >= 0 and _last_completed_logical_time_milli >= 0:
				fault_presentation += "\\nLast completed step: world %d ms / logical %d ms" % [_last_completed_world_time_milli, _last_completed_logical_time_milli]
			pause_controller.call("show_fault", fault_presentation)
	else:
		GameFlow.end_battle()
	process_mode = Node.PROCESS_MODE_DISABLED

## Presentation-only metadata frozen with the battle loadout; it never enters Jar's order contract.
func get_order_presentation_metadata() -> Dictionary:
	if _battle_loadout == null:
		return {}
	return _battle_loadout.order_presentation_metadata()

## Save integration captures processed EventIds and Jar world identity with the frozen loadout identity.
func capture_order_dispatcher_state() -> Dictionary:
	if _order_effect_dispatcher == null:
		return {}
	return _order_effect_dispatcher.capture_state()

func _physics_process(delta: float) -> void:
	if _stage_objective_runtime != null:
		_stage_objective_runtime.advance(delta)
		_try_complete_stage()
	# Buffs, the Space-owned ore parser, and Jar all consume the same authorized simulation step.
	if player != null and player.effects != null:
		player.effects.advance_from_space_world(delta)
	var jar_host := get_node_or_null("/root/WorldV2ShipHost")
	var jar_step_advanced := false
	if jar_host != null:
		# Host owns the sole fractional-millisecond accumulator. Space parses and imports
		# using exactly the same whole-millisecond delta that Jar receives next.
		var shared_delta_milli: int = jar_host.AccumulateSpaceSimulationDelta(delta)
		if _ore_parser_runtime != null and jar_host.IsShipWorldActive and shared_delta_milli > 0:
			var parser_step: Dictionary = _ore_parser_runtime.advance(shared_delta_milli)
			if not bool(parser_step.get("success", false)):
				_fail_ore_parser(jar_host, String(parser_step.get("reason", "unknown parser failure")))
				return
			var ingress: Dictionary = SpaceOreParserJarIngress.flush_pending(_ore_parser_runtime, jar_host)
			if not bool(ingress.get("success", false)):
				_fail_ore_parser(jar_host, String(ingress.get("reason", "Jar import failed")))
				return
		jar_step_advanced = jar_host.AdvanceSpaceSimulationMilliseconds(shared_delta_milli)
		if jar_host.IsFaulted:
			_on_ship_world_faulted(String(jar_host.FaultReason))
			return
	if jar_step_advanced:
		_refresh_last_completed_simulation_position(jar_host)
	if jar_step_advanced and delta > 0.0 and _order_effect_dispatcher != null and _order_effect_commit_callback.is_valid():
		_order_effect_dispatcher.drain_pending(jar_host, _order_effect_commit_callback)
	if _shake_time > 0.0:
		_shake_time-=delta
		var offset:=Vector2(randf_range(-1,1),randf_range(-1,1))*_shake_strength
		camera_2d.position=_camera_home+offset
		if _shake_time <=0.0:
			camera_2d.position=_camera_home

func _exit_tree() -> void:
	# Unexpected removal of a live battle is a fault, not a successful end.
	if not _battle_shutdown_started:
		_shutdown_battle(true, "combat scene removed before terminal shutdown")

func _on_ship_world_faulted(message: String) -> void:
	push_error("[Game] Ship world faulted: " + message)
	_shutdown_battle(true, "World V2 Host fault: " + message)

func _on_player_died()->void:
	_shutdown_battle(false, "player died")
	GameState.report_game_over()
	await get_tree().create_timer(1.0, false).timeout
	GameFlow.request_scene_transition(GameFlow.Screen.GAME_OVER, "res://scenes/menus/GameOver.tscn")

func _on_player_damaged()->void:
	_shake_time=0.28
	_shake_strength=10.0

func _scatter_asteroids()->void:
	if asteroid_scene ==null:
		return
	var rng:=RandomNumberGenerator.new()
	rng.randomize()
	var placed:Array[Vector2]=[]
	var attempts:=0
	while placed.size()<ASTEROID_COUNT and attempts<200:
		attempts+=1
		var p:=Vector2(
			rng.randf_range(ARENA_RECT.position.x,ARENA_RECT.end.x),
			rng.randf_range(ARENA_RECT.position.y,ARENA_RECT.end.y)
		)
		if p.distance_to(Vector2(640,360))<140.0:
			continue
		var ok:=true
		for q in placed:
			if p.distance_to(q)<90:
				ok=false
				break
		if not ok:
			continue
		var a:Node2D=asteroid_scene.instantiate()
		a.position=p
		arena.add_child(a)
		placed.append(p)
