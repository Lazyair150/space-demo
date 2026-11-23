extends Resource
class_name SpaceSkillBalanceProfile
## Data-only tuning profile for the benefit <-> Jar execution difficulty curve.
## Values are balance parameters, not gameplay constants hidden in code.

@export var profile_id: StringName = &"default"
@export var profile_version: int = 1

## Benefit score = weighted normalized effect dimensions.
@export var benefit_weights: Dictionary = {
	"power": 1.0,
	"duration": 0.25,
	"coverage": 0.35,
	"control": 0.45,
	"survivability": 0.8,
	"utility": 0.3,
	"periodic_damage": 0.5,
	"stack_potential": 0.2
}
@export var benefit_scales: Dictionary = {
	"power": 10.0,
	"duration": 10.0,
	"coverage": 1.0,
	"control": 10.0,
	"survivability": 10.0,
	"utility": 10.0,
	"periodic_damage": 20.0,
	"stack_potential": 5.0
}

## Target difficulty curve: base + coefficient * benefit^exponent.
@export var curve_base_difficulty: float = 1.0
@export var curve_coefficient: float = 1.0
@export var curve_exponent: float = 1.25
@export var on_curve_min_ratio: float = 0.8
@export var on_curve_max_ratio: float = 1.25

## Shorter Jar cooldown means more activations per battle-time unit and therefore greater effective benefit.
@export var cooldown_reference_logical_milli: float = 10000.0
@export var cooldown_floor_logical_milli: float = 1000.0
@export var cooldown_max_frequency_multiplier: float = 5.0

## Actual Jar requirement difficulty. Every requirement entry represents one required jar.
@export var jar_base_weight: float = 1.0
@export var liquid_jar_weight: float = 2.0
@export var distinct_liquid_weight: float = 0.75
@export var distinct_shape_weight: float = 0.5
@export var order_type_b_weight: float = 1.0
@export var workshop_operation_weight: float = 0.5
@export var production_pressure_weight: float = 1.0

## Optional per-resource multipliers; absent entries default to 1.0.
@export var shape_difficulty_multipliers: Dictionary = {}
@export var liquid_difficulty_multipliers: Dictionary = {}

## Difficulty bands are reporting thresholds, not automatic gameplay gates.
@export var difficulty_bands: Array[Dictionary] = [
	{"id": "entry", "minimum": 0.0},
	{"id": "standard", "minimum": 4.0},
	{"id": "advanced", "minimum": 9.0},
	{"id": "elite", "minimum": 16.0}
]

func is_valid() -> bool:
	if profile_id == &"" or profile_version <= 0:
		return false
	if curve_base_difficulty < 0.0 or curve_coefficient < 0.0 or curve_exponent <= 0.0:
		return false
	if cooldown_reference_logical_milli <= 0.0 or cooldown_floor_logical_milli <= 0.0 or cooldown_floor_logical_milli > cooldown_reference_logical_milli or cooldown_max_frequency_multiplier < 1.0:
		return false
	if on_curve_min_ratio < 0.0 or on_curve_max_ratio <= on_curve_min_ratio:
		return false
	if benefit_weights.is_empty():
		return false
	for key in benefit_weights:
		if float(benefit_weights[key]) < 0.0:
			return false
		if float(benefit_scales.get(key, 0.0)) <= 0.0:
			return false
	for value in [jar_base_weight, liquid_jar_weight, distinct_liquid_weight,
		distinct_shape_weight, order_type_b_weight, workshop_operation_weight,
		production_pressure_weight]:
		if value < 0.0:
			return false
	for multiplier in shape_difficulty_multipliers.values():
		if float(multiplier) <= 0.0:
			return false
	for multiplier in liquid_difficulty_multipliers.values():
		if float(multiplier) <= 0.0:
			return false
	var previous := -1.0
	for band in difficulty_bands:
		var minimum := float(band.get("minimum", -1.0))
		if String(band.get("id", "")).is_empty() or minimum < 0.0 or minimum <= previous:
			return false
		previous = minimum
	return true
