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
# 距离下一次 on_tick 还差多少秒。刷新/叠层时按策略重置或保留。
var _tick_acc: float = 0.0

func setup(def: BuffDefinition, owner_target: Node, duration: float) -> void:
	definition = def
	target = owner_target
	remaining = duration
	self.duration = duration
	stacks = 1
	_elapsed = 0.0
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
	_elapsed += step
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
	_elapsed = 0.0

# 延长时间：保留已经走过的 tick 进度
func extend_duration(extra: float) -> void:
	remaining += extra
	duration += extra

func is_expired() -> bool:
	return remaining <= 0.0

func owner_key() -> String:
	if definition == null:
		return "buff:?"
	return "buff:%s" % String(definition.id)
