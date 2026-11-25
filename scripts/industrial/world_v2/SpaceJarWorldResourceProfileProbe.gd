extends RefCounted
class_name SpaceJarWorldResourceProfileProbe
## Synthetic contract probe. Values validate adapter semantics, not production balance.

static func run() -> Dictionary:
	var profile := SpaceJarWorldResourceProfile.new()
	profile.profile_id = &"probe-jar-world"
	profile.profile_version = 1
	profile.world_options = {
		"shapes": ["round", "square"],
		"liquids": ["water", "oil"],
		"producers": [{"name": "legacy-producer", "rates": {"round": 0.0, "square": 0.0}}],
		"liquidProductionRates": {"water": 0.25, "oil": 0.0},
		"initialLiquidStock": {"water": 3, "oil": 1},
		"shipLiquidCapacity": 8,
		"jarFlowRatePerLogicalTime": 1.0,
		"liquidFlowRatePerLogicalTime": 1.0,
		"workshops": [
			{"name": "master", "baseMarks": ["round", "square"], "additionalMarks": [], "ban": [], "maxJars": 8, "maxLiquids": 8, "liquidStagingCapacity": 6},
			{"name": "slave", "baseMarks": ["round", "square"], "additionalMarks": [], "ban": [], "maxJars": 8, "maxLiquids": 8, "liquidStagingCapacity": 6}
		],
		"masterWorkshopName": "master",
		"slaveWorkshopName": "slave",
		"executionLogicalTimePerUnit": 1000
	}
	if not profile.is_valid():
		return {"passed": false, "reason": "; ".join(profile.get_validation_errors())}
	var forecast := profile.build_liquid_economy_resources()
	if int(forecast.liquidInventoryCapacity) != 8 or int(forecast.initialLiquids.water) != 3:
		return {"passed": false, "reason": "Jar liquid stock/capacity did not materialize"}
	if not is_equal_approx(float(forecast.liquidOutputPerSecond.water), 0.25):
		return {"passed": false, "reason": "logical-time liquid rate unit conversion changed the rate"}
	var invalid := profile.duplicate(true) as SpaceJarWorldResourceProfile
	invalid.world_options.initialLiquidStock = {"water": 8, "oil": 1}
	if invalid.is_valid():
		return {"passed": false, "reason": "shared liquid inventory capacity overflow was accepted"}
	return {
		"passed": true,
		"profileId": String(profile.profile_id),
		"profileVersion": profile.profile_version,
		"liquidCapacity": forecast.liquidInventoryCapacity,
		"liquidRates": forecast.liquidOutputPerSecond
	}
