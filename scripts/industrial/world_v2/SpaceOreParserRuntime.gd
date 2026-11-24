extends RefCounted
class_name SpaceOreParserRuntime
## Space-owned finite-input parser. It consumes typed stone volume and emits whole-Jar
## batches; it never creates or mutates Jar Core entities.
##
## Rates are progress units per logical second. delta_logical_milli uses 1000 per
## logical second. All progress/volume is stored in fixed-point micro-units.

const MICRO: int = 1000000
const RATE_DENOMINATOR: int = 100000
const STATE_SCHEMA_VERSION: int = 3
const MAX_INT64: int = 9223372036854775807
const MAX_FIXED_POINT_UNITS: float = 1000000000.0

var _definition: SpaceOreParserDefinition
var _parser_instance_id: String = ""
var _parser_token: String = ""
var _stone_queues_by_shape: Dictionary = {}
var _seen_pickups: Dictionary = {}
var _progress_micro_by_shape: Dictionary = {}
var _produced_jar_count_by_shape: Dictionary = {}
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

	# Freeze the selected pre-battle parser definition; later Resource edits must not
	# silently change a running battle or invalidate its checkpoint fingerprint.
	_definition = SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	_parser_instance_id = parser_instance_id
	_parser_token = _sha256(parser_instance_id).substr(0, 20)
	_stone_queues_by_shape.clear()
	_seen_pickups.clear()
	_progress_micro_by_shape.clear()
	_produced_jar_count_by_shape.clear()
	_rate_remainder_by_shape.clear()
	_pending_output_batches.clear()
	_next_batch_sequence = 1
	for raw_shape in shape_names:
		var shape := String(raw_shape)
		_stone_queues_by_shape[shape] = []
		_progress_micro_by_shape[shape] = 0
		_produced_jar_count_by_shape[shape] = 0
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

	if _seen_pickups.has(pickup_id):
		var prior: Variant = _seen_pickups[pickup_id]
		if not (prior is Dictionary) or String(prior.get("stoneType", "")) != stone_type or int(prior.get("originalVolumeMicro", 0)) != volume_micro:
			return _failure("pickup ID was reused with different stone data: " + pickup_id)
		return {"success": true, "duplicate": true, "acceptedVolume": 0.0}

	_seen_pickups[pickup_id] = {
		"stoneType": stone_type,
		"originalVolumeMicro": volume_micro
	}
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

	# Work on staged copies. Any arithmetic/bridge-limit rejection must leave queued
	# stones, accumulated progress, and rate remainders exactly as they were.
	var staged_queues: Dictionary = _stone_queues_by_shape.duplicate(true)
	var staged_progress: Dictionary = _progress_micro_by_shape.duplicate(true)
	var staged_produced: Dictionary = _produced_jar_count_by_shape.duplicate(true)
	var staged_remainders: Dictionary = _rate_remainder_by_shape.duplicate(true)
	var output_counts: Dictionary = {}
	var shapes: Array = staged_queues.keys()
	shapes.sort()
	for shape_value in shapes:
		var shape := String(shape_value)
		var raw_rate := float(_definition.shape_processing_rate_per_second[shape])
		if raw_rate > MAX_FIXED_POINT_UNITS:
			return _failure("ore parser processing rate exceeds the fixed-point representation limit: " + shape)
		var base_rate_micro := int(round(raw_rate * MICRO))
		var percentage := _definition.production_percentage
		if percentage > 0 and delta_logical_milli > int(MAX_INT64 / percentage):
			return _failure("ore parser logical time factor exceeds the supported fixed-point range")
		var rate_factor := percentage * delta_logical_milli
		var rate_remainder := int(staged_remainders[shape])
		if rate_factor > 0 and base_rate_micro > int((MAX_INT64 - rate_remainder) / rate_factor):
			return _failure("ore parser processing arithmetic exceeds the supported fixed-point range")
		var numerator := base_rate_micro * rate_factor + rate_remainder
		var process_budget_micro := int(numerator / RATE_DENOMINATOR)
		staged_remainders[shape] = numerator % RATE_DENOMINATOR
		if process_budget_micro <= 0:
			continue

		var queue: Array = staged_queues[shape]
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
		var previous_progress := int(staged_progress[shape])
		if consumed_micro > MAX_INT64 - previous_progress:
			return _failure("ore parser progress arithmetic exceeds the supported fixed-point range")
		var progress := previous_progress + consumed_micro
		var raw_threshold := float(_definition.progress_per_jar_by_shape[shape])
		if raw_threshold > MAX_FIXED_POINT_UNITS:
			return _failure("ore parser progress threshold exceeds the fixed-point representation limit: " + shape)
		var threshold := int(round(raw_threshold * MICRO))
		var produced := int(progress / threshold)
		staged_progress[shape] = progress % threshold
		if produced > 0:
			var previous_produced := int(staged_produced[shape])
			if produced > MAX_INT64 - previous_produced:
				return _failure("ore parser cumulative output accounting exceeds the supported range: " + shape)
			staged_produced[shape] = previous_produced + produced
			output_counts[shape] = produced

	if not output_counts.is_empty():
		# Jar's discrete import accepts positive Int32 counts per batch. Reject an
		# unrepresentable step before committing any parser consumption/progress.
		var total_output := 0
		for count in output_counts.values():
			if int(count) > 2147483647 - total_output:
				return _failure("one parser step exceeds the Jar import batch count limit")
			total_output += int(count)
		if _next_batch_sequence >= MAX_INT64:
			return _failure("ore parser output batch sequence is exhausted")
		var operation_id := "ore-parser:" + _parser_token + ":" + str(_next_batch_sequence)
		var batch := {
			"operationId": operation_id,
			"jarCounts": output_counts.duplicate(true)
		}
		var staged_pending: Dictionary = _pending_output_batches.duplicate(true)
		staged_pending[operation_id] = batch
		new_batches.append(batch.duplicate(true))
		_pending_output_batches = staged_pending
		_next_batch_sequence += 1

	_stone_queues_by_shape = staged_queues
	_progress_micro_by_shape = staged_progress
	_produced_jar_count_by_shape = staged_produced
	_rate_remainder_by_shape = staged_remainders
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
		"producedJarCountByShape": _produced_jar_count_by_shape.duplicate(true),
		"rateRemainderByShape": _rate_remainder_by_shape.duplicate(true),
		"pendingOutputBatches": _pending_output_batches.duplicate(true),
		"nextBatchSequence": _next_batch_sequence
	}

func restore_state(state: Dictionary) -> Dictionary:
	if _definition == null:
		return _failure("ore parser runtime is not initialized")
	var state_schema := int(state.get("schemaVersion", 0))
	if state_schema not in [2, STATE_SCHEMA_VERSION]:
		return _failure("unsupported ore parser state schema")
	if String(state.get("parserInstanceId", "")) != _parser_instance_id:
		return _failure("ore parser instance identity does not match")
	if state.get("parserProfile", {}) != _definition.build_runtime_profile():
		return _failure("ore parser definition/profile does not match the checkpoint")

	var queues: Variant = state.get("stoneQueuesByShape", null)
	var seen: Variant = state.get("seenPickups", null)
	var progress: Variant = state.get("progressMicroByShape", null)
	var produced: Variant = state.get("producedJarCountByShape", null)
	var remainders: Variant = state.get("rateRemainderByShape", null)
	var pending: Variant = state.get("pendingOutputBatches", null)
	var raw_next_sequence: Variant = state.get("nextBatchSequence", null)
	if not (queues is Dictionary) or not (seen is Dictionary) or not (progress is Dictionary) or (state_schema >= 3 and not (produced is Dictionary)) or not (remainders is Dictionary) or not (pending is Dictionary) or typeof(raw_next_sequence) != TYPE_INT or int(raw_next_sequence) <= 0:
		return _failure("ore parser checkpoint has invalid top-level state")

	var expected_shapes: Array = _stone_queues_by_shape.keys()
	expected_shapes.sort()
	if not _has_exact_shape_keys(queues, expected_shapes) or not _has_exact_shape_keys(progress, expected_shapes) or not _has_exact_shape_keys(remainders, expected_shapes) or (state_schema >= 3 and not _has_exact_shape_keys(produced, expected_shapes)):
		return _failure("ore parser checkpoint shape maps do not match the configured shape vocabulary")

	# Validate the pickup identity ledger before accepting any queue reference.
	for raw_pickup_id in seen:
		var pickup_id := String(raw_pickup_id)
		var record: Variant = seen[raw_pickup_id]
		if pickup_id.strip_edges().is_empty() or pickup_id.length() > 128 or not (record is Dictionary):
			return _failure("ore parser checkpoint contains an invalid pickup identity")
		var stone_type := String(record.get("stoneType", ""))
		var original_volume: Variant = record.get("originalVolumeMicro", null)
		if not _stone_queues_by_shape.has(stone_type) or typeof(original_volume) != TYPE_INT or int(original_volume) <= 0:
			return _failure("ore parser checkpoint contains invalid pickup data: " + pickup_id)

	# Every queued stone must point to exactly one matching, previously accepted pickup.
	var queued_pickups := {}
	for shape_value in expected_shapes:
		var shape := String(shape_value)
		var queue: Variant = queues[shape]
		if not (queue is Array):
			return _failure("ore parser checkpoint has an invalid shape queue: " + shape)
		for raw_stone in queue:
			if not (raw_stone is Dictionary):
				return _failure("ore parser checkpoint contains a malformed queued stone: " + shape)
			var pickup_id := String(raw_stone.get("pickupId", ""))
			var remaining: Variant = raw_stone.get("remainingVolumeMicro", null)
			if pickup_id.strip_edges().is_empty() or typeof(remaining) != TYPE_INT or int(remaining) <= 0 or queued_pickups.has(pickup_id) or not seen.has(pickup_id):
				return _failure("ore parser checkpoint contains an invalid queued stone: " + shape)
			var original: Dictionary = seen[pickup_id]
			if String(original.get("stoneType", "")) != shape or int(original.get("originalVolumeMicro", 0)) < int(remaining):
				return _failure("queued stone does not match its pickup identity: " + pickup_id)
			queued_pickups[pickup_id] = true

	# Progress and rate remainders are fixed-point integers and must stay below one Jar.
	for shape_value in expected_shapes:
		var shape := String(shape_value)
		var raw_progress: Variant = progress[shape]
		var raw_remainder: Variant = remainders[shape]
		if typeof(raw_progress) != TYPE_INT or int(raw_progress) < 0:
			return _failure("ore parser checkpoint has invalid shape progress: " + shape)
		var threshold := int(round(float(_definition.progress_per_jar_by_shape[shape]) * MICRO))
		if int(raw_progress) >= threshold:
			return _failure("ore parser checkpoint contains unconverted whole-Jar progress: " + shape)
		if typeof(raw_remainder) != TYPE_INT or int(raw_remainder) < 0 or int(raw_remainder) >= RATE_DENOMINATOR:
			return _failure("ore parser checkpoint has invalid rate remainder: " + shape)

	# Pending output IDs and counts are validated against this parser instance and shape vocabulary.
	var batch_sequences := {}
	var maximum_pending_sequence := 0
	var operation_prefix := "ore-parser:" + _parser_token + ":"
	for raw_operation_id in pending:
		var operation_id := String(raw_operation_id)
		var batch: Variant = pending[raw_operation_id]
		if not operation_id.begins_with(operation_prefix) or not (batch is Dictionary) or String(batch.get("operationId", "")) != operation_id:
			return _failure("ore parser checkpoint contains an invalid pending output identity")
		var sequence_text := operation_id.trim_prefix(operation_prefix)
		if not sequence_text.is_valid_int():
			return _failure("ore parser checkpoint contains an invalid pending batch sequence")
		var sequence := int(sequence_text)
		if sequence <= 0 or batch_sequences.has(sequence):
			return _failure("ore parser checkpoint contains a duplicate/invalid pending batch sequence")
		var counts: Variant = batch.get("jarCounts", null)
		if not (counts is Dictionary) or counts.is_empty():
			return _failure("ore parser checkpoint contains an empty pending output batch")
		var submitted_count := 0
		for shape_key in counts:
			var count: Variant = counts[shape_key]
			if not _stone_queues_by_shape.has(String(shape_key)) or typeof(count) != TYPE_INT or int(count) <= 0:
				return _failure("ore parser checkpoint contains an invalid pending Jar count")
			submitted_count += int(count)
			if submitted_count > 2147483647:
				return _failure("ore parser checkpoint pending batch exceeds the Jar import count limit")
		batch_sequences[sequence] = true
		maximum_pending_sequence = maxi(maximum_pending_sequence, sequence)

	if int(raw_next_sequence) <= maximum_pending_sequence:
		return _failure("ore parser checkpoint next batch sequence is not ahead of pending outputs")

	# Reconcile every accepted stone against queued volume, fractional progress and
	# cumulative completed Jars. Pending-vs-acknowledged output does not change this
	# conservation equation because both are already-produced Jars.
	var accepted_volume_by_shape := {}
	var queued_volume_by_shape := {}
	for shape_value in expected_shapes:
		var shape := String(shape_value)
		accepted_volume_by_shape[shape] = 0
		queued_volume_by_shape[shape] = 0
	for pickup_id_value in seen:
		var record: Dictionary = seen[pickup_id_value]
		var shape := String(record.get("stoneType", ""))
		var volume := int(record.get("originalVolumeMicro", 0))
		if volume > MAX_INT64 - int(accepted_volume_by_shape[shape]):
			return _failure("ore parser checkpoint accepted-volume ledger exceeds the supported range: " + shape)
		accepted_volume_by_shape[shape] = int(accepted_volume_by_shape[shape]) + volume
	for shape_value in expected_shapes:
		var shape := String(shape_value)
		for raw_stone in queues[shape]:
			var remaining := int(raw_stone.get("remainingVolumeMicro", 0))
			if remaining > MAX_INT64 - int(queued_volume_by_shape[shape]):
				return _failure("ore parser checkpoint queued-volume ledger exceeds the supported range: " + shape)
			queued_volume_by_shape[shape] = int(queued_volume_by_shape[shape]) + remaining

	var restored_produced: Dictionary = {}
	for shape_value in expected_shapes:
		var shape := String(shape_value)
		var threshold := int(round(float(_definition.progress_per_jar_by_shape[shape]) * MICRO))
		var accepted := int(accepted_volume_by_shape[shape])
		var queued := int(queued_volume_by_shape[shape])
		var fractional_progress := int(progress[shape])
		if state_schema >= 3:
			var raw_count: Variant = produced[shape]
			if typeof(raw_count) != TYPE_INT or int(raw_count) < 0:
				return _failure("ore parser checkpoint has invalid cumulative Jar count: " + shape)
			restored_produced[shape] = int(raw_count)
		else:
			# Schema 2 did not persist this ledger. Reconstruct it only when the
			# existing accepted/queued/progress data yields an exact whole-Jar count.
			var consumed := accepted - queued - fractional_progress
			if consumed < 0 or consumed % threshold != 0:
				return _failure("legacy Parser checkpoint cannot prove exact resource conservation: " + shape)
			restored_produced[shape] = int(consumed / threshold)
		var produced_count := int(restored_produced[shape])
		if produced_count > int((MAX_INT64 - queued - fractional_progress) / threshold):
			return _failure("ore parser checkpoint cumulative output volume exceeds the supported range: " + shape)
		var accounted := queued + fractional_progress + produced_count * threshold
		if accounted != accepted:
			return _failure("ore parser checkpoint violates accepted-stone resource conservation: " + shape)

	# Publish only after every nested structure has passed validation.
	_stone_queues_by_shape = queues.duplicate(true)
	_seen_pickups = seen.duplicate(true)
	_progress_micro_by_shape = progress.duplicate(true)
	_produced_jar_count_by_shape = restored_produced
	_rate_remainder_by_shape = remainders.duplicate(true)
	_pending_output_batches = pending.duplicate(true)
	_next_batch_sequence = int(raw_next_sequence)
	return {"success": true}


## Runtime identity is scoped to this battle and the exact installed parser copy.
## Definition-only identity is retained solely for isolated development fixtures.
static func build_runtime_instance_id(
	ship_world_id: String,
	parser_profile: Dictionary,
	persisted_parser_state: Dictionary = {}
) -> String:
	if ship_world_id.strip_edges().is_empty():
		return ""
	var parser_id := String(parser_profile.get("parserId", "")).strip_edges()
	var definition_version := int(parser_profile.get("definitionVersion", 0))
	if parser_id.is_empty() or definition_version <= 0:
		return ""
	var legacy_id := ship_world_id + ":" + parser_id
	# A checkpoint created before Owned Instance namespacing may still have a pending
	# batch already committed by Core but not acknowledged by Space. Keep its original
	# operation-ID namespace for that exact restore; restore_state still verifies profile.
	if String(persisted_parser_state.get("parserInstanceId", "")) == legacy_id:
		return legacy_id
	var raw_owned: Variant = parser_profile.get("ownedInstance", null)
	if raw_owned == null:
		# Stable Definition-only development identity; also preserves legacy fixture saves.
		return legacy_id
	if not (raw_owned is Dictionary):
		return ""
	var owned_id := String(raw_owned.get("instanceId", "")).strip_edges()
	if owned_id.is_empty() or String(raw_owned.get("itemKind", "")) != "ore_parser" or String(raw_owned.get("definitionId", "")) != parser_id or int(raw_owned.get("definitionVersion", 0)) != definition_version:
		return ""
	return ship_world_id + ":owned:" + owned_id

func _has_exact_shape_keys(values: Dictionary, expected_shapes: Array) -> bool:
	if values.size() != expected_shapes.size():
		return false
	for shape in expected_shapes:
		if not values.has(shape):
			return false
	return true

func _sha256(value: String) -> String:
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hasher.update(value.to_utf8_buffer())
	return hasher.finish().hex_encode()

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
