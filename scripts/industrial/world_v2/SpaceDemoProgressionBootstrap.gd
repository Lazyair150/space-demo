extends RefCounted
class_name SpaceDemoProgressionBootstrap
## DEMO ONLY: grants a small, clearly versioned prototype inventory when no player save exists.
## Production progression is always loaded from GameState's durable save and is never overwritten.

static func ensure_starting_inventory(bundle_resource: SpaceHangarCatalogBundleResource) -> bool:
	if bundle_resource == null or bundle_resource.create_runtime_bundle() == null:
		push_error("Demo progression bootstrap requires a valid prototype catalog bundle")
		return false
	if GameState.space_progression_state == null:
		var new_state := create_starting_inventory(bundle_resource)
		if new_state == null:
			return false
		return GameState.set_space_progression_state(new_state)

	# Existing demo saves may predate the complete starter assembly. Preserve
	# earned progression and repair only missing minimum starter inventory,
	# idempotently. A usable board needs two distinct workshop instances because
	# Master and Slave are separate required physical positions.
	var state: SpacePlayerProgressionState = GameState.space_progression_state
	if not state.get_validation_errors().is_empty():
		push_error("Demo progression bootstrap cannot repair an invalid player progression state")
		return false

	var has_ship := false
	var existing_instance_ids := {}
	for instance in state.owned_instances:
		if instance == null:
			continue
		existing_instance_ids[String(instance.instance_id)] = true
		if instance.item_kind == "ship":
			has_ship = true

	var changed := false
	if not has_ship:
		var starter_ship := _instance("demo.ship.starter.01", "ship", "demo.ship.starter", 1)
		if not state.unlock_and_acquire_instance(starter_ship, "demo-start:demo.ship.starter.01"):
			push_error("Demo progression migration could not grant the missing mandatory starter ship")
			return false
		changed = true

	var starter_workshops := [
		{"instanceId": "demo.workshop.alpha.01", "definitionId": "demo.workshop.alpha"},
		{"instanceId": "demo.workshop.beta.01", "definitionId": "demo.workshop.beta"}
	]
	for workshop in starter_workshops:
		var instance_id := String(workshop.instanceId)
		if existing_instance_ids.has(instance_id):
			continue
		var starter_workshop := _instance(instance_id, "workshop", String(workshop.definitionId), 1)
		if not state.unlock_and_acquire_instance(starter_workshop, "demo-start:" + instance_id):
			push_error("Demo progression migration could not grant required starter workshop instance: " + instance_id)
			return false
		existing_instance_ids[instance_id] = true
		changed = true

	var parser_revision_before := state.state_revision
	if not ensure_starting_parser_inventory(state, bundle_resource):
		return false
	changed = changed or state.state_revision != parser_revision_before
	return GameState.set_space_progression_state(state) if changed else true


## Older demo saves may have ship/workshop ownership but no parser. A production
## owned loadout requires one exact parser instance, so repair only that missing
## minimum inventory and keep the operation idempotent.
static func ensure_starting_parser_inventory(
	state: SpacePlayerProgressionState,
	bundle_resource: SpaceHangarCatalogBundleResource
) -> bool:
	if state == null or bundle_resource == null or bundle_resource.ore_parser_catalog == null:
		return false
	if not state.get_validation_errors().is_empty():
		return false
	var has_valid_parser := false
	for instance in state.owned_instances:
		if instance == null or instance.item_kind != "ore_parser":
			continue
		if bundle_resource.ore_parser_catalog.resolve_definition(
				String(instance.definition_id), instance.definition_version
			) == null:
			push_error("Demo progression migration found an owned parser with no exact catalog definition")
			return false
		has_valid_parser = true
	if has_valid_parser:
		return true
	var parser_definition := bundle_resource.ore_parser_catalog.resolve_definition("demo.parser.universal", 1)
	if parser_definition == null:
		push_error("Demo progression migration requires exact starter parser demo.parser.universal@1")
		return false
	var parser_instance_id := "demo.parser.universal.01"
	if state.resolve_instance(parser_instance_id) != null:
		push_error("Demo progression migration starter parser instance ID is already occupied")
		return false
	var starter_parser := _instance(parser_instance_id, "ore_parser", String(parser_definition.parser_id), parser_definition.definition_version)
	if not state.unlock_and_acquire_instance(starter_parser, "demo-start:" + parser_instance_id):
		push_error("Demo progression migration could not grant the missing starter parser")
		return false
	return true

static func create_starting_inventory(bundle_resource: SpaceHangarCatalogBundleResource) -> SpacePlayerProgressionState:
	if bundle_resource == null or bundle_resource.create_runtime_bundle() == null:
		push_error("Demo progression bootstrap requires a valid prototype catalog bundle")
		return null
	var state := SpacePlayerProgressionState.new()
	state.player_id = &"space_demo_player"
	var starting_instances: Array[SpaceOwnedProgressionInstance] = [
		_instance("demo.ship.starter.01", "ship", "demo.ship.starter", 1),
		_instance("demo.parser.universal.01", "ore_parser", "demo.parser.universal", 1),
		_instance("demo.parser.precision.01", "ore_parser", "demo.parser.precision", 1),
		_instance("demo.workshop.alpha.01", "workshop", "demo.workshop.alpha", 1),
		_instance("demo.workshop.beta.01", "workshop", "demo.workshop.beta", 1),
		_instance("demo.skill.rapid_fire.01", "skill", "demo.skill.rapid_fire", 1),
		_instance("demo.skill.recon_scan.01", "skill", "demo.skill.recon_scan", 1)
	]
	for instance in starting_instances:
		if String(instance.definition_id) == "demo.parser.precision":
			instance.growth_attributes = {
				"shapeProcessingRateMultiplier": 1.1,
				"progressPerJarMultiplier": 0.95,
				"productionPercentageBonus": 5
			}
		if not state.unlock_and_acquire_instance(instance, "demo-start:" + String(instance.instance_id)):
			push_error("Demo starting inventory could not acquire exact prototype instance: " + String(instance.instance_id))
			return null
	return state if state.get_validation_errors().is_empty() else null

static func _instance(instance_id: String, kind: String, definition_id: String, version: int) -> SpaceOwnedProgressionInstance:
	var instance := SpaceOwnedProgressionInstance.new()
	instance.instance_id = StringName(instance_id)
	instance.item_kind = kind
	instance.definition_id = StringName(definition_id)
	instance.definition_version = version
	instance.level = 1
	instance.experience = 0
	instance.progression_revision = 1
	instance.acquisition_provenance = {
		"source": "demo_starting_inventory",
		"contentTier": "prototype"
	}
	return instance
