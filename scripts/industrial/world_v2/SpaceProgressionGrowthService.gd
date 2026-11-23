extends RefCounted
class_name SpaceProgressionGrowthService
## Calculates an instance update from total accumulated XP and an exact curve version.
## It does not persist the update; the player aggregate performs the revision-checked commit.

static func calculate_update(
	instance: SpaceOwnedProgressionInstance,
	curve: SpaceProgressionCurveDefinition,
	total_experience: int
) -> SpaceOwnedProgressionInstance:
	if instance == null or curve == null:
		return null
	if not instance.get_validation_errors().is_empty() or not curve.get_validation_errors().is_empty():
		return null
	if instance.item_kind != curve.item_kind or total_experience < instance.experience:
		return null
	var target_level := curve.level_for_experience(total_experience)
	if target_level < instance.level:
		return null
	var growth := curve.build_growth_attributes(target_level)
	if growth.is_empty():
		return null
	var updated := instance.duplicate(true) as SpaceOwnedProgressionInstance
	if not updated.apply_progression(total_experience - instance.experience, target_level, growth):
		return null
	updated.growth_curve_id = curve.curve_id
	updated.growth_curve_version = curve.definition_version
	return updated

static func apply_to_player_state(
	player_state: SpacePlayerProgressionState,
	instance_id: String,
	curve: SpaceProgressionCurveDefinition,
	total_experience: int
) -> bool:
	if player_state == null or curve == null:
		return false
	var current := player_state.resolve_instance(instance_id)
	if current == null:
		return false
	var updated := calculate_update(current, curve, total_experience)
	return updated != null and player_state.replace_instance_progression(updated)
