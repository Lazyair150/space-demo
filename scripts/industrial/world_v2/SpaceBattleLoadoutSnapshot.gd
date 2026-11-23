extends RefCounted
class_name SpaceBattleLoadoutSnapshot
## Immutable-by-interface snapshot of the four player-authored pre-battle build dimensions.
## Mutable source dictionaries are deep-copied on creation and on every read.

const CURRENT_SCHEMA_VERSION: int = 2

var _data: Dictionary = {}

static func create(source: Dictionary) -> SpaceBattleLoadoutSnapshot:
	var staged := source.duplicate(true)
	var fingerprint := compute_fingerprint(staged)
	if staged.has("loadoutFingerprint") and String(staged["loadoutFingerprint"]) != fingerprint:
		push_error("Space battle loadout fingerprint does not match its contents")
		return null
	staged["loadoutFingerprint"] = fingerprint
	var errors := validate_data(staged)
	if not errors.is_empty():
		push_error("Space battle loadout rejected: " + "; ".join(errors))
		return null
	var snapshot := SpaceBattleLoadoutSnapshot.new()
	snapshot._data = staged
	return snapshot

## Preferred Hangar construction path for the required universal ore parser.
## The exact catalog version is materialized into the device slot before the full
## immutable loadout is fingerprinted and validated.
static func create_with_ore_parser(
	source: Dictionary,
	parser_catalog: SpaceOreParserCatalog,
	parser_id: String,
	parser_version: int,
	parser_slot_id: String
) -> SpaceBattleLoadoutSnapshot:
	if parser_catalog == null:
		return null
	var staged := source.duplicate(true)
	var jar_options: Variant = staged.get("jarWorldOptions", null)
	if not (jar_options is Dictionary) or not (jar_options.get("shapes", null) is Array):
		return null
	var devices: Variant = staged.get("productionDeviceSelections", null)
	if not (devices is Array):
		return null
	var used_slots := {}
	for raw_device in devices:
		if not (raw_device is Dictionary):
			return null
		var slot_id := String(raw_device.get("slotId", ""))
		if slot_id.is_empty() or used_slots.has(slot_id) or String(raw_device.get("deviceKind", "")) == "ore_parser":
			push_error("Loadout builder requires unique non-parser slots and exactly one catalog-selected ore parser")
			return null
		used_slots[slot_id] = true
	if used_slots.has(parser_slot_id):
		push_error("Ore parser slot collides with another selected production device")
		return null
	var parser_selection := parser_catalog.create_device_selection(
		parser_id,
		parser_version,
		parser_slot_id,
		jar_options.shapes
	)
	if parser_selection.is_empty() or not parser_catalog.validate_device_selection(
		parser_selection,
		parser_slot_id,
		jar_options.shapes
	).is_empty():
		return null
	devices.append(parser_selection)
	staged["productionDeviceSelections"] = devices
	return create(staged)

static func compute_fingerprint(source: Dictionary) -> String:
	var canonical_source := source.duplicate(true)
	canonical_source.erase("loadoutFingerprint")
	var canonical_json := JSON.stringify(_canonicalize(canonical_source))
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hasher.update(canonical_json.to_utf8_buffer())
	return hasher.finish().hex_encode()

static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var result := {}
		for key in keys:
			result[key] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonicalize(item))
		return result
	return value

static func validate_data(source: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(source.get("schemaVersion", 0)) != CURRENT_SCHEMA_VERSION:
		errors.append("unsupported schemaVersion")
	if _required_text(source, "shipWorldId").is_empty():
		errors.append("shipWorldId is required")
	if _required_text(source, "loadoutId").is_empty():
		errors.append("loadoutId is required")
	if _required_text(source, "loadoutFingerprint").is_empty():
		errors.append("loadoutFingerprint is required")
	if int(source.get("loadoutVersion", 0)) <= 0:
		errors.append("loadoutVersion must be positive")

	var ship: Variant = source.get("shipSelection", null)
	if not (ship is Dictionary):
		errors.append("shipSelection must be a dictionary")
	else:
		if _required_text(ship, "definitionId").is_empty() or int(ship.get("definitionVersion", 0)) <= 0:
			errors.append("shipSelection must identify a versioned ship definition")

	var devices: Variant = source.get("productionDeviceSelections", null)
	if not (devices is Array):
		errors.append("productionDeviceSelections must be an array")
	elif devices.is_empty():
		errors.append("at least one production device selection is required")
	else:
		var slots := {}
		for raw_device in devices:
			if not (raw_device is Dictionary):
				errors.append("production device selection must be a dictionary")
				continue
			var device: Dictionary = raw_device
			var slot_id := _required_text(device, "slotId")
			if slot_id.is_empty() or slots.has(slot_id):
				errors.append("production device slotId is missing or duplicated")
			else:
				slots[slot_id] = true
			if _required_text(device, "definitionId").is_empty() or int(device.get("definitionVersion", 0)) <= 0:
				errors.append("production device must identify a versioned definition")

	var workshop: Variant = source.get("workshopCombinationSelection", null)
	if not (workshop is Dictionary):
		errors.append("workshopCombinationSelection must be a dictionary")
	else:
		if _required_text(workshop, "definitionId").is_empty() or int(workshop.get("definitionVersion", 0)) <= 0:
			errors.append("workshop combination must identify a versioned definition")

	var jar_options: Variant = source.get("jarWorldOptions", null)
	if not (jar_options is Dictionary):
		errors.append("jarWorldOptions must be a fully materialized WorldV2Options dictionary")
	else:
		for required_key in ["shapes", "liquids", "producers", "workshops", "masterWorkshopName"]:
			if not jar_options.has(required_key):
				errors.append("jarWorldOptions is missing " + required_key)

	# The selected ore parser is part of the frozen pre-battle production-device build.
	# Its percentage is a parser attribute and scales that parser's own throughput;
	# it is not a per-shape output allocation.
	var ore_parser_count := 0
	var shape_set := {}
	if jar_options is Dictionary and jar_options.get("shapes", null) is Array:
		for raw_shape in jar_options.shapes:
			shape_set[String(raw_shape)] = true
	if devices is Array:
		for raw_device in devices:
			if not (raw_device is Dictionary) or String(raw_device.get("deviceKind", "")) != "ore_parser":
				continue
			ore_parser_count += 1
			var device: Dictionary = raw_device
			var parser: Variant = device.get("oreParserProfile", null)
			if not (parser is Dictionary):
				errors.append("selected ore parser must include oreParserProfile")
				continue
			if _required_text(parser, "parserId").is_empty() or int(parser.get("definitionVersion", 0)) <= 0:
				errors.append("oreParserProfile must identify a versioned parser definition")
			if _required_text(device, "definitionId") != _required_text(parser, "parserId") or int(device.get("definitionVersion", 0)) != int(parser.get("definitionVersion", 0)):
				errors.append("production device identity must match its oreParserProfile")
			var percentage: Variant = parser.get("productionPercentage", null)
			if typeof(percentage) != TYPE_INT or int(percentage) < 0 or int(percentage) > 100:
				errors.append("ore parser productionPercentage must be an integer from 0 to 100")
			var rates: Variant = parser.get("shapeProcessingRatePerSecond", null)
			var progress: Variant = parser.get("progressPerJarByShape", null)
			if not (rates is Dictionary) or not (progress is Dictionary):
				errors.append("ore parser must provide per-shape processing rates and progress thresholds")
				continue
			if rates.size() != shape_set.size() or progress.size() != shape_set.size():
				errors.append("ore parser must define every configured Jar shape exactly once")
			for shape in shape_set:
				if not rates.has(shape) or not progress.has(shape):
					errors.append("ore parser is missing shape configuration: " + String(shape))
					continue
				var rate: Variant = rates[shape]
				var threshold: Variant = progress[shape]
				if (typeof(rate) != TYPE_INT and typeof(rate) != TYPE_FLOAT) or not is_finite(float(rate)) or float(rate) < 0.0 or float(rate) > 1000000000.0:
					errors.append("ore parser shape rate is outside the supported fixed-point range: " + String(shape))
				if (typeof(threshold) != TYPE_INT and typeof(threshold) != TYPE_FLOAT) or not is_finite(float(threshold)) or float(threshold) <= 0.0 or float(threshold) > 1000000000.0 or round(float(threshold) * 1000000.0) < 1.0:
					errors.append("ore parser progress-per-Jar must be positive and representable in fixed-point: " + String(shape))
	if ore_parser_count != 1:
		errors.append("battle loadout must select exactly one universal ore parser")

	var orders: Variant = source.get("selectedOrderBindings", null)
	if not (orders is Array):
		errors.append("selectedOrderBindings must be an array")
	else:
		var order_keys := {}
		for raw_order in orders:
			if not (raw_order is Dictionary):
				errors.append("selected order binding must be a dictionary")
				continue
			var order: Dictionary = raw_order
			var order_key := _required_text(order, "orderDefinitionKey")
			if order_key.is_empty() or order_keys.has(order_key):
				errors.append("orderDefinitionKey is missing or duplicated")
			else:
				order_keys[order_key] = true

			var jar_order: Variant = order.get("jarOrder", null)
			if not (jar_order is Dictionary):
				errors.append("selected order must contain jarOrder data")
			else:
				if not ["A", "B"].has(String(jar_order.get("type", ""))):
					errors.append("Jar order type must be A or B")
				var requirements: Variant = jar_order.get("requirements", null)
				if not (requirements is Array):
					errors.append("Jar order requirements must be an array")
				elif requirements.is_empty():
					errors.append("Jar order requirements must be non-empty")
				else:
					for raw_requirement in requirements:
						if not (raw_requirement is Dictionary):
							errors.append("Jar order requirement must be a dictionary")
							continue
						var requirement: Dictionary = raw_requirement
						if String(requirement.get("shape", "")).strip_edges().is_empty():
							errors.append("Jar order requirement must identify a shape")
				if int(jar_order.get("cooldownDurationLogicalMilli", -1)) < 0:
					errors.append("order cooldown cannot be negative")
				if not ["Active", "Passive"].has(String(jar_order.get("area", ""))):
					errors.append("order area must be Active or Passive")

			var skill_identity_present := order.has("skillDefinitionId") or order.has("skillDefinitionVersion")
			if skill_identity_present and (_required_text(order, "skillDefinitionId").is_empty() or int(order.get("skillDefinitionVersion", 0)) <= 0):
				errors.append("skill definition identity must be fully versioned")
			if order.has("skillControl"):
				var skill_control: Variant = order.get("skillControl")
				if not (skill_control is Dictionary):
					errors.append("skillControl must be a dictionary")
				else:
					var control_area := String(skill_control.get("area", ""))
					var activation_policy := String(skill_control.get("activationPolicy", ""))
					if not ["Active", "Passive"].has(control_area):
						errors.append("skill control area must be Active or Passive")
					if (control_area == "Active" and activation_policy != "Manual") or (control_area == "Passive" and activation_policy != "Automatic"):
						errors.append("skill activation policy must match its selected control area")

			var effect: Variant = order.get("effectBinding", null)
			var balance_report: Variant = order.get("balanceReport", null)
			if not (balance_report is Dictionary) or not bool(balance_report.get("valid", false)):
				errors.append("selected skill must include a valid benefit-to-Jar balance report")
			else:
				if float(balance_report.get("targetDifficulty", -1.0)) < 0.0 or float(balance_report.get("actualDifficulty", -1.0)) < 0.0:
					errors.append("balance report difficulty values must be non-negative")
				var breakdown: Variant = balance_report.get("costBreakdown", null)
				if not (breakdown is Dictionary):
					errors.append("balance report must include a cost breakdown")
				elif jar_order is Dictionary and jar_order.get("requirements", null) is Array:
					var required_liquid_jars := 0
					for requirement in jar_order["requirements"]:
						if requirement is Dictionary and not String(requirement.get("liquid", "")).strip_edges().is_empty():
							required_liquid_jars += 1
					if int(breakdown.get("jarCount", -1)) != jar_order["requirements"].size() or int(breakdown.get("liquidJarCount", -1)) != required_liquid_jars:
						errors.append("balance report cost breakdown does not match actual Jar requirements")
			var balance_context: Variant = order.get("balanceContext", null)
			if not (balance_context is Dictionary) or not bool(balance_context.get("valid", false)) or float(balance_context.get("expectedBattleDurationLogicalMilli", 0.0)) <= 0.0:
				errors.append("selected skill must include build-derived production/workshop difficulty context")
			var balance_profile: Variant = order.get("balanceProfile", null)
			if not (balance_profile is Dictionary) or _required_text(balance_profile, "profileId").is_empty() or int(balance_profile.get("profileVersion", 0)) <= 0:
				errors.append("selected skill must identify its balance profile version")

			if not (effect is Dictionary):
				errors.append("effectBinding must be a dictionary")
			else:
				if _required_text(effect, "effectDefinitionId").is_empty() or int(effect.get("effectDefinitionVersion", 0)) <= 0:
					errors.append("effectBinding must identify a versioned Space effect")
				if not (effect.get("effectParameters", {}) is Dictionary):
					errors.append("effectParameters must be a dictionary")

	return errors

func ship_world_id() -> String:
	return String(_data.get("shipWorldId", ""))

func loadout_id() -> String:
	return String(_data.get("loadoutId", ""))

func loadout_version() -> int:
	return int(_data.get("loadoutVersion", 0))

func loadout_fingerprint() -> String:
	return String(_data.get("loadoutFingerprint", ""))

func to_dictionary() -> Dictionary:
	return _data.duplicate(true)

func jar_world_options() -> Dictionary:
	return _data.get("jarWorldOptions", {}).duplicate(true)

func jar_world_options_json() -> String:
	return JSON.stringify(jar_world_options())

func selected_order_bindings() -> Array:
	return _data.get("selectedOrderBindings", []).duplicate(true)
func ore_parser_profile() -> Dictionary:
	for device in _data.get("productionDeviceSelections", []):
		if String(device.get("deviceKind", "")) == "ore_parser":
			return device.get("oreParserProfile", {}).duplicate(true)
	return {}


func order_definition_keys() -> PackedStringArray:
	var result := PackedStringArray()
	for order in _data.get("selectedOrderBindings", []):
		result.append(String(order.get("orderDefinitionKey", "")))
	return result

func resolve_order_binding(order_definition_key: String) -> Dictionary:
	for order in _data.get("selectedOrderBindings", []):
		if String(order.get("orderDefinitionKey", "")) == order_definition_key:
			return order.duplicate(true)
	return {}

static func _required_text(source: Dictionary, key: String) -> String:
	return String(source.get(key, "")).strip_edges()
