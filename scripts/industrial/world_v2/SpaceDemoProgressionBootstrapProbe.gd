extends RefCounted
class_name SpaceDemoProgressionBootstrapProbe
## Covers the legacy-save migration where starter ship/workshops exist but parser inventory is absent.

static func run() -> bool:
	var bundle := load("res://data/hangar/demo_catalog_bundle.tres") as SpaceHangarCatalogBundleResource
	if bundle == null or bundle.create_runtime_bundle() == null:
		return false
	var state := SpacePlayerProgressionState.new()
	state.player_id = &"bootstrap-parser-probe"
	var starter_ship := SpaceOwnedProgressionInstance.new()
	starter_ship.instance_id = &"legacy.ship.01"
	starter_ship.item_kind = "ship"
	starter_ship.definition_id = &"demo.ship.starter"
	starter_ship.definition_version = 1
	if not state.unlock_and_acquire_instance(starter_ship):
		return false
	var first_revision := state.state_revision
	if not SpaceDemoProgressionBootstrap.ensure_starting_parser_inventory(state, bundle):
		return false
	if state.owned_instances.size() != 2:
		return false
	var parser_count := 0
	for instance in state.owned_instances:
		if instance.item_kind == "ore_parser":
			parser_count += 1
			if String(instance.instance_id) != "demo.parser.universal.01":
				return false
	if parser_count != 1 or state.state_revision != first_revision + 1:
		return false
	var repaired_revision := state.state_revision
	if not SpaceDemoProgressionBootstrap.ensure_starting_parser_inventory(state, bundle):
		return false
	if state.state_revision != repaired_revision or state.owned_instances.size() != 2:
		return false
	print("[SpaceDemoProgressionBootstrapProbe] legacy-missing-parser-repair=idempotent")

	# Verify the actual authored demo board receives a complete deterministic
	# owned-instance default and can freeze it through the production controller.
	var complete_state := SpaceDemoProgressionBootstrap.create_starting_inventory(bundle)
	if complete_state == null:
		return false
	var board := load("res://data/hangar/demo_board.tres") as SpaceHangarBoardDefinition
	if board == null:
		return false
	var preparation := SpaceHangarPreparation.new()
	preparation.catalog_bundle_resource = bundle
	preparation.require_owned_instances = true
	preparation.player_progression_state = complete_state
	var controller := SpaceHangarSelectionController.new()
	var identity := {
		"shipWorldId": "bootstrap-probe-world",
		"loadoutId": "bootstrap-probe-loadout",
		"loadoutVersion": 1
	}
	if not controller.configure(preparation, identity, board):
		return false
	var view_model := controller.get_view_model()
	if not bool(view_model.get("canBuild", false)):
		return false
	var selection: Dictionary = view_model.get("selection", {})
	if String(selection.get("shipInstanceId", "")).is_empty():
		return false
	if String(selection.get("parserId", "")) != "demo.parser.universal":
		return false
	if String(selection.get("parserInstanceId", "")) != "demo.parser.universal.01":
		return false
	if String(selection.get("masterWorkshopInstanceId", "")).is_empty():
		return false
	if String(selection.get("slaveWorkshopInstanceId", "")).is_empty():
		return false
	if String(selection.masterWorkshopInstanceId) == String(selection.slaveWorkshopInstanceId):
		return false
	if selection.skillSelections.size() != 2 or selection.boardAssignments.size() < 5:
		return false
	var default_loadout := controller.build_loadout_snapshot()
	if default_loadout == null or not default_loadout.is_valid():
		return false
	print("[SpaceDemoProgressionBootstrapProbe] default-owned-hangar-assembly=passed")
	return true
