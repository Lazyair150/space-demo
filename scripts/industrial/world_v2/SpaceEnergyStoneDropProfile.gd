extends Resource
class_name SpaceEnergyStoneDropProfile
## Versioned enemy/encounter content describing finite energy-stone pickups.
## No default drop probability, type, or volume is supplied: production balance is authored data.

@export var profile_id: StringName = &""
@export var profile_version: int = 1
@export_range(0.0, 1.0, 0.001) var drop_chance: float = 0.0
@export var weighted_stones: Array[Dictionary] = []

func get_validation_errors(shape_names: Array) -> Array[String]:
    var errors: Array[String] = []
    if profile_id == &"":
        errors.append("energy-stone drop profile ID is required")
    if profile_version <= 0:
        errors.append("energy-stone drop profile version must be positive")
    if not is_finite(drop_chance) or drop_chance < 0.0 or drop_chance > 1.0:
        errors.append("energy-stone drop chance must be finite and within 0..1")
    var known_shapes := {}
    for raw_shape in shape_names:
        var shape := String(raw_shape).strip_edges()
        if shape.is_empty() or known_shapes.has(shape):
            errors.append("Jar shape vocabulary contains an empty or duplicate shape")
        else:
            known_shapes[shape] = true
    if drop_chance > 0.0 and weighted_stones.is_empty():
        errors.append("enabled energy-stone drop profile requires at least one weighted stone entry")
    for entry in weighted_stones:
        if not (entry is Dictionary):
            errors.append("energy-stone drop entry must be a dictionary")
            continue
        var stone_type := String(entry.get("stoneType", "")).strip_edges()
        var volume: Variant = entry.get("volume", null)
        var weight: Variant = entry.get("weight", null)
        if not known_shapes.has(stone_type):
            errors.append("energy-stone type must map to a configured Jar shape: " + stone_type)
        if (typeof(volume) != TYPE_INT and typeof(volume) != TYPE_FLOAT) or not is_finite(float(volume)) or float(volume) <= 0.0 or float(volume) > 1000000000.0:
            errors.append("energy-stone volume must be finite, positive, and within parser fixed-point range")
        if (typeof(weight) != TYPE_INT and typeof(weight) != TYPE_FLOAT) or not is_finite(float(weight)) or float(weight) <= 0.0:
            errors.append("energy-stone weighted entry must have a finite positive weight")
    return errors

func is_valid_for_shapes(shape_names: Array) -> bool:
    return get_validation_errors(shape_names).is_empty()

func roll_drop(rng: RandomNumberGenerator, shape_names: Array) -> Dictionary:
    if rng == null:
        return {"success": false, "reason": "energy-stone drop RNG is required"}
    var errors := get_validation_errors(shape_names)
    if not errors.is_empty():
        return {"success": false, "reason": "; ".join(errors)}
    if drop_chance <= 0.0 or rng.randf() >= drop_chance:
        return {"success": true, "dropped": false}
    var total_weight := 0.0
    for entry in weighted_stones:
        total_weight += float(entry.weight)
    if not is_finite(total_weight) or total_weight <= 0.0:
        return {"success": false, "reason": "energy-stone drop weight total is invalid"}
    var choice := rng.randf() * total_weight
    for entry in weighted_stones:
        choice -= float(entry.weight)
        if choice < 0.0:
            return {
                "success": true,
                "dropped": true,
                "stoneType": String(entry.stoneType),
                "volume": float(entry.volume),
                "profileId": String(profile_id),
                "profileVersion": profile_version
            }
    var last: Dictionary = weighted_stones.back()
    return {
        "success": true,
        "dropped": true,
        "stoneType": String(last.stoneType),
        "volume": float(last.volume),
        "profileId": String(profile_id),
        "profileVersion": profile_version
    }

func build_runtime_profile() -> Dictionary:
    return {
        "profileId": String(profile_id),
        "profileVersion": profile_version,
        "dropChance": drop_chance,
        "weightedStones": weighted_stones.duplicate(true)
    }

static func from_runtime_profile(profile: Dictionary) -> SpaceEnergyStoneDropProfile:
    var definition := SpaceEnergyStoneDropProfile.new()
    definition.profile_id = StringName(profile.get("profileId", ""))
    definition.profile_version = int(profile.get("profileVersion", 0))
    definition.drop_chance = float(profile.get("dropChance", 0.0))
    var entries: Variant = profile.get("weightedStones", [])
    if entries is Array:
        definition.weighted_stones.clear()
        for entry in entries:
            if entry is Dictionary:
                definition.weighted_stones.append(entry.duplicate(true))
    return definition
