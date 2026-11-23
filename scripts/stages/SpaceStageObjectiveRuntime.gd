extends RefCounted
class_name SpaceStageObjectiveRuntime
## Runtime objective state. It is independent from encounter scheduling and reward settlement.

var _stage_id: String = ""
var _definition_version: int = 0
var _objective: String = ""
var _parameters: Dictionary = {}
var _elapsed_seconds: float = 0.0
var _collected_amount: float = 0.0
var _boss_defeated: bool = false
var _encounters_completed: bool = false
var _protected_target: Node
var _complete: bool = false
var _failed: bool = false
var _failure_reason: String = ""

func configure(stage: SpaceStageDefinition, protected_target: Node = null) -> bool:
	if stage == null or not stage.is_valid() or not _stage_id.is_empty():
		return false
	if stage.objective == "protect_target":
		if protected_target == null or not is_instance_valid(protected_target) or not _target_has_health(protected_target):
			return false
	_stage_id = String(stage.stage_id)
	_definition_version = stage.definition_version
	_objective = stage.objective
	_parameters = stage.objective_parameters.duplicate(true)
	_protected_target = protected_target
	return true

func advance(delta_seconds: float) -> bool:
	if not _is_configured() or _complete or _failed or not is_finite(delta_seconds) or delta_seconds < 0.0:
		return false
	if _objective == "survive_duration":
		_elapsed_seconds += delta_seconds
		_complete = _elapsed_seconds >= float(_parameters.get("duration_seconds", 0.0))
	elif _objective == "protect_target":
		if not is_instance_valid(_protected_target) or _read_target_health(_protected_target) <= 0.0:
			_failed = true
			_failure_reason = "protected target was destroyed or became unavailable"
			return true
		_complete = _encounters_completed
	return true

func record_resource(resource_type: String, amount: float) -> bool:
	if not _is_configured() or _complete or _failed or _objective != "collect_resource":
		return false
	if resource_type != String(_parameters.get("resource_type", "")) or not is_finite(amount) or amount <= 0.0:
		return false
	_collected_amount += amount
	_complete = _collected_amount >= float(_parameters.get("target_amount", 0.0))
	return true

func record_boss_defeated(definition_id: String) -> bool:
	if not _is_configured() or _complete or _failed or _objective != "boss":
		return false
	if definition_id != String(_parameters.get("boss_definition_id", "")):
		return false
	_boss_defeated = true
	_update_completion()
	return true

func mark_encounters_completed() -> bool:
	if not _is_configured() or _failed or _encounters_completed:
		return false
	_encounters_completed = true
	_update_completion()
	return true

func _update_completion() -> void:
	match _objective:
		"eliminate_all":
			_complete = _encounters_completed
		"survive_duration":
			_complete = _elapsed_seconds >= float(_parameters.get("duration_seconds", 0.0))
		"collect_resource":
			_complete = _collected_amount >= float(_parameters.get("target_amount", 0.0))
		"protect_target":
			_complete = _encounters_completed and is_instance_valid(_protected_target) and _read_target_health(_protected_target) > 0.0
		"boss":
			_complete = _encounters_completed and _boss_defeated

func is_complete() -> bool:
	return _complete and not _failed

func is_failed() -> bool:
	return _failed

func failure_reason() -> String:
	return _failure_reason

func progress() -> Dictionary:
	return {
		"objective": _objective,
		"elapsedSeconds": _elapsed_seconds,
		"collectedAmount": _collected_amount,
		"targetAmount": float(_parameters.get("target_amount", 0.0)),
		"bossDefeated": _boss_defeated,
		"encountersCompleted": _encounters_completed,
		"complete": _complete,
		"failed": _failed,
		"failureReason": _failure_reason
	}

func capture_state() -> Dictionary:
	if not _is_configured():
		return {}
	return {
		"schemaVersion": 1,
		"stageId": _stage_id,
		"definitionVersion": _definition_version,
		"objective": _objective,
		"elapsedSeconds": _elapsed_seconds,
		"collectedAmount": _collected_amount,
		"bossDefeated": _boss_defeated,
		"encountersCompleted": _encounters_completed,
		"complete": _complete,
		"failed": _failed,
		"failureReason": _failure_reason
	}

func restore_state(stage: SpaceStageDefinition, source: Dictionary, protected_target: Node = null) -> bool:
	if not _stage_id.is_empty() or stage == null or not stage.is_valid() or int(source.get("schemaVersion", 0)) != 1 or bool(source.get("failed", false)):
		return false
	if String(source.get("stageId", "")) != String(stage.stage_id) or int(source.get("definitionVersion", 0)) != stage.definition_version or String(source.get("objective", "")) != stage.objective:
		return false
	var elapsed: Variant = source.get("elapsedSeconds", null)
	var collected: Variant = source.get("collectedAmount", null)
	if typeof(elapsed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(elapsed)) or float(elapsed) < 0.0:
		return false
	if typeof(collected) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(collected)) or float(collected) < 0.0:
		return false
	if stage.objective == "protect_target" and (protected_target == null or not _target_has_health(protected_target)):
		return false
	_stage_id = String(stage.stage_id)
	_definition_version = stage.definition_version
	_objective = stage.objective
	_parameters = stage.objective_parameters.duplicate(true)
	_protected_target = protected_target
	_elapsed_seconds = float(elapsed)
	_collected_amount = float(collected)
	_boss_defeated = bool(source.get("bossDefeated", false))
	_encounters_completed = bool(source.get("encountersCompleted", false))
	_update_completion()
	if bool(source.get("complete", false)) != _complete:
		return false
	if bool(source.get("failed", false)) or not String(source.get("failureReason", "")).is_empty():
		return false
	return true

func _is_configured() -> bool:
	return not _stage_id.is_empty() and _definition_version > 0

func _target_has_health(target: Node) -> bool:
	return target != null and target.get_node_or_null("Health") != null and target.get_node("Health").get("current") != null

func _read_target_health(target: Node) -> float:
	if not is_instance_valid(target):
		return 0.0
	var health := target.get_node_or_null("Health")
	if health == null:
		return 0.0
	var value: Variant = health.get("current")
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0.0
