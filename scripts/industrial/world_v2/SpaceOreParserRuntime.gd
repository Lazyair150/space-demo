extends RefCounted
class_name SpaceOreParserRuntime
## Space-owned finite-input parser. It consumes typed stone volume and emits whole-Jar
## batches; it never creates or mutates Jar Core entities.
##
## Rates are progress units per logical second. delta_logical_milli uses 1000 per
## logical second. All progress/volume is stored in fixed-point micro-units.

const MICRO: int = 1000000
const RATE_DENOMINATOR: int = 100000
const STATE_SCHEMA_VERSION: int = 1
const MAX_INT64: int = 9223372036854775807

var _definition: SpaceOreParserDefinition
var _parser_instance_id: String = ""
var _parser_token: String = ""
var _stone_queues_by_shape: Dictionary = {}
var _seen_pickups: Dictionary = {}
var _progress_micro_by_shape: Dictionary = {}
var _rate_remainder_by_shape: Dictionary = {}
var _pending_output_batches: Dictionary = {}
var _next_batch_sequence: int = 1

func initialize(
	definition: SpaceOreParserDefinition,
	parser_instance_id: String,
	shape_names: Array
) -> Dictionary:
	if definition == null:
		return _failure("ore parser definition is required")
	if parser_instance_id.strip_edges().is_empty():
		return _failure("parser instance ID is required")
	var errors := definition.get_validation_errors(shape_names)
	if not errors.is_empty():
		return _failure("; ".join(errors))

	_definition = definition
	_parser_instance_id = parser_instance_id
	_parser_token = _sha256(parser_instance_id).substr(0, 20)
	_stone_queues_by_shape.clear()
	_seen_pickups.clear()
	_progress_micro_by_shape.clear()
	_rate_remainder_by_shape.clear()
	_pending_output_batches.clear()
	_next_batch_sequence = 1
	for raw_shape in shape_names:
		var shape := String(raw_shape)
		_stone_queues_by_shape[shape] = []
		_progress_micro_by_shape[shape] = 0
		_rate_remainder_by_shape[shape] = 0
	return {"success": true}

## Universal parser input: any configured energy-stone type is accepted.
## The stone type names the output Jar shape; its volume is finite parseable progress.
func ingest_stone(pickup_id: String, stone_type: String, volume: float) -> Dictionary:
	if _definition == null:
		return _failure("ore parser runtime is not initialized")
	if pickup_id.strip_edges().is_empty() or pickup_id.length() > 128:
		return _failure("pickup ID must contain 1 to 128 characters")
	if not _stone_queues_by_shape.has(stone_type):
		return _failure("unknown energy-stone type / Jar shape: " + stone_type)
	if not is_finite(volume) or volume <= 0.0 or volume > 1000000000.0:
		return _failure("stone volume must be finite and positive")
	var volume_micro := int(round(volume * MICRO))
	if volume_micro <= 0:
		return _failure("stone volume is below fixed-point precision")

	var fingerprint := stone_type + ":" + str(volume_micro)
	if _seen_pickups.has(pickup_id):
		if String(_seen_pickups[pickup_id]) != fingerprint:
			return _failure("pickup ID was reused with different stone data: " + pickup_id)
		return {"success": true, "duplicate": true, "acceptedVolume": 0.0}

	_seen_pickups[pickup_id] = fingerprint
	_stone_queues_by_shape[stone_type].append({
		"pickupId": pickup_id,
		"remainingVolumeMicro": volume_micro
	})
	return {"success": true, "duplicate": false, "acceptedVolume": float(volume_micro) / MICRO}

## Advance each shape independently. Unprocessed stone volume and fractional Jar progress
## remain in the parser snapshot; output batches stay pending until Jar confirms import.
func advance(delta_logical_milli: int) -> Dictionary:
	if _definition == null:
		return _failure("ore parser runtime is not initialized")
	if delta_logical_milli < 0:
		return _failure("logical time delta cannot be negative")
	var new_batches: Array[Dictionary] = []
	if delta_logical_milli == 0:
		return {"success": true, "newBatches": new_batches}

	var shapes: Array = _stone_queues_by_shape.keys()
	shapes.sort()
	var output_counts: Dictionary = {}
	for shape_value in shapes:
		var shape := String(shape_value)
		var base_rate_micro := int(round(float(_definition.shape_processing_rate_per_second[shape]) * MICRO))
		if _definition.production_percentage > 0 and delta_logical_milli > int(MAX_INT64 / _definition.production_percentage):
			return _failure("ore parser logical time factor exceeds the supported fixed-point range")
		var rate_factor := _definition.production_percentage * delta_logical_milli
		var rate_remainder := int(_rate_remainder_by_shape[shape])
		if rate_factor > 0 and base_rate_micro > int((MAX_INT64 - rate_remainder) / rate_factor):
			return _failure("ore parser processing arithmetic exceeds the supported fixed-point range")
		var numerator := base_rate_micro * rate_factor + rate_remainder
		var process_budget_micro := int(numerator / RATE_DENOMINATOR)
		_rate_remainder_by_shape[shape] = numerator % RATE_DENOMINATOR
		if process_budget_micro <= 0:
			continue

		var queue: Array = _stone_queues_by_shape[shape]
		var consumed_micro := 0
		while process_budget_micro > 0 and not queue.is_empty():
			var stone: Dictionary = queue[0]
			var remaining := int(stone.remainingVolumeMicro)
			var consumed := mini(process_budget_micro, remaining)
			remaining -= consumed
			process_budget_micro -= consumed
			consumed_micro += consumed
			if remaining == 0:
				queue.pop_front()
			else:
				stone["remainingVolumeMicro"] = remaining
				queue[0] = stone

		if consumed_micro <= 0:
			continue
		var previous_progress := int(_progress_micro_by_shape[shape])
		if consumed_micro > MAX_INT64 - previous_progress:
			return _failure("ore parser progress arithmetic exceeds the supported fixed-point range")
		var progress := previous_progress + consumed_micro
		var threshold := int(round(float(_definition.progress_per_jar_by_shape[shape]) * MICRO))
		var produced := int(progress / threshold)
		_progress_micro_by_shape[shape] = progress % threshold
		if produced > 0:
			output_counts[shape] = produced

	if not output_counts.is_empty():
		var operation_id := "ore-parser:" + _parser_token + ":" + str(_next_batch_sequence)
		_next_batch_sequence += 1
		var batch := {
			"operationId": operation_id,
			"jarCounts": output_counts.duplicate(true)
		}
		_pending_output_batches[operation_id] = batch
		new_batches.append(batch.duplicate(true))
	return {"success": true, "newBatches": new_batches}

func pending_output_batches() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for operation_id in _pending_output_batches:
		result.append(_pending_output_batches[operation_id].duplicate(true))
	return result

## Acknowledge only after WorldV2ShipHost.ImportProducedJars reports success.
func acknowledge_output_batch(operation_id: String) -> bool:
	if not _pending_output_batches.has(operation_id):
		return false
	_pending_output_batches.erase(operation_id)
	return true

func capture_state() -> Dictionary:
	if _definition == null:
		return {}
	return {
		"schemaVersion": STATE_SCHEMA_VERSION,
		"parserInstanceId": _parser_instance_id,
		"parserProfile": _definition.build_runtime_profile(),
		"stoneQueuesByShape": _stone_queues_by_shape.duplicate(true),
		"seenPickups": _seen_pickups.duplicate(true),
		"progressMicroByShape": _progress_micro_by_shape.duplicate(true),
		"rateRemainderByShape": _rate_remainder_by_shape.duplicate(true),
		"pendingOutputBatches": _pending_output_batches.duplicate(true),
		"nextBatchSequence": _next_batch_sequence
	}

func restore_state(state: Dictionary) -> Dictionary:
	if _definition == null:
		return _failure("ore parser runtime is not initialized")
	if int(state.get("schemaVersion", 0)) != STATE_SCHEMA_VERSION:
		return _failure("unsupported ore parser state schema")
	if String(state.get("parserInstanceId", "")) != _parser_instance_id:
		return _failure("ore parser instance identity does not match")
	if state.get("parserProfile", {}) != _definition.build_runtime_profile():
		return _failure("ore parser definition/profile does not match the checkpoint")

	var queues: Variant = state.get("stoneQueuesByShape", null)
	var seen: Variant = state.get("seenPickups", null)
	var progress: Variant = state.get("progressMicroByShape", null)
	var remainders: Variant = state.get("rateRemainderByShape", null)
	var pending: Variant = state.get("pendingOutputBatches", null)
	var next_sequence := int(state.get("nextBatchSequence", 0))
	if not (queues is Dictionary) or not (seen is Dictionary) or not (progress is Dictionary) or not (remainders is Dictionary) or not (pending is Dictionary) or next_sequence <= 0:
		return _failure("ore parser checkpoint has invalid top-level state")
	var expected_shapes := _stone_queues_by_shape.keys()
	if queues.size() != expected_shapes.size() or progress.size() != expected_shapes.size() or remainders.size() != expected_shapes.size():
		return _failure("ore parser checkpoint shape maps do not match the selected parser")
	var queued_pickup_ids := {}
	for shape in expected_shapes:
		if not queues.has(shape) or not (queues[shape] is Array):
			return _failure("ore parser checkpoint is missing a shape queue: " + String(shape))
		if not progress.has(shape) or int(progress[shape]) < 0:
			return _failure("ore parser checkpoint has invalid shape progress: " + String(shape))
		var threshold := int(round(float(_definition.progress_per_jar_by_shape[shape]) * MICRO))
		if int(progress[shape]) >= threshold:
			return _failure("ore parser checkpoint contains unconverted whole-Jar progress: " + String(shape))
		if not remainders.has(shape) or int(remainders[shape]) < 0 or int(remainders[shape]) >= RATE_DENOMINATOR:
			return _failure("ore parser checkpoint has invalid rate remainder: " + String(shape))
		for raw_stone in queues[shape]:
			if not (raw_stone is Dictionary):
				return _failure("ore parser checkpoint contains a malformed queued stone: " + String(shape))
			var pickup_id := String(raw_stone.get("pickupId", ""))
			var remaining_volume := int(raw_stone.get("remainingVolumeMicro", 0))
			if pickup_id.is_empty() or remaining_volume <= 0 or queued_pickup_ids.has(pickup_id) or not seen.has(pickup_id):
				return _failure("ore parser checkpoint contains an invalid or repeated queued pickup: " + String(shape))
			var pickup_fingerprint := String(seen[pickup_id])
			var pickup_parts := pickup_fingerprint.split(":")
			if pickup_parts.size() != 2 or pickup_parts[0] != shape or not pickup_parts[1].is_valid_int() or int(pickup_parts[1]) < remaining_volume:
				return _failure("queued pickup identity does not match its stone type/remaining volume")
			queued_pickup_ids[pickup_id] = true
	for pickup_id in seen:
		if String(pickup_id).strip_edges().is_empty() or not (seen[pickup_id] is String):
			return _failure("ore parser checkpoint contains an invalid pickup identity")
		var fingerprint_parts := String(seen[pickup_id]).split(":")
		if fingerprint_parts.size() != 2 or not _stone_queues_by_shape.has(fingerprint_parts[0]) or not fingerprint_parts[1].is_valid_int() or int(fingerprint_parts[1]) <= 0:
			return _failure("ore parser checkpoint contains an invalid pickup fingerprint")
	var maximum_pending_sequence := 0
	for operation_id in pending:
		var batch: Variant = pending[operation_id]
		if not (batch is Dictionary) or String(batch.get("operationId", "")) != String(operation_id) or not (batch.get("jarCounts", null) is Dictionary) or batch.jarCounts.is_empty():
			return _failure("ore parser checkpoint contains an invalid pending output batch")
		var parts := String(operation_id).split(":")
		if parts.size() != 3 or parts[0] != "ore-parser" or parts[1] != _parser_token or not parts[2].is_valid_int():
			return _failure("ore parser checkpoint contains an output batch from another parser")
		var sequence := int(parts[2])
		if sequence <= 0:
			return _failure("ore parser checkpoint contains an invalid output sequence")
		maximum_pending_sequence = maxi(maximum_pending_sequence, sequence)
		for shape in batch.jarCounts:
			if not _stone_queues_by_shape.has(shape) or int(batch.jarCounts[shape]) <= 0:
				return _failure("ore parser checkpoint contains an invalid produced Jar shape/count")
	if next_sequence <= maximum_pending_sequence:
		return _failure("ore parser checkpoint next batch sequence is not monotonic")

	_stone_queues_by_shape = queues.duplicate(true)
	_seen_pickups = seen.duplicate(true)
	_progress_micro_by_shape = progress.duplicate(true)
	_rate_remainder_by_shape = remainders.duplicate(true)
	_pending_output_batches = pending.duplicate(true)
	_next_batch_sequence = next_sequence
	return {"success": true}

func _sha256(value: String) -> String:
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hasher.update(value.to_utf8_buffer())
	return hasher.finish().hex_encode()

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
