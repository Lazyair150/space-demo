# Space abilities and Jar workshop rule scopes

## One skill model for all Space capabilities

Every player-configurable combat capability belongs to the same Space Skill model. This includes projectile weapons, rapid fire, lasers, missiles, shields, drones, reconnaissance, support actions, and combat modifiers. The visible/mechanical form is an effect category, not a separate progression or resource system.

A skill is the immutable binding of:
- Space identity and category (Offense, Defense, Support, Reconnaissance, Utility);
- a Jar order contract (requirements, order type, Active/Passive lane and cooldown);
- a Space effect definition/version and parameters;
- the selected ship/loadout context.

A skill may execute an instantaneous action, spawn an entity, enable a sustained beam, apply a timed shield, or create a persistent support actor. The Jar order cycle is the resource/admission unit; it is not necessarily one bullet, one laser frame, or one second of a sustained effect. The Space effect executor defines what a successful cycle means.

Jar must never branch on effect category. It sees an opaque order key and its own order contract. Space resolves the successful cycle against the frozen effect binding.

The current Space effect registry is Buff-first. It must be generalized into typed Space effect definitions and executors before non-Buff skill content is authored. Do not encode projectiles, beams, drones or reconnaissance as fake BuffDefinitions.

## Two workshop rule scopes

### Workshop-local rules

These describe one workshop in isolation and remain attached to that workshop regardless of role:
- base marks;
- additional marks;
- staging Ban;
- Jar capacity;
- per-liquid capacity and optional aggregate order-staging capacity;
- other local capabilities explicitly supported by the Jar Core contract.

They belong to a versioned `SpaceWorkshopDefinition`. The aggregate `liquidStagingCapacity` remains distinct from the per-liquid `maxLiquids`; when omitted, Core applies its documented fallback.

### Master/Slave relationship rules

These describe how two selected workshops interact:
- role assignment (which local definition is Master and which is Slave);
- one-way Master → Slave resource flow;
- Slave receives resources from Master while in use, not from an independent ship-liquid source;
- exact Jar and free-liquid transfer derived from the B-order solve/resource plan;
- Master staging Ban blocks prohibited liquid from being forwarded;
- Jar-internal liquid remains Jar-owned and must not be misclassified as Master staging liquid;
- generated loose liquid first enters the currently executing workshop staging area and is rejected/discarded according to Core ingress/capacity rules.

The selected roles belong to a versioned `SpaceWorkshopPairDefinition`. The actual transfer, Ban, ownership and resource accounting rules remain enforced by Jar Core. Space does not reimplement them and does not expose designer toggles that can weaken them.

A role swap changes the pair assignment; it does not mutate either workshop's local marks, Ban or capacities.

## Composition

`SpaceWorkshopCombinationDefinition` is the authored build bundle, not a third rule scope. It composes world-level Jar options, an exact-version roster of individual workshop profiles, one exact-version Master/Slave pair selection, and a separate Space-side forecast cost profile. It compiles those inputs into the Core options dictionary and freezes the exact generated options in the battle loadout.

## Active and Passive

- Active is player-requested. The exact demand ID is forwarded to Host/Core; Core decides admission and feasibility.
- Passive is automatically scheduled by Jar Core. It still consumes resources and obeys the same solve/cooldown rules.
- Space owns effect semantics and any future battlefield-context trigger policy. A battlefield condition may request an ability, but it must not duplicate Jar resource feasibility or cooldown logic.
- Active/Passive is independent of ability category. A shield, beam, missile or drone may be Active or Passive.

## Invariants

- No legacy IndustrialRuntime, legacy JarCoreBridge, standalone turn-based IndustrialMain, or old industrial test harness.
- No Jar rule reimplementation in Space; no Space combat/effect implementation in Jar.
- One battle simulation clock and one Host-owned time boundary.
- Frozen exact-version loadout and idempotent cross-domain event/operation identities.
- Do not claim full integration until typed effect executors, durable effect commit and Godot runtime validation are complete.
