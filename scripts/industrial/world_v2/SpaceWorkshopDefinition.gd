extends Resource
class_name SpaceWorkshopDefinition
## One workshop's local rules. These values remain attached to the workshop when its role changes.

@export var workshop_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var display_icon: Texture2D
@export var base_marks: Array[String] = []
@export var additional_marks: Array[String] = []
@export var banned_liquids: Array[String] = []
@export_range(0, 2147483647, 1) var max_jars: int = 0
@export_range(0, 2147483647, 1) var max_liquids: int = 0
## Optional aggregate staging limit. -1 means use Core's documented maxLiquids fallback.
@export_range(-1, 2147483647, 1) var liquid_staging_capacity: int = -1

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if workshop_id == &"" or definition_version <= 0:
		errors.append("workshop identity/version is invalid")
	if display_name.strip_edges().is_empty():
		errors.append("workshop display name is required")
	if base_marks.is_empty():
		errors.append("workshop must define at least one base mark")
	if max_jars <= 0 or max_liquids <= 0 or liquid_staging_capacity < -1:
		errors.append("workshop capacities are invalid")
	if _has_duplicates(base_marks) or _has_duplicates(additional_marks) or _has_duplicates(banned_liquids):
		errors.append("workshop local rule lists must not contain duplicates")
	for shape in base_marks:
		if additional_marks.has(shape):
			errors.append("workshop base and additional marks must not overlap")
	return errors

func build_core_definition() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	var result := {
		"name": display_name,
		"baseMarks": base_marks.duplicate(),
		"additionalMarks": additional_marks.duplicate(),
		"ban": banned_liquids.duplicate(),
		"maxJars": max_jars,
		"maxLiquids": max_liquids
	}
	if liquid_staging_capacity >= 0:
		result["liquidStagingCapacity"] = liquid_staging_capacity
	return result

func _has_duplicates(values: Array) -> bool:
	var seen := {}
	for value in values:
		var key := String(value).strip_edges()
		if key.is_empty() or seen.has(key):
			return true
		seen[key] = true
	return false

func is_compatible_with_world(shape_vocabulary: Array, liquid_vocabulary: Array) -> bool:
	if not get_validation_errors().is_empty():
		return false
	for mark in base_marks + additional_marks:
		if not shape_vocabulary.has(mark):
			return false
	for liquid in banned_liquids:
		if not liquid_vocabulary.has(liquid):
			return false
	return true
