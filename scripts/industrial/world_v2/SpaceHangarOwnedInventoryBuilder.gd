extends RefCounted
class_name SpaceHangarOwnedInventoryBuilder
## Projects authored definitions through the player's unlocked/owned instance aggregate.
## Definition-only catalog entries are never exposed as selectable owned inventory.

static func build(bundle: SpaceHangarCatalogBundleResource, progression: SpacePlayerProgressionState) -> Dictionary:
	if bundle == null or progression == null or not progression.get_validation_errors().is_empty():
		return _empty("Catalog bundle or player progression state is invalid")
	if bundle.create_runtime_bundle() == null:
		return _empty("Catalog bundle failed validation")
	var result := {
		"isReady": true,
		"shipChoices": [],
		"deviceChoices": [],
		"parserChoices": [],
		"workshopChoices": [],
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
				var definition := _resolve_workshop_definition(bundle, String(instance.definition_id), instance.definition_version)
				if definition == null:
					return _empty("Owned workshop instance references a missing exact definition")
				result.workshopInstanceChoices.append({
					"id": String(definition.workshop_id), "version": definition.definition_version,
					"instanceId": String(instance.instance_id), "level": instance.level,
					"experience": instance.experience, "growthAttributes": instance.growth_attributes.duplicate(true),
					"label": definition.display_name, "iconTexture": definition.display_icon
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
	var workshop_pairs := _build_owned_workshop_pairs(bundle, progression)
	if workshop_pairs.is_empty():
		result.workshopChoices = []
	else:
		result.workshopChoices = workshop_pairs
	return result

static func _resolve_workshop_definition(bundle: SpaceHangarCatalogBundleResource, definition_id: String, version: int) -> SpaceWorkshopDefinition:
	for combination in bundle.workshop_combination_catalog.definitions:
		if combination == null:
			continue
		for workshop in combination.workshop_definitions:
			if workshop != null and String(workshop.workshop_id) == definition_id and workshop.definition_version == version:
				return workshop.duplicate(true) as SpaceWorkshopDefinition
	return null

static func _resolve_skill_definition(bundle: SpaceHangarCatalogBundleResource, definition_id: String, version: int) -> SpaceSkillDefinition:
	for definition in bundle.skill_definitions:
		if definition != null and String(definition.skill_id) == definition_id and definition.definition_version == version:
			return definition.duplicate(true) as SpaceSkillDefinition
	return null

static func _build_owned_workshop_pairs(bundle: SpaceHangarCatalogBundleResource, progression: SpacePlayerProgressionState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for combination in bundle.workshop_combination_catalog.definitions:
		if combination == null:
			continue
		var available: Array[Dictionary] = []
		for instance in progression.owned_instances:
			if instance == null or instance.item_kind != "workshop":
				continue
			var definition := _find_workshop_in_combination(
				combination, String(instance.definition_id), instance.definition_version
			)
			if definition == null:
				continue
			available.append({
				"instance": instance,
				"definition": definition
			})
		# Every ordered pair of distinct owned instances is a legal slot candidate.
		# Definition identity may be equal: two independently owned copies remain distinct components.
		for master_entry in available:
			for slave_entry in available:
				var master: SpaceOwnedProgressionInstance = master_entry.instance
				var slave: SpaceOwnedProgressionInstance = slave_entry.instance
				if master.instance_id == slave.instance_id:
					continue
				var master_definition: SpaceWorkshopDefinition = master_entry.definition
				var slave_definition: SpaceWorkshopDefinition = slave_entry.definition
				result.append({
					"id": String(combination.combination_id),
					"version": combination.definition_version,
					"label": combination.display_name,
					"masterInstanceId": String(master.instance_id),
					"slaveInstanceId": String(slave.instance_id),
					"masterWorkshopId": String(master.definition_id),
					"slaveWorkshopId": String(slave.definition_id),
					"masterLevel": master.level,
					"slaveLevel": slave.level,
					"masterLabel": master_definition.display_name,
					"slaveLabel": slave_definition.display_name
				})
	return result

static func _empty(reason: String) -> Dictionary:
	return {
		"isReady": false, "unavailableReason": reason,
		"shipChoices": [], "deviceChoices": [], "parserChoices": [],
		"workshopChoices": [], "workshopInstanceChoices": [],
		"skillChoices": [], "effectChoices": []
	}

static func _find_workshop_in_combination(combination: SpaceWorkshopCombinationDefinition, definition_id: String) -> SpaceWorkshopDefinition:
	if combination == null:
		return null
	for definition in combination.workshop_definitions:
		if definition != null and String(definition.workshop_id) == definition_id:
			return definition.duplicate(true) as SpaceWorkshopDefinition
	return null
