# 2026-11-27 Parser reward identity and Windows rendering device-loss investigation

## Player-reported failure

At world/logical time 35,883 ms, finite-stage completion stopped with:

    progression reward facts could not be projected:
    Parser checkpoint identity does not match the frozen Owned Parser

After the fault/menu transition, Windows D3D12 emitted:

    Attempted to free invalid ID: 0
    Can't create buffer ... error 0x887a0005
    Condition "!buffer.driver_id" is true
    vertex/index buffer and array creation failures

## Confirmed Parser identity defect

The production Owned Parser profile contains an exact Owned Instance snapshot. Game._initialize_ore_parser creates the runtime identity using:

    SpaceOreParserRuntime.build_runtime_instance_id(shipWorldId, parserProfile, persistedParserState)

For a new owned instance this is:

    <shipWorldId>:owned:<ownedParser.instanceId>

The same helper retains a deliberate compatibility path for an already persisted legacy identity:

    <shipWorldId>:<parserDefinitionId>

SpaceBattleRewardFactProjection instead extracted the bare Owned Instance ID and compared it directly with the runtime checkpoint's parserInstanceId. The check was internally inconsistent and rejected valid production battles at Stage clear.

## Corrective change

The reward projection now:
- requires exactly one frozen Ore Parser Owned Instance;
- requires the composed Parser profile to carry the same frozen Owned Instance snapshot;
- verifies profile Definition ID/version against the frozen device selection;
- calls the exact same SpaceOreParserRuntime.build_runtime_instance_id helper as Game initialization, passing the checkpoint runtime state for explicit legacy restoration;
- compares the checkpoint identity to that canonical world-scoped runtime identity. It does not weaken or remove the identity boundary.

The projection probe now builds a real world-scoped Owned Parser profile and covers:
- matching owned identity accepted;
- different parser identity rejected;
- same Parser instance under a different ship World rejected;
- composed runtime profile detached from the selected Owned Instance rejected;
- the intentionally supported legacy definition-scoped checkpoint can still be restored/projected;
- invalid stage result remains rejected.

The existing SpaceDomainContractProbe already invokes SpaceBattleRewardFactProjectionProbe, and the cross-repository CI script already runs that suite. No duplicate probe scene or new CI invocation is needed.

## Windows rendering device-loss investigation

The project previously pinned Windows to D3D12 while retaining Godot's Mobile rendering method. The reported HRESULT 0x887A0005 is DXGI_ERROR_DEVICE_REMOVED. Subsequent invalid RID and buffer/vertex-array errors may cascade after the rendering device is lost; the supplied log does not establish whether the first device-loss cause is Godot, the NVIDIA driver, Windows TDR, an invalid GPU command, or system instability.

The Windows driver is changed to Vulkan for a controlled backend comparison while keeping renderer/rendering_method=mobile. This is a diagnostic configuration change, not a proven fix. If Vulkan is stable, retain it for this machine/desktop target and document the backend support decision. If Vulkan also loses the device, collect the first renderer error and Windows Reliability Monitor / Event Viewer LiveKernelEvent or nvlddmkm entries before diagnosing resource leaks.

Do not treat every later "Attempted to free invalid ID: 0" as an independently proven double-free; after the device is removed, follow-up RID create/free operations may already be invalid. A RenderingServer/GPU resource lifetime audit remains necessary only if the invalid-ID error reproduces before device loss or also occurs under Vulkan.

## Validation plan

- Run SpaceDomainContractProbe so the modified reward identity probe executes in the regular cross-repo integration workflow.
- Run the full World V2 cross-repository workflow with the exact Core PR head.
- The owner/receipt identities are deterministic synthetic fixtures; no production balance values are invented.
- Local desktop acceptance must confirm the first stage can settle at or beyond 35,883 ms, the progression receipt is persisted, and repeated stage completion does not award twice.
- Windows A/B: launch with the project-pinned Vulkan backend, exercise a long battle and stage completion, exit and re-enter. Record the first graphics error, not only the tail cascade.
- If another device-loss occurs, collect Windows Reliability Monitor (LiveKernelEvent 141/117 if present), Event Viewer System events for the display driver, GPU driver version and temperature/load; do not raise TDR registry delays as a first workaround.

## References

- Microsoft DXGI error codes: https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-error
- Godot 4.7 internal rendering architecture and supported driver/method combinations: https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html
- Godot 4.7 Windows driver setting and 4.6 default change: https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.6.html

