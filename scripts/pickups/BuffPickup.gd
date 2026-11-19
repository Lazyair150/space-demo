extends Area2D
class_name BuffPickup
# 通用状态效果拾取物。
#
# 它不知道"急速"是什么，也不碰 fire_rate——只持有一个 BuffDefinition，
# 碰到玩家就把定义交出去，由玩家身上的 StatusEffectManager 决定怎么生效。
# 想加一种新胶囊，只需要新建一个 .tres 定义 + 在场景里换一次 buff_definition。

signal picked(definition: BuffDefinition)

@export var buff_definition: BuffDefinition
@export var tint: Color = Color(1, 1, 1)
## 没人捡就自己消失，避免场上越积越多
@export var lifetime: float = 15.0

@onready var visual: Sprite2D = $Visual
@onready var life_timer: Timer = $Lifetime

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	visual.modulate = tint
	life_timer.wait_time = lifetime
	life_timer.timeout.connect(queue_free)
	life_timer.start()

func _on_body_entered(body: Node2D) -> void:
	if buff_definition == null:
		return
	if not body.is_in_group("player"):
		return
	var instance = null
	if body.has_method("grant_buff"):
		instance = body.grant_buff(buff_definition)
	if instance == null:
		# 没有 Buff 系统（例如别的宿主场景）就当没捡到，别把胶囊吞掉
		return
	picked.emit(buff_definition)
	queue_free()
