extends Resource
class_name SpaceIndividualPowerModelDefinition
## Subsystem-authored metric normalization model. Metric names and bounds belong to the owning subsystem.

const SUPPORTED_KINDS := ["ore_parser", "workshop", "skill"]

@export var model_id: StringName = &""
@export var definition_version: int = 1
@export_enum("ore_parser", "workshop", "skill") var item_kind: String = "skill"
## Unconfigured models may be evaluated in isolated tuning probes, but never referenced by production pools.
@export_enum("unconfigured", "configured") var configuration_status: String = "unconfigured"
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
		var scoring_mode := String(dimension.get("scoringMode", ""))
		if scoring_mode.is_empty():
			if typeof(dimension.get("higherIsBetter", null)) != TYPE_BOOL:
				errors.append("legacy directional metric must declare higherIsBetter: " + String(metric))
		elif not ["higher_is_better", "lower_is_better", "target_value"].has(scoring_mode):
			errors.append("power metric scoringMode is unsupported: " + String(metric))
		elif scoring_mode == "target_value":
			var target: Variant = dimension.get("targetValue", null)
			if not _valid_number(target) or float(target) < float(minimum) or float(target) > float(maximum):
				errors.append("target_value metric requires targetValue inside its model bounds: " + String(metric))
		elif dimension.has("targetValue"):
			errors.append("directional metric must not declare targetValue: " + String(metric))
	if total_weight <= 0.0:
		errors.append("power model requires positive total metric weight")
	return errors

## Production pools require explicit semantic direction/target and a configured model version.
## This gate is intentionally stricter than structural validation used by tuning Probes.
func get_production_validation_errors() -> PackedStringArray:
	var errors := get_validation_errors()
	if not errors.is_empty():
		return errors
	if configuration_status != "configured":
		errors.append("power model is unconfigured and cannot be referenced by a production pool")
	for metric in metric_dimensions:
		var dimension: Dictionary = metric_dimensions[metric]
		var mode := String(dimension.get("scoringMode", ""))
		if mode.is_empty():
			errors.append("production power metric must explicitly declare scoringMode: " + String(metric))
		if item_kind == "workshop" and ["max_jars", "max_liquids", "liquid_staging_capacity"].has(String(metric)) and mode != "target_value":
			errors.append("workshop capacity metric must use target_value rather than assuming more is always better: " + String(metric))
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
		var scoring_mode := String(dimension.get("scoringMode", ""))
		var normalized := (float(value) - minimum) / (maximum - minimum)
		match scoring_mode:
			"higher_is_better":
				pass
			"lower_is_better":
				normalized = 1.0 - normalized
			"target_value":
				var target := float(dimension.targetValue)
				if is_equal_approx(float(value), target):
					normalized = 1.0
				elif float(value) < target:
					var lower_span := target - minimum
					normalized = 0.0 if lower_span <= 0.0 else 1.0 - (target - float(value)) / lower_span
				else:
					var upper_span := maximum - target
					normalized = 0.0 if upper_span <= 0.0 else 1.0 - (float(value) - target) / upper_span
			_:
				if not bool(dimension.higherIsBetter):
					normalized = 1.0 - normalized
		var weight := float(dimension.weight)
		weighted_score += normalized * weight
		total_weight += weight
	return {"success": true, "powerScore": 10.0 * weighted_score / total_weight, "powerModelId": String(model_id), "powerModelVersion": definition_version}

func _valid_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
