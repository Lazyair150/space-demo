extends Node
class_name StatusEffectManager
# 临时状态效果（Buff / Debuff）管理器。
#
# 与 PlayerFeatures 的分工：
#   · PlayerFeatures 管"角色拥有哪些能力"，常驻、由玩家开关；
#   · 本管理器管"角色当前处于什么状态"，有剩余时间、层数、来源，到期必须撤回。
#
# 第一阶段只接 on_apply / on_expire / on_tick 三个回调；
# on_before_damage / on_hit 要等伤害结算顺序与命中上下文定下来再接。

signal buff_added(definition: BuffDefinition, stacks: int)
signal buff_removed(definition: BuffDefinition)
signal buff_refreshed(definition: BuffDefinition, remaining: float, stacks: int)

@export var stats_path: NodePath

var _instances: Array = []   # BuffInstance
var _stats: StatCalculator

func _ready() -> void:
	_stats = get_node_or_null(stats_path) as StatCalculator

# 供测试按显式 delta 驱动；正常运行时 _process 走同一条路径
func _process(delta: float) -> void:
	advance(delta)

func bind_stats(stats: StatCalculator) -> void:
	_stats = stats

func apply(definition: BuffDefinition, target: Node = null, duration_override: float = -1.0) -> BuffInstance:
	if definition == null or not definition.is_valid():
		return null
	var duration := definition.duration if duration_override < 0.0 else duration_override
	var existing := find(definition.id)

	if existing != null:
		match definition.stack_policy:
			BuffDefinition.StackPolicy.REJECT:
				return existing
			BuffDefinition.StackPolicy.REFRESH:
				existing.remaining = duration
				buff_refreshed.emit(definition, existing.remaining, existing.stacks)
				return existing
			BuffDefinition.StackPolicy.EXTEND:
				existing.remaining += duration
				buff_refreshed.emit(definition, existing.remaining, existing.stacks)
				return existing
			BuffDefinition.StackPolicy.KEEP_STRONGEST:
				if existing.stacks >= definition.max_stacks:
					existing.remaining = duration
					buff_refreshed.emit(definition, existing.remaining, existing.stacks)
					return existing
			BuffDefinition.StackPolicy.REPLACE:
				_remove_instance(existing)
			BuffDefinition.StackPolicy.ADD_STACK:
				existing.stacks = mini(definition.max_stacks, existing.stacks + 1)
				existing.remaining = duration
				_register_modifiers(existing)
				buff_refreshed.emit(definition, existing.remaining, existing.stacks)
				return existing
			BuffDefinition.StackPolicy.INDEPENDENT:
				pass

	var instance := _new_instance(definition)
	instance.setup(definition, target, duration)
	_instances.append(instance)
	_register_modifiers(instance)
	instance.on_apply()
	buff_added.emit(definition, instance.stacks)
	return instance

func remove(id: StringName) -> bool:
	var instance := find(id)
	if instance == null:
		return false
	_remove_instance(instance)
	return true

func clear_all() -> void:
	for instance in _instances.duplicate():
		_remove_instance(instance)

func find(id: StringName) -> BuffInstance:
	for instance in _instances:
		if instance.definition != null and instance.definition.id == id:
			return instance
	return null

func has(id: StringName) -> bool:
	return find(id) != null

func remaining(id: StringName) -> float:
	var instance := find(id)
	return instance.remaining if instance != null else 0.0

func stacks(id: StringName) -> int:
	var instance := find(id)
	return instance.stacks if instance != null else 0

func count() -> int:
	return _instances.size()

func active_ids() -> Array:
	var out: Array = []
	for instance in _instances:
		if instance.definition != null:
			out.append(instance.definition.id)
	return out

func advance(delta: float) -> int:
	if delta <= 0.0:
		return 0
	var ticks := 0
	for instance in _instances.duplicate():
		ticks += instance.advance(delta)
		if instance.is_expired():
			_remove_instance(instance)
	return ticks

# --- 内部 ---

func _new_instance(definition: BuffDefinition) -> BuffInstance:
	if definition.instance_script != null:
		var made = definition.instance_script.new()
		if made is BuffInstance:
			return made
		push_warning("instance_script 不是 BuffInstance：%s" % String(definition.id))
	return BuffInstance.new()

func _remove_instance(instance: BuffInstance) -> void:
	# 先撤修正器再回调，保证 on_expire 里看到的属性已经回到"没有这个 buff"的状态
	if _stats != null:
		_stats.remove_modifiers_by_owner(instance.owner_key())
	_instances.erase(instance)
	instance.on_expire()
	buff_removed.emit(instance.definition)

func _register_modifiers(instance: BuffInstance) -> void:
	if _stats == null:
		push_warning("StatusEffectManager 没有绑定 StatCalculator，修正器不会生效")
		return
	# 先清掉这个 owner 的旧修正器，再按当前层数重登，保证"重复施加不残留"
	_stats.remove_modifiers_by_owner(instance.owner_key())
	if instance.definition == null:
		return
	for entry in instance.definition.modifiers:
		if not (entry is Dictionary):
			continue
		var stat := StringName(entry.get("stat", ""))
		if stat == &"":
			continue
		var stage := int(entry.get("stage", StatCalculator.Stage.FLAT))
		var value := float(entry.get("value", 0.0))
		# 层数是"乘到修正器上"的：加算阶段层数越多越强，符合直觉；
		# 但乘算阶段若有 <1 的系数（例如 0.6 的急速），叠层会变成 1.2 反而更慢——
		# 这种定义一旦叠层就是设计错误，先告警，不静默算错。
		if instance.stacks > 1 and stage == StatCalculator.Stage.MULT and absf(value) < 1.0:
			push_warning("Buff %s 的乘算修正 <1 且叠了 %d 层：结果会反直觉，请改用 FLAT 或不要叠层" % [String(instance.definition.id), instance.stacks])
		value *= float(instance.stacks)
		_stats.add_modifier(instance.owner_key(), stat, stage, value)
