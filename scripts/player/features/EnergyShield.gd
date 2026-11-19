extends PlayerFeature
class_name EnergyShield

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

	print("能量盾抵挡了伤害！")

	return true


func set_feature_active_by_self(value: bool) -> void:
	active = value
	visual.visible = value
