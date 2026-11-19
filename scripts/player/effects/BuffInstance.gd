extends RefCounted
class_name BuffInstance
# 一个角色身上正在生效的某个 Buff 的运行时状态。
# 生命周期由 StatusEffectManager 驱动；属性修正器的登记/撤销**不在这里**，
# 管理器统一按 owner_key 处理，避免某个 Buff 忘记撤回自己的修正。

var definition: BuffDefinition
var target: Node
var remaining: float = 0.0
var duration: float = 0.0
var stacks: int = 1

var _elapsed: float = 0.0
var _ticks_fired: int = 0

func setup(def: BuffDefinition, owner_target: Node, duration: float) -> void:
	definition = def
	target = owner_target
	remaining = duration
	self.duration = duration
	stacks = 1
	_elapsed = 0.0
	_ticks_fired = 0

# 施加瞬间（修正器已登记）回调；子类按需覆盖
func on_apply() -> void:
	pass

# 到期移除瞬间（修正器已被撤销）回调；**不要**在这里撤修正器
func on_expire() -> void:
	pass

# 定时触发；子类按需覆盖
func on_tick() -> void:
	pass

# 推进时间，返回这次推进里触发了几次 on_tick
func advance(delta: float) -> int:
	if delta <= 0.0:
		return 0
	_elapsed += delta
	remaining = maxf(0.0, remaining - delta)
	if definition == null or definition.tick_interval <= 0.0:
		return 0
	# 只在"这一条 Buff 真正活过的时长"内结算：delta 一次给 3 秒、Buff 只剩 1.5 秒时，
	# 不能把后面 1.5 秒的 tick 也算进来（否则到期后还会凭空掉一次血）。
	var lived := minf(_elapsed, duration)
	var due := int(floor(lived / definition.tick_interval))
	var ticks := 0
	while _ticks_fired < due:
		_ticks_fired += 1
		ticks += 1
		on_tick()
	return ticks

func is_expired() -> bool:
	return remaining <= 0.0

func owner_key() -> String:
	if definition == null:
		return "buff:?"
	return "buff:%s" % String(definition.id)
