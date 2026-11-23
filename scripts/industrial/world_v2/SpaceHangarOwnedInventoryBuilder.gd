extends RefCounted
class_name SpaceHangarOwnedInventoryBuilder
## Projects authored definitions through the player's unlocked/owned instance aggregate.
## Definition-only catalog entries are never exposed as selectable owned inventory.

static func build(bundle: SpaceHangarCatalogBundleResource, progression: SpacePlayerProgressionState) -> Dictionary:
	if bundle == null or progression == null or not progression.get_validation_errors().is_empty():
		return _empty("Catalog bundle or player progression state is invalid")
	var runtime_bundle := bundle.create_runtime_bundle()
	if runtime_bundle == null:
		return _empty("Catalog bundle failed validation")
	var result := {
		"isReady": true,
		"shipChoices": [],
		"deviceChoices": [],
		"parserChoices": [],
		"workshopChoices": [],
		"workshopWorldChoices": [],
		"workshopInstanceChoices": [],
		"skillChoices": [],
		"effectChoices": []
	}
	for instance in progression.owned_instances:
		if instance == null:
			continue
		match instance.item_kind:
			"ship":
				var definition := bundle.ship_catalog.resolve_definition(String(instance.definition_id), instance.definition_version)
				if definition == null:
					return _empty("Owned ship instance references a missing exact definition")
				result.shipChoices.append({
					"id": String(definition.ship_id), "version": definition.definition_version,
					"instanceId": String(instance.instance_id), "level": instance.level,
					"experience": instance.experience, "growthAttributes": instance.growth_attributes.duplicate(true),
					"label": definition.display_name, "iconTexture": definition.display_icon,
					"hullTexture": definition.display_hull_texture
				})
			"ore_parser":
				var definition := bundle.ore_parser_catalog.resolve_definition(String(instance.definition_id), instance.definition_version)
				if definition == null:
					return _empty("Owned parser instance references a missing exact definition")
				result.parserChoices.append({
					"id": String(definition.parser_id), "version": definition.definition_version,
					"instanceId": String(instance.instance_id), "level": instance.level,
					"experience": instance.experience, "growthAttributes": instance.growth_attributes.duplicate(true),
					"label": definition.display_name, "iconTexture": definition.display_icon
				})
			"production_device":
				var definition := bundle.production_device_catalog.resolve_definition(String(instance.definition_id), instance.definition_version)
				if definition == null:
					return _empty("Owned production device references a missing exact definition")
				result.deviceChoices.append({
					"id": String(definition.device_id), "version": definition.definition_version,
					"instanceId": String(instance.instance_id), "level": instance.level,
					"experience": instance.experience, "growthAttributes": instance.growth_attributes.duplicate(true),
					"kind": definition.device_kind, "label": definition.display_name,
					"iconTexture": definition.display_icon
				})
			"workshop":
				var definition := runtime_bundle.workshop_catalog.resolve_definition(String(instance.definition_id), instance.definition_version)
				if definition == null:
					return _empty("Owned workshop instance references a missing exact definition")
				var compatible_world_keys: Array[String] = []
				for world in runtime_bundle.workshop_combination_catalog.definitions:
					if world != null and definition.is_compatible_with_world(world.jar_world_options.get("shapes", []), world.jar_world_options.get("liquids", [])):
						compatible_world_keys.append(String(world.combination_id) + "@" + str(world.definition_version))
				result.workshopInstanceChoices.append({
					"id": String(definition.workshop_id), "version": definition.definition_version,
					"instanceId": String(instance.instance_id), "level": instance.level,
					"experience": instance.experience, "growthAttributes": instance.growth_attributes.duplicate(true),
					"label": definition.display_name, "iconTexture": definition.display_icon,
					"compatibleWorldKeys": compatible_world_keys
				})
			"skill":
				var definition := _resolve_skill_definition(bundle, String(instance.definition_id), instance.definition_version)
				if definition == null:
					return _empty("Owned skill instance references a missing exact definition")
				result.skillChoices.append({
					"id": String(definition.skill_id), "version": definition.definition_version,
					"instanceId": String(instance.instance_id), "level": instance.level,
					"experience": instance.experience, "growthAttributes": instance.growth_attributes.duplicate(true),
					"label": definition.display_name, "description": definition.description,
					"category": definition.ability_category, "primaryShape": String(definition.primary_shape),
					"orderTemplateId": String(definition.jar_order_template_id),
					"orderTemplateVersion": definition.jar_order_template_version,
					"allowedControlAreas": definition.allowed_control_areas.duplicate(),
					"iconTexture": definition.display_icon
				})
	for effect in bundle.effect_definitions:
		if effect != null:
			result.effectChoices.append({
				"id": String(effect.id), "version": effect.definition_version,
				"label": effect.label, "iconTexture": effect.display_icon
			})
	var world_choices: Array[Dictionary] = []
	for combination in bundle.workshop_combination_catalog.definitions:
		if combination == null:
			continue
		world_choices.append({
			"id": String(combination.combination_id),
			"version": combination.definition_version,
			"label": combination.display_name,
			"iconTexture": combination.display_icon
		})
	result.workshopChoices = world_choices
	result.workshopWorldChoices = world_choices.duplicate(true)
	return result

static func _resolve_skill_definition(bundle: SpaceHangarCatalogBundleResource, definition_id: String, version: int) -> SpaceSkillDefinition:
	for definition in bundle.skill_definitions:
		if definition != null and String(definition.skill_id) == definition_id and definition.definition_version == version:
			return definition.duplicate(true) as SpaceSkillDefinition
	return null


static func _empty(reason: String) -> Dictionary:
	return {
		"isReady": false, "unavailableReason": reason,
		"shipChoices": [], "deviceChoices": [], "parserChoices": [],
		"workshopChoices": [], "workshopWorldChoices": [], "workshopInstanceChoices": [],
		"skillChoices": [], "effectChoices": []
	}

