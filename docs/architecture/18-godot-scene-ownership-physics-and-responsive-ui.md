# Godot Scene Ownership, Physics Mutation, and Responsive UI

Status: active architecture contract for Space's Godot 4.7.1 project.

## 1. Engine features to use instead of rebuilding

| Concern | Prefer Godot's built-in | Space boundary |
|---|---|---|
| Application scene navigation | SceneTree.current_scene and change_scene_to_file | GameFlow validates screen/battle phases; it does not magically destroy additional root-level nodes |
| Battle composition root | PackedScene + Node ownership + queue_free | SpaceHangarBattleLauncher configures Game before attach; Game owns actors, HUD, pickups and pause controller |
| Collision/pickup detection | Area2D signals, collision_layer/mask, CollisionShape2D | Pickup scripts validate player group and pass immutable pickup identity to Game/parser |
| Safe scene mutation during physics callbacks | Object.call_deferred / Callable.call_deferred | Spawner/Game defer Area2D attachment when death is raised from body_entered |
| Pause | SceneTree.paused and Node.process_mode | PauseController owns user intent; Game owns terminal shutdown; WorldV2ShipHost has its own gate |
| Timers and delayed actions | Timer, SceneTreeTimer, Tween | Gameplay timers inherit PAUSABLE; pause UI work is explicitly ALWAYS |
| Data-driven content | Resource and PackedScene | StageDefinition, DropProfile, BuffDefinition and catalog resources hold content; runtime owners execute them |
| HUD positioning | Control anchors, Container nodes, ScrollContainer, AspectRatioContainer | Avoid old viewport-specific x/y offsets; reserve regions and resize using viewport anchors |
| Short authored presentation | AnimationPlayer, Tween, Camera2D, AudioStreamPlayer | Compose presentation; do not create an independent timeline engine without a concrete need |

The principle is not “never write a framework.” Keep the project's domain-specific GameFlow, Jar bridge, stage director, resource ledger and progression settlement because they encode product rules. Do not duplicate an engine capability when a native node/property already owns that lifecycle.

## 2. The combat owner must be disposed by its owner

Current intentional launch shape:

    /root
    ├── GameState / GameFlow / WorldV2ShipHost (autoloads)
    ├── current_scene = SpaceHangar
    └── Game (separate root child attached by SpaceHangarBattleLauncher)
        ├── Arena
        ├── Player / enemies / projectiles / pickups
        ├── Hud
        └── PauseController

Changing current_scene from Hangar to MainMenu removes Hangar, not the separately attached /root/Game. Therefore, hiding the Game, setting PROCESS_MODE_DISABLED, or clearing SceneTree.paused is not disposal.

The only supported terminal route is:

1. PauseController receives the player's menu request.
2. PauseController delegates to its parent Game.
3. Game closes the Host and battle lifecycle exactly once.
4. GameFlow accepts the Main Menu transition.
5. Game queues its own root-level composition tree for deletion.

Both normal PAUSED exit and FAULTED retry use the same route. A direct call from PauseController to GameFlow is prohibited because it bypasses the actual battle owner.

Pickups use the same ownership graph. A SpaceEnergyStonePickup climbs its ancestors to find ingest_energy_stone. It must not use get_tree().current_scene: while this embedded combat is active, current_scene is still Hangar.

## 3. Physics callback safety

The reproduced failure was:

    PlayerBullet.body_entered
    → EnemyChaser.receive_damage
    → HealthComponent.died
    → Spawner._on_enemy_died
    → arena.add_child(BuffPickup)
    → PhysicsServer2D: Can't change this state while flushing queries

The pickup is an Area2D. The issue is not the collision mask: the player is on collision layer 2 and pickup scenes use collision mask 2. The issue is inserting a live Area2D into the physics space while the physics query callback is still being flushed.

Policy:

- Physics callbacks may calculate a drop and create a detached PackedScene instance.
- They must not directly mutate the live physics SceneTree by adding the Area2D.
- Defer attachment to an idle phase with call_deferred.
- The deferred helper must verify both the owner and intended arena still exist; otherwise free the detached node.
- Keep the roll, stable ID allocation, shape and volume deterministic at the original event boundary. Defer only node attachment.

Do not “fix” the error by turning monitoring off permanently or silently losing pickups.

## 4. Energy-stone identity and collection path

The blue diamond was a typed Space energy-stone pickup, not a generic buff. The drop profile supplies a shape type and volume; Game allocates the stable pickup ID; SpaceOreParserRuntime decides whether ingestion succeeds; only a successful receipt consumes the pickup.

The visual now uses the existing presentation-only ShapeVisuals vocabulary for tint and an in-world glyph. This is presentation metadata only; it does not introduce Jar rules or change the parser's shape vocabulary. The collision scene keeps layer 0/mask 2 and its 14px circle sensor.

Required manual acceptance:

- Touch a stone with the player's ship; the pickup disappears only on a successful receipt.
- Inspect parser status / world snapshot and verify the accepted stone is visible in the appropriate pipeline/account.
- Leave a stone uncollected, save/resume, and confirm stable pickup ID, type, volume and position survive.
- Verify a rejected ingestion leaves the pickup present and can be retried.
- Verify a scene shutdown before deferred attachment frees the pending node and does not add it to a dead battle.

## 5. Responsive combat UI

canvas_items + expand is retained as the project's base stretch policy. It does not compensate for Controls pinned to x=1020 or for several HUD regions all claiming the same screen space.

Layout regions:

- Top-left: score and wave.
- Top-right: hearts and passive orders.
- Under the top bar: Jar resource strip. It reserves the passive rail; when content exceeds width it scrolls horizontally instead of covering another HUD region.
- Bottom-left: temporary buff/status text, constrained to the left viewport region.
- Bottom-right: active order slots, width derived from the available viewport.
- Details: scrollable panel, width/height bounded by viewport.

Godot anchors answer “where should this control stay when the parent changes size?” Containers answer “how should these child controls share the available space?” Use both: anchors for HUD docks, HBox/VBox/Flow/Scroll containers inside each dock. AspectRatioContainer is only needed for content that must preserve a fixed aspect ratio; do not wrap every Control in one.

The current patch handles key battle HUD regions. Hangar and menu screens still require a complete viewport pass: identify fixed offsets/minimum widths, convert long selection pages to ScrollContainer/VBoxContainer, and verify that button hit rectangles remain inside their visible parents.

## 6. Encounter director versus cinematic director

These are separate concepts:

- SpaceStageEncounterDirector: data-driven finite encounter sequence, beat progression and checkpoint state. It supplies Spawner with authored beat plans.
- Endless Spawner loop: a separate mode without a finite stage.
- Cinematic/scene director: not implemented. There is no current authored cutscene timeline that coordinates camera rails, dialogue, shot transitions, audio and skip/fast-forward.

The first-unlocked campaign stage is now the Hangar default. Free Combat remains explicitly selectable. This restores the behavior already described in docs/design/15-stage-structure-and-art-direction.md; otherwise a default Free Combat selection makes the finite director look inactive.

When the first cinematic is designed, prototype one short non-interactive briefing using AnimationPlayer/Camera2D/Tween/AudioStreamPlayer. Define skip, pause, input lock, completion and scene-exit semantics. Only build a reusable timeline abstraction after two or more authored sequences prove that the native nodes are insufficient.

## 7. Open-source study plan and reuse decisions

Start from official samples matching the exact 4.7 engine line rather than copying a random tutorial's engine-version assumptions.

| Reference | Study for | Reuse decision |
|---|---|---|
| Godot Dodge the Creeps | Area2D player/enemy detection, timers, basic spawner and scene composition | Use as a small collision/spawn reference; Space already has richer domain ownership |
| Godot Pause demo | SceneTree pause and process-mode exceptions | Compare its lifecycle; retain Space's Host + SceneTree dual gate because Jar needs its own pause authority |
| Godot Scene Changer / Scene Instancing | current_scene and PackedScene ownership | Use to audit the distinction between replacing current_scene and separately attached root children |
| Godot Multiple Resolutions and Aspect Ratios | resize testing, stretch modes, GUI margins and aspect-ratio-aware HUD | Adopt anchor/container/scroll behavior, not its entire showcase configuration |
| Godot Hierarchical Finite State Machine | state decomposition and state transitions | Compare with GameFlow's application screen and battle-phase dimensions; do not add another parallel battle state machine |
| Existing docs/design/07-tiny-wizard-对照与改造.md | authored encounter pacing, gate-resource-reward sequencing and immediate reward feedback | Keep the ideas that translate to a single-arena shooter; do not import room-grid architecture |

Source and license notes:
- Official demo repository: https://github.com/godotengine/godot-demo-projects (MIT; use the branch matching the project's Godot version).
- Multiple-resolution demo notes: https://github.com/godotengine/godot-demo-projects/tree/4.7/gui/multiple_resolutions
- Official demos index: https://godotengine.github.io/godot-demo-projects/
- Godot UI anchors: https://docs.godotengine.org/en/stable/tutorials/ui/size_and_anchors.html
- Godot multiple resolutions: https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html
- Area2D and physics signal model: https://docs.godotengine.org/en/stable/classes/class_area2d.html
- Object.call_deferred: https://docs.godotengine.org/en/stable/classes/class_object.html

Do not add a third-party framework solely for architecture fashion. First finish the ownership, scene transitions, responsive HUD, encounter flow, save/restore and player-facing feedback using the engine's primitives and the existing Space/Core modules.

## 8. Validation matrix

| Check | Automated / source probe | Desktop acceptance |
|---|---|---|
| Pause → Resume | PauseControllerProbe | Overlay disappears; gameplay and Jar time both resume |
| Pause → Main Menu | PauseControllerProbe + Game terminal path | No battle HUD, overlay, actors or root-level Game remain |
| Fault → Main Menu retry | PauseControllerProbe | Fault panel disappears and menu input is usable |
| Enemy death drops | Spawn/drop profile probes | No PhysicsServer flush error during sustained kills |
| Energy stone pickup | Parser receipt probe | Ship contact is accepted; receipt/account changes visibly |
| Resize layout | UI scene geometry probe at multiple viewport sizes | 1280×720, 1024×768, 1600×900, 800×600 without overlap |
| Finite Stage | Director/objective/settlement probes | First mission runs authored beats and reaches a clear result |
| Free Combat | Existing endless Spawner probe | Explicit Free Combat choice returns to endless loop |
| Restart flow | Scene/lifecycle probes | Main Menu → Hangar → Battle → Menu → Hangar → Battle works repeatedly |

A successful Headless import/build is not a substitute for desktop GUI acceptance. Record which matrix cells are automated, manually observed, or still pending.


The player-death route also replaces current_scene with GameOver while Game remains a root child. The death transition now queues the same Game owner for deletion after GameFlow accepts the GameOver scene. This makes root-level battle disposal apply to both player-requested Menu return and terminal GameOver navigation.
