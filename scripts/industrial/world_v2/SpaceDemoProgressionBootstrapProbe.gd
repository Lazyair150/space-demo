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
	var default_loadout := _build_default_owned_loadout(bundle, complete_state, board)
	if default_loadout == null or not SpaceBattleLoadoutSnapshot.validate_data(default_loadout.to_dictionary()).is_empty():
		return false

	# Version 2 froze the Space liquid identities but not their polarity map.
	# Only the exact known Space pair has a deterministic migration.
	var legacy_loadout: Dictionary = default_loadout.to_dictionary()
	legacy_loadout["schemaVersion"] = 2
	var legacy_jar_options: Dictionary = legacy_loadout.jarWorldOptions.duplicate(true)
	legacy_jar_options.erase("liquidPolarities")
	legacy_loadout["jarWorldOptions"] = legacy_jar_options
	legacy_loadout.erase("loadoutFingerprint")
	legacy_loadout["loadoutFingerprint"] = SpaceBattleLoadoutSnapshot.compute_fingerprint(legacy_loadout)
	var migrated_loadout := SpaceBattleLoadoutSnapshot.create(legacy_loadout)
	if migrated_loadout == null:
		return false
	var migrated_data: Dictionary = migrated_loadout.to_dictionary()
	if int(migrated_data.get("schemaVersion", 0)) != SpaceBattleLoadoutSnapshot.CURRENT_SCHEMA_VERSION:
		return false
	if String(migrated_data.jarWorldOptions.liquidPolarities.get("燃料", "")) != "Anode":
		return false
	if String(migrated_data.jarWorldOptions.liquidPolarities.get("冷却液", "")) != "Cathode":
		return false
	var unsupported_legacy: Dictionary = legacy_loadout.duplicate(true)
	var unsupported_options: Dictionary = unsupported_legacy.jarWorldOptions.duplicate(true)
	unsupported_options["liquids"] = ["water", "oil"]
	unsupported_options.erase("liquidPolarities")
	unsupported_legacy["jarWorldOptions"] = unsupported_options
	unsupported_legacy.erase("loadoutFingerprint")
	unsupported_legacy["loadoutFingerprint"] = SpaceBattleLoadoutSnapshot.compute_fingerprint(unsupported_legacy)
	if SpaceBattleLoadoutSnapshot.create(unsupported_legacy) != null:
		return false
	print("[SpaceDemoProgressionBootstrapProbe] default-owned-hangar-assembly=passed")
	print("[SpaceDemoProgressionBootstrapProbe] legacy-loadout-polarity-migration=passed")
	print("[SpaceDemoProgressionBootstrapProbe] unknown-legacy-liquid-mapping=fail-closed")
	return true



## Build a detached frozen snapshot, then release the Node-owned preparation service.
static func _build_default_owned_loadout(
	bundle: SpaceHangarCatalogBundleResource,
	progression: SpacePlayerProgressionState,
	board: SpaceHangarBoardDefinition
) -> SpaceBattleLoadoutSnapshot:
	var preparation := SpaceHangarPreparation.new()
	preparation.catalog_bundle_resource = bundle
	preparation.require_owned_instances = true
	preparation.player_progression_state = progression
	var controller := SpaceHangarSelectionController.new()
	var identity := {
		"shipWorldId": "bootstrap-probe-world",
		"loadoutId": "bootstrap-probe-loadout",
		"loadoutVersion": 1
	}
	var result: SpaceBattleLoadoutSnapshot
	if controller.configure(preparation, identity, board):
		var view := controller.get_view_model()
		var selection: Dictionary = view.get("selection", {})
		var master_id := String(selection.get("masterWorkshopInstanceId", ""))
		var slave_id := String(selection.get("slaveWorkshopInstanceId", ""))
		var valid_selection := (
			bool(view.get("canBuild", false))
			and not String(selection.get("shipInstanceId", "")).is_empty()
			and String(selection.get("parserId", "")) == "demo.parser.universal"
			and String(selection.get("parserInstanceId", "")) == "demo.parser.universal.01"
			and not master_id.is_empty()
			and not slave_id.is_empty()
			and master_id != slave_id
			and selection.get("skillSelections", []).size() == 2
			and selection.get("boardAssignments", []).size() >= 5
		)
		if valid_selection:
			var candidate := controller.build_loadout_snapshot()
			if candidate != null and SpaceBattleLoadoutSnapshot.validate_data(candidate.to_dictionary()).is_empty():
				result = candidate
	controller = null
	preparation.free()
	return result
