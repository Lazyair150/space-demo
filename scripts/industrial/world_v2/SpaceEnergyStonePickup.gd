extends Area2D
class_name SpaceEnergyStonePickup
## Typed Space-world energy-stone pickup.
## The spawner must supply a stable pickup ID, stone type, and finite volume before
## adding this node to the SceneTree. The pickup is removed only after the battle parser
## accepts the identity (including an idempotent duplicate acknowledgment).

signal collected(pickup_id: String, stone_type: String, volume: float)

@export var pickup_id: String = ""
@export var stone_type: String = ""
@export var volume: float = 0.0

var _configured := false
var _collecting := false

func configure(stable_pickup_id: String, configured_stone_type: String, stone_volume: float) -> bool:
	if stable_pickup_id.strip_edges().is_empty() or stable_pickup_id.length() > 128:
		return false
	if configured_stone_type.strip_edges().is_empty():
		return false
	if not is_finite(stone_volume) or stone_volume <= 0.0 or stone_volume > 1000000000.0:
		return false
	pickup_id = stable_pickup_id
	stone_type = configured_stone_type
	volume = stone_volume
	_configured = true
	return true

func _ready() -> void:
	if not _configured:
		_configured = configure(pickup_id, stone_type, volume)
	if not _configured:
		monitoring = false
		push_error("[SpaceEnergyStonePickup] pickup must be configured with stable identity/type/volume before use")
		return
	add_to_group("space_energy_stone_pickups")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _collecting or not _configured or not body.is_in_group("player"):
		return
	var game := get_tree().current_scene
	if game == null or not game.has_method("ingest_energy_stone"):
		return

	_collecting = true
	var receipt: Variant = game.call("ingest_energy_stone", pickup_id, stone_type, volume)
	if receipt is Dictionary and bool(receipt.get("success", false)):
		collected.emit(pickup_id, stone_type, volume)
		queue_free()
	else:
		_collecting = false


## Save payload for the battle coordinator. Position is stored as scalar coordinates
## so it survives JSON-backed save serialization without Node/Object references.
func capture_persistence_state() -> Dictionary:
	if not _configured or is_queued_for_deletion():
		return {}
	return {
		"pickupId": pickup_id,
		"stoneType": stone_type,
		"volume": volume,
		"positionX": global_position.x,
		"positionY": global_position.y
	}
