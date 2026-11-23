extends Resource
class_name SpaceProductionDeviceDefinition
## Versioned non-parser production-device metadata and opaque runtime configuration.
## Device-specific execution semantics must be implemented by its owning subsystem.

@export var device_id: StringName = &""
@export var definition_version: int = 1
@export var device_kind: String = ""
@export var display_name: String = ""
@export var display_icon: Texture2D
@export var runtime_profile: Dictionary = {}

func is_valid() -> bool:
	return device_id != &"" and definition_version > 0 and not device_kind.strip_edges().is_empty() and device_kind != "ore_parser" and not display_name.strip_edges().is_empty()

func build_selection(slot_id: String) -> Dictionary:
	if not is_valid() or slot_id.strip_edges().is_empty():
		return {}
	return {
		"slotId": slot_id,
		"deviceKind": device_kind,
		"definitionId": String(device_id),
		"definitionVersion": definition_version,
		"deviceRuntimeProfile": runtime_profile.duplicate(true)
	}
