extends RefCounted
class_name SpaceEnergyStoneDropProfileProbe
## Synthetic validation of versioned enemy drop profiles. No fixture values are production balance.

static func run() -> Dictionary:
    var profile := SpaceEnergyStoneDropProfile.new()
    profile.profile_id = &"probe-enemy-drop"
    profile.profile_version = 1
    profile.drop_chance = 1.0
    profile.weighted_stones = [
        {"stoneType": "圆罐", "volume": 1.25, "weight": 1.0},
        {"stoneType": "方罐", "volume": 2.5, "weight": 3.0}
    ]
    var shapes := ["圆罐", "方罐"]
    if not profile.is_valid_for_shapes(shapes):
        return _failure("valid versioned drop profile was rejected")

    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 78123
    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 78123
    var first := profile.roll_drop(first_rng, shapes)
    var second := profile.roll_drop(second_rng, shapes)
    if not bool(first.get("success", false)) or not bool(first.get("dropped", false)):
        return _failure("enabled drop profile did not produce a deterministic result")
    if first != second:
        return _failure("same seed and profile produced different drop payloads")

    # RNG state, not just the initial seed, is the continuation point saved by the
    # battle checkpoint. A resumed stream must emit the same next drop.
    var checkpoint_rng := RandomNumberGenerator.new()
    checkpoint_rng.seed = 991827
    var saved_rng_state := checkpoint_rng.state
    var before_checkpoint := profile.roll_drop(checkpoint_rng, shapes)
    var resumed_rng := RandomNumberGenerator.new()
    resumed_rng.state = saved_rng_state
    var after_restore := profile.roll_drop(resumed_rng, shapes)
    if before_checkpoint != after_restore:
        return _failure("restored RNG state did not continue the same enemy drop stream")

    if not shapes.has(String(first.get("stoneType", ""))) or float(first.get("volume", 0.0)) <= 0.0:
        return _failure("weighted drop emitted an invalid type or volume")
    if String(first.get("profileId", "")) != "probe-enemy-drop" or int(first.get("profileVersion", 0)) != 1:
        return _failure("drop result did not retain profile identity/version")

    var incompatible := profile.duplicate(true) as SpaceEnergyStoneDropProfile
    if bool(incompatible.roll_drop(first_rng, ["圆罐"]).get("success", false)):
        return _failure("drop profile accepted a type outside the active Jar shape vocabulary")

    var disabled := SpaceEnergyStoneDropProfile.new()
    disabled.profile_id = &"disabled-probe"
    disabled.profile_version = 1
    disabled.drop_chance = 0.0
    var disabled_result := disabled.roll_drop(first_rng, shapes)
    if not bool(disabled_result.get("success", false)) or bool(disabled_result.get("dropped", true)):
        return _failure("empty disabled profile should be a valid no-drop result")

    return {
        "passed": true,
        "profileId": String(profile.profile_id),
        "profileVersion": profile.profile_version,
        "sampleStoneType": String(first.stoneType),
        "sampleVolume": float(first.volume)
    }

static func _failure(reason: String) -> Dictionary:
    return {"passed": false, "reason": reason}
