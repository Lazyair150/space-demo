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
## 由 Space 主世界统一提供时间时启用；此时禁止本节点用独立 _process 推进。
@export var external_time_authority: bool = false

var _instances: Array = []   # BuffInstance
var _stats: StatCalculator
var _processed_order_event_ids: Dictionary = {}

func _ready() -> void:
	_stats = get_node_or_null(stats_path) as StatCalculator

# 供测试按显式 delta 驱动；正常运行时 _process 走同一条路径
func _process(delta: float) -> void:
	if external_time_authority:
		return
	advance(delta)

## Space 世界时钟入口。外部时钟模式下每个世界推进步恰好调用一次。
func advance_from_space_world(delta: float) -> int:
	if not external_time_authority:
		push_error("StatusEffectManager 尚未启用 external_time_authority")
		return 0
	if delta < 0.0:
		push_error("Buff 世界时间增量不能为负数")
		return 0
	return advance(delta)

func bind_stats(stats: StatCalculator) -> void:
	_stats = stats

func apply(definition: BuffDefinition, target: Node = null, duration_override: float = -1.0, target_key: String = "") -> BuffInstance:
	if definition == null or not definition.is_valid():
		return null
	var duration := definition.duration if duration_override < 0.0 else duration_override
	if definition.stack_policy == BuffDefinition.StackPolicy.INDEPENDENT:
		# owner_key 目前按定义 id 生成，两个同源实例会互相撤掉修正器，
		# 所以 INDEPENDENT 还没真正实现，先拒绝而不是算错
		push_warning("INDEPENDENT 叠加策略尚未实现（owner_key 按定义 id 生成），已按 REFRESH 处理：%s" % String(definition.id))
	if definition.stack_policy == BuffDefinition.StackPolicy.KEEP_STRONGEST and find(definition.id) != null:
		push_warning("KEEP_STRONGEST 尚未实现比较规则（只比层数，不比强度），已按 REFRESH 处理：%s" % String(definition.id))

	var existing := find(definition.id)

	if existing != null:
		match definition.stack_policy:
			BuffDefinition.StackPolicy.REJECT:
				return existing
			BuffDefinition.StackPolicy.REFRESH, BuffDefinition.StackPolicy.INDEPENDENT, BuffDefinition.StackPolicy.KEEP_STRONGEST:
				# INDEPENDENT / KEEP_STRONGEST 目前按 REFRESH 处理：
				# owner_key 按定义 id 生成，同源多实例会互相撤掉修正器，所以绝不新建第二个实例。
				existing.remaining = duration
				existing.reset_tick_progress()
				buff_refreshed.emit(definition, existing.remaining, existing.stacks)
				return existing
			BuffDefinition.StackPolicy.EXTEND:
				existing.extend_duration(duration)
				buff_refreshed.emit(definition, existing.remaining, existing.stacks)
				return existing
			BuffDefinition.StackPolicy.REPLACE:
				_remove_instance(existing)
			BuffDefinition.StackPolicy.ADD_STACK:
				existing.stacks = mini(definition.max_stacks, existing.stacks + 1)
				existing.remaining = duration
				existing.reset_tick_progress()
				_register_modifiers(existing)
				buff_refreshed.emit(definition, existing.remaining, existing.stacks)
				return existing

	var instance := _new_instance(definition)
	instance.setup(definition, target, duration, target_key)
	_instances.append(instance)
	_register_modifiers(instance)
	instance.on_apply()
	buff_added.emit(definition, instance.stacks)
	return instance

## Runtime idempotency prevents a failed durable write/retry from stacking the same event twice.
func apply_order_event(event_id: String, definition: BuffDefinition, target: Node = null, duration_override: float = -1.0, target_key: String = "") -> BuffInstance:
	if event_id.strip_edges().is_empty():
		push_error("Order effect event ID is required")
		return null
	if _processed_order_event_ids.has(event_id):
		return find(definition.id) if definition != null else null
	if definition == null:
		return null
	var instance := apply(definition, target, duration_override, target_key)
	if instance != null:
		_processed_order_event_ids[event_id] = true
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

## HUD 用的只读快照：不改内部状态，也不暴露实例本身
func active_entries() -> Array:
	var out: Array = []
	for instance in _instances:
		if instance.definition == null:
			continue
		out.append({
			"id": instance.definition.id,
			"label": instance.definition.label,
			"remaining": instance.remaining,
			"stacks": instance.stacks,
		})
	return out

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


## Capture all manager-owned state needed to reconstruct active effects and idempotency.
func capture_runtime_state() -> Dictionary:
	var entries: Array = []
	for instance in _instances:
		entries.append(instance.capture_runtime_state())
	var event_ids := _processed_order_event_ids.keys()
	event_ids.sort()
	return {"schemaVersion": 1, "instances": entries, "processedOrderEventIds": event_ids}

## Stage and validate the entire snapshot before mutating the live manager.
## definition_resolver(id, version) -> BuffDefinition; target_resolver(target_key) -> Node.
func restore_runtime_state(snapshot: Dictionary, definition_resolver: Callable, target_resolver: Callable) -> bool:
	if int(snapshot.get("schemaVersion", 0)) != 1 or not definition_resolver.is_valid() or not target_resolver.is_valid():
		return false
	var raw_entries: Variant = snapshot.get("instances", null)
	var raw_ids: Variant = snapshot.get("processedOrderEventIds", null)
	if not (raw_entries is Array) or not (raw_ids is Array):
		return false
	var staged_instances: Array = []
	var staged_ids := {}
	for raw_id in raw_ids:
		var event_id := String(raw_id)
		if event_id.is_empty() or staged_ids.has(event_id):
			return false
		staged_ids[event_id] = true
	for raw_entry in raw_entries:
		if not (raw_entry is Dictionary):
			return false
		var entry: Dictionary = raw_entry
		var definition: Variant = definition_resolver.call(String(entry.get("definitionId", "")), int(entry.get("definitionVersion", 0)))
		if not (definition is BuffDefinition):
			return false
		var target_key := String(entry.get("targetKey", ""))
		var target: Variant = target_resolver.call(target_key)
		if target != null and not (target is Node):
			return false
		var instance := _new_instance(definition)
		if not instance.restore_runtime_state(entry, definition, target as Node):
			return false
		for existing in staged_instances:
			if existing.definition.id == instance.definition.id:
				return false
		staged_instances.append(instance)
	# Commit only after every resource, target and runtime field has validated.
	for old_instance in _instances.duplicate():
		_remove_instance(old_instance)
	_instances.clear()
	_processed_order_event_ids = staged_ids
	for instance in staged_instances:
		_instances.append(instance)
		_register_modifiers(instance)
		# Deliberately do not call on_apply: this is reconstruction, not a new application.
	return true
