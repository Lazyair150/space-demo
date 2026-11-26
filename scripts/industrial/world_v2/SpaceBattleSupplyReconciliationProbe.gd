extends RefCounted
## Synthetic contract checks for the read-only Parser/Core supply reconciliation.
## These fixtures test accounting semantics, not production balance values.

static func run() -> Dictionary:
    var checks := 0
    var failures: Array[String] = []

    var exact_parser := {
        "schemaVersion": 1,
        "parserInstanceId": "probe-parser",
        "completedJarCountByShape": {"round": 5, "square": 2},
        "pendingCoreImportJarCountByShape": {"round": 1, "square": 0},
        "acknowledgedCoreImportJarCountByShape": {"round": 4, "square": 2},
        "unattributedCompletedJarCountByShape": {"round": 0, "square": 0},
        "exactCoreStoredJarCountByShape": {"round": 3, "square": 1},
        "exactCoreDiscardedJarCountByShape": {"round": 1, "square": 1},
        "coreImportReceiptHistoryComplete": true,
        "perShapeCoreOutcomeHistoryComplete": true
    }
    var core_snapshot := {
        "available": true,
        "worldTimeMilli": 1200,
        "logicalTimeMilli": 1200,
        "resourceJars": [{"shape": "round"}, {"shape": "round"}, {"shape": "square"}],
        "master": {"jars": [{"shape": "round"}]},
        "slave": {"jars": [{"shape": "square"}, {"shape": "square"}]}
    }
    var exact := SpaceBattleSupplyReconciliation.build_snapshot(exact_parser, core_snapshot)
    checks += 1
    if not bool(exact.get("success", false)):
        failures.append("valid exact Parser/Core observations must reconcile")
    var round_row: Dictionary = exact.get("shapeRows", {}).get("round", {})
    checks += 1
    if int(round_row.get("parserCompletedJarCount", -1)) != 5 or int(round_row.get("parserPendingCoreImportJarCount", -1)) != 1 or int(round_row.get("parserAcknowledgedCoreImportJarCount", -1)) != 4:
        failures.append("parser completed/pending/acknowledged counts must remain distinct")
    checks += 1
    if int(round_row.get("parserExactCoreStoredJarCount", -1)) != 3 or int(round_row.get("parserExactCoreDiscardedJarCount", -1)) != 1:
        failures.append("exact historical Core outcome must retain per-shape stored/discarded counts")
    checks += 1
    if int(round_row.get("coreWarehouseCurrentJarCount", -1)) != 2 or int(round_row.get("masterWorkshopCurrentJarCount", -1)) != 1:
        failures.append("current Warehouse and Master balances must remain separate")
    checks += 1
    if bool(exact.get("sourceAttributionAvailable", true)):
        failures.append("aggregated import receipts must not be misrepresented as per-Jar source attribution")

    var legacy_parser := {
        "schemaVersion": 1,
        "completedJarCountByShape": {"round": 3},
        "pendingCoreImportJarCountByShape": {"round": 0},
        "acknowledgedCoreImportJarCountByShape": {"round": 2},
        "unattributedCompletedJarCountByShape": {"round": 1},
        "exactCoreStoredJarCountByShape": {"round": 1},
        "exactCoreDiscardedJarCountByShape": {"round": 0},
        "coreImportReceiptHistoryComplete": false,
        "perShapeCoreOutcomeHistoryComplete": false
    }
    var legacy_core := {
        "available": true,
        "resourceJars": [],
        "master": {"jars": []},
        "slave": {"jars": []}
    }
    var legacy := SpaceBattleSupplyReconciliation.build_snapshot(legacy_parser, legacy_core)
    checks += 1
    if not bool(legacy.get("success", false)) or bool(legacy.get("parserReceiptHistoryComplete", true)):
        failures.append("legacy incomplete receipt history must remain explicitly incomplete")

    var mismatched_parser := exact_parser.duplicate(true)
    mismatched_parser["completedJarCountByShape"] = {"round": 5, "square": 2}
    mismatched_parser["acknowledgedCoreImportJarCountByShape"] = {"round": 3, "square": 2}
    var mismatch := SpaceBattleSupplyReconciliation.build_snapshot(mismatched_parser, core_snapshot)
    checks += 1
    if bool(mismatch.get("success", false)):
        failures.append("unbalanced parser output accounting must fail closed")

    var invalid_core := core_snapshot.duplicate(true)
    invalid_core["resourceJars"] = [{"shape": ""}]
    var invalid := SpaceBattleSupplyReconciliation.build_snapshot(exact_parser, invalid_core)
    checks += 1
    if bool(invalid.get("success", false)):
        failures.append("invalid Core Jar inventory entries must not silently become zero")

    return {
        "passed": failures.is_empty(),
        "checks": checks,
        "reason": "; ".join(failures)
    }
