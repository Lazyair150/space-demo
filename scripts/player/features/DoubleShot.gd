
extends PlayerFeature
class_name DoubleShot

@export var second_shot_interval: float = 0.15
@onready var second_shot_timer: Timer = $SecondShotTimer

var pending_player: Node2D = null


func _ready() -> void:
	second_shot_timer.wait_time = second_shot_interval
	second_shot_timer.one_shot = true
	second_shot_timer.timeout.connect(_on_second_shot_timeout)


# 玩家攻击时，安排第二次发射
func on_attack(player: Node2D) -> void:
	pending_player = player
	$SecondShotTimer.start()


# 时间到，发射第二颗子弹
func _on_second_shot_timeout() -> void:
	if is_instance_valid(pending_player):
		pending_player.spawn_bullet()

	pending_player = null
