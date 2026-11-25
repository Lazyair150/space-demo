extends RefCounted
class_name SpaceHangarSelectionController
## UI-facing coordinator. Owns inventory snapshot + mutable draft, but delegates all
## compatibility, balance, and immutable snapshot decisions to Preparation/Assembler.

signal view_model_changed(view_model: Dictionary)

var _preparation: SpaceHangarPreparation
var _identity: Dictionary = {}
var _inventory: Dictionary = {}
var _draft: SpaceHangarSelectionDraft
var _board_definition: SpaceHangarBoardDefinition
var _last_error: String = ""

func configure(preparation: SpaceHangarPreparation, identity: Dictionary, board: SpaceHangarBoardDefinition = null) -> bool:
	_preparation = preparation
	_identity = identity.duplicate(true)
	_board_definition = board.duplicate(true) as SpaceHangarBoardDefinition if board != null else null
	return refresh_inventory()

func refresh_inventory() -> bool:
	if _preparation == null or _preparation.catalog_bundle_resource == null:
		_inventory = _unavailable_inventory("Authored Hangar catalog bundle is not assigned")
		_draft = SpaceHangarSelectionDraft.new()
		_draft.configure(_inventory, _board_definition)
		_last_error = "Hangar catalog bundle is not configured"
		_emit_changed()
		return false
	_inventory = _preparation.build_owned_selection_inventory() if (_preparation.require_owned_instances or _preparation.player_progression_state != null) else _preparation.catalog_bundle_resource.build_selection_inventory()
	_draft = SpaceHangarSelectionDraft.new()
	var ready := _draft.configure(_inventory, _board_definition)
	_last_error = "" if ready else "Authored Hangar catalogs are incomplete or invalid"
	_emit_changed()
	return ready

func set_ship(definition_id: String, version: int, instance_id: String = "") -> bool:
	if _draft == null:
		return _reject_ship("飞船选择失败：装配草稿尚未初始化。")
	if definition_id.strip_edges().is_empty() or version <= 0:
		return _reject_ship("飞船选择失败：候选项缺少有效定义 ID 或版本。")
	var matching_definition := false
	var matching_instance := false
	var choices: Variant = _inventory.get("shipChoices", [])
	if choices is Array:
		for raw_choice in choices:
			if not (raw_choice is Dictionary):
				continue
			if String(raw_choice.get("id", "")) != definition_id or int(raw_choice.get("version", 0)) != version:
				continue
			matching_definition = true
			if String(raw_choice.get("instanceId", "")) == instance_id:
				matching_instance = true
	if not matching_definition:
		return _reject_ship("飞船选择失败：库存中不存在 %s@%d。" % [definition_id, version])
	if _requires_owned_assembly() and instance_id.strip_edges().is_empty():
		return _reject_ship("飞船选择失败：当前机库要求拥有实例 ID，但候选项没有 instanceId。")
	if not matching_instance:
		return _reject_ship("飞船选择失败：实例 %s 与库存中的 %s@%d 不匹配。" % [instance_id, definition_id, version])
	if not _draft.set_ship(definition_id, version, instance_id):
		return _reject_ship("飞船选择失败：候选项通过库存检查，但装配草稿拒绝写入。")
	var committed := _draft.snapshot_data()
	if String(committed.get("shipId", "")) != definition_id or int(committed.get("shipVersion", 0)) != version or String(committed.get("shipInstanceId", "")) != instance_id:
		return _reject_ship("飞船选择失败：写入后的装配草稿与所选实例不一致。")
	_last_error = ""
	_emit_changed()
	return true

func _reject_ship(reason: String) -> bool:
	_last_error = reason
	push_warning("[Hangar] " + reason)
	_emit_changed()
	return false

func assign_instance(slot_id: String, owned_instance_id: String) -> bool:
	if _draft == null:
		return _apply(false)
	if _board_definition != null:
		for other_slot in _board_definition.slots:
			if other_slot == null:
				continue
			var other_slot_id := String(other_slot.slot_id)
			if other_slot_id == slot_id:
				continue
			var other_assignment := _draft.get_assignment(other_slot_id)
			if String(other_assignment.get("ownedInstanceId", "")) == owned_instance_id:
				_last_error = "同一个拥有实例不能安装到多个槽位：%s 已占用该元件。" % other_slot_id
				_emit_changed()
				return false
	return _apply(_draft.assign_instance(slot_id, owned_instance_id))

func unassign_slot(slot_id: String) -> bool:
	return _apply(_draft != null and _draft.unassign_slot(slot_id))

func get_assignment(slot_id: String) -> Dictionary:
	return {} if _draft == null else _draft.get_assignment(slot_id)

func validate_assignments() -> PackedStringArray:
	return PackedStringArray(["Hangar draft is not configured"]) if _draft == null else _draft.validate_assignments()

func set_parser(definition_id: String, version: int, slot_id: String, instance_id: String = "") -> bool:
	return _apply(_draft != null and _draft.set_parser(definition_id, version, slot_id, instance_id))

func set_workshop(definition_id: String, version: int, master_instance_id: String = "", slave_instance_id: String = "") -> bool:
	return _apply(_draft != null and _draft.set_workshop(definition_id, version, master_instance_id, slave_instance_id))

func set_device(slot_id: String, definition_id: String, version: int, instance_id: String = "") -> bool:
	return _apply(_draft != null and _draft.set_device(slot_id, definition_id, version, instance_id))

func remove_device(slot_id: String) -> bool:
	return _apply(_draft != null and _draft.remove_device(slot_id))

func set_skill(order_key: String, skill_id: String, version: int, control_area: String, instance_id: String = "") -> bool:
	return _apply(_draft != null and _draft.set_skill(order_key, skill_id, version, control_area, instance_id))

func remove_skill(order_key: String) -> bool:
	return _apply(_draft != null and _draft.remove_skill(order_key))

func set_expected_battle_duration(logical_milli: float) -> bool:
	return _apply(_draft != null and _draft.set_expected_battle_duration(logical_milli))

func build_loadout_snapshot() -> SpaceBattleLoadoutSnapshot:
	if _preparation == null or _draft == null:
		_last_error = "Hangar controller has not been configured"
		_emit_changed()
		return null
	if not _identity_is_valid():
		_last_error = "Stable ship-world/loadout identity must be supplied by the owning game flow"
		_emit_changed()
		return null
	if _requires_owned_assembly() and _board_definition == null:
		_last_error = "Owned production assembly requires an explicit Board Definition"
		_emit_changed()
		return null
	if _board_definition != null and not _draft.validate_assignments().is_empty():
		_last_error = "Board Assignment is incomplete or contains an incompatible/duplicate owned instance"
		_emit_changed()
		return null
	var snapshot := _preparation.build_owned_loadout_from_selection(_identity, _draft.snapshot_data()) if (_preparation.require_owned_instances or _preparation.player_progression_state != null) else _preparation.build_loadout_from_draft(_identity, _draft)
	_last_error = "" if snapshot != null else "Current selection could not be assembled; check exact versions and cross-catalog compatibility"
	_emit_changed()
	return snapshot

func get_view_model() -> Dictionary:
	var selection_data := {} if _draft == null else _draft.snapshot_data()
	var selection := null if _draft == null else _draft.build_selection()
	var validation_errors: PackedStringArray = PackedStringArray()
	if _draft != null and _draft.is_ready() and selection == null:
		validation_errors.append("Selection is incomplete or invalid")
	if not _identity_is_valid():
		validation_errors.append("Stable ship-world/loadout identity has not been supplied")
	if _requires_owned_assembly() and _board_definition == null:
		validation_errors.append("Owned production assembly requires an explicit Board Definition")
	return {
		"isReady": _draft != null and _draft.is_ready(),
		"inventory": _inventory.duplicate(true),
		"selection": selection_data,
		"canBuild": selection != null and _preparation != null and _identity_is_valid() and (not _requires_owned_assembly() or _board_definition != null),
		"validationErrors": validation_errors,
		"lastError": _last_error
	}

func _apply(accepted: bool) -> bool:
	if not accepted:
		_last_error = "Choice rejected: unavailable exact version, invalid slot, or unsupported control area"
		_emit_changed()
		return false
	_last_error = ""
	_emit_changed()
	return true

func _requires_owned_assembly() -> bool:
	return _preparation != null and (
		_preparation.require_owned_instances or _preparation.player_progression_state != null
	)

func _identity_is_valid() -> bool:
	return (
		String(_identity.get("shipWorldId", "")).strip_edges() != ""
		and String(_identity.get("loadoutId", "")).strip_edges() != ""
		and int(_identity.get("loadoutVersion", 0)) > 0
	)

func _emit_changed() -> void:
	view_model_changed.emit(get_view_model())

func _unavailable_inventory(reason: String) -> Dictionary:
	return {
		"isReady": false,
		"unavailableReason": reason,
		"shipChoices": [],
		"deviceChoices": [],
		"parserChoices": [],
		"workshopChoices": [],
		"skillChoices": [],
		"effectChoices": []
	}
