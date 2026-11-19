extends PlayerFeature
class_name EnergyShield

@export var block_invuln: float = 0.5

@onready var visual: Node2D = $Visual


func _ready() -> void:
	visual.visible = active


func on_feature_enabled() -> void:
	visual.visible = true


func on_feature_disabled() -> void:
	visual.visible = false


func try_block_damage(player: Node2D, amount: int) -> bool:

	var manager := get_parent() as PlayerFeatures

	if manager != null:
		manager.set_feature_active(feature_id, false)

	# 抵挡成功后给一段无敌窗口：盾碎的一瞬间玩家通常还贴在敌人身上，
	# 没有这段窗口会立刻掉第二次血，等于盾只值半条命。
	if player.has_method("grant_invuln"):
		player.grant_invuln(block_invuln)

	return true


func set_feature_active_by_self(value: bool) -> void:
	active = value
	visual.visible = value
