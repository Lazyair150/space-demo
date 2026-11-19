extends BuffInstance
class_name PoisonBuffInstance
# 中毒：每个 tick 对携带者造成一次伤害。
# 故意走目标自己的 take_damage，这样无敌时间、能量盾、以后可能加的减伤都会照常生效——
# 定时伤害不能绕过受伤判定，否则护盾会被中毒悄悄打穿。

func on_tick() -> void:
	if definition == null:
		return
	if not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.take_damage(maxi(1, definition.tick_damage))
