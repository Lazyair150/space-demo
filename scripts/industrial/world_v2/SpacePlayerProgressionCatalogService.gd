extends RefCounted
class_name SpacePlayerProgressionCatalogService
## Validates exact catalog identity before mutating the player's unlock/acquisition aggregate.

static func unlock_definition(
	state: SpacePlayerProgressionState,
	bundle: SpaceHangarCatalogBundle,
	item_kind: String,
	definition_id: String,
	version: int
) -> bool:
	if state == null or bundle == null or not bundle.validate_and_prepare().is_empty():
		return false
	if not _definition_exists(bundle, item_kind, definition_id, version):
		return false
	return state.unlock_definition(item_kind, definition_id, version)

static func acquire_instance(
	state: SpacePlayerProgressionState,
	bundle: SpaceHangarCatalogBundle,
	instance: SpaceOwnedProgressionInstance
) -> bool:
	if state == null or bundle == null or instance == null or not bundle.validate_and_prepare().is_empty():
		return false
	if not _definition_exists(bundle, instance.item_kind, String(instance.definition_id), instance.definition_version):
		return false
	return state.acquire_instance(instance)

static func _definition_exists(bundle: SpaceHangarCatalogBundle, item_kind: String, definition_id: String, version: int) -> bool:
	if definition_id.strip_edges().is_empty() or version <= 0:
		return false
	match item_kind:
		"ship":
			return bundle.ship_catalog.resolve_definition(definition_id, version) != null
		"ore_parser":
			return bundle.ore_parser_catalog.resolve_definition(definition_id, version) != null
		"production_device":
			return bundle.production_device_catalog.resolve_definition(definition_id, version) != null
		"skill":
			return bundle.skill_catalog.resolve_skill(definition_id, version) != null
		"workshop":
			for combination in bundle.workshop_combination_catalog.definitions:
				if combination == null:
					continue
				for definition in combination.workshop_definitions:
					if definition != null and String(definition.workshop_id) == definition_id and definition.definition_version == version:
						return true
	return false

static func validate_definition(bundle: SpaceHangarCatalogBundle, item_kind: String, definition_id: String, version: int) -> bool:
	return bundle != null and bundle.validate_and_prepare().is_empty() and _definition_exists(bundle, item_kind, definition_id, version)
