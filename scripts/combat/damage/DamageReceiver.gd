class_name DamageReceiver
extends Node
# 受击方的唯一入口：把一次 DamageInfo 结算成 DamageResult。
#
# 顺序是固定的（也是唯一允许加规则的地方）：
#   1. 目标还活着吗
#   2. 逐个防御组件询问（无敌 / 护盾 / 未来的护甲），每个组件返回自己挡掉多少
#   3. 剩下的交给 Health 扣血
#   4. 产出 DamageResult 并广播
#
# 攻击方不需要知道目标有没有盾、有几层、会不会无敌——它只描述这次攻击。

signal resolved(result: DamageResult)

@export var health_path: NodePath
## 防御组件（任何实现了 resolve_defense(info) -> int 的节点），按数组顺序询问
@export var defense_paths: Array[NodePath] = []

var health: Health
var defenses: Array[Node] = []

func _ready() -> void:
	if not health_path.is_empty():
		health = get_node_or_null(health_path) as Health
	for path in defense_paths:
		var node := get_node_or_null(path)
		if node != null:
			defenses.append(node)
	if health == null:
		push_warning("DamageReceiver 没有找到 Health（health_path=%s）" % String(health_path))

## 新代码走这里：带上下文、带结算结果
func receive(info: DamageInfo) -> DamageResult:
	if health == null:
		var missing := DamageResult.blocked(info.amount, &"no_health", info)
		resolved.emit(missing)
		return missing
	if not health.is_alive():
		var dead := DamageResult.blocked(info.amount, &"dead", info)
		resolved.emit(dead)
		return dead

	var result := DamageResult.new()
	result.requested = info.amount
	result.hit_position = info.hit_position
	result.info = info

	var remaining := info.amount
	for defense in defenses:
		if remaining <= 0:
			break
		if defense == null or not is_instance_valid(defense):
			continue
		var blocked := 0
		if defense.has_method("resolve_defense"):
			blocked = int(defense.resolve_defense(info))
		elif defense.has_method("try_block") and defense.try_block(info):
			blocked = remaining
		if blocked <= 0:
			continue
		blocked = mini(blocked, remaining)
		result.absorbed += blocked
		result.blocked_by = _defense_id(defense)
		remaining -= blocked

	result.hp_damage = health.apply_damage(remaining, info)
	result.died = not health.is_alive()
	resolved.emit(result)
	return result

## 旧接口适配器：迁移期两套调用并存，行为必须一致
func take_damage(amount: int, type: StringName = &"legacy") -> DamageResult:
	return receive(DamageInfo.make(amount, type))

func is_alive() -> bool:
	return health != null and health.is_alive()

func _defense_id(defense: Node) -> StringName:
	var id = defense.get("defense_id")
	return StringName(id) if id != null else StringName(defense.name)
