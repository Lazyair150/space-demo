extends Resource
class_name SpaceWorkshopCombinationDefinition
## Versioned World V2 rules profile.
## Workshop components are resolved from the global SpaceWorkshopCatalog and installed into board positions.

@export var combination_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var display_icon: Texture2D
## World-level options only: shapes, liquids, producers, initial stock and world rates. Templates are authored in core_order_templates.
## Do not put workshops/masterWorkshopName/slaveWorkshopName in this dictionary.
@export var jar_world_options: Dictionary = {}
## Exact-version Core-owned Jar order templates available in this World V2 vocabulary.
@export var core_order_templates: Array[SpaceCoreOrderTemplateDefinition] = []
## Runtime-only detached view of the global SpaceWorkshopCatalog; not serialized as part of this world profile.
var workshop_definitions: Array[SpaceWorkshopDefinition] = []
@export var operation_cost_by_order_type: Dictionary = {}
@export var liquid_handling_operation_cost: float = 0.0

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if combination_id == &"" or definition_version <= 0:
		errors.append("World V2 profile identity/version is invalid")
	if display_name.strip_edges().is_empty():
		errors.append("World V2 profile display name is required")
	for key in ["shapes", "liquids", "producers"]:
		if not jar_world_options.has(key):
			errors.append("World V2 profile options are missing " + key)
	for forbidden_key in ["workshops", "masterWorkshopName", "slaveWorkshopName", "orderTemplates"]:
		if jar_world_options.has(forbidden_key):
			errors.append("World V2 profile must author " + forbidden_key + " through the scoped workshop resources")
	var shapes: Variant = jar_world_options.get("shapes", null)
	var shape_set := {}
	if not (shapes is Array) or shapes.is_empty():
		errors.append("World V2 profile must provide a non-empty Jar shape vocabulary")
	elif shapes is Array:
		for shape in shapes:
			var shape_name := String(shape).strip_edges()
			if shape_name.is_empty() or shape_set.has(shape_name):
				errors.append("World V2 shape vocabulary contains an empty or duplicate name")
			shape_set[shape_name] = true
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
		var template_shapes: Array = shapes if shapes is Array else []
		var template_liquids: Array = liquids if liquids is Array else []
		errors.append_array(template.get_validation_errors(template_shapes, template_liquids))

	if not operation_cost_by_order_type.has("A") or not operation_cost_by_order_type.has("B"):
		errors.append("workshop combination must author operation costs for both A and B")
	for order_type in ["A", "B"]:
		var raw_cost: Variant = operation_cost_by_order_type.get(order_type, null)
		if (typeof(raw_cost) != TYPE_INT and typeof(raw_cost) != TYPE_FLOAT) or not is_finite(float(raw_cost)) or float(raw_cost) < 0.0:
			errors.append("workshop operation cost is invalid for order type " + order_type)
	if not is_finite(liquid_handling_operation_cost) or liquid_handling_operation_cost < 0.0:
		errors.append("liquid handling operation cost must be finite and non-negative")
	return errors

func build_jar_world_options(master_workshop_id: String = "", slave_workshop_id: String = "") -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	var selected_master_id := master_workshop_id
	var selected_slave_id := slave_workshop_id
	var shapes: Array = jar_world_options.get("shapes", [])
	var liquids: Array = jar_world_options.get("liquids", [])
	if selected_master_id.is_empty() and selected_slave_id.is_empty():
		# Bundle validation chooses compatible definitions only as a temporary template witness.
		var compatible_definitions: Array[SpaceWorkshopDefinition] = []
		for candidate in workshop_definitions:
			if candidate != null and candidate.is_compatible_with_world(shapes, liquids):
				compatible_definitions.append(candidate)
		if compatible_definitions.is_empty():
			return {}
		selected_master_id = String(compatible_definitions[0].workshop_id)
		selected_slave_id = String(compatible_definitions[1].workshop_id) if compatible_definitions.size() > 1 else selected_master_id
	if selected_master_id.is_empty() or selected_slave_id.is_empty():
		return {}
	var master_definition := find_workshop_definition(selected_master_id)
	var slave_definition := find_workshop_definition(selected_slave_id)
	if master_definition == null or slave_definition == null:
		return {}
	if not master_definition.is_compatible_with_world(shapes, liquids) or not slave_definition.is_compatible_with_world(shapes, liquids):
		return {}
	var result := jar_world_options.duplicate(true)
	var master_entry := master_definition.build_core_definition()
	var slave_entry := slave_definition.build_core_definition()
	if master_entry.is_empty() or slave_entry.is_empty():
		return {}
	# Core requires distinct role names even when two owned copies share one Definition.
	master_entry["name"] = master_definition.display_name + "（主台）"
	slave_entry["name"] = slave_definition.display_name + "（从台）"
	result["workshops"] = [master_entry, slave_entry]
	result["masterWorkshopName"] = String(master_entry["name"])
	result["slaveWorkshopName"] = String(slave_entry["name"])
	var core_templates: Array[Dictionary] = []
	for template in core_order_templates:
		core_templates.append(template.build_core_option())
	result["orderTemplates"] = core_templates
	return result

func find_workshop_definition(definition_id: String) -> SpaceWorkshopDefinition:
	for definition in workshop_definitions:
		if definition != null and String(definition.workshop_id) == definition_id:
			return definition.duplicate(true) as SpaceWorkshopDefinition
	return null

func build_selection() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	return {
		"definitionId": String(combination_id),
		"definitionVersion": definition_version,
		"workshopCombinationProfile": {
			"operationCostByOrderType": operation_cost_by_order_type.duplicate(true),
			"liquidHandlingOperationCost": liquid_handling_operation_cost
		}
	}
