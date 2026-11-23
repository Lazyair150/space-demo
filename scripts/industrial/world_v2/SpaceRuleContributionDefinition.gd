extends Resource
class_name SpaceRuleContributionDefinition
## Serializable rule declaration owned by a component Definition.
## It contains no executable callbacks; Jar Core owns rule interpretation.

const EFFECTS := [
	"GrantBaseMark", "GrantAdditionalMark", "BanLiquid", "SuppressOperation",
	"RequireCondition", "ModifyCapacity", "RetimeProcess", "ModifyIntensity"
]

@export var rule_id: StringName = &""
@export var rule_version: int = 1
@export_enum("GrantBaseMark", "GrantAdditionalMark", "BanLiquid", "SuppressOperation", "RequireCondition", "ModifyCapacity", "RetimeProcess", "ModifyIntensity") var effect: String = "GrantAdditionalMark"
@export var target: String = ""
@export var scope: String = "workshop"
@export var priority: int = 0
## Constant scalar parameters. Values are serialized to invariant strings for Core.
@export var parameters: Dictionary = {}
## Parameter name -> exact growth attribute key. A bound value replaces its constant.
@export var growth_parameter_bindings: Dictionary = {}

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if rule_id == &"" or rule_version <= 0:
		errors.append("rule contribution requires an exact stable rule identity/version")
	if not EFFECTS.has(effect):
		errors.append("rule contribution effect is unsupported")
	if target.strip_edges().is_empty() or scope.strip_edges().is_empty():
		errors.append("rule contribution target and scope are required")
	for key in parameters:
		if String(key).strip_edges().is_empty() or not _is_supported_scalar(parameters[key]):
			errors.append("rule contribution parameters must use non-empty keys and scalar values")
	for parameter_name in growth_parameter_bindings:
		var attribute_name := String(growth_parameter_bindings[parameter_name]).strip_edges()
		if String(parameter_name).strip_edges().is_empty() or attribute_name.is_empty():
			errors.append("growth parameter bindings require exact parameter and attribute names")
	return errors

func resolve(
	owned_instance: SpaceOwnedProgressionInstance,
	slot_id: String
) -> Dictionary:
	if owned_instance == null or not get_validation_errors().is_empty() or slot_id.strip_edges().is_empty():
		return {}
	if owned_instance.definition_id == &"" or owned_instance.definition_version <= 0:
		return {}
	var resolved_parameters := {}
	for key in parameters:
		resolved_parameters[String(key)] = _canonical_scalar(parameters[key])
	for parameter_name in growth_parameter_bindings:
		var attribute_name := String(growth_parameter_bindings[parameter_name])
		if not owned_instance.growth_attributes.has(attribute_name):
			return {}
		var value: Variant = owned_instance.growth_attributes[attribute_name]
		if not _is_supported_scalar(value):
			return {}
		resolved_parameters[String(parameter_name)] = _canonical_scalar(value)
	var parameter_keys: Array = resolved_parameters.keys()
	parameter_keys.sort()
	var canonical_parameters := {}
	for key in parameter_keys:
		canonical_parameters[key] = resolved_parameters[key]
	return {
		"ruleId": String(rule_id),
		"ruleVersion": rule_version,
		"effect": effect,
		"target": target,
		"scope": scope,
		"priority": priority,
		"source": {
			"sourceKind": "installed-component",
			"definitionId": String(owned_instance.definition_id),
			"definitionVersion": owned_instance.definition_version,
			"sourceInstanceId": String(owned_instance.instance_id),
			"sourceRevision": owned_instance.progression_revision,
			"slotId": slot_id
		},
		"parameters": canonical_parameters
	}

func _is_supported_scalar(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_STRING, TYPE_STRING_NAME, TYPE_BOOL:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		_:
			return false

func _canonical_scalar(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_FLOAT:
			return str(float(value))
		_:
			return str(value)
