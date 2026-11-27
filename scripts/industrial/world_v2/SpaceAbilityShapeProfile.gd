extends Resource
class_name SpaceAbilityShapeProfile
## Space-owned semantic mapping from ability families to the Jar shape vocabulary.
## Jar Core receives only concrete shape requirements; it never receives these categories.

const ABILITY_CATEGORIES := ["Offense", "Defense", "Support", "Reconnaissance", "Utility"]

@export var profile_id: StringName = &""
@export var profile_version: int = 1
@export var shape_by_ability_category: Dictionary = {}

func is_valid() -> bool:
	if profile_id == &"" or profile_version <= 0:
		return false
	if shape_by_ability_category.size() != ABILITY_CATEGORIES.size():
		return false
	var used_shapes := {}
	for category in ABILITY_CATEGORIES:
		if not shape_by_ability_category.has(category):
			return false
		var shape := String(shape_by_ability_category[category]).strip_edges()
		if shape.is_empty() or used_shapes.has(shape):
			return false
		used_shapes[shape] = true
	return true

func shape_for_category(category: String) -> String:
	if not is_valid() or not shape_by_ability_category.has(category):
		return ""
	return String(shape_by_ability_category[category]).strip_edges()

func validate_shape_vocabulary(raw_shape_names: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not (raw_shape_names is Array):
		errors.append("Jar shape vocabulary must be an array")
		return errors
	if not is_valid():
		errors.append("ability shape profile is invalid")
		return errors
	var known_shapes := {}
	var shape_names: Array = raw_shape_names
	for raw_shape in shape_names:
		known_shapes[String(raw_shape).strip_edges()] = true
	for category in ABILITY_CATEGORIES:
		var mapped_shape := String(shape_by_ability_category[category]).strip_edges()
		if not known_shapes.has(mapped_shape):
			errors.append("ability category %s maps to a shape outside the selected Jar vocabulary: %s" % [category, mapped_shape])
	return errors

func validate_skill(skill: SpaceSkillDefinition) -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_valid():
		errors.append("ability shape profile is invalid")
		return errors
	if skill == null or not skill.is_valid():
		errors.append("skill definition is invalid")
		return errors
	var expected_shape := shape_for_category(skill.ability_category)
	if expected_shape.is_empty():
		errors.append("skill category has no configured Jar shape")
		return errors
	if String(skill.primary_shape) != expected_shape:
		errors.append("skill primary shape does not match its ability category mapping")
	if skill.jar_order_template_id == &"" and not skill.has_majority_shape(expected_shape):
		errors.append("category shape must account for a strict majority of the skill Jar requirements")
	# Template-backed skills are checked against the exact Core template by SpaceSkillCatalog.
	return errors
