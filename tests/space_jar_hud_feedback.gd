extends SceneTree
## Pure aggregation checks for the read-only Jar HUD feedback layer.

var _checks := 0
var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", message)
	else:
		_fails += 1
		print("FAIL ", message)

func _run() -> void:
	var visuals = load("res://scripts/industrial/ui/ShapeVisuals.gd")
	_check(visuals.glyph_for("圆罐") == "●", "round Jar uses the round glyph")
	_check(visuals.glyph_for("方罐") == "■", "square Jar uses the square glyph")
	_check(visuals.glyph_for("三棱舱段") == "▲", "triangular archetype has a reserved glyph")
	_check(visuals.glyph_for("长条舱段") == "▬", "long archetype has a reserved glyph")
	_check(visuals.color_for("圆罐") != visuals.color_for("方罐"), "current Jar shapes remain visually distinguishable")
	var observer_script = load("res://scripts/industrial/ui/SpaceJarHudObserver.gd")
	var observer = observer_script.new()
	_check(observer._filled_jar_count([
		{"shape": "圆罐", "liquid": "酒"},
		{"shape": "方罐", "liquid": ""},
		{"shape": "圆罐", "liquid": "蜜"}
	]) == 2, "filled Jar count only counts non-empty liquid identities")
	_check(observer._dictionary_total({"酒": 2, "蜜": 3}) == 5, "liquid totals aggregate exact inventory quantities")
	_check(observer._dictionary_total([]) == 0, "invalid aggregate input fails closed to zero")
	var cooling := observer._cooling_demand_ids([
		{"id": 7, "isCoolingDown": true},
		{"id": 8, "isCoolingDown": false},
		{"id": 9, "isCoolingDown": true}
	])
	_check(cooling == ["7", "9"], "cooldown transition keys use demand identities")
	_check(observer._active_session_step_total([
		{"isTerminal": false, "completedMasterSteps": 2, "completedSlaveSteps": 1},
		{"isTerminal": true, "completedMasterSteps": 90, "completedSlaveSteps": 90}
	]) == 3, "terminal sessions do not contribute active progress")
	observer.free()
	print("=== %d checks, %d failures ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
