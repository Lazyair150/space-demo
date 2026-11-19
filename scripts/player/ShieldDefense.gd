extends Node
# 把"能量盾"这个 PlayerFeature 适配成伤害管线里的防御组件。
# 盾本身还是原来的能力（按 K 开关、挡一次就关掉），这里只负责在伤害结算时问它一句。

@export var defense_id: StringName = &"shield"
@export var player_path: NodePath

func resolve_defense(info: DamageInfo) -> int:
	var player := get_node_or_null(player_path)
	if player == null:
		return 0
	var features = player.get("features")
	if features == null or not features.has_method("try_block_damage"):
		return 0
	return info.amount if features.try_block_damage(player, info.amount) else 0
