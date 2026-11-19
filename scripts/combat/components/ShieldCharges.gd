class_name ShieldCharges
extends Node
# 通用"次数护盾"防御组件：谁都能挂，不依赖 PlayerFeatures。
# 每次挡下一整次伤害消耗 1 次；次数用尽后不再参与结算。
#
# 与能量盾的区别：能量盾是玩家能力（按 K 开关、挡一次自动关闭），
# 这里是纯数据组件，敌人也可以用它验证"防御组件能否跨角色复用"。

@export var defense_id: StringName = &"shield_charges"
@export var charges: int = 1

func resolve_defense(info: DamageInfo) -> int:
	if charges <= 0 or info.amount <= 0:
		return 0
	charges -= 1
	return info.amount

func remaining() -> int:
	return charges
