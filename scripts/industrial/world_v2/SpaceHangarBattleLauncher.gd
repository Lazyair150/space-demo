extends RefCounted
class_name SpaceHangarBattleLauncher
## Enforces the pre-SceneTree configuration boundary for new and resumed battles.
## The caller owns scene instantiation, save-store loading, and the durable commit callback.

static func launch_new_battle(
	parent: Node,
	game: Node,
	loadout: SpaceBattleLoadoutSnapshot,
	commit_callback: Callable,
	stage: SpaceStageDefinition = null,
	protected_target: Node = null
) -> bool:
	if not _can_attach(parent, game) or loadout == null:
		return false
	if not loadout.order_definition_keys().is_empty() and not commit_callback.is_valid():
		push_error("Hangar cannot launch selected orders without a durable effect commit callback")
		return false
	if not game.has_method("configure_battle_loadout") or not game.has_method("configure_order_effect_commit_callback"):
		push_error("Combat scene does not expose the frozen-loadout configuration contract")
		return false
	if commit_callback.is_valid() and not bool(game.call("configure_order_effect_commit_callback", commit_callback)):
		return false
	if not bool(game.call("configure_battle_loadout", loadout)):
		return false
	if stage != null:
		if not stage.is_valid() or not game.has_method("configure_battle_stage") or not bool(game.call("configure_battle_stage", stage, protected_target)):
			push_error("Combat scene rejected the exact finite-stage configuration")
			return false
	elif protected_target != null:
		return false
	if not GameFlow.begin_battle_preparation():
		push_error("GameFlow rejected the Hangar-to-Battle launch")
		return false
	parent.add_child(game)
	if not game.is_inside_tree():
		GameFlow.fault_battle()
		push_error("Combat scene could not be attached after loadout freeze")
		return false
	return true

static func launch_resumed_battle(
	parent: Node,
	game: Node,
	loadout: SpaceBattleLoadoutSnapshot,
	saved_snapshot: Dictionary,
	commit_callback: Callable,
	effect_catalog: SpaceEffectCatalog,
	effect_target_resolver: Callable
) -> bool:
	if not _can_attach(parent, game) or loadout == null or effect_catalog == null or not effect_target_resolver.is_valid():
		return false
	if not game.has_method("configure_battle_loadout_from_checkpoint"):
		push_error("Combat scene does not expose the coordinated checkpoint restore contract")
		return false
	if not bool(game.call(
		"configure_battle_loadout_from_checkpoint",
		loadout,
		saved_snapshot,
		commit_callback,
		effect_catalog,
		effect_target_resolver
	)):
		push_error("Hangar rejected the saved battle checkpoint or its frozen loadout identity")
		return false
	if not GameFlow.begin_battle_preparation():
		push_error("GameFlow rejected the Hangar resume launch")
		return false
	parent.add_child(game)
	if not game.is_inside_tree():
		GameFlow.fault_battle()
		push_error("Restored combat scene could not be attached")
		return false
	return true

static func _can_attach(parent: Node, game: Node) -> bool:
	return parent != null and parent.is_inside_tree() and game != null and not game.is_inside_tree()
