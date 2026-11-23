extends Resource
class_name SpaceOreParserDefinition

const MAX_FIXED_POINT_UNITS: float = 1000000000.0
## Versioned pre-battle definition for the universal energy-stone parser.
## production_percentage belongs to this selected parser. It scales this parser's
## own per-shape throughput; it is not a distribution of output among Jar shapes.

@export var parser_id: StringName = &""
@export var definition_version: int = 1
@export_range(0, 100, 1) var production_percentage: int = 0
@export var shape_processing_rate_per_second: Dictionary = {}
@export var progress_per_jar_by_shape: Dictionary = {}

func get_validation_errors(shape_names: Array) -> Array[String]:
	var errors: Array[String] = []
	if parser_id == &"":
		errors.append("parser_id is required")
	if definition_version <= 0:
		errors.append("definition_version must be positive")
	if production_percentage < 0 or production_percentage > 100:
		errors.append("production_percentage must be between 0 and 100")
	if shape_names.is_empty():
		errors.append("shape vocabulary must be non-empty")
	if not (shape_processing_rate_per_second is Dictionary):
		errors.append("shape_processing_rate_per_second must be a dictionary")
	if not (progress_per_jar_by_shape is Dictionary):
		errors.append("progress_per_jar_by_shape must be a dictionary")
	if not errors.is_empty():
		return errors

	var known_shapes := {}
	for raw_shape in shape_names:
		var shape := String(raw_shape).strip_edges()
		if shape.is_empty() or known_shapes.has(shape):
			errors.append("shape vocabulary contains an empty or duplicate shape")
		else:
			known_shapes[shape] = true

	if shape_processing_rate_per_second.size() != known_shapes.size():
		errors.append("universal parser must define a processing rate for every Jar shape")
	if progress_per_jar_by_shape.size() != known_shapes.size():
		errors.append("universal parser must define progress required for every Jar shape")

	for shape in known_shapes:
		if not shape_processing_rate_per_second.has(shape):
			errors.append("parser is missing processing rate for shape: " + shape)
			continue
		var rate: Variant = shape_processing_rate_per_second[shape]
		if (typeof(rate) != TYPE_INT and typeof(rate) != TYPE_FLOAT) or not is_finite(float(rate)) or float(rate) < 0.0 or float(rate) > MAX_FIXED_POINT_UNITS:
			errors.append("parser processing rate is outside the supported fixed-point range: " + shape)

		if not progress_per_jar_by_shape.has(shape):
			errors.append("parser is missing progress-per-Jar for shape: " + shape)
			continue
		var threshold: Variant = progress_per_jar_by_shape[shape]
		if (typeof(threshold) != TYPE_INT and typeof(threshold) != TYPE_FLOAT) or not is_finite(float(threshold)) or float(threshold) <= 0.0 or float(threshold) > MAX_FIXED_POINT_UNITS or round(float(threshold) * 1000000.0) < 1.0:
			errors.append("progress-per-Jar must be positive and representable in the supported fixed-point range: " + shape)

	for shape in shape_processing_rate_per_second:
		if not known_shapes.has(String(shape)):
			errors.append("parser contains an unknown shape rate: " + String(shape))
	for shape in progress_per_jar_by_shape:
		if not known_shapes.has(String(shape)):
			errors.append("parser contains an unknown progress shape: " + String(shape))
	return errors

func is_valid_for_shapes(shape_names: Array) -> bool:
	return get_validation_errors(shape_names).is_empty()

func build_runtime_profile() -> Dictionary:
	return {
		"parserId": String(parser_id),
		"definitionVersion": definition_version,
		"productionPercentage": production_percentage,
		"shapeProcessingRatePerSecond": shape_processing_rate_per_second.duplicate(true),
		"progressPerJarByShape": progress_per_jar_by_shape.duplicate(true)
	}

static func from_runtime_profile(profile: Dictionary) -> SpaceOreParserDefinition:
	var definition := SpaceOreParserDefinition.new()
	definition.parser_id = StringName(profile.get("parserId", ""))
	definition.definition_version = int(profile.get("definitionVersion", 0))
	definition.production_percentage = int(profile.get("productionPercentage", -1))
	definition.shape_processing_rate_per_second = profile.get("shapeProcessingRatePerSecond", {}).duplicate(true)
	definition.progress_per_jar_by_shape = profile.get("progressPerJarByShape", {}).duplicate(true)
	return definition

func build_device_selection(slot_id: String, shape_names: Array) -> Dictionary:
	if slot_id.strip_edges().is_empty() or not is_valid_for_shapes(shape_names):
		return {}
	return {
		"slotId": slot_id,
		"deviceKind": "ore_parser",
		"definitionId": String(parser_id),
		"definitionVersion": definition_version,
		"oreParserProfile": build_runtime_profile()
	}
