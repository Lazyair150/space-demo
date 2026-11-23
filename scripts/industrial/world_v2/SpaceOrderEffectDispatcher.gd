extends RefCounted
class_name SpaceOrderEffectDispatcher
## Space-owned consumer for Jar's detached OrderCycleCompleted events.
##
## The effect commit callback is deliberately injected: it must resolve/apply the
## Space effect and durably persist BOTH the resulting effect state and the supplied
## dispatcher state before returning true. Jar is acknowledged only after that commit.

const STATE_SCHEMA_VERSION: int = 1

var _loadout: SpaceBattleLoadoutSnapshot
var _processed_event_ids: Dictionary = {}
var _jar_world_instance_id: String = ""

func configure(
	loadout: SpaceBattleLoadoutSnapshot,
	persisted_state: Dictionary = {}
) -> bool:
	if loadout == null:
		push_error("Order effect dispatcher requires a frozen battle loadout")
		return false
	_loadout = loadout
	_processed_event_ids.clear()
	_jar_world_instance_id = ""
	if persisted_state.is_empty():
		return true
	return restore_state(persisted_state)

## Read is repeatable. Events with missing bindings or failed Space commits remain pending.
func drain_pending(jar_host: Object, commit_effect: Callable) -> int:
	if _loadout == null:
		push_error("Order effect dispatcher is not configured")
		return 0
	if jar_host == null or not jar_host.has_method("GetPendingOrderCycleEvents") or not jar_host.has_method("AcknowledgeOrderCycleEvent"):
		push_error("Jar host does not expose the order-cycle outbox contract")
		return 0
	if not commit_effect.is_valid():
		push_error("Order effect dispatcher requires a valid durable commit callback")
		return 0

	var acknowledged_count := 0
	var pending: Array = jar_host.GetPendingOrderCycleEvents()
	for raw_event in pending:
		if not (raw_event is Dictionary):
			push_error("Jar returned a malformed order-cycle event")
			break
		var event: Dictionary = raw_event
		if not _validate_event(event):
			push_error("Jar returned an invalid order-cycle event: " + str(event))
			break

		var event_id := String(event["eventId"])
		if _processed_event_ids.has(event_id):
			# This state came from a prior durable Space save; only the Jar ack remains.
			jar_host.AcknowledgeOrderCycleEvent(event_id)
			continue

		var order_key := String(event["orderDefinitionKey"])
		var order_binding := _loadout.resolve_order_binding(order_key)
		if order_binding.is_empty():
			# Never acknowledge an event whose order is not part of this immutable battle build.
			push_error("No selected order binding for orderDefinitionKey: " + order_key)
			break

		var event_world_id := String(event["worldInstanceId"])
		if not _jar_world_instance_id.is_empty() and _jar_world_instance_id != event_world_id:
			push_error("Order-cycle event belongs to a different Jar world instance")
			break

		var next_processed_ids := _processed_event_ids.keys()
		next_processed_ids.append(event_id)
		next_processed_ids.sort()
		var next_state := {
			"schemaVersion": STATE_SCHEMA_VERSION,
			"shipWorldId": _loadout.ship_world_id(),
			"loadoutId": _loadout.loadout_id(),
			"loadoutVersion": _loadout.loadout_version(),
			"loadoutFingerprint": _loadout.loadout_fingerprint(),
			"jarWorldInstanceId": event_world_id,
			"processedEventIds": next_processed_ids
		}

		# Callback owns Space semantics: BuffDefinition or any other effect, target,
		# duration/stacking rules, and atomic persistence of effect + next_state.
		var committed: Variant = commit_effect.call(
			event.duplicate(true),
			order_binding.duplicate(true),
			next_state.duplicate(true)
		)
		if committed != true:
			# Stop here to preserve event order; this event remains pending in Jar.
			break

		_jar_world_instance_id = event_world_id
		_processed_event_ids[event_id] = true
		jar_host.AcknowledgeOrderCycleEvent(event_id)
		acknowledged_count += 1

	return acknowledged_count

func capture_state() -> Dictionary:
	if _loadout == null:
		return {}
	var ids := _processed_event_ids.keys()
	ids.sort()
	return {
		"schemaVersion": STATE_SCHEMA_VERSION,
		"shipWorldId": _loadout.ship_world_id(),
		"loadoutId": _loadout.loadout_id(),
		"loadoutVersion": _loadout.loadout_version(),
		"loadoutFingerprint": _loadout.loadout_fingerprint(),
		"jarWorldInstanceId": _jar_world_instance_id,
		"processedEventIds": ids
	}

func restore_state(snapshot: Dictionary) -> bool:
	if _loadout == null:
		return false
	if int(snapshot.get("schemaVersion", 0)) != STATE_SCHEMA_VERSION:
		push_error("Unsupported Space order dispatcher state schema")
		return false
	if String(snapshot.get("shipWorldId", "")) != _loadout.ship_world_id() or String(snapshot.get("loadoutId", "")) != _loadout.loadout_id() or int(snapshot.get("loadoutVersion", 0)) != _loadout.loadout_version() or String(snapshot.get("loadoutFingerprint", "")) != _loadout.loadout_fingerprint():
		push_error("Persisted order dispatcher state does not match the frozen battle loadout")
		return false

	var ids: Variant = snapshot.get("processedEventIds", null)
	if not (ids is Array):
		push_error("Processed order event identities must be an array")
		return false
	var staged := {}
	for value in ids:
		var event_id := String(value)
		if event_id.is_empty() or staged.has(event_id):
			push_error("Processed order event identities contain an empty or duplicate ID")
			return false
		staged[event_id] = true

	var restored_world_id := String(snapshot.get("jarWorldInstanceId", ""))
	if not staged.is_empty() and restored_world_id.is_empty():
		push_error("Processed order events require a Jar world-instance identity")
		return false
	for event_id in staged:
		if not restored_world_id.is_empty() and not event_id.begins_with(restored_world_id + ":"):
			push_error("Processed order event belongs to a different Jar world instance")
			return false

	_processed_event_ids = staged
	_jar_world_instance_id = restored_world_id
	return true

func is_processed(event_id: String) -> bool:
	return _processed_event_ids.has(event_id)

func _validate_event(event: Dictionary) -> bool:
	var event_id := String(event.get("eventId", ""))
	var world_id := String(event.get("worldInstanceId", ""))
	var demand_id := int(event.get("demandId", 0))
	var order_key := String(event.get("orderDefinitionKey", ""))
	var cycle_sequence := int(event.get("cycleSequence", 0))
	if event_id.is_empty() or world_id.is_empty() or demand_id <= 0 or order_key.is_empty() or cycle_sequence <= 0:
		return false
	return event_id == world_id + ":" + str(demand_id) + ":" + str(cycle_sequence)
