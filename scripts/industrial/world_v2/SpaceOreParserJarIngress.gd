extends RefCounted
class_name SpaceOreParserJarIngress
## Delivers Space-owned completed-Jar batches to Jar Core.
## A batch remains pending in the parser until Jar confirms the import. A retry after
## an ambiguous response is safe because Jar persists the same operation ID in its ledger.

static func flush_pending(parser_runtime: SpaceOreParserRuntime, ship_host: Object) -> Dictionary:
	if parser_runtime == null or ship_host == null:
		return {"success": false, "reason": "parser runtime and ship host are required"}
	if not bool(ship_host.get("IsShipWorldActive")) or not ship_host.has_method("ImportProducedJars"):
		return {"success": false, "reason": "ship world is not active or has no Jar import API"}

	var imported_count := 0
	var duplicate_count := 0
	for batch in parser_runtime.pending_output_batches():
		var receipt: Dictionary = ship_host.call(
			"ImportProducedJars",
			String(batch.operationId),
			batch.jarCounts
		)
		if not bool(receipt.get("success", false)):
			return {
				"success": false,
				"reason": String(receipt.get("error", "Jar import was rejected")),
				"importedBatches": imported_count,
				"duplicateBatches": duplicate_count
			}
		if bool(receipt.get("wasDuplicate", false)):
			duplicate_count += 1
		else:
			imported_count += 1
		if not parser_runtime.acknowledge_output_batch(String(batch.operationId)):
			return {
				"success": false,
				"reason": "parser output batch disappeared before acknowledgment",
				"importedBatches": imported_count,
				"duplicateBatches": duplicate_count
			}
	return {
		"success": true,
		"importedBatches": imported_count,
		"duplicateBatches": duplicate_count
	}
