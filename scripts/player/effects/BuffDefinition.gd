extends Resource
class_name BuffDefinition
# Buff 的静态定义：只描述"是什么"，不保存"谁身上还剩几秒"。
# 同一个定义可以被反复施加到不同角色身上，各自得到独立的 BuffInstance。

enum StackPolicy {
	INDEPENDENT,     # 每次施加都新建一个独立实例
	ADD_STACK,       # 加层，层数乘到修正器上
	REFRESH,         # 不叠层，只把剩余时间重置回 duration
	EXTEND,          # 把新时间加到旧时间上
	KEEP_STRONGEST,  # 保留层数更高的那个，层数相同才刷新
	REPLACE,         # 移除旧实例，换新的
	REJECT,          # 已有就不接受
}

@export var id: StringName = &""
## Increment whenever the gameplay meaning or serialized behavior of this definition changes.
@export var definition_version: int = 1
@export var label: String = ""
@export var duration: float = 5.0
@export var stack_policy: StackPolicy = StackPolicy.REFRESH
@export var max_stacks: int = 1

# 每条修正器：{"stat": StringName, "stage": StatCalculator.Stage, "value": float}
@export var modifiers: Array = []

# 定时效果：tick_interval > 0 时，每过这么久调一次 instance.on_tick()
@export var tick_interval: float = 0.0
@export var tick_damage: int = 0

# 需要特殊行为的 Buff（例如中毒）指定自己的实例脚本，否则用 BuffInstance
## Balance annotations belong to this exact effect version, next to its real gameplay values.\n@export var balance_metrics: Dictionary = {}\n\n@export var instance_script: Script

func is_valid() -> bool:
	if id == &"" or definition_version <= 0 or duration <= 0.0:\n\t\treturn false\n\tfor value in balance_metrics.values():\n\t\tif float(value) < 0.0:\n\t\t\treturn false\n\treturn true
