extends Node
class_name SpaceHangarPreparation
## Non-UI Hangar owner. UI supplies selections; this node resolves, freezes, and launches them.
## All catalogs/profiles are authored Resources assigned by the project, never synthesized here.

@export var ship_catalog: SpaceShipCatalog
@export var production_device_catalog: SpaceProductionDeviceCatalog
@export var ore_parser_catalog: SpaceOreParserCatalog
@export var workshop_combination_catalog: SpaceWorkshopCombinationCatalog
@export var skill_catalog: SpaceSkillCatalog
@export var balance_profile: SpaceSkillBalanceProfile
@export var effect_catalog: SpaceEffectCatalog

func build_loadout(
	identity: Dictionary,
	ship_id: String,
	ship_version: int,
	device_selections: Array,
	parser_id: String,
	parser_version: int,
	parser_slot_id: String,
	workshop_id: String,
	workshop_version: int,
	skill_selections: Array,
	expected_battle_duration_logical_milli: float
) -> SpaceBattleLoadoutSnapshot:
	return SpaceHangarLoadoutAssembler.assemble(
		identity,
		ship_catalog,
		ship_id,
		ship_version,
		production_device_catalog,
		device_selections,
		ore_parser_catalog,
		parser_id,
		parser_version,
		parser_slot_id,
		workshop_combination_catalog,
		workshop_id,
		workshop_version,
		skill_catalog,
		skill_selections,
		balance_profile,
		expected_battle_duration_logical_milli,
		effect_catalog
	)

func launch_new_battle(
	parent: Node,
	game_scene: PackedScene,
	identity: Dictionary,
	ship_id: String,
	ship_version: int,
	device_selections: Array,
	parser_id: String,
	parser_version: int,
	parser_slot_id: String,
	workshop_id: String,
	workshop_version: int,
	skill_selections: Array,
	expected_battle_duration_logical_milli: float,
	commit_callback: Callable
) -> Dictionary:
	if parent == null or not parent.is_inside_tree() or game_scene == null:
		return _failure("Hangar launch parent or combat scene is unavailable")
	var loadout := build_loadout(
		identity, ship_id, ship_version, device_selections,
		parser_id, parser_version, parser_slot_id,
		workshop_id, workshop_version, skill_selections,
		expected_battle_duration_logical_milli
	)
	if loadout == null:
		return _failure("selected build could not be frozen into a valid battle loadout")
	var game := game_scene.instantiate()
	if game == null:
		return _failure("combat scene could not be instantiated")
	if not SpaceHangarBattleLauncher.launch_new_battle(parent, game, loadout, commit_callback):
		if not game.is_inside_tree():
			game.free()
		return _failure("combat scene rejected the frozen loadout launch contract")
	return {
		"success": true,
		"loadout": loadout,
		"loadoutFingerprint": loadout.loadout_fingerprint()
	}

func launch_resumed_battle(
	parent: Node,
	game_scene: PackedScene,
	loadout: SpaceBattleLoadoutSnapshot,
	saved_snapshot: Dictionary,
	commit_callback: Callable,
	effect_target_resolver: Callable
) -> bool:
	if parent == null or not parent.is_inside_tree() or game_scene == null or effect_catalog == null:
		return false
	var game := game_scene.instantiate()
	if game == null:
		return false
	if not SpaceHangarBattleLauncher.launch_resumed_battle(
		parent, game, loadout, saved_snapshot, commit_callback,
		effect_catalog, effect_target_resolver
	):
		if not game.is_inside_tree():
			game.free()
		return false
	return true

func _failure(reason: String) -> Dictionary:
	push_error("Space Hangar preparation failed: " + reason)
	return {"success": false, "reason": reason}
