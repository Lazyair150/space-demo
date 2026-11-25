extends Node
## Runs the Hangar ownership and board contract suite inside the real project tree.
## This must run as a scene, not --script: project Autoload singletons are part of the contract.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var passed := SpaceHangarCatalogOwnershipProbe.run()
	if not passed:
		push_error("[SpaceHangarContractProbe] failed")
		get_tree().quit(1)
		return
	print("[SpaceHangarContractProbe] passed")
	get_tree().quit(0)
