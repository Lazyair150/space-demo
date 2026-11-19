extends PlayerFeature
class_name PiercingShot
# 穿透弹：开启后新发射的子弹可以穿过一个目标继续飞。
#
# 这个能力是"组件架构能不能扩展"的实验：它只靠 PlayerFeature 的既有接口
# （on_attack 拿到玩家节点）+ 监听场景树的节点加入事件生效，
# 不需要改 Player.gd，也不需要给 PlayerFeatures.gd 加新接口。
# 代价写在 docs/design/10-玩家能力组件.md：现有接口没有把"这一发子弹"交给能力，
# 所以只能靠树事件+鸭子类型补挂，真要做暴击/吸血那种要读命中结果的，必须补上下文对象。

@export var pierce_count: int = 1
@export var tint: Color = Color(0.55, 0.9, 1.0)

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if not active:
		return
	if not (node is Area2D):
		return
	if not node.has_method("_try_hit"):
		return
	node.set("pierce_count", pierce_count)
	if node is CanvasItem:
		(node as CanvasItem).modulate = tint
