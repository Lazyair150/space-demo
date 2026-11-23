extends RefCounted
class_name SpaceWorkshopSlotSelectionProbe
## Proves that role positions are selected from independent workshop components,
## not imposed by a pre-authored definition pair.

static func run() -> bool:
	var first := _workshop("component.alpha", "Alpha")
	var second := _workshop("component.beta", "Beta")
	var world := _world([first, second])
	if not world.get_validation_errors().is_empty():
		return false
	var alpha_master := world.build_jar_world_options("component.alpha", "component.beta")
	var beta_master := world.build_jar_world_options("component.beta", "component.alpha")
	if not _has_roles(alpha_master, "Alpha（主台）", "Beta（从台）"):
		return false
	if not _has_roles(beta_master, "Beta（主台）", "Alpha（从台）"):
		return false
	# Two different owned copies may share one Definition; role labels stay unique.
	var same_component := world.build_jar_world_options("component.alpha", "component.alpha")
	if not _has_roles(same_component, "Alpha（主台）", "Alpha（从台）"):
		return false
	# No authored pair is required for the production component roster.
	var single_roster := _world([first])
	return single_roster.get_validation_errors().is_empty() and single_roster.build_jar_world_options("component.alpha", "component.alpha").size() > 0

static func _workshop(id: String, label: String) -> SpaceWorkshopDefinition:
	var value := SpaceWorkshopDefinition.new()
	value.workshop_id = StringName(id)
	value.definition_version = 1
	value.display_name = label
	value.base_marks = ["round"]
	value.max_jars = 4
	value.max_liquids = 4
	return value

static func _world(roster: Array[SpaceWorkshopDefinition]) -> SpaceWorkshopCombinationDefinition:
	var value := SpaceWorkshopCombinationDefinition.new()
	value.combination_id = &"probe.world"
	value.definition_version = 1
	value.display_name = "Probe World"
	value.jar_world_options = {
		"shapes": ["round"], "liquids": ["water", "fuel"], "producers": []
	}
	value.workshop_definitions = roster
	value.operation_cost_by_order_type = {"A": 1.0, "B": 1.0}
	return value

static func _has_roles(options: Dictionary, master_name: String, slave_name: String) -> bool:
	var workshops: Array = options.get("workshops", [])
	return workshops.size() == 2 \\
		and String(workshops[0].get("name", "")) == master_name \\
		and String(workshops[1].get("name", "")) == slave_name \\
		and String(options.get("masterWorkshopName", "")) == master_name \\
		and String(options.get("slaveWorkshopName", "")) == slave_name
