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
