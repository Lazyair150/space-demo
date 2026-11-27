extends Resource
class_name SpaceParserSupplyEvaluationContext
## Encounter-side inputs for parser sustain evaluation, not parser-owned attributes.

@export var energy_stone_drop_profile: SpaceEnergyStoneDropProfile
@export_range(0.0, 1000000.0, 0.001) var expected_enemy_defeats_per_second: float = 0.0

func get_validation_errors(shape_vocabulary: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if energy_stone_drop_profile == null:
		errors.append("exact energy-stone drop profile is required")
	else:
		errors.append_array(energy_stone_drop_profile.get_validation_errors(shape_vocabulary))
	if not is_finite(expected_enemy_defeats_per_second) or expected_enemy_defeats_per_second <= 0.0:
		errors.append("expected enemy defeat rate must be finite and positive")
	return errors

func build_frozen_context() -> Dictionary:
	if energy_stone_drop_profile == null:
		return {}
	return {
		"dropProfile": energy_stone_drop_profile.build_runtime_profile(),
		"expectedEnemyDefeatsPerSecond": expected_enemy_defeats_per_second
	}
