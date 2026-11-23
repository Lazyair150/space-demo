extends Node
## Synthetic scene-tree probe for the presentation-only assembly preview.
## No production catalog, identity, balance, or gameplay values are authored here.

func _ready() -> void:
	if not run_probe():
		push_error("[SpaceHangarAssemblyPreviewProbe] failed")
		return
	print("[SpaceHangarAssemblyPreviewProbe] passed")

func run_probe() -> bool:
	var preview := SpaceHangarAssemblyPreview.new()
	add_child(preview)
	var ship_icon := GradientTexture2D.new()
	var device_icon := GradientTexture2D.new()
	var skill_icon := GradientTexture2D.new()
	preview.render({
		"isReady": true,
		"canBuild": true,
		"inventory": {
			"shipChoices": [{"id": "probe.ship", "version": 2, "label": "Probe Ship", "iconTexture": ship_icon, "hullTexture": ship_icon, "displayAnchors": [
				{"anchorId": "device-anchor", "logicalSlotId": "probe-device-slot", "componentKind": "device", "normalizedPosition": Vector2(0.7, 0.5), "rotationDegrees": 0.0, "iconScale": 1.0},
				{"anchorId": "parser-anchor", "logicalSlotId": "probe-parser-slot", "componentKind": "parser", "normalizedPosition": Vector2(0.3, 0.5), "rotationDegrees": 0.0, "iconScale": 1.0}
			]}],
			"parserChoices": [{"id": "probe.parser", "version": 1, "label": "Probe Parser"}],
			"workshopChoices": [{"id": "probe.workshop", "version": 3, "label": "Probe Workshop"}],
			"deviceChoices": [{"id": "probe.device", "version": 4, "label": "Probe Device", "iconTexture": device_icon}],
			"skillChoices": [{"id": "probe.skill", "version": 5, "label": "Probe Skill", "iconTexture": skill_icon}]
		},
		"selection": {
			"shipId": "probe.ship",
			"shipVersion": 2,
			"parserId": "probe.parser",
			"parserVersion": 1,
			"parserSlotId": "probe-parser-slot",
			"workshopId": "probe.workshop",
			"workshopVersion": 3,
			"deviceSelections": [{"slotId": "probe-device-slot", "definitionId": "probe.device", "definitionVersion": 4}],
			"skillSelections": [{"orderDefinitionKey": "probe-order-key", "skillId": "probe.skill", "definitionVersion": 5, "controlArea": "Active"}],
			"expectedBattleDurationLogicalMilli": 60000.0
		}
	})
	return (
		preview._ship_name.text == "Probe Ship  [v2]"
		and preview._device_list.get_child_count() == 1
		and preview._skill_list.get_child_count() == 1
		and preview._anchor_icons.size() == 2
		and preview._status.text.contains("跨目录兼容性")
	)
