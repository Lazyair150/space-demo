extends Node
class_name PlayerFeature

@export var feature_id:StringName

@export var active:bool=false

@export var input_action: StringName

func on_feature_enabled()->void:
	pass

func on_feature_disabled()->void:
	pass

# 玩家发起攻击时调用
func on_attack(player:Node2D)->void:
	pass
	
# 玩家受到伤害前调用
# 返回 true：本次伤害已经被处理，不再扣血
# 返回 false：继续执行正常伤害逻辑
func try_block_damage(player:Node2D,amount:int)->bool:
	return false
