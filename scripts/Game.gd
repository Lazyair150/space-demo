extends Node2D

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
	effect_target_resolver: Callable = Callable()
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
	if not (runtime_checkpoint is Dictionary) or int(runtime_checkpoint.get("schemaVersion", 0)) != 2 or not (dispatcher_state is Dictionary) or not (effect_state is Dictionary):
		return false
	if int(effect_state.get("schemaVersion", 0)) != 1 or not (effect_state.get("instances", null) is Array) or not (effect_state.get("processedOrderEventIds", null) is Array):
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
	_effect_catalog = effect_catalog
	_effect_target_resolver = effect_target_resolver
	if commit_callback.is_valid() and not configure_order_effect_commit_callback(commit_callback):
		return false
	return true

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
		_shutdown_battle(true, "battle initialization failed")
		return
	var active_jar_host := get_node_or_null("/root/WorldV2ShipHost")
	if active_jar_host != null and not active_jar_host.ShipWorldFaulted.is_connected(_on_ship_world_faulted):
		active_jar_host.ShipWorldFaulted.connect(_on_ship_world_faulted)
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
	if player:
		if not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)
		if not player.damaged.is_connected(_on_player_damaged):
			player.damaged.connect(_on_player_damaged)

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
			if jar_host.IsShipWorldActive:
				jar_host.EndShipWorld()
			push_error("[Game] Jar execution checkpoint restore failed")
			return false
	else:
		var materialized: Dictionary = jar_host.MaterializeSelectedOrders(
			_battle_loadout.selected_order_bindings()
		)
		if not bool(materialized.get("success", false)):
			if jar_host.IsShipWorldActive:
				jar_host.EndShipWorld()
			push_error("[Game] Selected order materialization failed: " + str(materialized.get("error", "")))
			return false

	if _persisted_space_clock_remainder_milli >= 0.0:
		if not jar_host.RestoreSpaceClockRemainderMilli(_persisted_space_clock_remainder_milli):
			jar_host.EndShipWorld()
			push_error("[Game] Saved Space clock remainder is invalid or was restored too late")
			return false

	if not _initialize_ore_parser():
		if jar_host.IsShipWorldActive:
			jar_host.EndShipWorld()
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
	return _ore_parser_runtime.ingest_stone(pickup_id, stone_type, volume)

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
	return {
		"schemaVersion": 2,
		"loadoutIdentity": identity,
		"jarExecutionCheckpointJson": jar_host.CaptureExecutionCheckpointJson(),
		"spaceClockRemainderMilli": jar_host.CaptureSpaceClockRemainderMilli(),
		"oreParserState": capture_ore_parser_state(),
		"runState": GameState.capture_run_state()
	}

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
		GameFlow.fault_battle()
	else:
		GameFlow.end_battle()
	process_mode = Node.PROCESS_MODE_DISABLED

## Save integration captures processed EventIds and Jar world identity with the frozen loadout identity.
func capture_order_dispatcher_state() -> Dictionary:
	if _order_effect_dispatcher == null:
		return {}
	return _order_effect_dispatcher.capture_state()

func _physics_process(delta: float) -> void:
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
