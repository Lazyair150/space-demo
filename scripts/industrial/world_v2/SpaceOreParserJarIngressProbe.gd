extends Node
## End-to-end probe for Space-owned finite stone parsing -> idempotent Jar warehouse import.
## All numeric values are synthetic fixtures, not production balance settings.

func _ready() -> void:
    var parser_probe := SpaceOreParserRuntimeProbe.run()
    assert(bool(parser_probe.get("passed", false)), "Space ore parser unit probe must pass")

    var jar_host := WorldV2ShipHost.new()
    add_child(jar_host)

    var world_json := FileAccess.get_file_as_string("res://data/industrial/world_v2_sandbox.json")
    assert(not world_json.is_empty(), "sandbox World V2 fixture must be readable")
    assert(jar_host.BeginShipWorldFromJson(world_json), "Jar host must accept the test world")
    var before: Dictionary = jar_host.GetWorldSnapshot()
    var initial_warehouse_count := before.get("resourceJars", []).size()
    var initial_master_count := before.get("master", {}).get("jars", []).size()

    var definition := SpaceOreParserDefinition.new()
    definition.parser_id = &"space-jar-ingress-probe"
    definition.definition_version = 1
    definition.production_percentage = 100
    definition.shape_processing_rate_per_second = {
        "圆罐": 1.0,
        "方罐": 1.0
    }
    definition.progress_per_jar_by_shape = {
        "圆罐": 1.0,
        "方罐": 1.0
    }

    var parser := SpaceOreParserRuntime.new()
    var initialized := parser.initialize(
        definition,
        "space-jar-ingress-probe-ship",
        ["圆罐", "方罐"]
    )
    assert(bool(initialized.get("success", false)), "universal parser must initialize")

    var accepted := parser.ingest_stone("probe-stone-001", "圆罐", 1.0)
    assert(bool(accepted.get("success", false)), "configured stone type must be accepted")
    var parsed := parser.advance(1000)
    assert(bool(parsed.get("success", false)), "parser must advance")
    assert(parsed.get("newBatches", []).size() == 1, "one complete Jar should be emitted")
    var batch: Dictionary = parsed.newBatches[0]
    assert(int(batch.jarCounts.get("圆罐", 0)) == 1, "stone type must map to its Jar shape")

    # Simulate an ambiguous transport outcome: Jar committed the batch, but Space did not
    # receive/record the receipt and therefore deliberately leaves the parser batch pending.
    var first_receipt: Dictionary = jar_host.ImportProducedJars(
        String(batch.operationId),
        batch.jarCounts
    )
    assert(bool(first_receipt.get("success", false)), "first Jar import must commit")
    assert(not bool(first_receipt.get("wasDuplicate", true)), "first Jar import must be new")
    assert(int(first_receipt.get("storedJarCount", 0)) == 1, "Jar must store the completed empty Jar")

    # Retrying the same pending operation must receive Jar's durable duplicate receipt,
    # acknowledge the Space batch, and never create a second physical Jar.
    var retry := SpaceOreParserJarIngress.flush_pending(parser, jar_host)
    assert(bool(retry.get("success", false)), "pending Jar import retry must succeed")
    assert(int(retry.get("duplicateBatches", 0)) == 1, "retry must be recognized as duplicate")
    assert(parser.pending_output_batches().is_empty(), "confirmed batch must leave the parser outbox")

    var after: Dictionary = jar_host.GetWorldSnapshot()
    assert(
        after.get("resourceJars", []).size() == initial_warehouse_count + 1,
        "exactly one Jar must be present in the central warehouse"
    )
    assert(
        after.get("master", {}).get("jars", []).size() == initial_master_count,
        "external parser output must not bypass the central warehouse into Master"
    )

    jar_host.EndShipWorld()
    print("[SpaceOreParserJarIngressProbe] passed parsed=1 stored=1 retry_duplicate=1 workshop_bypass=0")
    queue_free()
