extends Node2D
# 测试用假目标：只记录挨了几下

var hits: int = 0

func take_damage(_amount: int = 1) -> void:
	hits += 1
