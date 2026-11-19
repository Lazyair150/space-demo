extends RefCounted
class_name CombatFx
# 表现层小工具：把一次结算结果显示成飘字。
# 放在 combat 目录但只做表现——它不参与任何规则判断。

static func show_damage(parent: Node, result: DamageResult) -> void:
	if parent == null or result == null:
		return
	if result.hp_damage == 0 and result.absorbed == 0:
		return
	var label: Node = (load("res://scripts/combat/FloatingDamage.gd") as Script).new()
	label.position = result.hit_position
	parent.add_child(label)
	label.show_result(result)
