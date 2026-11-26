extends RefCounted
class_name SpaceOreParserRuntimeProbe
## Synthetic deterministic checks. Values here are fixtures, not production balance data.

static func run() -> Dictionary:
	var definition := SpaceOreParserDefinition.new()
	definition.parser_id = &"probe-universal-parser"
	definition.definition_version = 1
	definition.production_percentage = 50
	definition.shape_processing_rate_per_second = {
		"圆罐": 4.0,
		"方罐": 2.0
	}
	definition.progress_per_jar_by_shape = {
		"圆罐": 2.0,
		"方罐": 3.0
	}

	# Parser-local Rule Contributions are composed after owned growth and must
	# change the actual finite-input production runtime, not the Core workshop rules.
	var rule_definition := SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	var rate_rule := SpaceRuleContributionDefinition.new()
	rate_rule.rule_id = &"probe.parser.rate.boost"
	rate_rule.rule_version = 1
	rate_rule.effect = "ModifyIntensity"
	rate_rule.target = "shape_processing_rate"
	rate_rule.scope = "parser"
	rate_rule.parameters = {"shape": "圆罐", "multiplier": 1.5}
	var retime_rule := SpaceRuleContributionDefinition.new()
	retime_rule.rule_id = &"probe.parser.jar.retime"
	retime_rule.rule_version = 1
	retime_rule.effect = "RetimeProcess"
	retime_rule.target = "progress_per_jar"
	retime_rule.scope = "parser"
	retime_rule.parameters = {"shape": "圆罐", "multiplier": 0.5}
	rule_definition.rule_contributions = [rate_rule, retime_rule]
	var parser_owned := SpaceOwnedProgressionInstance.new()
	parser_owned.instance_id = &"parser-rule-owned"
	parser_owned.item_kind = "ore_parser"
	parser_owned.definition_id = rule_definition.parser_id
	parser_owned.definition_version = rule_definition.definition_version
	parser_owned.growth_attributes = {
		"shapeProcessingRateMultiplier": 2.0,
		"progressPerJarMultiplier": 0.5
	}
	var composed_parser := SpaceProgressionRuntimeProfileComposer.compose_parser(
		rule_definition, parser_owned, ["圆罐", "方罐"], "parser.slot.primary"
	)
	if composed_parser.is_empty():
		return _failure("valid Parser-local contributions failed composition")
	if not is_equal_approx(float(composed_parser.shapeProcessingRatePerSecond["圆罐"]), 12.0):
		return _failure("Parser rate contribution did not compose after Owned Instance growth")
	if not is_equal_approx(float(composed_parser.progressPerJarByShape["圆罐"]), 0.5):
		return _failure("Parser retiming contribution did not compose after Owned Instance growth")
	var parser_rule_profile: Dictionary = composed_parser.get("parserRuleProfile", {})
	if parser_rule_profile.is_empty() or String(parser_rule_profile.get("fingerprint", "")).is_empty() or parser_rule_profile.get("contributions", []).size() != 2:
		return _failure("Parser-local contribution provenance was not frozen")
	var parser_assignment := {
		"boardId": "probe.parser.board",
		"definitionVersion": 1,
		"assignmentFingerprint": "probe.assignment.fingerprint",
		"boardDefinition": {"boardId": "probe.parser.board"},
		"assignments": [{
			"slotId": "parser.slot.primary",
			"componentKind": "ore_parser",
			"ownedInstanceId": String(parser_owned.instance_id),
			"definitionId": String(parser_owned.definition_id),
			"definitionVersion": parser_owned.definition_version,
			"sourceRevision": parser_owned.progression_revision
		}]
	}
	var parser_device := {
		"slotId": "parser.slot.primary",
		"deviceKind": "ore_parser",
		"definitionId": String(parser_owned.definition_id),
		"definitionVersion": parser_owned.definition_version,
		"ownedInstance": parser_owned.build_frozen_snapshot(),
		"oreParserProfile": composed_parser
	}
	var routed_parser_profile := SpaceBoardRuntimeProfileSet.build(
		parser_assignment,
		{"boardRuleProfile": {"fingerprint": "probe.core.workshop.profile"}},
		[parser_device],
		[],
		{"developmentFixture": true}
	)
	if routed_parser_profile.is_empty():
		return _failure("valid Parser-local contribution profile failed Board consumer provenance validation")
	var tampered_parser_device := parser_device.duplicate(true)
	tampered_parser_device.oreParserProfile.parserRuleProfile.slotId = "parser.slot.foreign"
	if not SpaceBoardRuntimeProfileSet.build(
		parser_assignment,
		{"boardRuleProfile": {"fingerprint": "probe.core.workshop.profile"}},
		[tampered_parser_device],
		[],
		{"developmentFixture": true}
	).is_empty():
		return _failure("Board consumer accepted Parser contribution provenance from another slot")
	var tampered_parser_effective_rate := parser_device.duplicate(true)
	tampered_parser_effective_rate.oreParserProfile.shapeProcessingRatePerSecond["圆罐"] = 99.0
	if not SpaceBoardRuntimeProfileSet.build(
		parser_assignment,
		{"boardRuleProfile": {"fingerprint": "probe.core.workshop.profile"}},
		[tampered_parser_effective_rate],
		[],
		{"developmentFixture": true}
	).is_empty():
		return _failure("Board consumer accepted effective Parser rates inconsistent with its contribution replay")

	# A Parser with no authored local rules still needs a post-growth baseline.
	# Removing that baseline must not turn an edited effective rate into an accepted profile.
	var no_rule_profile := SpaceProgressionRuntimeProfileComposer.compose_parser(
		definition, parser_owned, ["圆罐", "方罐"], "parser.slot.primary"
	)
	if no_rule_profile.is_empty() or not (no_rule_profile.get("parserRuleProfile", null) is Dictionary):
		return _failure("Parser without local rules did not freeze its post-growth baseline")
	var no_rule_device := parser_device.duplicate(true)
	no_rule_device.oreParserProfile = no_rule_profile
	if SpaceBoardRuntimeProfileSet.build(
		parser_assignment,
		{"boardRuleProfile": {"fingerprint": "probe.core.workshop.profile"}},
		[no_rule_device],
		[],
		{"developmentFixture": true}
	).is_empty():
		return _failure("valid Parser profile without local rules was rejected")
	var stripped_baseline_device := no_rule_device.duplicate(true)
	stripped_baseline_device.oreParserProfile.erase("parserRuleProfile")
	stripped_baseline_device.oreParserProfile.shapeProcessingRatePerSecond["圆罐"] = 99.0
	if not SpaceBoardRuntimeProfileSet.build(
		parser_assignment,
		{"boardRuleProfile": {"fingerprint": "probe.core.workshop.profile"}},
		[stripped_baseline_device],
		[],
		{"developmentFixture": true}
	).is_empty():
		return _failure("Board consumer accepted a Parser profile after its replay baseline was stripped")

	var executable_parser_definition := SpaceOreParserDefinition.from_runtime_profile(composed_parser)
	var executable_parser := SpaceOreParserRuntime.new()
	var executable_init := executable_parser.initialize(executable_parser_definition, "parser-rule-execution", ["圆罐", "方罐"])
	if not bool(executable_init.get("success", false)):
		return _failure("composed Parser rule profile could not initialize its runtime")
	if not bool(executable_parser.ingest_stone("parser-rule-stone", "圆罐", 4.0).get("success", false)):
		return _failure("composed Parser runtime rejected its finite stone input")
	var executable_step := executable_parser.advance(1000)
	if not bool(executable_step.get("success", false)) or executable_step.newBatches.size() != 1 or int(executable_step.newBatches[0].jarCounts.get("圆罐", 0)) != 8:
		return _failure("Parser-local rate/retiming contributions did not affect actual Jar output")

	var wrong_scope_definition := SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	var wrong_scope_rule := SpaceRuleContributionDefinition.new()
	wrong_scope_rule.rule_id = &"probe.parser.wrong.scope"
	wrong_scope_rule.effect = "ModifyIntensity"
	wrong_scope_rule.target = "shape_processing_rate"
	wrong_scope_rule.scope = "workshop"
	wrong_scope_rule.parameters = {"shape": "圆罐", "multiplier": 2.0}
	wrong_scope_definition.rule_contributions = [wrong_scope_rule]
	if not SpaceProgressionRuntimeProfileComposer.compose_parser(wrong_scope_definition, parser_owned, ["圆罐", "方罐"], "parser.slot.primary").is_empty():
		return _failure("Parser executor accepted a non-parser contribution scope")
	var unsupported_parser_definition := SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	var unsupported_parser_rule := SpaceRuleContributionDefinition.new()
	unsupported_parser_rule.rule_id = &"probe.parser.unsupported.effect"
	unsupported_parser_rule.effect = "SuppressOperation"
	unsupported_parser_rule.target = "shape_processing_rate"
	unsupported_parser_rule.scope = "parser"
	unsupported_parser_rule.parameters = {"shape": "圆罐", "multiplier": 2.0}
	unsupported_parser_definition.rule_contributions = [unsupported_parser_rule]
	if not SpaceProgressionRuntimeProfileComposer.compose_parser(unsupported_parser_definition, parser_owned, ["圆罐", "方罐"], "parser.slot.primary").is_empty():
		return _failure("Parser executor accepted an unsupported effect/target combination")
	var wrong_target_definition := SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	var wrong_target_rule := SpaceRuleContributionDefinition.new()
	wrong_target_rule.rule_id = &"probe.parser.wrong.target"
	wrong_target_rule.effect = "ModifyIntensity"
	wrong_target_rule.target = "parser.throughput"
	wrong_target_rule.scope = "parser"
	wrong_target_rule.parameters = {"shape": "圆罐", "multiplier": 2.0}
	wrong_target_definition.rule_contributions = [wrong_target_rule]
	if not SpaceProgressionRuntimeProfileComposer.compose_parser(wrong_target_definition, parser_owned, ["圆罐", "方罐"], "parser.slot.primary").is_empty():
		return _failure("Parser executor accepted an unsupported target contract")
	var duplicate_rule_definition := SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	var duplicate_rate_rule := rate_rule.duplicate(true) as SpaceRuleContributionDefinition
	duplicate_rule_definition.rule_contributions = [rate_rule, duplicate_rate_rule]
	if not SpaceProgressionRuntimeProfileComposer.compose_parser(duplicate_rule_definition, parser_owned, ["圆罐", "方罐"], "parser.slot.primary").is_empty():
		return _failure("Parser executor accepted duplicate Rule identities")
	var overflow_rule_definition := SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	var overflow_rule := SpaceRuleContributionDefinition.new()
	overflow_rule.rule_id = &"probe.parser.overflow.rate"
	overflow_rule.effect = "ModifyIntensity"
	overflow_rule.target = "shape_processing_rate"
	overflow_rule.scope = "parser"
	overflow_rule.parameters = {"shape": "圆罐", "multiplier": 1000000000.0}
	overflow_rule_definition.rule_contributions = [overflow_rule]
	if not SpaceProgressionRuntimeProfileComposer.compose_parser(overflow_rule_definition, parser_owned, ["圆罐", "方罐"], "parser.slot.primary").is_empty():
		return _failure("Parser executor accepted a rate beyond the fixed-point range")
	var underflow_rule_definition := SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	var underflow_rule := SpaceRuleContributionDefinition.new()
	underflow_rule.rule_id = &"probe.parser.underflow.threshold"
	underflow_rule.effect = "RetimeProcess"
	underflow_rule.target = "progress_per_jar"
	underflow_rule.scope = "parser"
	underflow_rule.parameters = {"shape": "圆罐", "multiplier": 0.000000001}
	underflow_rule_definition.rule_contributions = [underflow_rule]
	if not SpaceProgressionRuntimeProfileComposer.compose_parser(underflow_rule_definition, parser_owned, ["圆罐", "方罐"], "parser.slot.primary").is_empty():
		return _failure("Parser executor accepted a threshold below fixed-point precision")

	# Two owned copies of one exact parser Definition must never share runtime state identity.
	var owned_profile_a := definition.build_runtime_profile()
	owned_profile_a["ownedInstance"] = {
		"instanceId": "parser-copy-a", "itemKind": "ore_parser",
		"definitionId": String(definition.parser_id), "definitionVersion": definition.definition_version
	}
	var owned_profile_b := definition.build_runtime_profile()
	owned_profile_b["ownedInstance"] = {
		"instanceId": "parser-copy-b", "itemKind": "ore_parser",
		"definitionId": String(definition.parser_id), "definitionVersion": definition.definition_version
	}
	var owned_runtime_id_a := SpaceOreParserRuntime.build_runtime_instance_id("probe-ship-world", owned_profile_a)
	var owned_runtime_id_b := SpaceOreParserRuntime.build_runtime_instance_id("probe-ship-world", owned_profile_b)
	if owned_runtime_id_a.is_empty() or owned_runtime_id_b.is_empty() or owned_runtime_id_a == owned_runtime_id_b:
		return _failure("same Definition copies must resolve to distinct Owned Instance runtime identities")
	var mismatched_owned_profile := owned_profile_a.duplicate(true)
	mismatched_owned_profile.ownedInstance.definitionId = "another-parser"
	if not SpaceOreParserRuntime.build_runtime_instance_id("probe-ship-world", mismatched_owned_profile).is_empty():
		return _failure("parser runtime identity accepted an Owned Instance from another Definition")
	var definition_only_profile := definition.build_runtime_profile()
	if SpaceOreParserRuntime.build_runtime_instance_id("probe-ship-world", definition_only_profile) != "probe-ship-world:probe-universal-parser":
		return _failure("definition-only development identity must remain stable")
	var legacy_checkpoint_identity := {"parserInstanceId": "probe-ship-world:probe-universal-parser"}
	if SpaceOreParserRuntime.build_runtime_instance_id("probe-ship-world", owned_profile_a, legacy_checkpoint_identity) != "probe-ship-world:probe-universal-parser":
		return _failure("legacy checkpoint restore must preserve pending Core import operation IDs")

	var owned_runtime_a := SpaceOreParserRuntime.new()
	var owned_runtime_b := SpaceOreParserRuntime.new()
	if not bool(owned_runtime_a.initialize(definition, owned_runtime_id_a, ["圆罐", "方罐"]).get("success", false)):
		return _failure("first owned parser runtime could not initialize")
	if not bool(owned_runtime_b.initialize(definition, owned_runtime_id_b, ["圆罐", "方罐"]).get("success", false)):
		return _failure("second owned parser runtime could not initialize")
	if bool(owned_runtime_b.restore_state(owned_runtime_a.capture_state()).get("success", false)):
		return _failure("one Owned Instance parser checkpoint was accepted by another copy")

	var runtime := SpaceOreParserRuntime.new()
	var initialized := runtime.initialize(definition, "probe-ship-world-parser", ["圆罐", "方罐"])
	if not bool(initialized.get("success", false)):
		return _failure("parser initialization failed: " + String(initialized.get("reason", "")))

	var circle_input := runtime.ingest_stone("stone-circle-1", "圆罐", 4.0)
	var square_input := runtime.ingest_stone("stone-square-1", "方罐", 2.0)
	if not bool(circle_input.success) or not bool(square_input.success):
		return _failure("universal parser rejected a configured stone type")
	var duplicate := runtime.ingest_stone("stone-circle-1", "圆罐", 4.0)
	if not bool(duplicate.success) or not bool(duplicate.duplicate):
		return _failure("repeated pickup identity was not idempotent")
	var collision := runtime.ingest_stone("stone-circle-1", "方罐", 4.0)
	if bool(collision.success):
		return _failure("pickup identity reuse with changed type was not rejected")

	var first_step := runtime.advance(1000)
	if not bool(first_step.success) or first_step.newBatches.size() != 1:
		return _failure("first parallel parse step should produce one circle Jar batch")
	var first_counts: Dictionary = first_step.newBatches[0].jarCounts
	if int(first_counts.get("圆罐", 0)) != 1 or first_counts.has("方罐"):
		return _failure("shape progress was not accumulated independently")

	var second_step := runtime.advance(1000)
	if not bool(second_step.success) or second_step.newBatches.size() != 1:
		return _failure("second parse step should produce the second circle Jar")
	var second_counts: Dictionary = second_step.newBatches[0].jarCounts
	if int(second_counts.get("圆罐", 0)) != 1:
		return _failure("circle stone volume was not consumed at the selected parser percentage")

	var square_before := runtime.ingest_stone("stone-square-2", "方罐", 1.0)
	if not bool(square_before.success):
		return _failure("parser rejected a second square stone")
	var third_step := runtime.advance(1000)
	if not bool(third_step.success) or third_step.newBatches.size() != 1:
		return _failure("square progress should complete independently on the third step")
	var third_counts: Dictionary = third_step.newBatches[0].jarCounts
	if int(third_counts.get("方罐", 0)) != 1:
		return _failure("square Jar was not produced at its independent threshold")

	# Splitting the same logical interval must preserve fixed-point production and remainder.
	var whole_step_runtime := SpaceOreParserRuntime.new()
	whole_step_runtime.initialize(definition, "chunk-invariance-parser", ["圆罐", "方罐"])
	whole_step_runtime.ingest_stone("chunk-circle", "圆罐", 10.0)
	whole_step_runtime.advance(1000)
	var split_step_runtime := SpaceOreParserRuntime.new()
	split_step_runtime.initialize(definition, "chunk-invariance-parser", ["圆罐", "方罐"])
	split_step_runtime.ingest_stone("chunk-circle", "圆罐", 10.0)
	for _i in range(100):
		split_step_runtime.advance(10)
	if whole_step_runtime.capture_state() != split_step_runtime.capture_state():
		return _failure("fixed-point parser output changed when logical time was split into smaller steps")

	# The battle runtime must freeze its selected parser definition.
	var mutable_definition := SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	var frozen_runtime := SpaceOreParserRuntime.new()
	var frozen_init := frozen_runtime.initialize(mutable_definition, "frozen-profile-probe", ["圆罐", "方罐"])
	if not bool(frozen_init.get("success", false)):
		return _failure("immutable parser runtime initialization failed")
	var frozen_profile: Dictionary = frozen_runtime.capture_state().get("parserProfile", {}).duplicate(true)
	mutable_definition.production_percentage = 100
	mutable_definition.shape_processing_rate_per_second["圆罐"] = 999.0
	if frozen_runtime.capture_state().parserProfile != frozen_profile:
		return _failure("mutating the source Resource changed the frozen battle parser")

	# Arithmetic overflow and the Jar Int32 import ceiling must reject atomically.
	var overflow_definition := SpaceOreParserDefinition.new()
	overflow_definition.parser_id = &"probe-overflow-parser"
	overflow_definition.definition_version = 1
	overflow_definition.production_percentage = 100
	overflow_definition.shape_processing_rate_per_second = {"圆罐": 1000000000.0, "方罐": 0.0}
	overflow_definition.progress_per_jar_by_shape = {"圆罐": 1.0, "方罐": 1.0}
	var overflow_runtime := SpaceOreParserRuntime.new()
	var overflow_init := overflow_runtime.initialize(overflow_definition, "overflow-parser-instance", ["圆罐", "方罐"])
	if not bool(overflow_init.get("success", false)):
		return _failure("overflow parser fixture initialization failed")
	overflow_runtime.ingest_stone("overflow-stone", "圆罐", 1.0)
	var overflow_before := overflow_runtime.capture_state()
	var overflow_result := overflow_runtime.advance(9223372036854775807)
	if bool(overflow_result.get("success", false)) or overflow_runtime.capture_state() != overflow_before:
		return _failure("fixed-point arithmetic overflow was not rejected atomically")

	var batch_limit_definition := SpaceOreParserDefinition.new()
	batch_limit_definition.parser_id = &"probe-batch-limit-parser"
	batch_limit_definition.definition_version = 1
	batch_limit_definition.production_percentage = 100
	batch_limit_definition.shape_processing_rate_per_second = {"圆罐": 214748.4, "方罐": 0.0}
	batch_limit_definition.progress_per_jar_by_shape = {"圆罐": 0.0001, "方罐": 1.0}
	var batch_limit_runtime := SpaceOreParserRuntime.new()
	var batch_limit_init := batch_limit_runtime.initialize(batch_limit_definition, "batch-limit-parser-instance", ["圆罐", "方罐"])
	if not bool(batch_limit_init.get("success", false)):
		return _failure("batch-limit parser fixture initialization failed")
	batch_limit_runtime.ingest_stone("batch-limit-stone", "圆罐", 214748.4)
	var batch_limit_before := batch_limit_runtime.capture_state()
	var batch_limit_result := batch_limit_runtime.advance(1000)
	if bool(batch_limit_result.get("success", false)) or batch_limit_runtime.capture_state() != batch_limit_before:
		return _failure("Jar import Int32 batch ceiling was not rejected atomically")

	var checkpoint := runtime.capture_state()
	var restored := SpaceOreParserRuntime.new()
	var restored_init := restored.initialize(definition, "probe-ship-world-parser", ["圆罐", "方罐"])
	if not bool(restored_init.get("success", false)):
		return _failure("restored parser initialization failed")
	var restore_result := restored.restore_state(checkpoint)
	if not bool(restore_result.get("success", false)):
		return _failure("parser checkpoint restore failed: " + String(restore_result.get("reason", "")))
	if restored.pending_output_batches().size() != 3:
		return _failure("pending output batches were not preserved by checkpoint")

	# Schema 3 persists cumulative completed Jars and checks per-shape resource
	# conservation. Schema 2 migration derives the same ledger only from exact evidence.
	var legacy_checkpoint := checkpoint.duplicate(true)
	legacy_checkpoint.schemaVersion = 2
	legacy_checkpoint.erase("producedJarCountByShape")
	var legacy_restored := SpaceOreParserRuntime.new()
	legacy_restored.initialize(definition, "probe-ship-world-parser", ["圆罐", "方罐"])
	var legacy_result := legacy_restored.restore_state(legacy_checkpoint)
	if not bool(legacy_result.get("success", false)) or legacy_restored.capture_state().producedJarCountByShape != checkpoint.producedJarCountByShape:
		return _failure("schema 2 checkpoint did not migrate its provable cumulative Jar ledger")

	var corrupt_output_ledger := checkpoint.duplicate(true)
	corrupt_output_ledger.producedJarCountByShape["圆罐"] = int(corrupt_output_ledger.producedJarCountByShape["圆罐"]) + 1
	var rejected_output_ledger := restored.restore_state(corrupt_output_ledger)
	if bool(rejected_output_ledger.get("success", false)):
		return _failure("checkpoint restore accepted cumulative output that violates stone resource conservation")
	if restored.capture_state() != checkpoint:
		return _failure("rejected output-ledger checkpoint partially mutated parser state")

	# Corrupt a queued pickup's shape identity. Restore must reject the whole snapshot
	# and leave the already-restored live parser state untouched.
	var state_before_rejection := restored.capture_state()
	var corrupt_pickup := checkpoint.duplicate(true)
	corrupt_pickup.seenPickups["stone-circle-1"].stoneType = "方罐"
	var rejected_pickup := restored.restore_state(corrupt_pickup)
	if bool(rejected_pickup.get("success", false)):
		return _failure("checkpoint restore accepted a pickup/queue shape mismatch")
	if restored.capture_state() != state_before_rejection:
		return _failure("rejected checkpoint partially mutated parser state")

	var excess_pending_output := checkpoint.duplicate(true)
	var excess_pending_id := String(excess_pending_output.pendingOutputBatches.keys()[0])
	excess_pending_output.pendingOutputBatches[excess_pending_id].jarCounts["圆罐"] = int(excess_pending_output.pendingOutputBatches[excess_pending_id].jarCounts.get("圆罐", 0)) + 1
	var rejected_excess_pending := restored.restore_state(excess_pending_output)
	if bool(rejected_excess_pending.get("success", false)):
		return _failure("checkpoint restore accepted pending Jar output beyond cumulative completed production")
	if restored.capture_state() != state_before_rejection:
		return _failure("rejected excess pending output partially mutated parser state")

	var corrupt_batch := checkpoint.duplicate(true)
	var corrupt_batch_id := String(corrupt_batch.pendingOutputBatches.keys()[0])
	corrupt_batch.pendingOutputBatches[corrupt_batch_id].jarCounts["未知罐"] = 1
	var rejected_batch := restored.restore_state(corrupt_batch)
	if bool(rejected_batch.get("success", false)):
		return _failure("checkpoint restore accepted an unknown pending output shape")
	if restored.capture_state() != state_before_rejection:
		return _failure("rejected pending batch checkpoint partially mutated parser state")
	var pending_batch: Dictionary = restored.pending_output_batches()[0]
	var pending_id := String(pending_batch.operationId)
	var pending_counts: Dictionary = pending_batch.get("jarCounts", {})
	var pending_jar_count := 0
	for amount in pending_counts.values():
		pending_jar_count += int(amount)
	var malformed_receipt := {
		"success": true,
		"wasDuplicate": false,
		"hasExactReceipt": true,
		"submittedJarCount": pending_jar_count + 1,
		"storedJarCount": pending_jar_count + 1,
		"discardedJarCount": 0
	}
	var before_bad_receipt := restored.capture_state()
	if restored.acknowledge_output_batch(pending_id, malformed_receipt) or restored.capture_state() != before_bad_receipt:
		return _failure("malformed Core import receipt must reject without removing the pending batch")
	var exact_receipt := {
		"success": true,
		"wasDuplicate": false,
		"hasExactReceipt": true,
		"submittedJarCount": pending_jar_count,
		"storedJarCount": pending_jar_count - 1,
		"discardedJarCount": 1
	}
	if not restored.acknowledge_output_batch(pending_id, exact_receipt):
		return _failure("complete Core import receipt was not accepted")
	if restored.acknowledge_output_batch(pending_id, exact_receipt):
		return _failure("output batch receipt acknowledgment must be one-shot")
	var captured_receipts := restored.capture_state()
	if captured_receipts.coreImportReceipts.size() != 1 or not bool(captured_receipts.coreImportReceiptHistoryComplete):
		return _failure("complete schema 4 receipt history was not retained after an exact import")
	var receipt_observation: Dictionary = restored.build_supply_observation_snapshot()
	if int(receipt_observation.get("exactCoreStoredJarCount", -1)) != pending_jar_count - 1 or int(receipt_observation.get("exactCoreDiscardedJarCount", -1)) != 1:
		return _failure("read-only parser supply observation did not expose exact stored/discarded counts")
	var receipt_restored := SpaceOreParserRuntime.new()
	if not bool(receipt_restored.initialize(definition, "probe-ship-world-parser", ["圆罐", "方罐"]).get("success", false)):
		return _failure("receipt round-trip parser initialization failed")
	if not bool(receipt_restored.restore_state(captured_receipts).get("success", false)):
		return _failure("Core import receipt history did not survive parser checkpoint restore")
	if receipt_restored.get_core_import_receipts() != restored.get_core_import_receipts():
		return _failure("restored Core import receipts changed their exact payload")
	# A newly initialized Parser can prove a complete history when every emitted batch
	# is still pending or has an exact retained Core response.
	var fresh_history_runtime := SpaceOreParserRuntime.new()
	if not bool(fresh_history_runtime.initialize(definition, "fresh-receipt-history-parser", ["圆罐", "方罐"]).get("success", false)):
		return _failure("fresh receipt-history parser initialization failed")
	if not bool(fresh_history_runtime.ingest_stone("fresh-receipt-stone", "圆罐", 4.0).get("success", false)):
		return _failure("fresh receipt-history parser rejected its stone fixture")
	var fresh_parse := fresh_history_runtime.advance(1000)
	if not bool(fresh_parse.get("success", false)) or fresh_parse.get("newBatches", []).size() != 1:
		return _failure("fresh receipt-history parser did not produce its expected batch")
	var fresh_batch: Dictionary = fresh_parse.newBatches[0]
	var fresh_exact_receipt := {
		"success": true,
		"wasDuplicate": false,
		"hasExactReceipt": true,
		"submittedJarCount": 1,
		"storedJarCount": 1,
		"discardedJarCount": 0
	}
	if not fresh_history_runtime.acknowledge_output_batch(String(fresh_batch.operationId), fresh_exact_receipt):
		return _failure("fresh Parser could not commit its exact Core receipt")
	if not bool(fresh_history_runtime.build_supply_observation_snapshot().get("coreImportReceiptHistoryComplete", false)):
		return _failure("new Parser with complete exact receipts did not retain its complete-history status")

	# A duplicate response carrying the durable Core receipt is exact, not unknown.
	var duplicate_exact_runtime := SpaceOreParserRuntime.new()
	if not bool(duplicate_exact_runtime.initialize(definition, "duplicate-exact-parser", ["圆罐", "方罐"]).get("success", false)):
		return _failure("duplicate-exact parser initialization failed")
	if not bool(duplicate_exact_runtime.ingest_stone("duplicate-exact-stone", "圆罐", 4.0).get("success", false)):
		return _failure("duplicate-exact parser rejected its stone fixture")
	var duplicate_exact_parse := duplicate_exact_runtime.advance(1000)
	if not bool(duplicate_exact_parse.get("success", false)) or duplicate_exact_parse.get("newBatches", []).size() != 1:
		return _failure("duplicate-exact parser did not produce its batch")
	var duplicate_exact_batch: Dictionary = duplicate_exact_parse.newBatches[0]
	var duplicate_exact_response := {
		"success": true,
		"wasDuplicate": true,
		"hasExactReceipt": true,
		"submittedJarCount": 1,
		"storedJarCount": 0,
		"discardedJarCount": 1
	}
	if not duplicate_exact_runtime.acknowledge_output_batch(String(duplicate_exact_batch.operationId), duplicate_exact_response):
		return _failure("Core duplicate with durable exact receipt was not accepted")
	var duplicate_exact_observation: Dictionary = duplicate_exact_runtime.build_supply_observation_snapshot()
	if int(duplicate_exact_observation.get("exactCoreDiscardedJarCount", -1)) != 1 or int(duplicate_exact_observation.get("duplicateExactBatchCount", -1)) != 1 or int(duplicate_exact_observation.get("duplicateConfirmationBatchCountWithUnknownOutcome", -1)) != 0:
		return _failure("exact duplicate receipt was incorrectly classified as unknown")

	# Parser schema 4 / receipt schema 1 remains loadable and preserves unknown outcome.
	var legacy_receipt_state := captured_receipts.duplicate(true)
	legacy_receipt_state["schemaVersion"] = 4
	var legacy_receipt: Dictionary = legacy_receipt_state["coreImportReceipts"].values()[0].duplicate(true)
	legacy_receipt["schemaVersion"] = 1
	legacy_receipt["coreResponse"].erase("hasExactReceipt")
	legacy_receipt["coreResponse"]["wasDuplicate"] = true
	legacy_receipt["coreResponse"]["submittedJarCount"] = 0
	legacy_receipt["coreResponse"]["storedJarCount"] = 0
	legacy_receipt["coreResponse"]["discardedJarCount"] = 0
	legacy_receipt["outcomeStatus"] = "duplicate_confirmation_only"
	var legacy_receipt_id := String(legacy_receipt.get("operationId", ""))
	legacy_receipt_state["coreImportReceipts"][legacy_receipt_id] = legacy_receipt
	var legacy_receipt_runtime := SpaceOreParserRuntime.new()
	legacy_receipt_runtime.initialize(definition, "probe-ship-world-parser", ["圆罐", "方罐"])
	if not bool(legacy_receipt_runtime.restore_state(legacy_receipt_state).get("success", false)):
		return _failure("schema 4 legacy receipt checkpoint was not accepted")
	var legacy_receipt_observation: Dictionary = legacy_receipt_runtime.build_supply_observation_snapshot()
	if int(legacy_receipt_observation.get("duplicateConfirmationBatchCountWithUnknownOutcome", 0)) != 1 or bool(legacy_receipt_observation.get("coreImportReceiptHistoryComplete", false)) != bool(captured_receipts.coreImportReceiptHistoryComplete):
		return _failure("schema 4 legacy receipt did not preserve its unknown outcome / history flag")

	# Schema 3 had cumulative output accounting but no Core receipt ledger. It remains
	# loadable, but must advertise that historical import outcomes are incomplete.
	var legacy_schema_three := checkpoint.duplicate(true)
	legacy_schema_three["schemaVersion"] = 3
	var legacy_schema_three_runtime := SpaceOreParserRuntime.new()
	legacy_schema_three_runtime.initialize(definition, "probe-ship-world-parser", ["圆罐", "方罐"])
	if not bool(legacy_schema_three_runtime.restore_state(legacy_schema_three).get("success", false)):
		return _failure("schema 3 parser checkpoint was not accepted by the receipt-ledger migration")
	if bool(legacy_schema_three_runtime.build_supply_observation_snapshot().get("coreImportReceiptHistoryComplete", true)):
		return _failure("legacy schema 3 checkpoint falsely claimed a complete Core receipt history")
	print("[SpaceOreParserRuntimeProbe] core-import-receipt-retention=passed")
	print("[SpaceOreParserRuntimeProbe] receipt-validation-is-atomic=passed")
	print("[SpaceOreParserRuntimeProbe] receipt-history-schema-migration=passed")

	return {
		"passed": true,
		"productionPercentage": definition.production_percentage,
		"pendingBatchesBeforeAck": 3,
		"remainingCircleProgress": runtime.capture_state().progressMicroByShape["圆罐"],
		"remainingSquareProgress": runtime.capture_state().progressMicroByShape["方罐"],
		"retainedCoreImportReceipts": restored.get_core_import_receipts().size(),
		"receiptHistoryComplete": receipt_observation.coreImportReceiptHistoryComplete
	}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
