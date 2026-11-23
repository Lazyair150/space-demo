extends RefCounted
class_name SpaceHangarSelectionController
## UI-facing coordinator. Owns inventory snapshot + mutable draft, but delegates all
## compatibility, balance, and immutable snapshot decisions to Preparation/Assembler.

signal view_model_changed(view_model: Dictionary)

var _preparation: SpaceHangarPreparation
var _identity: Dictionary = {}
var _inventory: Dictionary = {}
var _draft: SpaceHangarSelectionDraft
var _last_error: String = ""

func configure(preparation: SpaceHangarPreparation, identity: Dictionary) -> bool:
	_preparation = preparation
	_identity = identity.duplicate(true)
	return refresh_inventory()

func refresh_inventory() -> bool:
	if _preparation == null or _preparation.catalog_bundle_resource == null:
		_inventory = _unavailable_inventory("Authored Hangar catalog bundle is not assigned")
		_draft = SpaceHangarSelectionDraft.new()
		_draft.configure(_inventory)
		_last_error = "Hangar catalog bundle is not configured"
		_emit_changed()
		return false
	_inventory = _preparation.catalog_bundle_resource.build_selection_inventory()
	_draft = SpaceHangarSelectionDraft.new()
	var ready := _draft.configure(_inventory)
	_last_error = "" if ready else "Authored Hangar catalogs are incomplete or invalid"
	_emit_changed()
	return ready

func set_ship(definition_id: String, version: int) -> bool:
	return _apply(_draft != null and _draft.set_ship(definition_id, version))

func set_parser(definition_id: String, version: int, slot_id: String) -> bool:
	return _apply(_draft != null and _draft.set_parser(definition_id, version, slot_id))

func set_workshop(definition_id: String, version: int) -> bool:
	return _apply(_draft != null and _draft.set_workshop(definition_id, version))

func set_device(slot_id: String, definition_id: String, version: int) -> bool:
	return _apply(_draft != null and _draft.set_device(slot_id, definition_id, version))

func remove_device(slot_id: String) -> bool:
	return _apply(_draft != null and _draft.remove_device(slot_id))

func set_skill(order_key: String, skill_id: String, version: int, control_area: String) -> bool:
	return _apply(_draft != null and _draft.set_skill(order_key, skill_id, version, control_area))

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
	var snapshot := _preparation.build_loadout_from_draft(_identity, _draft)
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
	return {
		"isReady": _draft != null and _draft.is_ready(),
		"inventory": _inventory.duplicate(true),
		"selection": selection_data,
		"canBuild": selection != null and _preparation != null and _identity_is_valid(),
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
