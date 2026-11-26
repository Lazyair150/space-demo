extends RefCounted
class_name SpaceBattleSupplyReconciliation
## Read-only join of Space parser facts and the current Core-owned inventory snapshot.
## Historical parser import outcomes and live account balances are deliberately kept separate.

static func build_snapshot(
    parser_observation: Dictionary,
    core_world_snapshot: Dictionary
) -> Dictionary:
    if parser_observation.is_empty():
        return _failure("parser observation is unavailable")
    if int(parser_observation.get("schemaVersion", -1)) != 1:
        return _failure("unsupported parser observation schema")
    if core_world_snapshot.is_empty() or not bool(core_world_snapshot.get("available", false)):
        return _failure("Core World V2 snapshot is unavailable")

    var parser_history_complete: Variant = parser_observation.get("coreImportReceiptHistoryComplete", null)
    var per_shape_history_complete: Variant = parser_observation.get("perShapeCoreOutcomeHistoryComplete", null)
    if typeof(parser_history_complete) != TYPE_BOOL or typeof(per_shape_history_complete) != TYPE_BOOL:
        return _failure("parser receipt history flags are missing or invalid")

    var completed := _normalize_count_map(parser_observation.get("completedJarCountByShape", null))
    var pending := _normalize_count_map(parser_observation.get("pendingCoreImportJarCountByShape", null))
    var acknowledged := _normalize_count_map(parser_observation.get("acknowledgedCoreImportJarCountByShape", null))
    var unattributed := _normalize_count_map(parser_observation.get("unattributedCompletedJarCountByShape", null))
    var exact_stored := _normalize_count_map(parser_observation.get("exactCoreStoredJarCountByShape", null))
    var exact_discarded := _normalize_count_map(parser_observation.get("exactCoreDiscardedJarCountByShape", null))
    if completed == null or pending == null or acknowledged == null or unattributed == null or exact_stored == null or exact_discarded == null:
        return _failure("parser observation contains an invalid per-shape count map")

    var warehouse := _count_jar_shapes(core_world_snapshot.get("resourceJars", null))
    var master := _count_workshop_jars(core_world_snapshot.get("master", null))
    var slave := _count_workshop_jars(core_world_snapshot.get("slave", null))
    if warehouse == null or master == null or slave == null:
        return _failure("Core snapshot is missing a valid Warehouse/Master/Slave Jar inventory")

    var shape_set := {}
    for count_map in [completed, pending, acknowledged, unattributed, exact_stored, exact_discarded, warehouse, master, slave]:
        for raw_shape in count_map:
            shape_set[String(raw_shape)] = true
    var shapes: Array = shape_set.keys()
    shapes.sort()

    var rows := {}
    for shape_value in shapes:
        var shape := String(shape_value)
        var parser_completed := int(completed.get(shape, 0))
        var parser_pending := int(pending.get(shape, 0))
        var parser_acknowledged := int(acknowledged.get(shape, 0))
        var parser_unattributed := int(unattributed.get(shape, 0))
        var stored := int(exact_stored.get(shape, 0))
        var discarded := int(exact_discarded.get(shape, 0))

        if parser_completed != parser_pending + parser_acknowledged + parser_unattributed:
            return _failure("parser output flow does not balance for shape: " + shape)
        if stored + discarded > parser_acknowledged:
            return _failure("exact Core import outcome exceeds acknowledged parser output for shape: " + shape)
        if bool(per_shape_history_complete) and stored + discarded != parser_acknowledged:
            return _failure("complete per-shape Core receipt history does not balance for shape: " + shape)

        var warehouse_count := int(warehouse.get(shape, 0))
        var master_count := int(master.get(shape, 0))
        var slave_count := int(slave.get(shape, 0))
        rows[shape] = {
            "parserCompletedJarCount": parser_completed,
            "parserPendingCoreImportJarCount": parser_pending,
            "parserAcknowledgedCoreImportJarCount": parser_acknowledged,
            "parserUnattributedCompletedJarCount": parser_unattributed,
            "parserExactCoreStoredJarCount": stored,
            "parserExactCoreDiscardedJarCount": discarded,
            "coreWarehouseCurrentJarCount": warehouse_count,
            "masterWorkshopCurrentJarCount": master_count,
            "slaveWorkshopCurrentJarCount": slave_count,
            "currentListedAccountJarCount": warehouse_count + master_count + slave_count
        }

    return {
        "success": true,
        "schemaVersion": 1,
        "parserInstanceId": String(parser_observation.get("parserInstanceId", "")),
        "worldTimeMilli": int(core_world_snapshot.get("worldTimeMilli", 0)),
        "logicalTimeMilli": int(core_world_snapshot.get("logicalTimeMilli", 0)),
        "shapeRows": rows,
        "parserFlowConservationValid": true,
        "parserReceiptHistoryComplete": bool(parser_history_complete),
        "perShapeCoreOutcomeHistoryComplete": bool(per_shape_history_complete),
        "currentInventoryScope": "core_warehouse_master_workshop_slave_workshop",
        "currentCoreWarehouseJarCountByShape": warehouse,
        "currentMasterWorkshopJarCountByShape": master,
        "currentSlaveWorkshopJarCountByShape": slave,
        # Core exposes current account balances and import receipts, but does not yet
        # link each historical imported Jar to a current Jar ID/location.
        "sourceAttributionAvailable": false,
        "sourceAttributionReason": "Core import receipts are aggregated by shape; current Jar snapshots do not expose a durable import-operation provenance link per Jar."
    }


static func _normalize_count_map(raw: Variant) -> Variant:
    if not (raw is Dictionary):
        return null
    var result := {}
    for raw_key in raw:
        var shape := String(raw_key)
        var amount: Variant = raw[raw_key]
        if shape.strip_edges().is_empty() or typeof(amount) != TYPE_INT or int(amount) < 0:
            return null
        result[shape] = int(amount)
    return result


static func _count_jar_shapes(raw: Variant) -> Variant:
    if not (raw is Array):
        return null
    var result := {}
    for raw_jar in raw:
        if not (raw_jar is Dictionary):
            return null
        var shape := String(raw_jar.get("shape", ""))
        if shape.strip_edges().is_empty():
            return null
        result[shape] = int(result.get(shape, 0)) + 1
    return result


static func _count_workshop_jars(raw: Variant) -> Variant:
    if not (raw is Dictionary):
        return null
    return _count_jar_shapes(raw.get("jars", null))


static func _failure(reason: String) -> Dictionary:
    return {"success": false, "reason": reason}
