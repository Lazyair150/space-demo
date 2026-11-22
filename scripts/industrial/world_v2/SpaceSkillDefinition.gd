extends Resource
class_name SpaceSkillDefinition
## Player-facing skill definition. Jar receives only the nested jarOrder contract.

enum ControlArea { ACTIVE, PASSIVE }
enum ActivationPolicy { MANUAL, AUTOMATIC }

@export var skill_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export_multiline var description: String = ""

## Jar-owned execution contract. Keep this data free of Space effect semantics.
@export_enum("A", "B") var jar_order_type: String = "A"
@export_enum("Active", "Passive") var jar_order_area: String = "Active"
@export_range(0, 2147483647, 1) var jar_cooldown_logical_milli: int = 0
@export var jar_requirements: Array[Dictionary] = []

## Space-owned player control assignment and trigger policy.
@export_enum("Active", "Passive") var control_area: String = "Active"
@export_enum("Manual", "Automatic") var activation_policy: String = "Manual"

## Space-owned benefit/effect binding. Buff is the first executor, not the only future type.
@export var effect_definition_id: StringName = &""
@export var effect_definition_version: int = 1
@export var effect_parameters: Dictionary = {}

func is_valid() -> bool:
	if skill_id == &"" or definition_version <= 0 or display_name.strip_edges().is_empty():
		return false
	if not ["A", "B"].has(jar_order_type) or not ["Active", "Passive"].has(jar_order_area):
		return false
	if jar_cooldown_logical_milli < 0 or jar_requirements.is_empty():
		return false
	if not ["Active", "Passive"].has(control_area):
		return false
	if not ["Manual", "Automatic"].has(activation_policy):
		return false
	if control_area == "Active" and activation_policy != "Manual":
		return false
	if control_area == "Passive" and activation_policy != "Automatic":
		return false
	if effect_definition_id == &"" or effect_definition_version <= 0:
		return false
	for requirement in jar_requirements:
		if String(requirement.get("shape", "")).strip_edges().is_empty():
			return false
		if int(requirement.get("count", 0)) <= 0:
			return false
	return true

func create_order_binding(order_definition_key: String) -> Dictionary:
	if not is_valid() or order_definition_key.strip_edges().is_empty():
		return {}
	return {
		"orderDefinitionKey": order_definition_key,
		"skillDefinitionId": String(skill_id),
		"skillDefinitionVersion": definition_version,
		"jarOrder": {
			"type": jar_order_type,
			"area": jar_order_area,
			"cooldownDurationLogicalMilli": jar_cooldown_logical_milli,
			"requirements": jar_requirements.duplicate(true)
		},
		"skillControl": {
			"area": control_area,
			"activationPolicy": activation_policy
		},
		"effectBinding": {
			"effectDefinitionId": String(effect_definition_id),
			"effectDefinitionVersion": effect_definition_version,
			"effectParameters": effect_parameters.duplicate(true)
		}
	}
