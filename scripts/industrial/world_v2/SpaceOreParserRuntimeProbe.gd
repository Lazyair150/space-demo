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
	var pending_id := String(restored.pending_output_batches()[0].operationId)
	if not restored.acknowledge_output_batch(pending_id) or restored.acknowledge_output_batch(pending_id):
		return _failure("output batch acknowledgment must be one-shot")

	return {
		"passed": true,
		"productionPercentage": definition.production_percentage,
		"pendingBatchesBeforeAck": 3,
		"remainingCircleProgress": runtime.capture_state().progressMicroByShape["圆罐"],
		"remainingSquareProgress": runtime.capture_state().progressMicroByShape["方罐"]
	}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
