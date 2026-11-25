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
	return true
