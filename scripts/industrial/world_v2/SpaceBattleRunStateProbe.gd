extends RefCounted
class_name SpaceBattleRunStateProbe
## Checks transient progression validation and the Spawner's wave-resume policy.
const SPAWNER_SCRIPT = preload("res://scripts/Spawner.gd")

static func run() -> Dictionary:
    var scene_tree := Engine.get_main_loop() as SceneTree
    if scene_tree == null:
        return _failure("SceneTree is unavailable")
    var game_state := scene_tree.root.get_node_or_null("GameState")
    if game_state == null or not game_state.has_method("capture_run_state") or not game_state.has_method("restore_run_state"):
        return _failure("GameState run checkpoint API is unavailable")
    var original: Dictionary = game_state.capture_run_state()
    var expected := {
        "schemaVersion": 1,
        "score": 1250,
        "wave": 6,
        "segment": "压力"
    }
    if not game_state.restore_run_state(expected):
        return _failure("valid transient run state was rejected")
    if game_state.capture_run_state() != expected:
        game_state.restore_run_state(original)
        return _failure("transient score/wave/segment did not round-trip")

    var invalid := expected.duplicate(true)
    invalid.wave = -1
    if game_state.restore_run_state(invalid):
        game_state.restore_run_state(original)
        return _failure("negative wave checkpoint was accepted")
    if game_state.capture_run_state() != expected:
        game_state.restore_run_state(original)
        return _failure("rejected run-state checkpoint partially mutated live state")

    var inconsistent := expected.duplicate(true)
    inconsistent.segment = "精英"
    if game_state.restore_run_state(inconsistent):
        game_state.restore_run_state(original)
        return _failure("wave/segment mismatch was accepted")
    if game_state.capture_run_state() != expected:
        game_state.restore_run_state(original)
        return _failure("rejected wave/segment mismatch partially mutated live state")

    if SPAWNER_SCRIPT.initial_wave_for_checkpoint(6) != 6:
        game_state.restore_run_state(original)
        return _failure("resume policy advanced or reset the saved wave")
    if SPAWNER_SCRIPT.initial_wave_for_checkpoint(0) != 1:
        game_state.restore_run_state(original)
        return _failure("new-run policy did not begin at wave one")

    if not game_state.restore_run_state(original):
        return _failure("probe could not restore the original GameState")
    if game_state.capture_run_state() != original:
        return _failure("probe did not restore the original transient run state")
    return {"passed": true, "fields": ["score", "wave", "segment"]}

static func _failure(reason: String) -> Dictionary:
    return {"passed": false, "reason": reason}
