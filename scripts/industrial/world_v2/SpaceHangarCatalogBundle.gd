extends RefCounted
class_name SpaceHangarCatalogBundle
## One coherent dependency set for a single Hangar build. No content or defaults are created here.

var ship_catalog: SpaceShipCatalog
var production_device_catalog: SpaceProductionDeviceCatalog
var ore_parser_catalog: SpaceOreParserCatalog
var workshop_combination_catalog: SpaceWorkshopCombinationCatalog
var skill_catalog: SpaceSkillCatalog
var balance_profile: SpaceSkillBalanceProfile
var effect_catalog: SpaceEffectCatalog

static func create(
	ships: SpaceShipCatalog,
	devices: SpaceProductionDeviceCatalog,
	parsers: SpaceOreParserCatalog,
	workshops: SpaceWorkshopCombinationCatalog,
	skills: SpaceSkillCatalog,
	balance: SpaceSkillBalanceProfile,
	effects: SpaceEffectCatalog
) -> SpaceHangarCatalogBundle:
	var bundle := SpaceHangarCatalogBundle.new()
	bundle.ship_catalog = ships
	bundle.production_device_catalog = devices
	bundle.ore_parser_catalog = parsers
	bundle.workshop_combination_catalog = workshops
	bundle.skill_catalog = skills
	bundle.balance_profile = balance
	bundle.effect_catalog = effects
	return bundle

func validate_and_prepare() -> PackedStringArray:
	var errors := PackedStringArray()
	if ship_catalog == null: errors.append("ship catalog is missing")
	elif not ship_catalog.rebuild_index(): errors.append("ship catalog index is invalid")
	if production_device_catalog == null: errors.append("production device catalog is missing")
	elif not production_device_catalog.rebuild_index(): errors.append("production device catalog index is invalid")
	if ore_parser_catalog == null: errors.append("ore parser catalog is missing")
	elif not ore_parser_catalog.rebuild_index(): errors.append("ore parser catalog index is invalid")
	if workshop_combination_catalog == null: errors.append("workshop combination catalog is missing")
	elif not workshop_combination_catalog.rebuild_index(): errors.append("workshop combination catalog index is invalid")
	if skill_catalog == null: errors.append("skill catalog is missing")
	if balance_profile == null or not balance_profile.is_valid(): errors.append("skill balance profile is missing or invalid")
	if effect_catalog == null: errors.append("effect catalog is missing")
	return errors
