# 2026-11-27 Battle checkpoint JSON integer boundary

## Repository state

- Space repository: `space-demo`
- Branch: `world-v2/phase-4.10b-hangar-ui`
- Base commit before this record: `3fbba75` (Track generated Godot script UID sidecars)
- Engine: Godot 4.7.1 stable mono (.NET 10)
- Jar Core exact dependency: `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`
- Previous cross-repo result: run `45942323918` SUCCESS (parser schema 2/5 confusion fixed in `SpaceBattleEffectStateStore`)

## Why the previous green CI did not cover the restart path

The checkpoint was always saved and loaded inside a single process, and every probe built its
state with in-memory integer values. Nothing ever handed a JSON-decoded snapshot back to the
production restore path, which is exactly what "quit the game and start it again" does.

`SpaceBattleEffectStateStoreProbe` also compared loaded values with

    actual == JSON.parse_string(JSON.stringify(expected))

so both sides were JSON-normalised before comparison. That helper can only prove that Godot
decodes numbers as floats; it silently hides the int/float difference the production validators
care about.

## Confirmed defect

Godot 4.7.1 JSON behaviour, measured directly:

- `JSON.parse_string('{"i":100,"f":1.0,"n":7}')` returns every number with `typeof(...) == 3`
  (`TYPE_FLOAT`); integers are not preserved.
- `JSON.stringify` writes integers as `100.0`.
- Variant deep comparison distinguishes the two types: `{"x":1} != {"x":1.0}` and
  `[1,2] != [1.0,2.0]`. `StringName == String` is still true, so only numbers are affected.

`SpaceOreParserRuntime.restore_state()` compares the checkpoint's parser profile with the
definition's runtime profile using strict `!=`, and validates fixed-point fields with
`typeof(...) != TYPE_INT`. A profile decoded from disk is therefore always rejected:

    the real Parser Runtime rejected a JSON-decoded checkpoint:
    ore parser definition/profile does not match the checkpoint

with `persistedProfile.definitionVersion == 1.0` against `fixtureProfile.definitionVersion == 1`.

Reachability in production is direct: `Game.gd:465` calls

    var restored := _ore_parser_runtime.restore_state(parser_state)

where `parser_state` comes from the persisted battle snapshot, so every real save/restart would
have ended in the "Battle runtime checkpoint is incomplete or does not match the frozen loadout"
fault path.

## Fix

Single owner for the decode boundary:
`scripts/industrial/world_v2/SpaceJsonNumberCanonicalizer.gd`

    class_name SpaceJsonNumberCanonicalizer
    const MAX_EXACT_INTEGER := 9007199254740991.0
    static func canonicalize(value: Variant) -> Variant

It returns a deep copy in which a float is converted to `int` only when it is finite, within the
exact-integer range and has no fractional part. Fractional or out-of-range values keep their
float type on purpose: the existing schema validators then reject them instead of a silent
truncation. Dictionaries and arrays recurse; the input is never mutated.

Applied at one place — the only point where a checkpoint is decoded —
`SpaceBattleEffectStateStore.gd:81 load()` canonicalises the parsed dictionary before
`_valid_snapshot` and uses the canonical result from then on. Everything downstream keeps its
integer contract unchanged: `Game.gd:151-153` (`runState.score` / `runState.wave`),
`Game.gd:454` / `Game.gd:459` (`nextPickupSequence`, `dropRngState`), the order dispatcher, the
stage encounter director and the objective runtime.

`SpaceOreParserRuntime.restore_state()` canonicalises both the incoming state and
`_definition.build_runtime_profile()` before comparing, so the profile check stays strict without
admitting fractional values.

## Regression correction in an existing probe

`SpaceBattleEffectStateStoreProbe._matches_json_value` previously JSON-normalised the expected
value only, which no longer matches a store that deliberately returns integers. It now canonicalises
the decoded expected value as well, with a comment stating why comparing a raw JSON roundtrip would
only re-prove that Godot decodes numbers as floats.

## New two-process restart probe

`tests/battle_checkpoint_restart.gd` + `tests/battle_checkpoint_restart.tscn`

- `-- --mode=write` builds a schema-v3 snapshot with the real `SpaceOreParserRuntime`
  (definition `restart-probe-parser`, instance `restart-probe-parser-instance`, round-tank shape,
  ore ingested and 1000 ms advanced) and persists it through
  `SpaceBattleEffectStateStore.new(path).save(...)`.
- `-- --mode=restore` runs in a separate process, loads the same file through `store.load()`, and
  hands the decoded nested parser state to the real `restore_state()`.

Restore asserts: recaptured state equals the persisted state; re-ingesting the same pickup returns
`duplicate == true` with `acceptedVolume == 0`; no output batch is emitted twice; both processed
event ledgers still contain `restart-probe-jar-world:1:7`; dispatcher fingerprint matches; run state
(wave 3, segment `精英`, score) matches; and the loaded snapshot exposes `nextPickupSequence` and
`runState.score` as `TYPE_INT`.

Markers: `[BattleCheckpointRestart] write=checkpoint-written` and
`[BattleCheckpointRestart] restore=checkpoint-restored-after-process-restart`.

`scripts/ci/verify-world-v2-cross-repo.sh` now runs both phases as step `[4b/4]`, so the restart
path cannot regress silently again.

## Verification performed locally

All commands were run from `space-demo` with Godot 4.7.1 mono. Headless runs are wrapped in
`timeout` because a parse failure in the main scene script keeps the process alive instead of
exiting.

- `godot --headless --path . --editor --quit` — registers the new `class_name` in
  `.godot/global_script_class_cache.cfg`; without it the canonicalizer is "not declared in the
  current scope".
- `godot --headless --path . --scene res://tests/battle_checkpoint_restart.tscn --quit-after 180 -- --mode=write`
  → exit 0, `write=checkpoint-written`.
- same scene with `-- --mode=restore` → exit 0,
  `restore=checkpoint-restored-after-process-restart`.
- `godot --headless --path . --scene res://tests/space_hangar_contracts.tscn --quit-after 180`
  → exit 0, `[SpaceDomainContractProbe] all-domain-contracts=passed`, including
  `progression-reward-profile`, `progression-reward-coordinator`,
  `progression-reward-settlement`, `battle-jar-supply-forecast` and
  `battle-supply-reconciliation`.
- Full script:
  `GODOT_BIN=... CORE_REPO_DIR=D:/godot/programs/jar-system-dotnet CORE_EXPECTED_SHA=116c0bb7... RUNNER_TEMP=/tmp bash scripts/ci/verify-world-v2-cross-repo.sh`
  → exit 0, steps `[1/4]`–`[4/4]` plus `[4b/4]`, ending in
  `CROSS-REPO-WORLD-V2-OK core=116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`.

The script needs `CORE_REPO_DIR` when run from Windows/MSYS: passing the MSYS-style
`/d/godot/...` root to `dotnet -p:JarSystemWorldV2BridgeProject` makes MSBuild look for a
non-existent project. Linux CI is unaffected.

## Boundary of this verification

Proven: the JSON integer boundary is canonicalised at the single decode point; the real Parser
Runtime accepts a snapshot that has been through disk; the two-process write/restore cycle
preserves parser, effect, dispatcher and run state idempotently; the domain contracts and the whole
cross-repo script still pass.

Not proven: any desktop GUI run. This is a headless SceneTree probe with a synthetic identity and
loadout — it does not exercise the real Hangar, the real frozen Owned Loadout, the actual
save-on-quit timing, or Windows rendering. `world_v2` production catalog and reward/curve data
remain empty, so no real progression value was validated either.

## Desktop acceptance still required

1. Play a finite campaign stage, trigger an order effect, and confirm the checkpoint is written
   without the "incomplete or does not match the frozen loadout" fault.
2. Quit the application, restart, and confirm Jar, Parser, effect and dispatcher state all restore
   with no duplicate order confirmation or duplicate effect application.
3. Walk the full GUI path: main menu → hangar → battle → pause → resume → return to main menu →
   battle again → game over.
4. Run windowed first, then resize; only afterwards test fullscreen and multi-monitor separately.
5. Record the first error, Godot version, NVIDIA driver version and window mode if any device-loss
   message appears.
