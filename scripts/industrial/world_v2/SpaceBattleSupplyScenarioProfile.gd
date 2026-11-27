extends Resource
class_name SpaceBattleSupplyScenarioProfile
## Versioned sensitivity assumptions for expected enemy defeats.
## These rates are authored/planning inputs, not facts inferred from stage wave counts.

const SCENARIO_KEYS: Array[String] = ["low", "baseline", "high"]
const MAX_DEFEATS_PER_SECOND: float = 1000000.0

@export var profile_id: StringName = &""
@export var profile_version: int = 1
@export var low_expected_enemy_defeats_per_second: float = 0.0
@export var baseline_expected_enemy_defeats_per_second: float = 0.0
@export var high_expected_enemy_defeats_per_second: float = 0.0

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if profile_id == &"" or String(profile_id).strip_edges() != String(profile_id):
		errors.append("supply scenario profile requires a canonical non-empty profile ID")
	if profile_version <= 0:
		errors.append("supply scenario profile version must be positive")
	var rates := {
		"low": low_expected_enemy_defeats_per_second,
		"baseline": baseline_expected_enemy_defeats_per_second,
		"high": high_expected_enemy_defeats_per_second
	}
	for key in SCENARIO_KEYS:
		var rate := float(rates[key])
		if not is_finite(rate) or rate < 0.0 or rate > MAX_DEFEATS_PER_SECOND:
			errors.append("%s expected enemy defeat rate must be finite and within 0..%s" % [key, str(MAX_DEFEATS_PER_SECOND)])
	if errors.is_empty():
		if low_expected_enemy_defeats_per_second > baseline_expected_enemy_defeats_per_second:
			errors.append("low expected enemy defeat rate cannot exceed baseline")
		if baseline_expected_enemy_defeats_per_second > high_expected_enemy_defeats_per_second:
			errors.append("baseline expected enemy defeat rate cannot exceed high")
	return errors

func is_valid() -> bool:
	return get_validation_errors().is_empty()

func build_runtime_profile() -> Dictionary:
	if not is_valid():
		return {}
	return {
		"profileId": String(profile_id),
		"profileVersion": profile_version,
		"expectedEnemyDefeatsPerSecondByBand": {
			"low": low_expected_enemy_defeats_per_second,
			"baseline": baseline_expected_enemy_defeats_per_second,
			"high": high_expected_enemy_defeats_per_second
		}
	}

static func from_runtime_profile(source: Dictionary) -> SpaceBattleSupplyScenarioProfile:
	var profile_id_value: Variant = source.get("profileId", null)
	var version_value: Variant = source.get("profileVersion", null)
	var raw_rates: Variant = source.get("expectedEnemyDefeatsPerSecondByBand", null)
	if typeof(profile_id_value) != TYPE_STRING or typeof(version_value) != TYPE_INT or not (raw_rates is Dictionary):
		return null
	if raw_rates.size() != SCENARIO_KEYS.size():
		return null
	for key in SCENARIO_KEYS:
		if not raw_rates.has(key) or typeof(raw_rates[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return null
	for key in raw_rates:
		if not SCENARIO_KEYS.has(String(key)):
			return null
	var profile := SpaceBattleSupplyScenarioProfile.new()
	profile.profile_id = StringName(profile_id_value)
	profile.profile_version = int(version_value)
	profile.low_expected_enemy_defeats_per_second = float(raw_rates["low"])
	profile.baseline_expected_enemy_defeats_per_second = float(raw_rates["baseline"])
	profile.high_expected_enemy_defeats_per_second = float(raw_rates["high"])
	return profile if profile.is_valid() else null
