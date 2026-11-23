extends RefCounted
class_name BuffInstance
# 一个角色身上正在生效的某个 Buff 的运行时状态。
# 生命周期由 StatusEffectManager 驱动；属性修正器的登记/撤销**不在这里**，
# 管理器统一按 owner_key 处理，避免某个 Buff 忘记撤回自己的修正。

var definition: BuffDefinition
var target: Node
## Stable battle-local identity used to restore target references after loading.
var target_key: String = ""
var remaining: float = 0.0
var stacks: int = 1

var _ticks_fired: int = 0
# 距离下一次 on_tick 还差多少秒。刷新/叠层时按策略重置或保留。
var _tick_acc: float = 0.0

func setup(def: BuffDefinition, owner_target: Node, duration: float, owner_target_key: String = "") -> void:
	definition = def
	target = owner_target
	target_key = owner_target_key
	remaining = duration
	stacks = 1
	_ticks_fired = 0
	_tick_acc = 0.0

# 施加瞬间（修正器已登记）回调；子类按需覆盖
func on_apply() -> void:
	pass

# 到期移除瞬间（修正器已被撤销）回调；**不要**在这里撤修正器
func on_expire() -> void:
	pass

# 定时触发；子类按需覆盖
func on_tick() -> void:
	pass

# 推进时间，返回这次推进里触发了几次 on_tick。
# 计时用"距下次 tick 的累积器"，而不是"总存活时长 / 间隔"：
# 后者会以初始 duration 为上限，刷新延长后定时效果就停了（这是修掉的真 bug）。
func advance(delta: float) -> int:
	if delta <= 0.0:
		return 0
	# 只把"真正还活着的时间"算进去：一次给 3 秒而 Buff 只剩 1.5 秒时，
	# 不能把后面 1.5 秒也算进来（否则到期后还会凭空掉一次血）。
	var step := minf(delta, remaining)
	remaining = maxf(0.0, remaining - step)
	if definition == null or definition.tick_interval <= 0.0:
		return 0
	_tick_acc += step
	var ticks := 0
	while _tick_acc + 0.000001 >= definition.tick_interval:
		_tick_acc -= definition.tick_interval
		_ticks_fired += 1
		ticks += 1
		on_tick()
	if _tick_acc < 0.0:
		_tick_acc = 0.0
	return ticks

# 刷新/叠层：定时效果从头开始
func reset_tick_progress() -> void:
	_tick_acc = 0.0

# 延长时间：保留已经走过的 tick 进度
func extend_duration(extra: float) -> void:
	remaining += extra

func is_expired() -> bool:
	return remaining <= 0.0

func owner_key() -> String:
	if definition == null:
		return "buff:?"
	return "buff:%s" % String(definition.id)


## Runtime snapshot excludes the Resource and Node references; those are resolved by the manager.
func capture_runtime_state() -> Dictionary:
	return {
		"definitionId": String(definition.id) if definition != null else "",
		"definitionVersion": definition.definition_version if definition != null else 0,
		"targetKey": target_key,
		"remaining": remaining,
		"stacks": stacks,
		"ticksFired": _ticks_fired,
		"tickAccumulator": _tick_acc,
		"customState": capture_custom_state()
	}

## Restore fields without invoking on_apply; the manager rebuilds stat modifiers separately.
func restore_runtime_state(snapshot: Dictionary, resolved_definition: BuffDefinition, resolved_target: Node) -> bool:
	if resolved_definition == null or not resolved_definition.is_valid():
		return false
	var raw_definition_id: Variant = snapshot.get("definitionId", null)
	var raw_definition_version: Variant = snapshot.get("definitionVersion", null)
	var raw_target_key: Variant = snapshot.get("targetKey", null)
	var raw_remaining: Variant = snapshot.get("remaining", null)
	var raw_stacks: Variant = snapshot.get("stacks", null)
	var raw_ticks: Variant = snapshot.get("ticksFired", null)
	var raw_accumulator: Variant = snapshot.get("tickAccumulator", null)
	var raw_custom_state: Variant = snapshot.get("customState", null)
	if typeof(raw_definition_id) != TYPE_STRING or String(raw_definition_id) != String(resolved_definition.id):
		return false
	if typeof(raw_definition_version) != TYPE_INT or int(raw_definition_version) != resolved_definition.definition_version:
		return false
	if typeof(raw_target_key) != TYPE_STRING:
		return false
	if (typeof(raw_remaining) != TYPE_INT and typeof(raw_remaining) != TYPE_FLOAT) or (typeof(raw_accumulator) != TYPE_INT and typeof(raw_accumulator) != TYPE_FLOAT):
		return false
	if typeof(raw_stacks) != TYPE_INT or typeof(raw_ticks) != TYPE_INT or not (raw_custom_state is Dictionary):
		return false
	var restored_remaining := float(raw_remaining)
	var restored_stacks := int(raw_stacks)
	var restored_ticks := int(raw_ticks)
	var restored_acc := float(raw_accumulator)
	if not is_finite(restored_remaining) or not is_finite(restored_acc):
		return false
	if restored_remaining <= 0.0 or restored_stacks <= 0 or restored_stacks > resolved_definition.max_stacks or restored_ticks < 0 or restored_acc < 0.0:
		return false
	if resolved_definition.tick_interval <= 0.0 and restored_acc > 0.000001:
		return false
	if resolved_definition.tick_interval > 0.0 and restored_acc >= resolved_definition.tick_interval + 0.000001:
		return false
	definition = resolved_definition
	target = resolved_target
	target_key = String(raw_target_key)
	remaining = restored_remaining
	stacks = restored_stacks
	_ticks_fired = restored_ticks
	_tick_acc = restored_acc
	return restore_custom_state(raw_custom_state)

## Subclasses with additional mutable behavior must override both custom-state hooks.
func capture_custom_state() -> Dictionary:
	return {}

func restore_custom_state(_state: Variant) -> bool:
	return true
