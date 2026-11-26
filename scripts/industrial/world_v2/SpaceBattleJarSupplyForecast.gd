extends RefCounted
class_name SpaceBattleJarSupplyForecast
## Read-only expected-scenario forecast. Core remains authoritative for admission,
## Warehouse overflow, Jar IDs, Master mark preference and Workshop capacity.
## It keeps initial stock, Core time Producers and finite-input Space Parser output separate.

const MICRO: int = 1000000
const RATE_MILLI: int = 1000
const PRODUCER_DENOMINATOR: int = 1000000
const PARSER_DENOMINATOR: int = 100000
const MAX_INT64: int = 9223372036854775807
const MAX_INT32: int = 2147483647

static func evaluate(
	world_options: Dictionary,
	parser_profile: Dictionary,
	parser_supply_context: Dictionary,
	duration_logical_milli: float,
	scenario: Dictionary = {}
) -> Dictionary:
	if not is_finite(duration_logical_milli) or duration_logical_milli <= 0.0:
		return _failure("battle duration must be finite and positive")
	var duration_ms := int(round(duration_logical_milli))
	if absf(float(duration_ms) - duration_logical_milli) > 0.000001:
		return _failure("battle duration must be a whole logical millisecond")
	var raw_shapes: Variant = world_options.get("shapes", null)
	if not (raw_shapes is Array) or raw_shapes.is_empty():
		return _failure("World shapes must be a non-empty array")
	var shapes: Array = raw_shapes
	var shape_set := {}
	for raw_shape in shapes:
		var shape := String(raw_shape).strip_edges()
		if shape.is_empty() or shape_set.has(shape):
			return _failure("World shape vocabulary contains an empty or duplicate identity")
		shape_set[shape] = true

	var parser_rates: Variant = parser_profile.get("shapeProcessingRatePerSecond", null)
	var parser_thresholds: Variant = parser_profile.get("progressPerJarByShape", null)
	var percentage: Variant = parser_profile.get("productionPercentage", null)
	if not (parser_rates is Dictionary) or not (parser_thresholds is Dictionary):
		return _failure("effective Parser profile requires rate and progress-per-Jar maps")
	if typeof(percentage) != TYPE_INT or int(percentage) < 0 or int(percentage) > 100:
		return _failure("Parser productionPercentage must be an integer within 0..100")
	if parser_rates.size() != shapes.size() or parser_thresholds.size() != shapes.size():
		return _failure("Parser rate/threshold maps must cover the exact World shape vocabulary")

	var initial_warehouse := _complete_integer_map(scenario.get("initialWarehouseJarsByShape", {}), shape_set, 0, MAX_INT32, "initial Warehouse Jars")
	if not bool(initial_warehouse.get("valid", false)):
		return initial_warehouse
	var initial_core_remainders := _complete_integer_map(scenario.get("initialCoreProducerAccumulatorMicroByShape", {}), shape_set, 0, PRODUCER_DENOMINATOR - 1, "Core Producer remainders")
	if not bool(initial_core_remainders.get("valid", false)):
		return initial_core_remainders
	var initial_parser_progress := _complete_integer_map(scenario.get("initialParserProgressMicroByShape", {}), shape_set, 0, MAX_INT64, "Parser progress")
	if not bool(initial_parser_progress.get("valid", false)):
		return initial_parser_progress
	var initial_parser_rate_remainders := _complete_integer_map(scenario.get("initialParserRateRemainderByShape", {}), shape_set, 0, PARSER_DENOMINATOR - 1, "Parser rate remainders")
	if not bool(initial_parser_rate_remainders.get("valid", false)):
		return initial_parser_rate_remainders

	var initial_warehouse_values: Dictionary = initial_warehouse.values
	var core_remainder_values: Dictionary = initial_core_remainders.values
	var parser_progress_values: Dictionary = initial_parser_progress.values
	var parser_rate_remainder_values: Dictionary = initial_parser_rate_remainders.values
	for shape_value in shapes:
		var shape := String(shape_value)
		var raw_threshold: Variant = parser_thresholds.get(shape, null)
		if (typeof(raw_threshold) != TYPE_INT and typeof(raw_threshold) != TYPE_FLOAT) or not is_finite(float(raw_threshold)) or float(raw_threshold) <= 0.0 or float(raw_threshold) > 1000000000.0:
			return _failure("Parser threshold is invalid: " + shape)
		var threshold_micro := int(round(float(raw_threshold) * MICRO))
		if threshold_micro <= 0 or int(parser_progress_values[shape]) >= threshold_micro:
			return _failure("Parser initial progress must be below one Jar threshold: " + shape)
		var raw_rate: Variant = parser_rates.get(shape, null)
		if (typeof(raw_rate) != TYPE_INT and typeof(raw_rate) != TYPE_FLOAT) or not is_finite(float(raw_rate)) or float(raw_rate) < 0.0 or float(raw_rate) > 1000000000.0:
			return _failure("Parser rate is invalid: " + shape)

	# Mirror Core ProducerModule: quantize every producer/shape rate to 0.001 first,
	# sum the quantized rates per shape, then accumulate rateMilli * deltaLogicalMilli.
	var core_rate_milli := {}
	for shape_value in shapes:
		core_rate_milli[String(shape_value)] = 0
	var producer_entries: Variant = world_options.get("producers", null)
	if not (producer_entries is Array):
		return _failure("World producers must be an array")
	var producer_names := {}
	var producer_ids := {}
	for raw_producer in producer_entries:
		if not (raw_producer is Dictionary):
			return _failure("Core Producer entry must be a dictionary")
		var producer: Dictionary = raw_producer
		var producer_name := String(producer.get("name", "")).strip_edges()
		var producer_id := String(producer.get("producerInstanceId", "")).strip_edges()
		if producer_name.is_empty() or producer_names.has(producer_name):
			return _failure("Core Producer names must be non-empty and unique")
		producer_names[producer_name] = true
		if producer_id.is_empty() or producer_id.length() > 128 or producer_id.contains(" ") or producer_ids.has(producer_id):
			return _failure("Core Producers require unique stable producerInstanceId values")
		producer_ids[producer_id] = true
		var producer_rates: Variant = producer.get("rates", null)
		if not (producer_rates is Dictionary):
			return _failure("Core Producer rates must be a dictionary")
		for raw_shape in producer_rates:
			var shape := String(raw_shape)
			if not shape_set.has(shape):
				return _failure("Core Producer references an unknown shape: " + shape)
			var rate: Variant = producer_rates[raw_shape]
			if (typeof(rate) != TYPE_INT and typeof(rate) != TYPE_FLOAT) or not is_finite(float(rate)) or float(rate) < 0.0 or float(rate) > 1000000000.0:
				return _failure("Core Producer rate is invalid: " + producer_name + "/" + shape)
			core_rate_milli[shape] = int(core_rate_milli[shape]) + int(round(float(rate) * RATE_MILLI))

	var core_output := {}
	var core_remainders := {}
	var core_total := 0
	for shape_value in shapes:
		var shape := String(shape_value)
		var rate_milli := int(core_rate_milli[shape])
		var accumulator := int(core_remainder_values[shape])
		if rate_milli > 0 and duration_ms > int((MAX_INT64 - accumulator) / rate_milli):
			return _failure("Core Producer fixed-point arithmetic exceeds Int64: " + shape)
		var numerator: int = rate_milli * duration_ms + accumulator
		var produced := int(numerator / PRODUCER_DENOMINATOR)
		if produced > MAX_INT32:
			return _failure("one Core Producer step exceeds the supported Jar count: " + shape)
		core_output[shape] = produced
		core_remainders[shape] = numerator % PRODUCER_DENOMINATOR
		core_total += produced

	# Encounter profile provides a probability-weighted expected input volume. This is a
	# scenario estimate; it is not a deterministic sequence of actual pickups.
	var drop_profile: Variant = parser_supply_context.get("dropProfile", null)
	var defeats: Variant = parser_supply_context.get("expectedEnemyDefeatsPerSecond", null)
	if not (drop_profile is Dictionary):
		return _failure("Parser supply context requires a frozen drop profile")
	if (typeof(defeats) != TYPE_INT and typeof(defeats) != TYPE_FLOAT) or not is_finite(float(defeats)) or float(defeats) < 0.0 or float(defeats) > 1000000.0:
		return _failure("expected enemy defeats per second is invalid")
	var drop_chance: Variant = drop_profile.get("dropChance", null)
	var weighted_stones: Variant = drop_profile.get("weightedStones", null)
	if (typeof(drop_chance) != TYPE_INT and typeof(drop_chance) != TYPE_FLOAT) or not is_finite(float(drop_chance)) or float(drop_chance) < 0.0 or float(drop_chance) > 1.0:
		return _failure("energy-stone drop chance must be finite and within 0..1")
	if not (weighted_stones is Array):
		return _failure("weightedStones must be an array")
	var total_weight := 0.0
	for raw_entry in weighted_stones:
		if not (raw_entry is Dictionary):
			return _failure("energy-stone weighted entry must be a dictionary")
		var entry: Dictionary = raw_entry
		var stone_shape := String(entry.get("stoneType", "")).strip_edges()
		var volume: Variant = entry.get("volume", null)
		var weight: Variant = entry.get("weight", null)
		if not shape_set.has(stone_shape):
			return _failure("energy-stone profile references an unknown shape: " + stone_shape)
		if (typeof(volume) != TYPE_INT and typeof(volume) != TYPE_FLOAT) or not is_finite(float(volume)) or float(volume) <= 0.0 or float(volume) > 1000000000.0:
			return _failure("energy-stone volume is invalid: " + stone_shape)
		if (typeof(weight) != TYPE_INT and typeof(weight) != TYPE_FLOAT) or not is_finite(float(weight)) or float(weight) <= 0.0:
			return _failure("energy-stone weight is invalid: " + stone_shape)
		total_weight += float(weight)
	if float(drop_chance) > 0.0 and weighted_stones.is_empty():
		return _failure("enabled drop profile requires weighted Stone entries")
	if not is_finite(total_weight) or (not weighted_stones.is_empty() and total_weight <= 0.0):
		return _failure("energy-stone total weight is invalid")

	var expected_seconds := float(duration_ms) / RATE_MILLI
	var expected_stone_volume := {}
	for shape_value in shapes:
		expected_stone_volume[String(shape_value)] = 0.0
	if float(drop_chance) > 0.0 and total_weight > 0.0:
		for raw_entry in weighted_stones:
			var entry: Dictionary = raw_entry
			var shape := String(entry.get("stoneType", ""))
			var volume_per_defeat := float(drop_chance) * float(entry.get("weight", 0.0)) / total_weight * float(entry.get("volume", 0.0))
			expected_stone_volume[shape] = float(expected_stone_volume[shape]) + volume_per_defeat * float(defeats) * expected_seconds

	var parser_processed := {}
	var parser_unprocessed := {}
	var parser_whole_jars := {}
	var parser_jar_equivalents := {}
	var parser_progress_remainders := {}
	var parser_rate_remainders_after := {}
	var parser_total := 0
	for shape_value in shapes:
		var shape := String(shape_value)
		var threshold_micro := int(round(float(parser_thresholds[shape]) * MICRO))
		var rate_micro := int(round(float(parser_rates[shape]) * MICRO))
		var rate_factor := int(percentage) * duration_ms
		var rate_remainder := int(parser_rate_remainder_values[shape])
		if percentage > 0 and duration_ms > int((MAX_INT64 - rate_remainder) / int(percentage)):
			return _failure("Parser logical-time factor exceeds Int64: " + shape)
		if rate_factor > 0 and rate_micro > int((MAX_INT64 - rate_remainder) / rate_factor):
			return _failure("Parser processing arithmetic exceeds Int64: " + shape)
		var process_numerator: int = rate_micro * rate_factor + rate_remainder
		var process_budget_micro := int(process_numerator / PARSER_DENOMINATOR)
		var stone_micro_float := float(expected_stone_volume[shape]) * MICRO
		if not is_finite(stone_micro_float) or stone_micro_float < 0.0 or stone_micro_float > float(MAX_INT64):
			return _failure("expected Stone volume exceeds fixed-point range: " + shape)
		var available_stone_micro := int(round(stone_micro_float))
		var processed_micro := mini(process_budget_micro, available_stone_micro)
		var unprocessed_micro := available_stone_micro - processed_micro
		var progress_before := int(parser_progress_values[shape])
		if processed_micro > MAX_INT64 - progress_before:
			return _failure("Parser progress arithmetic exceeds Int64: " + shape)
		var total_progress_micro: int = progress_before + processed_micro
		var produced := int(total_progress_micro / threshold_micro)
		if produced > MAX_INT32 - parser_total:
			return _failure("Parser expected batch exceeds the supported Jar count")
		parser_total += produced
		parser_processed[shape] = float(processed_micro) / MICRO
		parser_unprocessed[shape] = float(unprocessed_micro) / MICRO
		parser_whole_jars[shape] = produced
		parser_jar_equivalents[shape] = float(total_progress_micro) / threshold_micro
		parser_progress_remainders[shape] = total_progress_micro % threshold_micro
		parser_rate_remainders_after[shape] = process_numerator % PARSER_DENOMINATOR

	var gross_warehouse_supply := {}
	var gross_total := 0
	for shape_value in shapes:
		var shape := String(shape_value)
		var combined := int(initial_warehouse_values[shape]) + int(core_output[shape]) + int(parser_whole_jars[shape])
		if combined > MAX_INT32 - gross_total:
			return _failure("gross Warehouse Jar supply exceeds the supported combined count")
		gross_warehouse_supply[shape] = combined
		gross_total += combined

	var flow_rate: Variant = world_options.get("jarFlowRatePerLogicalTime", null)
	if (typeof(flow_rate) != TYPE_INT and typeof(flow_rate) != TYPE_FLOAT) or not is_finite(float(flow_rate)) or float(flow_rate) < 0.0 or float(flow_rate) > 2147483.647:
		return _failure("jarFlowRatePerLogicalTime is invalid")
	var flow_rate_milli := int(round(float(flow_rate) * RATE_MILLI))
	var initial_flow: Variant = scenario.get("initialJarFlowAccumulatorMicro", 0)
	if typeof(initial_flow) != TYPE_INT or int(initial_flow) < 0 or int(initial_flow) >= PRODUCER_DENOMINATOR:
		return _failure("initial Jar flow accumulator must be an integer in 0..999999")
	if flow_rate_milli > 0 and duration_ms > int((MAX_INT64 - int(initial_flow)) / flow_rate_milli):
		return _failure("Jar flow quota arithmetic exceeds Int64")
	var flow_numerator: int = flow_rate_milli * duration_ms + int(initial_flow)
	var master_flow_quota := int(flow_numerator / PRODUCER_DENOMINATOR)
	if master_flow_quota > MAX_INT32:
		return _failure("Master Jar flow quota exceeds the Core bridge count range")

	return {
		"valid": true,
		"forecastMode": "probability_weighted_expected_scenario",
		"durationLogicalMilli": duration_ms,
		"shapeVocabulary": shapes.duplicate(),
		"sourceProvenance": {
			"dropProfileId": String(drop_profile.get("profileId", "")),
			"dropProfileVersion": int(drop_profile.get("profileVersion", 0)),
			"parserDefinitionId": String(parser_profile.get("parserId", "")),
			"parserDefinitionVersion": int(parser_profile.get("definitionVersion", 0))
		},
		"expectedStoneVolumeByShape": expected_stone_volume,
		"parserProcessedVolumeByShape": parser_processed,
		"parserUnprocessedVolumeByShape": parser_unprocessed,
		"parserWholeJarEstimateByShape": parser_whole_jars,
		"parserJarEquivalentByShape": parser_jar_equivalents,
		"parserProgressRemainderMicroByShape": parser_progress_remainders,
		"parserRateRemainderAfterByShape": parser_rate_remainders_after,
		"coreProducerIds": producer_ids.keys(),
		"coreProducerRateMilliByShape": core_rate_milli,
		"coreProducerJarOutputByShape": core_output,
		"coreProducerAccumulatorMicroByShape": core_remainders,
		"initialWarehouseJarCountsByShape": initial_warehouse_values,
		"grossWarehouseJarSupplyByShape": gross_warehouse_supply,
		"grossWarehouseJarSupplyTotal": gross_total,
		"jarFlowQuotaRemainderMicro": flow_numerator % PRODUCER_DENOMINATOR,
		"masterJarFlowQuotaUpperBound": master_flow_quota,
		"masterPotentialReceiptUpperBound": mini(gross_total, master_flow_quota),
		"authoritativeLimits": [
			"Core Warehouse capacity/overflow admission",
			"Core Master mark preference and Workshop Jar capacity",
			"actual stochastic enemy/drop event ordering",
			"per-tick Core/Parser state unless initial accumulator snapshots are supplied"
		]
	}

static func _complete_integer_map(value: Variant, shape_set: Dictionary, minimum: int, maximum: int, label: String) -> Dictionary:
	if not (value is Dictionary):
		return _failure(label + " must be a dictionary")
	var result := {}
	for shape in shape_set:
		result[String(shape)] = 0
	for raw_key in value:
		var key := String(raw_key)
		var amount: Variant = value[raw_key]
		if not shape_set.has(key) or typeof(amount) != TYPE_INT or int(amount) < minimum or int(amount) > maximum:
			return _failure(label + " contains an invalid shape/value: " + key)
		result[key] = int(amount)
	return {"valid": true, "values": result}

static func _failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
