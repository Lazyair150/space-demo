extends SceneTree

func _initialize() -> void:
	var runtime = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
	runtime.name = "IndustrialRuntime"
	get_root().add_child(runtime)
	runtime.freeze_when_unfocused = false
	var env: Dictionary = runtime.ensure_started()
	print("start ", env.get("success"), " ", env.get("message"))
	print("master ", runtime.set_master(0).get("success"), " slave ", runtime.set_slave(1).get("success"))
	for i in range(3):
		runtime.advance_manual()
	for attempt in range(6):
		runtime.create_random_order()
		runtime.check_all_feasibility()
		var state: Dictionary = runtime.get_state()
		for order in state.get("orders", []):
			var f = order.get("feasibilityResult")
			var feasible = bool((f as Dictionary).get("feasible", false)) if f is Dictionary else false
			print("  try%d order #%s %s status=%s feasible=%s" % [attempt, order.get("index"), order.get("description"), order.get("status"), feasible])
			if feasible and str(order.get("status", "")) == "待执行":
				var r: Dictionary = runtime.start_order(int(order.get("index", 0)))
				print("  -> start success=%s message=%s code=%s" % [r.get("success"), r.get("message"), r.get("error_code")])
				print("  -> processes=", (runtime.get_state().get("processes", []) as Array).size())
				quit(0)
				return
	quit(0)
