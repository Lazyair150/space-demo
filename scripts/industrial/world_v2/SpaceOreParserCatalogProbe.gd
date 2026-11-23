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

	# The loadout builder must materialize the exact catalog version before computing
	# the immutable fingerprint. These values are synthetic contract fixtures only.
	var loadout_source := {
		"schemaVersion": SpaceBattleLoadoutSnapshot.CURRENT_SCHEMA_VERSION,
		"shipWorldId": "parser-catalog-probe-world",
		"loadoutId": "parser-catalog-probe-loadout",
		"loadoutVersion": 1,
		"shipSelection": {"definitionId": "probe-ship", "definitionVersion": 1},
		"productionDeviceSelections": [],
		"workshopCombinationSelection": {"definitionId": "probe-workshop", "definitionVersion": 1},
		"jarWorldOptions": {
			"shapes": ["圆罐", "方罐"],
			"liquids": ["酒", "蜜"],
			"producers": [],
			"workshops": [{
				"name": "主台",
				"baseMarks": [],
				"additionalMarks": [],
				"ban": [],
				"maxJars": 10,
				"maxLiquids": 10
			}],
			"masterWorkshopName": "主台"
		},
		"selectedOrderBindings": []
	}
	var frozen_loadout := SpaceBattleLoadoutSnapshot.create_with_ore_parser(
		loadout_source, catalog, "probe-universal-parser", 3, "parser-slot"
	)
	if frozen_loadout == null:
		return _failure("catalog-backed pre-battle loadout construction failed")
	if int(frozen_loadout.ore_parser_profile().get("productionPercentage", -1)) != 65:
		return _failure("frozen loadout did not retain exact catalog parser attributes")
	if not loadout_source.productionDeviceSelections.is_empty():
		return _failure("loadout construction mutated the caller's production-device array")

	var next_version := SpaceOreParserDefinition.new()
	next_version.parser_id = &"probe-universal-parser"
	next_version.definition_version = 4
	next_version.production_percentage = 70
	next_version.shape_processing_rate_per_second = {"圆罐": 8.0, "方罐": 5.0}
	next_version.progress_per_jar_by_shape = {"圆罐": 4.0, "方罐": 2.5}
	if not catalog.register_definition(next_version):
		return _failure("catalog rejected a new immutable parser definition version")
	var next_loadout := SpaceBattleLoadoutSnapshot.create_with_ore_parser(
		loadout_source, catalog, "probe-universal-parser", 4, "parser-slot"
	)
	if next_loadout == null or next_loadout.loadout_fingerprint() == frozen_loadout.loadout_fingerprint():
		return _failure("parser attribute/version change did not change the frozen loadout fingerprint")

	var duplicate_parser_source := loadout_source.duplicate(true)
	duplicate_parser_source.productionDeviceSelections = [selection]
	if SpaceBattleLoadoutSnapshot.create_with_ore_parser(
		duplicate_parser_source, catalog, "probe-universal-parser", 3, "second-parser-slot"
	) != null:
		return _failure("loadout builder accepted a second ore parser")

	return {
		"passed": true,
		"parserId": "probe-universal-parser",
		"definitionVersion": 3,
		"productionPercentage": 65,
		"registeredVersionCount": versions.size()
	}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
