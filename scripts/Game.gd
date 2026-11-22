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

@export var allow_sandbox_world_for_development: bool = true

## Hangar must call this before adding the combat scene to the SceneTree.
func configure_battle_loadout(loadout: SpaceBattleLoadoutSnapshot) -> bool:
	if is_inside_tree() or loadout == null:
		return false
	_battle_loadout = loadout
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

	_order_effect_dispatcher = SpaceOrderEffectDispatcher.new()
	if not _order_effect_dispatcher.configure(_battle_loadout):
		jar_host.EndShipWorld()
		return false
	if not _battle_loadout.order_definition_keys().is_empty() and not _order_effect_commit_callback.is_valid():
		jar_host.EndShipWorld()
		push_error("[Game] Selected orders require a durable Space effect commit callback")
		return false
	return true

func _physics_process(delta: float) -> void:
	# This is the owning combat world's simulation step. Delta is already simulation-scaled.
	# Advance active buffs first. Effects emitted by Jar during this step begin their duration
	# at the step boundary and are advanced starting with the next step.
	if player != null and player.effects != null:
		player.effects.advance_from_space_world(delta)
	var jar_host := get_node_or_null("/root/WorldV2ShipHost")
	if jar_host != null:
		jar_host.AdvanceSpaceSimulation(delta)
		if _order_effect_dispatcher != null and _order_effect_commit_callback.is_valid():
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
