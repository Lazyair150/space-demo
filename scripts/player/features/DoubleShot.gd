
extends PlayerFeature
class_name DoubleShot

@export var second_shot_interval: float = 0.15
@onready var second_shot_timer: Timer = $SecondShotTimer

var _pending_shots: int = 0
var _player: Node2D = null


func _ready() -> void:
	second_shot_timer.wait_time = second_shot_interval
	second_shot_timer.one_shot = true
	second_shot_timer.timeout.connect(_on_second_shot_timeout)


# 玩家攻击时，安排第二次发射
func on_attack(player: Node2D) -> void:
	_player = player
	_pending_shots += 1
	# 计时器还在走就只是排队：一次冷却只排一次第二发，但连续两次攻击
	# （射速已经快于 second_shot_interval）不会把上一次的第二发吃掉。
	if $SecondShotTimer.is_stopped():
		$SecondShotTimer.start()


# 时间到，发射第二颗子弹
func _on_second_shot_timeout() -> void:
	if _pending_shots <= 0:
		return
	_pending_shots -= 1
	if is_instance_valid(_player):
		_player.spawn_bullet()
	if _pending_shots > 0:
		$SecondShotTimer.start()
