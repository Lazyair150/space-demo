extends Resource
class_name SpaceWorkshopPairDefinition
## Selects workshop roles only. It does not reimplement or parameterize Jar's pair rules.

@export var pair_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var master_workshop_id: StringName = &""
@export var slave_workshop_id: StringName = &""

func get_validation_errors(workshops: Array[SpaceWorkshopDefinition]) -> PackedStringArray:
	var errors := PackedStringArray()
	if pair_id == &"" or definition_version <= 0:
		errors.append("workshop pair identity/version is invalid")
	if display_name.strip_edges().is_empty():
		errors.append("workshop pair display name is required")
	if master_workshop_id == &"" or slave_workshop_id == &"" or master_workshop_id == slave_workshop_id:
		errors.append("Master and Slave must identify two distinct workshops")
	var found_master := false
	var found_slave := false
	for workshop in workshops:
		if workshop == null:
			continue
		found_master = found_master or workshop.workshop_id == master_workshop_id
		found_slave = found_slave or workshop.workshop_id == slave_workshop_id
	if not found_master or not found_slave:
		errors.append("workshop pair roles must reference workshops in this roster")
	return errors

func build_core_role_assignment(workshops: Array[SpaceWorkshopDefinition]) -> Dictionary:
	if not get_validation_errors(workshops).is_empty():
		return {}
	var names := {}
	for workshop in workshops:
		if workshop != null:
			names[workshop.workshop_id] = workshop.display_name
	return {
		"masterWorkshopName": String(names[master_workshop_id]),
		"slaveWorkshopName": String(names[slave_workshop_id])
	}
