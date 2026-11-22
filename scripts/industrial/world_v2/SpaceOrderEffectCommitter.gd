extends RefCounted
class_name SpaceOrderEffectCommitter
## Concrete Buff-backed commit callback for SpaceOrderEffectDispatcher.

var _catalog: SpaceEffectCatalog
var _manager: StatusEffectManager
var _store: SpaceBattleEffectStateStore
var _target_resolver: Callable
var _loadout: SpaceBattleLoadoutSnapshot

func configure(
	catalog: SpaceEffectCatalog,
	manager: StatusEffectManager,
	store: SpaceBattleEffectStateStore,
	loadout: SpaceBattleLoadoutSnapshot,
	target_resolver: Callable
) -> bool:
	if catalog == null or manager == null or store == null or loadout == null or not target_resolver.is_valid():
		return false
	_catalog = catalog
	_manager = manager
	_store = store
	_loadout = loadout
	_target_resolver = target_resolver
	return true

## Signature matches Game.configure_order_effect_commit_callback.
func commit(event: Dictionary, order_binding: Dictionary, next_dispatcher_state: Dictionary) -> bool:
	if _catalog == null or _manager == null or _store == null or _loadout == null:
		return false
	var effect_binding: Variant = order_binding.get("effectBinding", null)
	if not (effect_binding is Dictionary):
		return false
	var definition_id := String(effect_binding.get("effectDefinitionId", ""))
	var version := int(effect_binding.get("effectDefinitionVersion", 0))
	var definition := _catalog.resolve_buff(definition_id, version)
	if definition == null:
		push_error("Selected skill references an unavailable exact effect version: %s@%d" % [definition_id, version])
		return false
	var parameters: Dictionary = effect_binding.get("effectParameters", {})
	var target: Variant = _target_resolver.call(effect_binding, event)
	if target != null and not (target is Node):
		push_error("Skill effect target resolver returned a non-Node target")
		return false
	var duration_override := float(parameters.get("durationOverride", -1.0))
	var applied := _manager.apply_order_event(
		String(event.get("eventId", "")),
		definition,
		target as Node,
		duration_override,
		String(parameters.get("targetKey", ""))
	)
	if applied == null:
		return false
	var identity := {
		"shipWorldId": _loadout.ship_world_id(),
		"loadoutId": _loadout.loadout_id(),
		"loadoutVersion": _loadout.loadout_version(),
		"loadoutFingerprint": _loadout.loadout_fingerprint()
	}
	return _store.save(_manager.capture_runtime_state(), next_dispatcher_state, identity)
