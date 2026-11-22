extends Resource
class_name SpaceJarWorldResourceProfile
## Versioned Space-owned profile that freezes the real Jar World V2 resource/workshop options.
## Liquid production rates retain Jar's unit: quantity per logical time unit (1000 logical ms).
## The battle evaluator uses logical milliseconds, so this is numerically per logical second.

const LOGICAL_MILLI_PER_TIME_UNIT: float = 1000.0

@export var profile_id: StringName = &""
@export var profile_version: int = 1
@export var world_options: Dictionary = {}

func is_valid() -> bool:
	return validate_world_options(world_options).is_empty() and profile_id != &"" and profile_version > 0

func get_validation_errors() -> Array[String]:
	var errors := validate_world_options(world_options)
	if profile_id == &"":
		errors.append("profile_id is required")
	if profile_version <= 0:
		errors.append("profile_version must be positive")
	return errors

func build_jar_world_options() -> Dictionary:
	if not is_valid():
		return {}
	return world_options.duplicate(true)

func build_liquid_economy_resources() -> Dictionary:
	if not is_valid():
		return {}
	var duration_unit_seconds := LOGICAL_MILLI_PER_TIME_UNIT / 1000.0
	if not is_equal_approx(duration_unit_seconds, 1.0):
		return {}
	return {
		"initialLiquids": world_options.initialLiquidStock.duplicate(true),
		"liquidOutputPerSecond": world_options.liquidProductionRates.duplicate(true),
		"liquidInventoryCapacity": int(world_options.shipLiquidCapacity),
		"liquidRateUnit": "per_logical_time_unit",
		"jarResourceProfileId": String(profile_id),
		"jarResourceProfileVersion": profile_version
	}

static func validate_world_options(options: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var shapes: Variant = options.get("shapes", null)
	var liquids: Variant = options.get("liquids", null)
	if not (shapes is Array) or shapes.is_empty():
		errors.append("shapes must be a non-empty array")
	if not (liquids is Array) or liquids.size() != 2:
		errors.append("liquids must contain exactly two entries")
	if not errors.is_empty():
		return errors
	if not _valid_names(shapes) or not _valid_names(liquids):
		errors.append("shape/liquid names must be non-empty and unique")
	var shape_set := {}
	for shape in shapes:
		shape_set[String(shape)] = true
	var liquid_set := {}
	for liquid in liquids:
		liquid_set[String(liquid)] = true

	var capacity: Variant = options.get("shipLiquidCapacity", null)
	if typeof(capacity) != TYPE_INT or int(capacity) < 0:
		errors.append("shipLiquidCapacity must be a non-negative integer")
	var stock: Variant = options.get("initialLiquidStock", null)
	var rates: Variant = options.get("liquidProductionRates", null)
	if not (stock is Dictionary):
		errors.append("initialLiquidStock must be a dictionary")
	if not (rates is Dictionary):
		errors.append("liquidProductionRates must be a dictionary")
	if stock is Dictionary:
		var total_stock := 0
		for key in stock:
			var amount: Variant = stock[key]
			if not liquid_set.has(String(key)) or typeof(amount) != TYPE_INT or int(amount) < 0:
				errors.append("initialLiquidStock contains an invalid liquid or amount: " + String(key))
			else:
				total_stock += int(amount)
		if typeof(capacity) == TYPE_INT and total_stock > int(capacity):
			errors.append("initialLiquidStock exceeds shared shipLiquidCapacity")
	if rates is Dictionary:
		for key in rates:
			var rate: Variant = rates[key]
			if not liquid_set.has(String(key)) or (typeof(rate) != TYPE_INT and typeof(rate) != TYPE_FLOAT):
				errors.append("liquidProductionRates contains an invalid liquid or rate: " + String(key))
			elif float(rate) < 0.0 or not is_finite(float(rate)):
				errors.append("liquidProductionRates must be finite and non-negative: " + String(key))

	var producers: Variant = options.get("producers", null)
	if not (producers is Array):
		errors.append("producers must be an array")
	else:
		for producer in producers:
			if not (producer is Dictionary) or String(producer.get("name", "")).strip_edges().is_empty():
				errors.append("producer entries require a name")
				continue
			var producer_rates: Variant = producer.get("rates", null)
			if not (producer_rates is Dictionary):
				errors.append("producer rates must be a dictionary")
				continue
			for shape in producer_rates:
				var rate: Variant = producer_rates[shape]
				if not shape_set.has(String(shape)) or (typeof(rate) != TYPE_INT and typeof(rate) != TYPE_FLOAT):
					errors.append("producer contains an invalid shape or rate: " + String(shape))
				elif float(rate) < 0.0 or not is_finite(float(rate)):
					errors.append("producer rates must be finite and non-negative: " + String(shape))

	var workshops: Variant = options.get("workshops", null)
	if not (workshops is Array) or workshops.is_empty():
		errors.append("workshops must be a non-empty array")
	else:
		var workshop_names := {}
		for workshop in workshops:
			if not (workshop is Dictionary):
				errors.append("workshop entries must be dictionaries")
				continue
			var name := String(workshop.get("name", "")).strip_edges()
			if name.is_empty() or workshop_names.has(name):
				errors.append("workshop names must be non-empty and unique")
			else:
				workshop_names[name] = true
			if not (workshop.get("baseMarks", null) is Array) or not (workshop.get("additionalMarks", null) is Array):
				errors.append("workshop shape marks must be arrays: " + name)
		else:
				for mark in workshop.baseMarks + workshop.additionalMarks:
					if not shape_set.has(String(mark)):
						errors.append("workshop references an unknown shape: " + String(mark))
			for ban in workshop.get("ban", []):
				var normalized := String(ban).trim_prefix("禁")
				if not liquid_set.has(normalized):
					errors.append("workshop references an unknown banned liquid: " + String(ban))
			for capacity_key in ["maxJars", "maxLiquids"]:
				if typeof(workshop.get(capacity_key, null)) != TYPE_INT or int(workshop[capacity_key]) <= 0:
					errors.append("workshop " + name + " requires positive " + capacity_key)
			if workshop.has("liquidStagingCapacity") and int(workshop.liquidStagingCapacity) < 0:
				errors.append("workshop liquidStagingCapacity cannot be negative")
		var master_name := String(options.get("masterWorkshopName", ""))
		var slave_name := String(options.get("slaveWorkshopName", ""))
		if not workshop_names.has(master_name):
			errors.append("masterWorkshopName must identify a configured workshop")
		if not slave_name.is_empty() and (not workshop_names.has(slave_name) or slave_name == master_name):
			errors.append("slaveWorkshopName must identify a different configured workshop")
	return errors

static func _valid_names(values: Array) -> bool:
	var seen := {}
	for value in values:
		var name := String(value).strip_edges()
		if name.is_empty() or seen.has(name):
			return false
		seen[name] = true
	return true
