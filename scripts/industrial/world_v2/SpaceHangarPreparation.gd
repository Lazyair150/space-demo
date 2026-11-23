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
@export var catalog_bundle_resource: SpaceHangarCatalogBundleResource
## Production Hangar must select player-owned instances; definition-only selection is an explicit development mode.
@export var require_owned_instances: bool = true
## Injected from the player save/session owner; never authored into a shared catalog Resource.
var player_progression_state: SpacePlayerProgressionState

func create_catalog_bundle() -> SpaceHangarCatalogBundle:
	if catalog_bundle_resource != null:
		return catalog_bundle_resource.create_runtime_bundle()
	return SpaceHangarCatalogBundle.create(
		ship_catalog, production_device_catalog, ore_parser_catalog,
		workshop_combination_catalog, skill_catalog, balance_profile, effect_catalog
	)

func build_loadout_from_selection(
	identity: Dictionary,
	selection: SpaceHangarSelection
) -> SpaceBattleLoadoutSnapshot:
	if selection == null:
		return _failure_snapshot("Hangar selection is missing")
	if require_owned_instances or player_progression_state != null:
		return build_owned_loadout_from_selection(identity, selection.to_data())
	var selection_errors := selection.validate()
	if not selection_errors.is_empty():
		return _failure_snapshot("Hangar selection rejected: " + "; ".join(selection_errors))
	var bundle := create_catalog_bundle()
	if bundle == null:
		return _failure_snapshot("Hangar catalog bundle resource could not be materialized")
	var dependency_errors := bundle.validate_and_prepare()
	if not dependency_errors.is_empty():
		return _failure_snapshot("Hangar catalog bundle rejected: " + "; ".join(dependency_errors))
	return SpaceHangarLoadoutAssembler.assemble(
		identity, bundle.ship_catalog, selection.ship_id, selection.ship_version,
		bundle.production_device_catalog, selection.device_selections,
		bundle.ore_parser_catalog, selection.parser_id, selection.parser_version,
		selection.parser_slot_id, bundle.workshop_combination_catalog,
		selection.workshop_id, selection.workshop_version, bundle.skill_catalog,
		selection.skill_selections, bundle.balance_profile,
		selection.expected_battle_duration_logical_milli, bundle.effect_catalog
	)

func build_owned_selection_inventory() -> Dictionary:
	if catalog_bundle_resource == null or player_progression_state == null:
		return {"isReady": false, "unavailableReason": "Player progression state or authored catalog bundle is missing"}
	return SpaceHangarOwnedInventoryBuilder.build(catalog_bundle_resource, player_progression_state)

func build_owned_loadout_from_selection(identity: Dictionary, selection_data: Dictionary) -> SpaceBattleLoadoutSnapshot:
	if player_progression_state == null:
		return _failure_snapshot("Player progression state is not attached to Hangar preparation")
	var errors := player_progression_state.get_validation_errors()
	if not errors.is_empty():
		return _failure_snapshot("Player progression state rejected: " + "; ".join(errors))
	var selection := SpaceHangarSelection.from_data(selection_data)
	if selection == null or not selection.has_owned_instance_selection() or not selection.validate().is_empty():
		return _failure_snapshot("Owned Hangar selection is incomplete or invalid")
	var bundle := create_catalog_bundle()
	if bundle == null or not bundle.validate_and_prepare().is_empty():
		return _failure_snapshot("Hangar catalog bundle could not be prepared")
	return SpaceHangarOwnedLoadoutAssembler.assemble(identity, selection_data, bundle, player_progression_state)

func build_loadout_from_draft(
	identity: Dictionary,
	draft: SpaceHangarSelectionDraft
) -> SpaceBattleLoadoutSnapshot:
	if draft == null or not draft.is_ready():
		return _failure_snapshot("Hangar selection draft is unavailable or its catalog inventory is not ready")
	var selection := draft.build_selection()
	if selection == null:
		return _failure_snapshot("Hangar selection draft is incomplete or invalid")
	return build_loadout_from_selection(identity, selection)

func _failure_snapshot(reason: String) -> SpaceBattleLoadoutSnapshot:
	push_error("Space Hangar preparation failed: " + reason)
	return null

func launch_new_battle_from_selection(
	parent: Node,
	game_scene: PackedScene,
	identity: Dictionary,
	selection: SpaceHangarSelection,
	commit_callback: Callable,
	stage: SpaceStageDefinition = null,
	protected_target: Node = null
) -> Dictionary:
	if parent == null or not parent.is_inside_tree() or game_scene == null:
		return _failure("Hangar launch parent or combat scene is unavailable")
	var loadout := build_loadout_from_selection(identity, selection)
	if loadout == null:
		return _failure("selected build could not be frozen into a valid battle loadout")
	var game := game_scene.instantiate()
	if game == null:
		return _failure("combat scene could not be instantiated")
	if not SpaceHangarBattleLauncher.launch_new_battle(parent, game, loadout, commit_callback, stage, protected_target):
		if not game.is_inside_tree():
			game.free()
		return _failure("combat scene rejected the frozen loadout launch contract")
	return {
		"success": true,
		"loadout": loadout,
		"loadoutFingerprint": loadout.loadout_fingerprint()
	}

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
	if parent == null or not parent.is_inside_tree() or game_scene == null:
		return false
	var bundle := create_catalog_bundle()
	if bundle == null or not bundle.validate_and_prepare().is_empty():
		return false
	var resolved_effect_catalog := bundle.effect_catalog
	var game := game_scene.instantiate()
	if game == null:
		return false
	if not SpaceHangarBattleLauncher.launch_resumed_battle(
		parent, game, loadout, saved_snapshot, commit_callback,
		resolved_effect_catalog, effect_target_resolver
	):
		if not game.is_inside_tree():
			game.free()
		return false
	return true

func _failure(reason: String) -> Dictionary:
	push_error("Space Hangar preparation failed: " + reason)
	return {"success": false, "reason": reason}
