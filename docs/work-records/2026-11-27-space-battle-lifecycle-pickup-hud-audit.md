# 2026-11-27 Space battle lifecycle, pickup, HUD and director audit

## User-observed evidence

The desktop run showed a paused battle overlay remaining above the newly opened Main Menu, with the old battle title/HUD still present. The runtime log also showed this physics error during enemy death:

    Can't change this state while flushing queries.
    Spawner._on_enemy_died
    → EnemyChaser._on_health_died
    → HealthComponent.apply_damage
    → DamageReceiver.receive
    → PlayerBullet._on_body_entered

The blue diamond was not collected after touching it with the ship. Window resizing also caused controls to overlap.

## Root causes confirmed from the PR branch

### 1. Battle root survived the Main Menu transition

SpaceHangarBattleLauncher.launch_new_battle attaches Game to get_tree().root, while current_scene remains SpaceHangar. GameFlow.return_to_menu replaces only current_scene. The old Game was hidden/disabled by shutdown but never freed, so its CanvasLayers remained visible above the new MainMenu.

### 2. Typed energy stone used the wrong owner lookup

SpaceEnergyStonePickup._on_body_entered looked up get_tree().current_scene and called ingest_energy_stone. During embedded combat current_scene is still Hangar, not Game. Pickup sensor configuration itself was consistent: Player uses collision layer 2 and pickup mask 2.

### 3. New pickup Area2Ds were attached during the physics query flush

The death callback instantiated BuffPickup and synchronously added it to Arena. The same event could also create a typed EnergyStone pickup. Both now defer SceneTree insertion; they still decide their drop and stable identity at the death event, and deferred helpers reject an already-ended owner.

### 4. Layout source contradicted the project stretch policy

Project settings already used canvas_items + expand; however, the heart HUD was pinned to x=1020..1260, the resource strip used a fixed 960px width, and the Jar detail/status/skill docks used several fixed widths. Resizing therefore caused regions to collide even though the project stretch settings were reasonable.

### 5. The finite director existed, but default selection bypassed it

SpaceStageEncounterDirector is configured before Game enters the tree and Spawner reads it. However, Hangar always selected Free Combat at picker index 0, making the finite director inactive unless the player manually picked a stage. The design doc already stated first-unlocked stage as the default; code drifted from that documented behavior.

A cinematic director is a different feature. No cutscene timeline/camera/dialogue director was found. The encounter scheduler must not be overloaded with cutscene responsibilities.

## Changes written to the active Space PR branch

- scripts/Game.gd: after GameFlow accepts Main Menu, Game queues its root-level battle composition for deletion.
- SpaceBattlePauseController.gd: both normal Main Menu and fault retry route through parent Game's end_battle_for_menu; direct navigation from the controller is removed.
- SpaceBattlePauseControllerProbe.gd: synthetic probe owner exposes the same terminal-navigation method.
- scripts/Spawner.gd: BuffPickup insertion is deferred until physics query flushing has completed.
- scripts/Game.gd: typed energy-stone Area2D insertion is deferred and canceled if Game has ended.
- SpaceEnergyStonePickup.gd: resolves its battle owner through ancestry, not current_scene; shape color/glyph are presentation-only.
- SpaceEnergyStonePickup.tscn: adds the glyph label.
- scenes/ui/HUD.tscn: hearts are anchored to viewport top-right; score/wave bounds corrected.
- scripts/Hud.gd: bottom-left buff status is constrained to the left viewport region.
- SpaceJarHudObserver.gd: resource strip becomes horizontally scrollable and reserves the passive-order rail; active/passive docks and details pane are sized against current viewport.
- SpaceHangarScreen.gd: first unlocked finite campaign stage is selected by default; exact selection survives campaign-progress refresh; Free Combat remains explicit.

## References studied

- Existing local comparison: docs/design/07-tiny-wizard-对照与改造.md (authored encounter pacing, gate-resource-reward sequencing, immediate feedback and data-driven content).
- Godot official samples: Dodge the Creeps, Pause, Scene Changer, Scene Instancing, Hierarchical Finite State Machine, Multiple Resolutions and Aspect Ratios. Use the branch matching Godot 4.7 and its MIT license.
- Godot engine references: Area2D overlap/monitoring; Object.call_deferred; Control anchors and Containers; multiple resolutions and stretch aspects.

The reusable-engine conclusion is to keep Space's product-specific GameFlow, encounter director, Core/Jar bridge and settlement services, while using SceneTree, Node ownership/queue_free, Area2D, Timer, Resource, AnimationPlayer/Tween, Control anchors and Containers rather than duplicating those engine features.

## Validation status

- Confirmed before this patch: ordinary Headless run and --headless --editor --quit returned to PowerShell after resource unloading; C# build and script class registration had completed.
- Source-level diagnosis and remote code changes are complete for this batch.
- NOT YET VERIFIED locally: Godot 4.7.1 Mono import/build after edits, PauseControllerProbe, finite-stage probe, parser pickup receipt, physical enemy-death stress, or GUI resizing.
- No claim is made that the game is now visually accepted or fully playable. The next local run must pull this branch and execute the acceptance matrix in docs/architecture/18-godot-scene-ownership-physics-and-responsive-ui.md.

## Follow-up work

1. Pull the verified branch locally, open the editor, then perform the desktop GUI acceptance matrix; the CI headless build/probes are already green.
2. Perform desktop exit/re-entry and resize acceptance at the four listed sizes.
3. Extend the lifecycle probe with the production Game owner and a stub Host, so the real Game.end_battle_for_menu path is exercised in addition to the current root-owner contract fixture.
4. Add a visible collection receipt/toast with shape and volume, plus a physics-backed Area2D contact test. The current ingress probe directly invokes the pickup adapter and covers accepted, duplicate, and conflicting receipts; it does not yet simulate actual overlapping physics bodies.
5. Design the first actual cinematic beat separately from finite encounter scheduling; only build a timeline abstraction once there are multiple authored sequences.

- scripts/Game.gd: the player-death → GameOver route now also queues the root-level Game owner for deletion after the screen transition is accepted; the same leak was possible outside the pause-menu path.
- Energy-stone glyph hover tooltip now explains its exact shape type, volume and automatic ship-contact collection behavior.


## Validation and probe correction (2026-11-27)

### Cross-repository CI result

- Final run: **45937110830**, status **success**, workflow World V2 cross-repository integration.
- Space PR branch head tested: d40da2af81a7de7633d1c5b421e8ee70907898cb.
- Exact Core PR #63 dependency: 116c0bb7e3589a2850bf1b85f6da4c48de8c0a28.
- Both Core World V2 Bridge and Space .NET project builds succeeded.
- Godot 4.7.1 .NET project import and script/scene parse succeeded.
- Parser/Core integration and World V2 runtime/lifecycle/fault/disposal/snapshot probes completed.
- SpaceOreParserJarIngressProbe passed: it loads the typed pickup scene, accepts a stable pickup identity, consumes an accepted pickup, consumes an exact duplicate idempotently, and leaves a conflicting same-ID/different-volume pickup unconsumed. It invokes _on_body_entered directly with a fake player, so this is adapter/receipt verification, not a physics-overlap simulation.
- SpaceBattlePauseControllerProbe passed both expected-transition-rejection=passed and passed real-main-menu-transition=true. It exercises the real Main Menu scene transition using a separate root-level battle-owner fixture and asserts the owner is queued for deletion.
- Final workflow marker: CROSS-REPO-WORLD-V2-OK core=116c0bb7e3589a2850bf1b85f6da4c48de8c0a28.

### Intermediate probe failures and corrections

- Run 45936806694 exposed that the new root-owner fixture called add_child() from within the active _ready() child-setup traversal. Godot rejected it with Parent node is busy setting up children. The fixture now defers root attachment and awaits SceneTree.process_frame.
- Run 45937004564 then exposed a duplicate local scene_tree declaration in the same probe. Renamed the initial reference to probe_tree.
- Run 45937110830 passed after both corrections. These were test-fixture errors introduced while strengthening the regression test; they were not the original runtime pause/physics defects.

### Refined remaining validation

- Automated: source builds, project import, parser receipt/identity adapter, pause state/focus/resume/fault rollback, and root-level owner disposal contract are green.
- Still requires local desktop observation: the actual Game.gd path with the production Host, enemy-death drop stress while physics queries are active, real energy-stone/player overlap, and four-size HUD resize visuals.
- The 2026-11-27 top-left HUD score/wave region was additionally anchored to 62% of viewport width with a 20px right inset, preserving a gap before the top-right hearts.
- No claim is made that the GUI is visually accepted or that the project is fully playable solely from CI.
