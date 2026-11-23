extends Resource
class_name SpaceHangarCatalogBundleResource
## Editor-authored Hangar dependency bundle. Runtime registries are rebuilt from these Resources.

@export var ship_catalog: SpaceShipCatalog
@export var production_device_catalog: SpaceProductionDeviceCatalog
@export var ore_parser_catalog: SpaceOreParserCatalog
@export var workshop_combination_catalog: SpaceWorkshopCombinationCatalog
## Global independent component definitions; each world profile receives a detached runtime view.
@export var workshop_catalog: SpaceWorkshopCatalog
## Legacy embedded workshop definitions are allowed only by isolated synthetic probes.
@export var allow_legacy_embedded_workshops_for_probes: bool = false
@export var skill_definitions: Array[SpaceSkillDefinition] = []
@export var ability_shape_profile: SpaceAbilityShapeProfile
@export var balance_profile: SpaceSkillBalanceProfile
@export var effect_definitions: Array[BuffDefinition] = []
## Explicitly enabled only by isolated source probes; production resources must leave this false.
@export var allow_legacy_inline_skill_orders_for_probes: bool = false
## Optional until production exact-version pool assets are authored.
@export var roguelike_individual_library: SpaceRoguelikeIndividualLibrary

func create_runtime_bundle() -> SpaceHangarCatalogBundle:
	if roguelike_individual_library != null and not roguelike_individual_library.is_valid():
		push_error("Hangar bundle roguelike individual library has invalid power bands or exact-version entries")
		return null
	if ability_shape_profile == null or not ability_shape_profile.is_valid():
		push_error("Hangar bundle requires a valid ability category to Jar shape profile")
		return null
	if workshop_combination_catalog == null:
		push_error("Hangar bundle requires a World V2 rules profile catalog")
		return null
	var resolved_workshop_catalog := _resolve_global_workshop_catalog()
	if resolved_workshop_catalog == null or not resolved_workshop_catalog.is_valid():
		push_error("Hangar bundle requires a valid global exact-version workshop component catalog")
		return null
	var runtime_world_catalog := SpaceWorkshopCombinationCatalog.new()
	for authored_world in workshop_combination_catalog.definitions:
		if authored_world == null:
			push_error("Hangar bundle contains a null World V2 profile")
			return null
		var materialized_world := authored_world.duplicate(true) as SpaceWorkshopCombinationDefinition
		materialized_world.workshop_definitions = resolved_workshop_catalog.definitions.duplicate(true)
		if not runtime_world_catalog.register_definition(materialized_world):
			push_error("World V2 profile or its globally sourced workshop component view is invalid")
			return null
	for world in runtime_world_catalog.definitions:
		if world == null or not world.get_validation_errors().is_empty():
			push_error("Selectable World V2 rules profile or Core template catalog is invalid")
			return null
		if not ability_shape_profile.validate_shape_vocabulary(world.jar_world_options.get("shapes", [])).is_empty():
			push_error("Ability category shape mapping must exist in every selectable Jar world vocabulary")
			return null
		if world.build_jar_world_options().is_empty():
			push_error("Selectable World V2 rules profile could not materialize its two workshop positions")
			return null
	var skill_catalog := SpaceSkillCatalog.new()
	for definition in skill_definitions:
		if definition == null or not ability_shape_profile.validate_skill(definition).is_empty():
			push_error("Hangar skill category/shape affinity or dominant Jar shape is invalid")
			return null
		if not skill_catalog.register_skill(definition):
			push_error("Hangar bundle resource contains an invalid or duplicate skill definition")
			return null
	for definition in skill_definitions:
		if definition == null:
			return null
		if definition.jar_order_template_id == &"":
			if allow_legacy_inline_skill_orders_for_probes:
				continue
			push_error("Production Hangar skills must reference an exact Core order template; inline requirements are probe-only")
			return null
		var template_by_control_area := {}
		for world in runtime_world_catalog.definitions:
			if world == null or not world.get_validation_errors().is_empty():
				push_error("World V2 rules profile cannot be used to resolve Core order templates")
				return null
			var frozen_world_options := world.build_jar_world_options()
			if frozen_world_options.is_empty():
				push_error("World V2 rules profile could not materialize its Core order template catalog")
				return null
			for control_area in definition.allowed_control_areas:
				var resolved := skill_catalog.resolve_order_template(definition, frozen_world_options, control_area)
				if resolved.is_empty():
					push_error("Skill Core order template is missing or incompatible with world/control area: " + String(definition.skill_id))
					return null
				if template_by_control_area.has(control_area) and template_by_control_area[control_area] != resolved:
					push_error("Exact skill template content must be identical across selectable World V2 profiles: " + String(definition.skill_id))
					return null
				template_by_control_area[control_area] = resolved
	var effect_catalog := SpaceEffectCatalog.new()
	for definition in effect_definitions:
		if not effect_catalog.register_buff(definition):
			push_error("Hangar bundle resource contains an invalid or duplicate effect definition")
			return null
	var bundle := SpaceHangarCatalogBundle.create(
		ship_catalog, production_device_catalog, ore_parser_catalog,
		runtime_world_catalog, skill_catalog, balance_profile, effect_catalog
	)
	bundle.workshop_catalog = resolved_workshop_catalog
	if not bundle.validate_and_prepare().is_empty():
		return null
	return bundle

func _resolve_global_workshop_catalog() -> SpaceWorkshopCatalog:
	if workshop_catalog != null:
		return workshop_catalog
	if not allow_legacy_embedded_workshops_for_probes:
		return null
	var fallback := SpaceWorkshopCatalog.new()
	if workshop_combination_catalog == null:
		return null
	for world in workshop_combination_catalog.definitions:
		if world == null:
			continue
		for definition in world.workshop_definitions:
			if definition == null:
				return null
			if fallback.resolve_definition(String(definition.workshop_id), definition.definition_version) != null:
				continue
			if not fallback.register_definition(definition):
				return null
	return fallback if fallback.is_valid() else null

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
				"orderTemplateId": String(definition.jar_order_template_id),
				"orderTemplateVersion": definition.jar_order_template_version,
				"categoryShape": ability_shape_profile.shape_for_category(definition.ability_category) if ability_shape_profile != null else "",
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
		"effectChoices": effects,
		"individualPools": _build_individual_pool_inventory(),
		"individualLibraryReady": roguelike_individual_library != null and roguelike_individual_library.is_valid()
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

func _build_individual_pool_inventory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if roguelike_individual_library == null:
		return result
	for pool in roguelike_individual_library.pools:
		if pool == null:
			continue
		result.append({
			"poolId": String(pool.pool_id),
			"poolVersion": pool.definition_version,
			"powerModelId": String(pool.power_model_id),
			"powerModelVersion": pool.power_model_version,
			"itemKind": pool.item_kind,
			"entryCount": pool.entries.size(),
			"powerBands": pool.power_bands.duplicate(true)
		})
	return result
