extends Node
## End-to-end probe for Space-owned finite stone parsing -> idempotent Jar warehouse import.
## All numeric values are synthetic fixtures, not production balance settings.

var _probe_parser: SpaceOreParserRuntime

func ingest_energy_stone(pickup_id: String, stone_type: String, volume: float) -> Dictionary:
    if _probe_parser == null:
        return {"success": false, "reason": "probe parser is not initialized"}
    return _probe_parser.ingest_stone(pickup_id, stone_type, volume)

func _ready() -> void:
    var parser_probe := SpaceOreParserRuntimeProbe.run()
    assert(bool(parser_probe.get("passed", false)), "Space ore parser unit probe must pass")
    var save_store_probe := SpaceBattleEffectStateStoreProbe.run()
    assert(bool(save_store_probe.get("passed", false)),
        "unified battle checkpoint store probe must pass: " + String(save_store_probe.get("reason", "")))
    var run_state_probe := SpaceBattleRunStateProbe.run()
    assert(bool(run_state_probe.get("passed", false)),
        "transient GameState checkpoint probe must pass: " + String(run_state_probe.get("reason", "")))
    var catalog_probe := SpaceOreParserCatalogProbe.run()
    assert(bool(catalog_probe.get("passed", false)),
        "pre-battle ore parser catalog probe must pass: " + String(catalog_probe.get("reason", "")))
    var drop_profile_probe := SpaceEnergyStoneDropProfileProbe.run()
    assert(bool(drop_profile_probe.get("passed", false)),
        "energy-stone drop profile probe must pass: " + String(drop_profile_probe.get("reason", "")))
    var hangar_catalog_probe := SpaceHangarCatalogOwnershipProbe.run()
    assert(hangar_catalog_probe, "Hangar exact-version catalogs must isolate authoring and resolved definitions")
    var skill_catalog_probe := SpaceSkillCatalogProbe.run()
    assert(skill_catalog_probe, "versioned skill catalog must isolate registered and resolved Resources")
    var build_context_probe := SpaceSkillBuildContextEvaluatorProbe.run()
    assert(bool(build_context_probe.get("passed", false)),
        "parser percentage build-context probe must pass: " + String(build_context_probe.get("reason", "")))

    var drop_profile := SpaceEnergyStoneDropProfile.new()
    drop_profile.profile_id = &"probe-energy-stone-drop"
    drop_profile.profile_version = 1
    drop_profile.drop_chance = 1.0
    drop_profile.weighted_stones = [
        {"stoneType": "圆罐", "volume": 1.5, "weight": 1.0},
        {"stoneType": "方罐", "volume": 2.5, "weight": 1.0}
    ]
    var drop_rng := RandomNumberGenerator.new()
    drop_rng.seed = 123456
    var drop_roll: Dictionary = drop_profile.roll_drop(drop_rng, ["圆罐", "方罐"])
    assert(bool(drop_roll.get("success", false)) and bool(drop_roll.get("dropped", false)),
        "versioned typed energy-stone drop profile must produce a valid configured type/volume")

    var pickup_scene := load("res://scenes/industrial/SpaceEnergyStonePickup.tscn") as PackedScene
    assert(pickup_scene != null, "typed energy-stone pickup scene must load")
    var pickup := pickup_scene.instantiate() as SpaceEnergyStonePickup
    assert(pickup != null, "typed energy-stone pickup script must instantiate")
    assert(not pickup.configure("", "圆罐", 1.0), "pickup must reject an unstable empty ID")
    assert(pickup.configure("probe-pickup-stable-id", "圆罐", 1.0), "pickup must accept a stable typed resource identity")
    pickup.free()

    var jar_host_script := load("res://scripts/industrial/world_v2/WorldV2ShipHost.cs") as Script
    assert(jar_host_script != null, "WorldV2ShipHost C# script resource must load")
    var jar_host = jar_host_script.new()
    assert(jar_host != null, "WorldV2ShipHost C# script must instantiate")
    add_child(jar_host)

    var world_json := FileAccess.get_file_as_string("res://data/industrial/world_v2_sandbox.json")
    assert(not world_json.is_empty(), "sandbox World V2 fixture must be readable")
    var world_options_raw: Variant = JSON.parse_string(world_json)
    assert(world_options_raw is Dictionary, "sandbox World V2 options must parse as a dictionary")
    var world_options: Dictionary = world_options_raw
    # JSON.parse_string represents numeric values as Variants; restore the Core Int64 field
    # before re-serializing this fixture for System.Text.Json.
    world_options["executionLogicalTimePerUnit"] = 1000
    world_options["orderTemplates"] = [
        {
            "name": "probe.order.active@1",
            "type": "A",
            "requirements": [{"shape": "圆罐"}]
        },
        {
            "name": "probe.order.passive@1",
            "type": "B",
            "requirements": [
                {"shape": "方罐"},
                {"shape": "圆罐", "liquid": "酒"}
            ]
        }
    ]
    world_json = JSON.stringify(world_options)
    assert(jar_host.BeginShipWorldFromJson(world_json), "Jar host must accept the test world")
    var selected_orders: Array = [
        {
            "orderDefinitionKey": "probe.skill.active",
            "jarOrder": {
                "templateName": "probe.order.active@1",
                "area": "Active",
                "cooldownDurationLogicalMilli": 0
            }
        },
        {
            "orderDefinitionKey": "probe.skill.passive",
            "jarOrder": {
                "templateName": "probe.order.passive@1",
                "area": "Passive",
                "cooldownDurationLogicalMilli": 2500
            }
        }
    ]
    var materialized: Dictionary = jar_host.MaterializeSelectedOrders(selected_orders)
    assert(bool(materialized.get("success", false)),
        "Space must materialize exact Core order templates through Host: " + String(materialized.get("error", "")))
    var materialized_ids: Array = materialized.get("demandIds", [])
    assert(materialized_ids.size() == 2, "Core template ingress must return both exact demand IDs")
    var template_snapshot: Dictionary = jar_host.GetWorldSnapshot()
    var found_template_keys := {}
    for raw_demand in template_snapshot.get("demands", []):
        var demand: Dictionary = raw_demand
        var order_key := String(demand.get("orderDefinitionKey", ""))
        if order_key == "probe.skill.active":
            assert(String(demand.get("type", "")) == "A", "Core must own the Active template order type")
            assert(String(demand.get("area", "")) == "Active", "Active control area must survive template ingress")
            assert(demand.get("requirements", []).size() == 1, "Core must instantiate Active template requirements")
            found_template_keys[order_key] = true
        elif order_key == "probe.skill.passive":
            assert(String(demand.get("type", "")) == "B", "Core must own the Passive template order type")
            assert(String(demand.get("area", "")) == "Passive", "Passive control area must survive template ingress")
            assert(demand.get("requirements", []).size() == 2, "Core must instantiate Passive template requirements")
            found_template_keys[order_key] = true
    assert(found_template_keys.has("probe.skill.active") and found_template_keys.has("probe.skill.passive"),
        "Core snapshot must retain both opaque Space order keys")
    var duplicate_materialization: Dictionary = jar_host.MaterializeSelectedOrders(selected_orders)
    assert(not bool(duplicate_materialization.get("success", false)),
        "Host must not materialize the same frozen loadout orders twice")

    # The Host is the sole fractional-millisecond accumulator. Two 0.75ms deltas
    # must forward 0ms then 1ms, and each prepared delta must be consumed exactly once.
    var first_half_milli: int = jar_host.AccumulateSpaceSimulationDelta(0.00075)
    assert(first_half_milli == 0, "first fractional step must not advance a whole millisecond")
    assert(jar_host.AdvanceSpaceSimulationMilliseconds(first_half_milli), "zero whole-ms step must still close its prepared boundary")
    var second_half_milli: int = jar_host.AccumulateSpaceSimulationDelta(0.00075)
    assert(second_half_milli == 1, "fractional remainder must combine into one whole millisecond")
    assert(jar_host.AdvanceSpaceSimulationMilliseconds(second_half_milli), "prepared one-ms step must advance Jar")

    var before: Dictionary = jar_host.GetWorldSnapshot()
    var initial_warehouse_jars: Array = before.get("resourceJars", [])
    var initial_master: Dictionary = before.get("master", {})
    var initial_master_jars: Array = initial_master.get("jars", [])
    var initial_warehouse_count: int = initial_warehouse_jars.size()
    var initial_master_count: int = initial_master_jars.size()

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

    _probe_parser = parser
    var collected_pickup: SpaceEnergyStonePickup = pickup_scene.instantiate()
    assert(collected_pickup.configure("probe-stone-001", "圆罐", 1.0), "live typed pickup must configure")
    add_child(collected_pickup)
    var fake_player := Node2D.new()
    fake_player.add_to_group("player")
    add_child(fake_player)
    collected_pickup._on_body_entered(fake_player)
    assert(collected_pickup.is_queued_for_deletion(), "accepted pickup must be consumed by the actual pickup adapter")

    var duplicate_pickup: SpaceEnergyStonePickup = pickup_scene.instantiate()
    assert(duplicate_pickup.configure("probe-stone-001", "圆罐", 1.0), "duplicate pickup fixture must configure")
    add_child(duplicate_pickup)
    duplicate_pickup._on_body_entered(fake_player)
    assert(duplicate_pickup.is_queued_for_deletion(), "same identity and payload must be consumed idempotently")

    var conflicting_pickup: SpaceEnergyStonePickup = pickup_scene.instantiate()
    assert(conflicting_pickup.configure("probe-stone-001", "圆罐", 2.0), "conflicting pickup fixture must configure")
    add_child(conflicting_pickup)
    conflicting_pickup._on_body_entered(fake_player)
    assert(not conflicting_pickup.is_queued_for_deletion(),
        "reusing an identity with changed volume must leave the pickup unconsumed")
    conflicting_pickup.free()
    fake_player.queue_free()

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

    # Simulate a process restart after Jar committed but before Space persisted the receipt.
    # The Jar execution checkpoint must carry the import deduplication receipt; the Host's
    # fractional millisecond remainder is a separate Space-owned checkpoint field.
    var jar_checkpoint_json: String = jar_host.CaptureExecutionCheckpointJson()
    var clock_remainder: float = jar_host.CaptureSpaceClockRemainderMilli()
    var parser_checkpoint: Dictionary = parser.capture_state()
    assert(absf(clock_remainder - 0.5) < 0.000001, "Host clock remainder must be captured separately")

    # Reconstruct the Space parser from its own checkpoint too; the pending operation ID
    # must remain byte-identical so Jar's restored resource-ledger receipt can deduplicate it.
    var restored_parser := SpaceOreParserRuntime.new()
    var parser_reinitialized := restored_parser.initialize(
        definition,
        "space-jar-ingress-probe-ship",
        ["圆罐", "方罐"]
    )
    assert(bool(parser_reinitialized.get("success", false)), "restored parser must initialize")
    var parser_restored := restored_parser.restore_state(parser_checkpoint)
    assert(bool(parser_restored.get("success", false)), "Space parser checkpoint must restore")
    jar_host.EndShipWorld()

    var restored_jar_host = jar_host_script.new()
    assert(restored_jar_host != null, "restored WorldV2ShipHost C# script must instantiate")
    add_child(restored_jar_host)
    assert(restored_jar_host.BeginShipWorldFromJson(world_json), "restored Jar Host must initialize")
    assert(restored_jar_host.RestoreExecutionCheckpointJson(jar_checkpoint_json),
        "Jar execution checkpoint must restore before any new order/time mutation")
    assert(restored_jar_host.RestoreSpaceClockRemainderMilli(clock_remainder),
        "Space fractional-millisecond remainder must restore before the next step")

    # A rejected Core import must not be converted into a success receipt or remove
    # the parser outbox entry. The stable operation ID remains available for a safe retry.
    var rejected_receipt: Dictionary = restored_jar_host.ImportProducedJars("", batch.jarCounts)
    assert(not bool(rejected_receipt.get("success", false)),
        "invalid Core import must return an explicit rejection, never a synthetic success")
    assert(restored_parser.pending_output_batches().size() == 1,
        "a rejected import must leave the parser batch pending")

    # Retrying the same pending operation after checkpoint restore must receive Jar's
    # persisted duplicate receipt, acknowledge Space's outbox, and create no second Jar.
    var retry := SpaceOreParserJarIngress.flush_pending(restored_parser, restored_jar_host)
    assert(bool(retry.get("success", false)), "pending Jar import retry must succeed after restore")
    assert(int(retry.get("duplicateBatches", 0)) == 1, "restored Jar ledger must recognize the duplicate")
    assert(restored_parser.pending_output_batches().is_empty(), "confirmed batch must leave the parser outbox")

    # The restored Host must combine its 0.5ms remainder with the next 0.75ms Space step.
    var resumed_delta: int = restored_jar_host.AccumulateSpaceSimulationDelta(0.00075)
    assert(resumed_delta == 1, "restored fractional clock remainder must survive the restart")
    var resumed_parse := restored_parser.advance(resumed_delta)
    assert(bool(resumed_parse.get("success", false)), "Space parser must use the exact restored whole-ms delta")
    var resumed_flush := SpaceOreParserJarIngress.flush_pending(restored_parser, restored_jar_host)
    assert(bool(resumed_flush.get("success", false)), "parser outbox flush must remain valid after restore")
    assert(restored_jar_host.AdvanceSpaceSimulationMilliseconds(resumed_delta),
        "Jar must receive the exact same whole-ms delta after parser processing")

    var after: Dictionary = restored_jar_host.GetWorldSnapshot()
    assert(
        after.get("resourceJars", []).size() == initial_warehouse_count + 1,
        "exactly one Jar must be present in the central warehouse"
    )
    assert(
        after.get("master", {}).get("jars", []).size() == initial_master_count,
        "external parser output must not bypass the central warehouse into Master"
    )

    restored_jar_host.EndShipWorld()
    print("[SpaceOreParserJarIngressProbe] passed parsed=1 stored=1 retry_after_restore=1 shared_clock=1 workshop_bypass=0")
    queue_free()
