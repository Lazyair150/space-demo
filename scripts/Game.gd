extends Node2D

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
var _ore_parser_world_time_remainder_milli: float

@export var allow_sandbox_world_for_development: bool = true

## Hangar must call this before adding the combat scene to the SceneTree.
func configure_battle_loadout(
	loadout: SpaceBattleLoadoutSnapshot,
	persisted_dispatcher_state: Dictionary = {},
	persisted_ore_parser_state: Dictionary = {}
) -> bool:
	if is_inside_tree() or loadout == null or loadout.to_dictionary().is_empty():
		return false
	_battle_loadout = loadout
	_persisted_order_dispatcher_state = persisted_dispatcher_state.duplicate(true)
	_persisted_ore_parser_state = persisted_ore_parser_state.duplicate(true)
	return true

## The callback must atomically persist Space effect state and dispatcher state before returning true.
func configure_order_effect_commit_callback(callback: Callable) -> bool:
	if is_inside_tree() or not callback.is_valid():
		return false
	_order_effect_commit_callback = callback
	return true

func _ready() -> void:
	GameState.reset_run()
	# Buff durations consume the same combat simulation delta as Jar and actors.
	if player != null and player.effects != null:
		player.effects.external_time_authority = true
	if not _begin_ship_world():
		push_error("[Game] Ship world initialization failed; combat build is not allowed to proceed")
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	_camera_home=camera_2d.position
	_scatter_asteroids()
	if player:
		if not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)
		if not player.damaged.is_connected(_on_player_damaged):
			player.damaged.connect(_on_player_damaged)

func _begin_ship_world() -> bool:
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

	var materialized: Dictionary = jar_host.MaterializeSelectedOrders(
		_battle_loadout.selected_order_bindings()
	)
	if not bool(materialized.get("success", false)):
		if jar_host.IsShipWorldActive:
			jar_host.EndShipWorld()
		push_error("[Game] Selected order materialization failed: " + str(materialized.get("error", "")))
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
	_ore_parser_world_time_remainder_milli = 0.0
	if not _persisted_ore_parser_state.is_empty():
		var parser_state: Variant = _persisted_ore_parser_state.get("parserRuntime", null)
		if not (parser_state is Dictionary):
			push_error("[Game] Saved ore parser state is malformed")
			return false
		var restored := _ore_parser_runtime.restore_state(parser_state)
		if not bool(restored.get("success", false)):
			push_error("[Game] Ore parser state restore failed: " + String(restored.get("reason", "")))
			return false
		var remainder := float(_persisted_ore_parser_state.get("worldTimeRemainderMilli", -1.0))
		if not is_finite(remainder) or remainder < 0.0 or remainder >= 1.0:
			push_error("[Game] Ore parser world-time remainder is invalid")
			return false
		_ore_parser_world_time_remainder_milli = remainder
	return true

## Space pickup systems call this after the ship has acquired an energy stone.
func ingest_energy_stone(pickup_id: String, stone_type: String, volume: float) -> Dictionary:
	if _ore_parser_runtime == null:
		return {"success": false, "reason": "no frozen ore parser is active"}
	return _ore_parser_runtime.ingest_stone(pickup_id, stone_type, volume)

## Persist this beside the frozen loadout and Jar execution checkpoint.
func capture_ore_parser_state() -> Dictionary:
	if _ore_parser_runtime == null:
		return {}
	return {
		"parserRuntime": _ore_parser_runtime.capture_state(),
		"worldTimeRemainderMilli": _ore_parser_world_time_remainder_milli
	}

func _fail_ore_parser(jar_host: WorldV2ShipHost, reason: String) -> void:
	push_error("[Game] Ore parser/ingress failed closed: " + reason)
	process_mode = Node.PROCESS_MODE_DISABLED
	if jar_host != null and jar_host.IsShipWorldActive:
		jar_host.EndShipWorld()

## Save integration captures processed EventIds and Jar world identity with the frozen loadout identity.
func capture_order_dispatcher_state() -> Dictionary:
	if _order_effect_dispatcher == null:
		return {}
	return _order_effect_dispatcher.capture_state()

func _physics_process(delta: float) -> void:
	# This is the owning combat world's simulation step. Delta is already simulation-scaled.
	# Buffs, the Space-owned ore parser, and Jar all consume this same authorized time.
	if player != null and player.effects != null:
		player.effects.advance_from_space_world(delta)
	var jar_host := get_node_or_null("/root/WorldV2ShipHost")
	if jar_host != null and _ore_parser_runtime != null and jar_host.IsShipWorldActive and delta > 0.0:
		_ore_parser_world_time_remainder_milli += delta * 1000.0
		var parser_delta_milli := int(floor(_ore_parser_world_time_remainder_milli))
		_ore_parser_world_time_remainder_milli -= parser_delta_milli
		if parser_delta_milli > 0:
			var parser_step: Dictionary = _ore_parser_runtime.advance(parser_delta_milli)
			if not bool(parser_step.get("success", false)):
				_fail_ore_parser(jar_host, String(parser_step.get("reason", "unknown parser failure")))
				return
			var ingress: Dictionary = SpaceOreParserJarIngress.flush_pending(_ore_parser_runtime, jar_host)
			if not bool(ingress.get("success", false)):
				_fail_ore_parser(jar_host, String(ingress.get("reason", "Jar import failed")))
				return

	var jar_step_advanced := false
	if jar_host != null:
		jar_step_advanced = jar_host.AdvanceSpaceSimulation(delta)
	if jar_step_advanced and delta > 0.0 and _order_effect_dispatcher != null and _order_effect_commit_callback.is_valid():
		_order_effect_dispatcher.drain_pending(jar_host, _order_effect_commit_callback)
	if _shake_time > 0.0:
		_shake_time-=delta
		var offset:=Vector2(randf_range(-1,1),randf_range(-1,1))*_shake_strength
		camera_2d.position=_camera_home+offset
		if _shake_time <=0.0:
			camera_2d.position=_camera_home

func _exit_tree() -> void:
	# Leaving the owning ship-world is terminal for this Jar session.
	var jar_host := get_node_or_null("/root/WorldV2ShipHost")
	if jar_host != null:
		jar_host.EndShipWorld()

func _on_player_died()->void:
	GameState.report_game_over()
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/menus/GameOver.tscn")

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
