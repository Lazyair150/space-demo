extends Node
class_name PlayerFeatures

func _unhandled_input(event: InputEvent) -> void:
	
	if not  event.is_pressed() or event.is_echo():
		return
	
	for feature in get_children():
		if not feature is PlayerFeature:\
			continue
		if feature.input_action ==&"":
			continue
		if event.is_action_pressed(feature.input_action):
			set_feature_active(
				feature.feature_id,
				not feature.active
			)

#获取指定能力
func get_feature(id:StringName)->PlayerFeature:
	for feature in get_children():
		if feature is PlayerFeature:
			if feature.feature_id==id:
				return feature
	return null

#开启或关闭能力
func set_feature_active(id:StringName,value:bool)->void:
	var feature=get_feature(id)
	if feature==null:
		push_warning("没有找到能力："+str(id))
		return
	if feature.active==value:
		return
	feature.active=value
	if value:
		feature.on_feature_enabled()
	else:
		feature.on_feature_disabled()

# 通知所有能力：玩家发起攻击
func notify_attack(player:Node2D)->void:
	for feature in  get_children():
		if feature is PlayerFeature and feature.active:
			feature.on_attack(player)

# 询问所有能力：是否有人抵挡了伤害
func try_block_damage(player: Node2D, amount: int) -> bool:
	for feature in get_children():
		if feature is PlayerFeature and feature.active:
			if feature.try_block_damage(player, amount):
				return true

	return false
