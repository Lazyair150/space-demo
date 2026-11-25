extends SceneTree
## Headless entry point for the complete Hangar catalog/ownership/board contract suite.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var passed := SpaceHangarCatalogOwnershipProbe.run()
	if not passed:
		push_error("[SpaceHangarContractProbe] failed")
		quit(1)
		return
	print("[SpaceHangarContractProbe] passed")
	quit(0)
