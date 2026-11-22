extends RefCounted
class_name SpaceBattleLoadoutSnapshot
## Immutable-by-interface snapshot of the four player-authored pre-battle build dimensions.
## Mutable source dictionaries are deep-copied on creation and on every read.

const CURRENT_SCHEMA_VERSION: int = 1

var _data: Dictionary = {}

static func create(source: Dictionary) -> SpaceBattleLoadoutSnapshot:
	var errors := validate_data(source)
	if not errors.is_empty():
		push_error("Space battle loadout rejected: " + "; ".join(errors))
		return null
	var snapshot := SpaceBattleLoadoutSnapshot.new()
	snapshot._data = source.duplicate(true)
	return snapshot

static func validate_data(source: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(source.get("schemaVersion", 0)) != CURRENT_SCHEMA_VERSION:
		errors.append("unsupported schemaVersion")
	if _required_text(source, "shipWorldId").is_empty():
		errors.append("shipWorldId is required")
	if _required_text(source, "loadoutId").is_empty():
		errors.append("loadoutId is required")
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

			var effect: Variant = order.get("effectBinding", null)
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

func to_dictionary() -> Dictionary:
	return _data.duplicate(true)

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
