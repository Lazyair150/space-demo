extends Resource
class_name SpacePlayerProgressionState
## Persistent player progression aggregate: unlocks and owned item instances.
## It stores references to exact catalog versions, never copies catalog definitions as mutable state.

const CURRENT_SCHEMA_VERSION := 1

signal progression_changed(state_revision: int)

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var player_id: StringName = &""
@export var state_revision: int = 1
@export var unlocked_definition_keys: PackedStringArray = PackedStringArray()
@export var owned_instances: Array[SpaceOwnedProgressionInstance] = []

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != CURRENT_SCHEMA_VERSION:
		errors.append("unsupported player progression schema version")
	if player_id == &"" or state_revision <= 0:
		errors.append("player progression identity/revision is invalid")
	var unlocked := {}
	for key in unlocked_definition_keys:
		if key.strip_edges().is_empty() or unlocked.has(key):
			errors.append("unlocked definition keys must be non-empty and unique")
		unlocked[key] = true
	var instances := {}
	for instance in owned_instances:
		if instance == null:
			errors.append("owned instance collection cannot contain null")
			continue
		errors.append_array(instance.get_validation_errors())
		var id := String(instance.instance_id)
		if instances.has(id):
			errors.append("owned instance IDs must be unique: " + id)
		instances[id] = true
		var definition_key := _definition_key(instance.item_kind, String(instance.definition_id), instance.definition_version)
		if not unlocked.has(definition_key):
			errors.append("owned instance definition must be unlocked: " + definition_key)
	return errors

func unlock_definition(item_kind: String, definition_id: String, definition_version: int) -> bool:
	var key := _definition_key(item_kind, definition_id, definition_version)
	if key.is_empty() or unlocked_definition_keys.has(key):
		return false
	unlocked_definition_keys.append(key)
	state_revision += 1
	progression_changed.emit(state_revision)
	return true

func acquire_instance(instance: SpaceOwnedProgressionInstance) -> bool:
	if instance == null or not instance.get_validation_errors().is_empty():
		return false
	var key := _definition_key(instance.item_kind, String(instance.definition_id), instance.definition_version)
	if not unlocked_definition_keys.has(key) or resolve_instance(String(instance.instance_id)) != null:
		return false
	owned_instances.append(instance.duplicate(true) as SpaceOwnedProgressionInstance)
	state_revision += 1
	progression_changed.emit(state_revision)
	return true


## Atomically unlock the exact definition if needed and acquire one owned copy.
func unlock_and_acquire_instance(instance: SpaceOwnedProgressionInstance) -> bool:
	if instance == null or not instance.get_validation_errors().is_empty():
		return false
	var definition_key := _definition_key(instance.item_kind, String(instance.definition_id), instance.definition_version)
	if definition_key.is_empty() or resolve_instance(String(instance.instance_id)) != null:
		return false
	var unlocked := unlocked_definition_keys.has(definition_key)
	if not unlocked:
		unlocked_definition_keys.append(definition_key)
	owned_instances.append(instance.duplicate(true) as SpaceOwnedProgressionInstance)
	state_revision += 1
	progression_changed.emit(state_revision)
	return get_validation_errors().is_empty()

func resolve_instance(instance_id: String) -> SpaceOwnedProgressionInstance:
	if instance_id.strip_edges().is_empty():
		return null
	for instance in owned_instances:
		if instance != null and String(instance.instance_id) == instance_id:
			return instance.duplicate(true) as SpaceOwnedProgressionInstance
	return null

func build_owned_instance_snapshot(instance_id: String) -> Dictionary:
	var instance := resolve_instance(instance_id)
	return instance.build_frozen_snapshot() if instance != null else {}

func replace_instance_progression(updated: SpaceOwnedProgressionInstance) -> bool:
	if updated == null or not updated.get_validation_errors().is_empty():
		return false
	for index in range(owned_instances.size()):
		var current := owned_instances[index]
		if current != null and current.instance_id == updated.instance_id:
			if current.item_kind != updated.item_kind or current.definition_id != updated.definition_id or current.definition_version != updated.definition_version:
				return false
			if current.growth_curve_id != &"" and (updated.growth_curve_id != current.growth_curve_id or updated.growth_curve_version != current.growth_curve_version):
				return false # Curve provenance is immutable after first calculation; migration needs a separate explicit transaction.
			if updated.progression_revision != current.progression_revision + 1 or updated.level < current.level or updated.experience < current.experience:
				return false
			owned_instances[index] = updated.duplicate(true) as SpaceOwnedProgressionInstance
			state_revision += 1
			progression_changed.emit(state_revision)
			return true
	return false

static func from_data(source: Dictionary) -> SpacePlayerProgressionState:
	var state := SpacePlayerProgressionState.new()
	state.schema_version = int(source.get("schemaVersion", 0))
	state.player_id = StringName(source.get("playerId", ""))
	state.state_revision = int(source.get("stateRevision", 0))
	var raw_unlocks: Variant = source.get("unlockedDefinitionKeys", null)
	var raw_instances: Variant = source.get("ownedInstances", null)
	if not (raw_unlocks is Array) or not (raw_instances is Array):
		return null
	for raw_key in raw_unlocks:
		if not (raw_key is String):
			return null
		state.unlocked_definition_keys.append(raw_key)
	for raw_instance in raw_instances:
		if not (raw_instance is Dictionary):
			return null
		var instance := SpaceOwnedProgressionInstance.new()
		instance.instance_id = StringName(raw_instance.get("instanceId", ""))
		instance.item_kind = String(raw_instance.get("itemKind", ""))
		instance.definition_id = StringName(raw_instance.get("definitionId", ""))
		instance.definition_version = int(raw_instance.get("definitionVersion", 0))
		instance.level = int(raw_instance.get("level", 0))
		instance.experience = int(raw_instance.get("experience", -1))
		instance.progression_revision = int(raw_instance.get("progressionRevision", 0))
		instance.growth_curve_id = StringName(raw_instance.get("growthCurveId", ""))
		instance.growth_curve_version = int(raw_instance.get("growthCurveVersion", 0))
		var growth: Variant = raw_instance.get("growthAttributes", null)
		if not (growth is Dictionary):
			return null
		instance.growth_attributes = growth.duplicate(true)
		state.owned_instances.append(instance)
	if not state.get_validation_errors().is_empty():
		return null
	return state

func to_data() -> Dictionary:
	var instances: Array[Dictionary] = []
	for instance in owned_instances:
		if instance != null:
			instances.append(instance.build_frozen_snapshot())
	return {
		"schemaVersion": schema_version,
		"playerId": String(player_id),
		"stateRevision": state_revision,
		"unlockedDefinitionKeys": Array(unlocked_definition_keys),
		"ownedInstances": instances
	}

static func _definition_key(item_kind: String, definition_id: String, version: int) -> String:
	if not SpaceOwnedProgressionInstance.ITEM_KINDS.has(item_kind) or definition_id.strip_edges().is_empty() or version <= 0:
		return ""
	return "%s:%s@%d" % [item_kind, definition_id, version]
