extends RefCounted
class_name SpaceBattleJarSupplyForecastProbe
## Synthetic deterministic contract checks. Values are fixtures, not production balance data.

static func run() -> Dictionary:
	var world_options := {
		"shapes": ["round", "square"],
		"executionLogicalTimePerUnit": 1000,
		"jarFlowRatePerLogicalTime": 1.0,
		"producers": [
			{"name": "producer.alpha", "producerInstanceId": "probe.producer.alpha", "rates": {"round": 0.5, "square": 0.25}},
			{"name": "producer.beta", "producerInstanceId": "probe.producer.beta", "rates": {"round": 0.25}}
		]
	}
	var parser_profile := {
		"parserId": "probe.parser",
		"definitionVersion": 1,
		"productionPercentage": 50,
		"shapeProcessingRatePerSecond": {"round": 2.0, "square": 1.0},
		"progressPerJarByShape": {"round": 1.0, "square": 2.0}
	}
	var supply_context := {
		"dropProfile": {
			"profileId": "probe.drops",
			"profileVersion": 3,
			"dropChance": 0.5,
			"weightedStones": [
				{"stoneType": "round", "volume": 2.0, "weight": 1.0},
				{"stoneType": "square", "volume": 4.0, "weight": 1.0}
			]
		},
		"expectedEnemyDefeatsPerSecond": 2.0
	}
	var forecast := SpaceBattleJarSupplyForecast.evaluate(
		world_options, parser_profile, supply_context, 2000.0,
		{"initialWarehouseJarsByShape": {"round": 1, "square": 1}}
	)
	if not bool(forecast.get("valid", false)):
		return _failure("valid dual-source forecast was rejected: " + String(forecast.get("reason", "")))
	var expected_stone: Dictionary = forecast.get("expectedStoneVolumeByShape", {})
	if not is_equal_approx(float(expected_stone.get("round", 0.0)), 2.0) or not is_equal_approx(float(expected_stone.get("square", 0.0)), 4.0):
		return _failure("weighted encounter drops did not create independent expected shape volumes")
	var parser_output: Dictionary = forecast.get("parserWholeJarEstimateByShape", {})
	if int(parser_output.get("round", 0)) != 2 or int(parser_output.get("square", 0)) != 0:
		return _failure("finite Parser input, rate limit or per-shape Jar threshold was not applied")
	var parser_leftovers: Dictionary = forecast.get("parserUnprocessedVolumeByShape", {})
	if not is_equal_approx(float(parser_leftovers.get("square", 0.0)), 3.0):
		return _failure("Parser unprocessed stone volume was not preserved in the forecast")
	var core_output: Dictionary = forecast.get("coreProducerJarOutputByShape", {})
	if int(core_output.get("round", 0)) != 1 or int(core_output.get("square", 0)) != 0:
		return _failure("Core time Producer output did not use its per-shape fixed-point rate contract")
	var core_remainders: Dictionary = forecast.get("coreProducerAccumulatorMicroByShape", {})
	if int(core_remainders.get("round", 0)) != 500000 or int(core_remainders.get("square", 0)) != 500000:
		return _failure("Core Producer fractional output accumulators were not preserved")
	var gross: Dictionary = forecast.get("grossWarehouseJarSupplyByShape", {})
	if int(gross.get("round", 0)) != 4 or int(gross.get("square", 0)) != 1 or int(forecast.get("grossWarehouseJarSupplyTotal", 0)) != 5:
		return _failure("initial Warehouse, Core Producer and Parser supplies were not counted exactly once")
	if int(forecast.get("masterJarFlowQuotaUpperBound", 0)) != 2 or int(forecast.get("masterPotentialReceiptUpperBound", 0)) != 2:
		return _failure("Core Warehouse-to-Master flow quota was not kept separate from gross production")

	var processor_limited := parser_profile.duplicate(true)
	processor_limited["shapeProcessingRatePerSecond"]["round"] = 0.5
	var limited := SpaceBattleJarSupplyForecast.evaluate(world_options, processor_limited, supply_context, 2000.0)
	var limited_parser: Dictionary = limited.get("parserWholeJarEstimateByShape", {})
	var limited_remaining: Dictionary = limited.get("parserUnprocessedVolumeByShape", {})
	if not bool(limited.get("valid", false)) or int(limited_parser.get("round", -1)) != 0 or not is_equal_approx(float(limited_remaining.get("round", 0.0)), 1.5):
		return _failure("finite Parser rate did not bound the expected stone volume")

	var bad_shape_profile := parser_profile.duplicate(true)
	bad_shape_profile["progressPerJarByShape"].erase("square")
	var bad_shape := SpaceBattleJarSupplyForecast.evaluate(world_options, bad_shape_profile, supply_context, 2000.0)
	if bool(bad_shape.get("valid", false)):
		return _failure("Parser missing a World shape threshold was accepted")
	var invalid_drop := supply_context.duplicate(true)
	invalid_drop["dropProfile"]["dropChance"] = 1.1
	var bad_drop := SpaceBattleJarSupplyForecast.evaluate(world_options, parser_profile, invalid_drop, 2000.0)
	if bool(bad_drop.get("valid", false)):
		return _failure("invalid energy-stone drop probability was accepted")

	var missing_producer_id := world_options.duplicate(true)
	missing_producer_id["producers"][0].erase("producerInstanceId")
	var bad_producer_id := SpaceBattleJarSupplyForecast.evaluate(missing_producer_id, parser_profile, supply_context, 2000.0)
	if bool(bad_producer_id.get("valid", false)):
		return _failure("Core Producer without a stable identity was accepted")

	# Low/Baseline/High are explicit scenario assumptions. They change only expected
	# enemy defeat rate; the frozen world/parser/drop profile and initial stocks are shared.
	var rate_profile := SpaceBattleSupplyScenarioProfile.new()
	rate_profile.profile_id = &"probe.encounter-rate"
	rate_profile.profile_version = 4
	rate_profile.low_expected_enemy_defeats_per_second = 1.0
	rate_profile.baseline_expected_enemy_defeats_per_second = 2.0
	rate_profile.high_expected_enemy_defeats_per_second = 3.0
	var rate_roundtrip := SpaceBattleSupplyScenarioProfile.from_runtime_profile(rate_profile.build_runtime_profile())
	if rate_roundtrip == null or rate_roundtrip.profile_version != 4:
		return _failure("versioned supply scenario profile did not survive its runtime roundtrip")
	var band := SpaceBattleJarSupplyForecast.evaluate_scenario_band(
		world_options,
		parser_profile,
		supply_context,
		2000.0,
		rate_roundtrip,
		{"initialWarehouseJarsByShape": {"round": 1, "square": 1}}
	)
	if not bool(band.get("valid", false)):
		return _failure("valid Low/Baseline/High supply band was rejected: " + String(band.get("reason", "")))
	var band_comparison: Dictionary = band.get("comparisonByShape", {})
	var round_metrics: Dictionary = band_comparison.get("round", {})
	var round_stone_band: Dictionary = round_metrics.get("expectedStoneVolume", {})
	var round_parser_band: Dictionary = round_metrics.get("parserWholeJarEstimate", {})
	if not is_equal_approx(float(round_stone_band.get("low", -1.0)), 1.0) or not is_equal_approx(float(round_stone_band.get("baseline", -1.0)), 2.0) or not is_equal_approx(float(round_stone_band.get("high", -1.0)), 3.0):
		return _failure("scenario band did not preserve explicit expected input-rate assumptions")
	if int(round_parser_band.get("low", -1)) != 1 or int(round_parser_band.get("baseline", -1)) != 2 or int(round_parser_band.get("high", -1)) != 2:
		return _failure("Parser output band did not expose the high-scenario throughput bottleneck")
	var low_report: Dictionary = band.scenarios.low
	var high_report: Dictionary = band.scenarios.high
	if low_report.coreProducerJarOutputByShape != high_report.coreProducerJarOutputByShape:
		return _failure("Core Producer supply was changed or counted differently across encounter bands")
	if int(band.grossWarehouseJarSupplyTotalByBand.low) > int(band.grossWarehouseJarSupplyTotalByBand.baseline) or int(band.grossWarehouseJarSupplyTotalByBand.baseline) > int(band.grossWarehouseJarSupplyTotalByBand.high):
		return _failure("gross Warehouse supply band is not monotonic")
	var invalid_rate_profile := SpaceBattleSupplyScenarioProfile.new()
	invalid_rate_profile.profile_id = &"probe.invalid-rate-order"
	invalid_rate_profile.profile_version = 1
	invalid_rate_profile.low_expected_enemy_defeats_per_second = 3.0
	invalid_rate_profile.baseline_expected_enemy_defeats_per_second = 2.0
	invalid_rate_profile.high_expected_enemy_defeats_per_second = 4.0
	if invalid_rate_profile.get_validation_errors().is_empty():
		return _failure("inverted Low/Baseline scenario rates were accepted")
	print("[SpaceBattleJarSupplyForecastProbe] explicit-scenario-sensitivity-band=passed")
	print("[SpaceBattleJarSupplyForecastProbe] scenario-core-supply-invariance=passed")
	print("[SpaceBattleJarSupplyForecastProbe] high-scenario-parser-bottleneck=passed")
	print("[SpaceBattleJarSupplyForecastProbe] inverted-scenario-band=fail-closed")
	return {
		"passed": true,
		"expectedStoneVolumeByShape": expected_stone,
		"parserWholeJarEstimateByShape": parser_output,
		"coreProducerJarOutputByShape": core_output,
		"grossWarehouseJarSupplyByShape": gross,
		"masterJarFlowQuotaUpperBound": int(forecast.get("masterJarFlowQuotaUpperBound", 0)),
		"scenarioProfileId": String(band.get("scenarioProfileId", "")),
		"scenarioGrossWarehouseSupplyByBand": band.get("grossWarehouseJarSupplyTotalByBand", {})
	}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
