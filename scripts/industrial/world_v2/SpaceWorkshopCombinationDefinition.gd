extends Resource
class_name SpaceWorkshopCombinationDefinition
## Versioned world-level workshop configuration.
## Individual workshop rules and Master/Slave role assignment are authored separately.

@export var combination_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var display_icon: Texture2D
## World-level options only: shapes, liquids, producers, initial stock and world rates. Templates are authored in core_order_templates.
## Do not put workshops/masterWorkshopName/slaveWorkshopName in this dictionary.
@export var jar_world_options: Dictionary = {}
## Exact-version Core-owned Jar order templates available in this World V2 vocabulary.
@export var core_order_templates: Array[SpaceCoreOrderTemplateDefinition] = []
@export var workshop_definitions: Array[SpaceWorkshopDefinition] = []
@export var workshop_pair: SpaceWorkshopPairDefinition
@export var operation_cost_by_order_type: Dictionary = {}
@export var liquid_handling_operation_cost: float = 0.0

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if combination_id == &"" or definition_version <= 0:
		errors.append("workshop combination identity/version is invalid")
	if display_name.strip_edges().is_empty():
		errors.append("workshop combination display name is required")
	for key in ["shapes", "liquids", "producers"]:
		if not jar_world_options.has(key):
			errors.append("workshop combination world options are missing " + key)
	for forbidden_key in ["workshops", "masterWorkshopName", "slaveWorkshopName", "orderTemplates"]:
		if jar_world_options.has(forbidden_key):
			errors.append("workshop combination must author " + forbidden_key + " through the scoped workshop resources")
	var shapes: Variant = jar_world_options.get("shapes", null)
	var shape_set := {}
	if not (shapes is Array) or shapes.is_empty():
		errors.append("workshop combination must provide a non-empty Jar shape vocabulary")
	elif shapes is Array:
		for shape in shapes:
			shape_set[String(shape)] = true
	var liquids: Variant = jar_world_options.get("liquids", null)
	var liquid_set := {}
	if not (liquids is Array) or liquids.size() != 2:
		errors.append("workshop combination must provide the Core's exact two-liquid vocabulary")
	elif liquids is Array:
		for liquid in liquids:
			var liquid_name := String(liquid).strip_edges()
			if liquid_name.is_empty() or liquid_set.has(liquid_name):
				errors.append("workshop combination liquid vocabulary contains an empty or duplicate name")
			liquid_set[liquid_name] = true
	var template_names := {}
	for template in core_order_templates:
		if template == null:
			errors.append("Core order template catalog contains a null definition")
			continue
		var template_name := template.template_name()
		if template_name.is_empty() or template_names.has(template_name):
			errors.append("Core order template names must be non-empty and unique within a World")
		template_names[template_name] = true
		errors.append_array(template.get_validation_errors(
			shapes if shapes is Array else [],
			liquids if liquids is Array else []
		))
	if workshop_definitions.size() != 2:
		errors.append("workshop combination must provide exactly two individual workshop definitions for its Master/Slave pair")
	var ids := {}
	var names := {}
	for workshop in workshop_definitions:
		if workshop == null:
			errors.append("workshop roster contains a null definition")
			continue
		for error in workshop.get_validation_errors():
			errors.append("workshop %s: %s" % [String(workshop.workshop_id), error])
		for mark in workshop.base_marks + workshop.additional_marks:
			if not shape_set.has(mark):
				errors.append("workshop %s references unknown shape %s" % [String(workshop.workshop_id), mark])
		for liquid in workshop.banned_liquids:
			if not liquid_set.has(liquid):
				errors.append("workshop %s bans unknown liquid %s" % [String(workshop.workshop_id), liquid])
		var id := String(workshop.workshop_id)
		var name := workshop.display_name.strip_edges()
		if ids.has(id) or names.has(name):
			errors.append("workshop roster identities and names must be unique")
		ids[id] = true
		names[name] = true
	if workshop_pair == null:
		errors.append("Master/Slave pair definition is missing")
	else:
		errors.append_array(workshop_pair.get_validation_errors(workshop_definitions))
	if not operation_cost_by_order_type.has("A") or not operation_cost_by_order_type.has("B"):
		errors.append("workshop combination must author operation costs for both A and B")
	for order_type in ["A", "B"]:
		var raw_cost: Variant = operation_cost_by_order_type.get(order_type, null)
		if (typeof(raw_cost) != TYPE_INT and typeof(raw_cost) != TYPE_FLOAT) or not is_finite(float(raw_cost)) or float(raw_cost) < 0.0:
			errors.append("workshop operation cost is invalid for order type " + order_type)
	if not is_finite(liquid_handling_operation_cost) or liquid_handling_operation_cost < 0.0:
		errors.append("liquid handling operation cost must be finite and non-negative")
	return errors

func build_jar_world_options() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	var result := jar_world_options.duplicate(true)
	var workshop_entries: Array[Dictionary] = []
	for definition in workshop_definitions:
		workshop_entries.append(definition.build_core_definition())
	var role_assignment := workshop_pair.build_core_role_assignment(workshop_definitions)
	if role_assignment.is_empty():
		return {}
	result["workshops"] = workshop_entries
	var core_templates: Array[Dictionary] = []
	for template in core_order_templates:
		core_templates.append(template.build_core_option())
	result["orderTemplates"] = core_templates
	result.merge(role_assignment, true)
	return result

func build_selection() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	var roster: Array[Dictionary] = []
	for definition in workshop_definitions:
		roster.append({
			"definitionId": String(definition.workshop_id),
			"definitionVersion": definition.definition_version,
			"name": definition.display_name
		})
	return {
		"definitionId": String(combination_id),
		"definitionVersion": definition_version,
		"workshopRoster": roster,
		"workshopPair": {
			"definitionId": String(workshop_pair.pair_id),
			"definitionVersion": workshop_pair.definition_version,
			"masterWorkshopId": String(workshop_pair.master_workshop_id),
			"slaveWorkshopId": String(workshop_pair.slave_workshop_id)
		},
		"workshopCombinationProfile": {
			"operationCostByOrderType": operation_cost_by_order_type.duplicate(true),
			"liquidHandlingOperationCost": liquid_handling_operation_cost
		}
	}
