extends Resource
class_name SpaceCoreOrderTemplateDefinition
## Space-authored, exact-version metadata for a Jar Core-owned OrderTemplate.
## This resource never executes an order; it materializes immutable WorldV2Options data.

@export var template_id: StringName = &""
@export var template_version: int = 1
@export_enum("A", "B") var order_type: String = "A"
## One entry per Jar requirement. Repeated shapes are intentional and represent separate Jars.
@export var requirements: Array[Dictionary] = []

func template_name() -> String:
	if template_id == &"" or template_version <= 0:
		return ""
	return "%s@%d" % [String(template_id), template_version]

func get_validation_errors(shape_vocabulary: Array, liquid_vocabulary: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if template_id == &"" or template_version <= 0:
		errors.append("Core order template identity/version is invalid")
	if not ["A", "B"].has(order_type):
		errors.append("Core order template type must be A or B")
	if requirements.is_empty():
		errors.append("Core order template must contain at least one Jar requirement")
	for index in range(requirements.size()):
		var requirement: Dictionary = requirements[index]
		var shape := String(requirement.get("shape", "")).strip_edges()
		if shape.is_empty() or not shape_vocabulary.has(shape):
			errors.append("Core order template requirement %d uses an unknown or empty shape" % (index + 1))
		var liquid := String(requirement.get("liquid", "")).strip_edges()
		if not liquid.is_empty() and not liquid_vocabulary.has(liquid):
			errors.append("Core order template requirement %d uses an unknown liquid" % (index + 1))
		for key in requirement:
			if not ["shape", "liquid"].has(String(key)):
				errors.append("Core order template requirement %d contains unsupported field %s" % [index + 1, String(key)])
	return errors

func build_core_option() -> Dictionary:
	if template_name().is_empty() or not ["A", "B"].has(order_type) or requirements.is_empty():
		return {}
	return {
		"name": template_name(),
		"type": order_type,
		"requirements": requirements.duplicate(true)
	}

func duplicate_definition() -> SpaceCoreOrderTemplateDefinition:
	var copy := SpaceCoreOrderTemplateDefinition.new()
	copy.template_id = template_id
	copy.template_version = template_version
	copy.order_type = order_type
	copy.requirements = requirements.duplicate(true)
	return copy
