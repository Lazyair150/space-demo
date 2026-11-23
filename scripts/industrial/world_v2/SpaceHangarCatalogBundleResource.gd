extends Resource
class_name SpaceHangarCatalogBundleResource
## Editor-authored Hangar dependency bundle. Runtime registries are rebuilt from these Resources.

@export var ship_catalog: SpaceShipCatalog
@export var production_device_catalog: SpaceProductionDeviceCatalog
@export var ore_parser_catalog: SpaceOreParserCatalog
@export var workshop_combination_catalog: SpaceWorkshopCombinationCatalog
@export var skill_definitions: Array[SpaceSkillDefinition] = []
@export var balance_profile: SpaceSkillBalanceProfile
@export var effect_definitions: Array[BuffDefinition] = []

func create_runtime_bundle() -> SpaceHangarCatalogBundle:
	var skill_catalog := SpaceSkillCatalog.new()
	for definition in skill_definitions:
		if not skill_catalog.register_skill(definition):
			push_error("Hangar bundle resource contains an invalid or duplicate skill definition")
			return null
	var effect_catalog := SpaceEffectCatalog.new()
	for definition in effect_definitions:
		if not effect_catalog.register_buff(definition):
			push_error("Hangar bundle resource contains an invalid or duplicate effect definition")
			return null
	var bundle := SpaceHangarCatalogBundle.create(
		ship_catalog, production_device_catalog, ore_parser_catalog,
		workshop_combination_catalog, skill_catalog, balance_profile, effect_catalog
	)
	if not bundle.validate_and_prepare().is_empty():
		return null
	return bundle

func build_selection_inventory() -> Dictionary:
	var ships: Array[Dictionary] = []
	var devices: Array[Dictionary] = []
	var parsers: Array[Dictionary] = []
	var workshops: Array[Dictionary] = []
	var skills: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	if ship_catalog != null:
		for definition in ship_catalog.definitions:
			if definition != null:
				ships.append({
					"id": String(definition.ship_id),
					"version": definition.definition_version,
					"label": definition.display_name,
					"iconTexture": definition.display_icon,
					"hullTexture": definition.display_hull_texture,
					"displayAnchors": _build_display_anchor_inventory(definition.display_anchors)
				})
	if production_device_catalog != null:
		for definition in production_device_catalog.definitions:
			if definition != null:
				devices.append({
					"id": String(definition.device_id),
					"version": definition.definition_version,
					"kind": definition.device_kind,
					"label": definition.display_name,
					"iconTexture": definition.display_icon
				})
	if ore_parser_catalog != null:
		for definition in ore_parser_catalog.definitions:
			if definition != null:
				parsers.append({
					"id": String(definition.parser_id),
					"version": definition.definition_version,
					"label": definition.display_name if not definition.display_name.is_empty() else String(definition.parser_id),
					"iconTexture": definition.display_icon
				})
	if workshop_combination_catalog != null:
		for definition in workshop_combination_catalog.definitions:
			if definition != null:
				workshops.append({
					"id": String(definition.combination_id),
					"version": definition.definition_version,
					"label": definition.display_name,
					"iconTexture": definition.display_icon
				})
	for definition in skill_definitions:
		if definition != null:
			skills.append({
				"id": String(definition.skill_id),
				"version": definition.definition_version,
				"label": definition.display_name,
				"description": definition.description,
				"category": definition.ability_category,
				"primaryShape": String(definition.primary_shape),
				"allowedControlAreas": definition.allowed_control_areas.duplicate(),
				"iconTexture": definition.display_icon
			})
	for definition in effect_definitions:
		if definition != null:
			effects.append({
				"id": String(definition.id),
				"version": definition.definition_version,
				"label": definition.label,
				"iconTexture": definition.display_icon
			})
	var ready := create_runtime_bundle() != null
	return {
		"isReady": ready,
		"shipChoices": ships,
		"deviceChoices": devices,
		"parserChoices": parsers,
		"workshopChoices": workshops,
		"skillChoices": skills,
		"effectChoices": effects
	}


func _build_display_anchor_inventory(anchors: Array[SpaceShipDisplayAnchor]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var validation_definition := SpaceShipDefinition.new()
	validation_definition.display_anchors = anchors
	if not validation_definition.get_display_validation_errors().is_empty():
		return result
	for anchor in anchors:
		if anchor == null:
			continue
		result.append({
			"anchorId": String(anchor.anchor_id),
			"logicalSlotId": anchor.logical_slot_id,
			"componentKind": anchor.component_kind,
			"normalizedPosition": anchor.normalized_position,
			"rotationDegrees": anchor.rotation_degrees,
			"iconScale": anchor.icon_scale
		})
	return result
