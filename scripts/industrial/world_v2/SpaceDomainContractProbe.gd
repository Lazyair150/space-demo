extends RefCounted
class_name SpaceDomainContractProbe
## Runs deterministic domain contracts that previously existed as isolated probes.
## This suite is invoked from a project SceneTree so autoload-dependent probes are valid.

static func run() -> bool:
	if not _check("skill-template", SpaceSkillTemplateContractProbe.run()):
		return false
	if not _check("ore-parser-catalog", SpaceOreParserCatalogProbe.run()):
		return false
	if not _check("energy-stone-drop-profile", SpaceEnergyStoneDropProfileProbe.run()):
		return false
	if not _check("jar-world-resource-profile", SpaceJarWorldResourceProfileProbe.run()):
		return false
	if not _check("skill-balance-model", SpaceSkillBalanceModelProbe.run()):
		return false
	if not _check("battle-economy-evaluator", SpaceBattleEconomyEvaluatorProbe.run()):
		return false
	if not _check("battle-effect-state-store", SpaceBattleEffectStateStoreProbe.run()):
		return false
	if not _check("battle-run-state", SpaceBattleRunStateProbe.run()):
		return false
	if not _check("battle-reward-fact-projection", SpaceBattleRewardFactProjectionProbe.run()):
		return false
	if not _check("progression-reward-profile", SpaceProgressionRewardProfileProbe.run()):
		return false
	if not _check("progression-reward-coordinator", SpaceProgressionRewardCoordinatorProbe.run()):
		return false
	if not _check("progression-reward-settlement", SpaceProgressionRewardServiceProbe.run()):
		return false
	if not _check("battle-jar-supply-forecast", SpaceBattleJarSupplyForecastProbe.run()):
		return false
	if not _check("battle-supply-reconciliation", SpaceBattleSupplyReconciliationProbe.run()):
		return false
	print("[SpaceDomainContractProbe] all-domain-contracts=passed")
	return true

static func _check(contract_name: String, result: Variant) -> bool:
	var passed := false
	var reason := "probe returned an unsupported result type"
	if result is Dictionary:
		passed = bool(result.get("passed", false))
		reason = String(result.get("reason", "unspecified failure"))
	elif result is bool:
		passed = result
		reason = "probe returned false"
	if not passed:
		push_error("[SpaceDomainContractProbe] " + contract_name + " failed: " + reason)
		return false
	print("[SpaceDomainContractProbe] " + contract_name + "=passed")
	return true
