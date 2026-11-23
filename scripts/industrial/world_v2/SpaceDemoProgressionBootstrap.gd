extends RefCounted
class_name SpaceDemoProgressionBootstrap
## DEMO ONLY: grants a small, clearly versioned prototype inventory when no player save exists.
## Production progression is always loaded from GameState's durable save and is never overwritten.

static func ensure_starting_inventory(bundle_resource: SpaceHangarCatalogBundleResource) -> bool:
	if GameState.space_progression_state != null:
		return GameState.space_progression_state.get_validation_errors().is_empty()
	if bundle_resource == null or bundle_resource.create_runtime_bundle() == null:
		push_error("Demo progression bootstrap requires a valid prototype catalog bundle")
		return false
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
			return false
	return GameState.set_space_progression_state(state)

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
