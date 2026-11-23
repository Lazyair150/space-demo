extends RefCounted
class_name SpaceOreParserCatalogProbe
## Synthetic catalog tests only; these values are not production balance data.

static func run() -> Dictionary:
	var definition := SpaceOreParserDefinition.new()
	definition.parser_id = &"probe-universal-parser"
	definition.definition_version = 3
	definition.production_percentage = 65
	definition.shape_processing_rate_per_second = {"圆罐": 8.0, "方罐": 5.0}
	definition.progress_per_jar_by_shape = {"圆罐": 4.0, "方罐": 2.5}

	var catalog := SpaceOreParserCatalog.new()
	if not catalog.register_definition(definition):
		return _failure("valid exact-version parser definition was not registered")
	if catalog.register_definition(definition):
		return _failure("duplicate parser ID/version was accepted")
	var versions := catalog.registered_versions("probe-universal-parser")
	if versions.size() != 1 or versions[0] != 3:
		return _failure("catalog did not expose the registered exact version")

	# Mutating the authoring Resource after registration must not mutate catalog data.
	definition.production_percentage = 1
	definition.shape_processing_rate_per_second["圆罐"] = 999.0
	var selection := catalog.create_device_selection(
		"probe-universal-parser", 3, "parser-slot", ["圆罐", "方罐"]
	)
	if selection.is_empty():
		return _failure("catalog could not materialize a selected parser device")
	var embedded: Dictionary = selection.oreParserProfile
	if int(embedded.productionPercentage) != 65 or absf(float(embedded.shapeProcessingRatePerSecond["圆罐"]) - 8.0) > 0.000001:
		return _failure("catalog selection was changed by mutation of the source Resource")
	if not catalog.validate_device_selection(selection, "parser-slot", ["圆罐", "方罐"]).is_empty():
		return _failure("catalog rejected its own exact-version device selection")

	var changed_profile := selection.duplicate(true)
	changed_profile.oreParserProfile.productionPercentage = 66
	if catalog.validate_device_selection(changed_profile, "parser-slot", ["圆罐", "方罐"]).is_empty():
		return _failure("catalog accepted an altered frozen profile under the same version")
	if catalog.validate_device_selection(selection, "other-slot", ["圆罐", "方罐"]).is_empty():
		return _failure("catalog accepted a parser selection assigned to another slot")
	if catalog.create_device_selection("probe-universal-parser", 2, "parser-slot", ["圆罐", "方罐"]) != {}:
		return _failure("catalog silently substituted a different parser version")
	if catalog.create_device_selection("probe-universal-parser", 3, "parser-slot", ["圆罐"]) != {}:
		return _failure("universal parser selection omitted a configured Jar shape")

	return {
		"passed": true,
		"parserId": "probe-universal-parser",
		"definitionVersion": 3,
		"productionPercentage": 65,
		"registeredVersionCount": versions.size()
	}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
