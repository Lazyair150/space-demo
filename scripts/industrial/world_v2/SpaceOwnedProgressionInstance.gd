extends Resource
class_name SpaceOwnedProgressionInstance
## A player's persistent, individually identified copy of a catalog definition.
## Definition data is immutable catalog content; progression data belongs to this instance.

const ITEM_KINDS := ["ship", "ore_parser", "production_device", "workshop", "skill"]

@export var instance_id: StringName = &""
@export_enum("ship", "ore_parser", "production_device", "workshop", "skill") var item_kind: String = "skill"
@export var definition_id: StringName = &""
@export var definition_version: int = 1
@export var level: int = 1
@export var experience: int = 0
@export var progression_revision: int = 1
## Exact curve asset used for the latest calculated growth snapshot; empty/0 means not curve-calculated yet.
@export var growth_curve_id: StringName = &""
@export var growth_curve_version: int = 0
## Space-owned additive/multiplicative growth data. Interpretation is defined by the owning item subsystem.
@export var growth_attributes: Dictionary = {}
## Acquisition provenance is immutable reward/source metadata, not a subsystem growth attribute.
@export var acquisition_provenance: Dictionary = {}

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if instance_id == &"":
		errors.append("owned instance requires a stable instance_id")
	if not ITEM_KINDS.has(item_kind):
		errors.append("owned instance item_kind is unsupported")
	if definition_id == &"" or definition_version <= 0:
		errors.append("owned instance requires an exact definition identity/version")
	if level <= 0 or experience < 0 or progression_revision <= 0:
		errors.append("owned instance progression counters are invalid")
	if (growth_curve_id == &"" and growth_curve_version != 0) or (growth_curve_id != &"" and growth_curve_version <= 0):
		errors.append("growth curve identity/version must be both absent or exact and positive")
	if not _is_finite_tree(growth_attributes):
		errors.append("owned instance growth_attributes must contain only finite numeric values, strings, booleans, arrays, or dictionaries")
	if not _is_finite_tree(acquisition_provenance):
		errors.append("owned instance acquisition_provenance must contain only finite serializable values")
	return errors

func build_frozen_snapshot() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	var snapshot := {
		"instanceId": String(instance_id),
		"itemKind": item_kind,
		"definitionId": String(definition_id),
		"definitionVersion": definition_version,
		"level": level,
		"experience": experience,
		"progressionRevision": progression_revision,
		"growthCurveId": String(growth_curve_id),
		"growthCurveVersion": growth_curve_version,
		"growthAttributes": growth_attributes.duplicate(true)
	}
	# Preserve the pre-provenance snapshot shape for ordinary instances so existing
	# frozen loadout fingerprints remain stable; emit the optional field when present.
	if not acquisition_provenance.is_empty():
		snapshot["acquisitionProvenance"] = acquisition_provenance.duplicate(true)
	return snapshot

func apply_progression(experience_delta: int, target_level: int, new_growth_attributes: Dictionary) -> bool:
	if experience_delta < 0 or target_level < level or not _is_finite_tree(new_growth_attributes):
		return false
	experience += experience_delta
	level = target_level
	growth_attributes = new_growth_attributes.duplicate(true)
	progression_revision += 1
	return get_validation_errors().is_empty()

func _is_finite_tree(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_STRING, TYPE_BOOL, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
	TYPE_NIL:
			return false
	TYPE_ARRAY:
		for item in value:
			if not _is_finite_tree(item):
				return false
		return true
	TYPE_DICTIONARY:
		for key in value:
			if not _is_finite_tree(value[key]):
				return false
		return true
	_:
		return false
