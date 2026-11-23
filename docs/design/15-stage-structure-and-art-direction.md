# Stage Structure and Art Direction

## Why the endless arena is not the campaign

The current Spawner is an endless four-beat loop (warmup, pressure, elite, rest). Keep it as an arcade/endless mode, but do not let it stand in for campaign progression. A campaign is a finite, authored sequence of missions with a clear objective, encounter beats, completion boundary, unlock chain, and reward settlement.

## Stage hierarchy

- Campaign: a thematic arc / sector containing ordered stages.
- Stage: a finite mission with a stable ID and definition version.
- Encounter beat: one authored combat segment inside a stage. Beats define composition, pacing, rest windows and optional duration/elite/boss markers.
- Objective: eliminate all, survive duration, protect target, collect resource, or boss encounter.
- Reward settlement: emits a result payload to progression; it does not directly mutate Jar World or owned instances.
- Endless: a separate replayable mode that continues the existing four-beat loop.

## Growth adaptation

Every stage authors its recommended loadout level and an optional bounded difficulty profile. The profile compares the average level of the exact owned instances frozen into the battle loadout against the recommendation. It returns an encounter-scale proposal only; the encounter director applies it to authored enemy counts/health/speed. It never changes the player's curve, owned instances, Jar definitions, workshop bans, order costs, or skill balance.

A stage can be deliberately fixed-difficulty by setting both scale bounds and per-level coefficients to neutral values. This avoids silently rubber-banding every encounter. The recommended level is also useful for Hangar warnings and stage unlock requirements.

## Campaign progression

Stage completion must be a separate durable aggregate from transient combat state. A successful clear records exact stage ID/version, best result, and reward settlement identity. A failed run does not unlock the next stage. Reward settlement must be idempotent and commit once; it may grant XP/resources/unlocks but must call the existing progression services rather than editing owned-instance fields directly.

## Presentation and HUD

The HUD should display campaign / stage / objective / encounter beat, objective progress, and stage completion state. The endless mode retains wave and segment labels. Stage transitions should not be represented as infinite wave increments.

## Art direction

Use a coherent vector sprite language: deep-space navy silhouettes, restrained cyan/amber energy accents, clear negative space, thick readable outlines, and simplified geometry that survives 32–128 px display. Keep gameplay sprites separate from Hangar category icons. SVG assets are source artwork and should remain editable; runtime animation, hitboxes and collision geometry remain Godot scene responsibilities.

## First authored campaign slice

Build the first campaign as a short onboarding arc:
1. **Drift Perimeter** — movement / basic chaser engagement.
2. **Signal Interference** — mixed chasers and shooters, introduces ranged pressure.
3. **Ore Convoy** — resource pickup and parser throughput under combat pressure.
4. **Broken Relay** — elite encounter and controlled rest window.
5. **Warden of the Rift** — boss capstone, unlocks the next sector.

The current commit introduces stage data contracts and progression comparison. It does not yet replace the live Spawner loop or claim campaign gameplay is playable; that integration is the next implementation increment.
