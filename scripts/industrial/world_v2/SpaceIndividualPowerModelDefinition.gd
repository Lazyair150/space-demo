extends Resource
class_name SpaceIndividualPowerModelDefinition
## Subsystem-authored metric normalization model. Metric names and bounds belong to the owning subsystem.

@export var model_id: StringName = &""
@export var definition_version: int = 1
@export_enum("ore_parser", "workshop", "skill") var item_kind: String = "skill"
## metric -> {minimum, maximum, weight, higherIsBetter}
@export var metric_dimensions: Dictionary = {}

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if model_id == &"" or definition_version <= 0 or not SUPPORTED_KINDS.has(item_kind):
		errors.append("power model requires a stable versioned supported item kind")
	if metric_dimensions.is_empty():
		errors.append("power model requires at least one subsystem metric dimension")
	var total_weight := 0.0
	for metric in metric_dimensions:
		var dimension: Variant = metric_dimensions[metric]
		if String(metric).strip_edges().is_empty() or not (dimension is Dictionary):
			errors.append("power metric dimension must be a named dictionary")
			continue
		var minimum: Variant = dimension.get("minimum", null)
		var maximum: Variant = dimension.get("maximum", null)
		var weight: Variant = dimension.get("weight", null)
		if not _valid_number(minimum) or not _valid_number(maximum) or float(maximum) <= float(minimum):
			errors.append("power metric bounds are invalid: " + String(metric))
		if not _valid_number(weight) or float(weight) <= 0.0:
			errors.append("power metric weight must be positive: " + String(metric))
		else:
			total_weight += float(weight)
		if typeof(dimension.get("higherIsBetter", null)) != TYPE_BOOL:
			errors.append("power metric dimension must declare higherIsBetter: " + String(metric))
	if total_weight <= 0.0:
		errors.append("power model requires positive total metric weight")
	return errors

func calculate_power_score(metrics: Dictionary) -> Dictionary:
	var errors := get_validation_errors()
	if not errors.is_empty():
		return {"success": false, "reason": "; ".join(errors)}
	if metrics.size() != metric_dimensions.size():
		return {"success": false, "reason": "power metric payload must provide every configured dimension exactly once"}
	var weighted_score := 0.0
	var total_weight := 0.0
	for metric in metric_dimensions:
		if not metrics.has(metric):
			return {"success": false, "reason": "missing power metric: " + String(metric)}
		var value: Variant = metrics[metric]
		var dimension: Dictionary = metric_dimensions[metric]
		if not _valid_number(value):
			return {"success": false, "reason": "power metric is not finite: " + String(metric)}
		var minimum := float(dimension.minimum)
		var maximum := float(dimension.maximum)
		if float(value) < minimum or float(value) > maximum:
			return {"success": false, "reason": "power metric is outside its subsystem model range: " + String(metric)}
		var normalized := (float(value) - minimum) / (maximum - minimum)
		if not bool(dimension.higherIsBetter):
			normalized = 1.0 - normalized
		var weight := float(dimension.weight)
		weighted_score += normalized * weight
		total_weight += weight
	return {"success": true, "powerScore": 10.0 * weighted_score / total_weight, "powerModelId": String(model_id), "powerModelVersion": definition_version}

func _valid_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
