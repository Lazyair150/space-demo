using System;
using System.Linq;
using System.Text.Json;
using Godot;
using JarSystem.Core.World;
using JarSystem.Core.World.Demands;
using JarSystem.WorldV2Bridge;
using GDictionary = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

namespace SpaceDemo.Industrial.WorldV2;

[GlobalClass]
public partial class WorldV2RuntimeNode : Node
{
    [Signal] public delegate void RuntimeReadyEventHandler();
    [Signal] public delegate void SnapshotChangedEventHandler();
    [Signal] public delegate void RuntimeFaultedEventHandler(string message);

    [Export] public string WorldConfigPath { get; set; } =
        "res://data/industrial/world_v2_sandbox.json";
    [Export] public bool AutoAdvance { get; set; } = true;
    [Export] public bool InitializeOnReady { get; set; } = true;

    private WorldV2BridgeSession? _session;
    private WorldV2Options? _worldOptions;
    private double _worldTimeRemainderMilli;
    private bool _faulted;
    private string? _faultReason;
    private bool _disposed;

    public bool IsInitialized => _session?.HasWorld == true;
    public bool IsFaulted => _faulted;
    public string FaultReason => _faultReason ?? "";
    public bool IsDisposed => _disposed;
    public bool CanAcceptCommands => _session != null && !_faulted && !_disposed;

    public override void _Ready()
    {
        if (InitializeOnReady)
            InitializeWorld();
    }

    /// <summary>Initialize from the configured file. Used only by isolated probes/default sandbox host.</summary>
    public bool InitializeWorld() =>
        InitializeWorldFromJson(
            Godot.FileAccess.GetFileAsString(WorldConfigPath),
            WorldConfigPath);

    /// <summary>
    /// Initialize from a caller-frozen world configuration. Production Hangar flow must use
    /// this path so the ship host never silently substitutes the sandbox configuration.
    /// </summary>
    public bool InitializeWorldFromJson(string json, string sourceLabel = "battle loadout")
    {
        if (_disposed)
            return false;

        if (_session != null)
        {
            GD.PushWarning("[WorldV2Runtime] initialization ignored: session already exists");
            return false;
        }

        _faulted = false;
        _faultReason = null;

        try
        {
            if (string.IsNullOrWhiteSpace(json))
                throw new InvalidOperationException("World V2 configuration is empty: " + sourceLabel);

            var options = JsonSerializer.Deserialize<WorldV2Options>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
            if (options == null)
                throw new InvalidOperationException("World v2 configuration deserialized to null");

            var validation = options.Validate();
            if (!validation.IsValid)
                throw new InvalidOperationException(
                    "World v2 configuration validation failed: " + string.Join("; ", validation.Errors));

            var session = new WorldV2BridgeSession();
            try
            {
                session.CreateOrReplaceWorld(options);
                _session = session;
                _worldOptions = options;
            }
            catch
            {
                session.Dispose();
                throw;
            }

            _worldTimeRemainderMilli = 0;
            _faulted = false;
            _faultReason = null;
            EmitSignal(SignalName.RuntimeReady);
            EmitSignal(SignalName.SnapshotChanged);
            GD.Print("[WorldV2Runtime] initialized: ", sourceLabel);
            return true;
        }
        catch (Exception ex)
        {
            LatchFault(ex.Message, "initialization");
            return false;
        }
    }

    public override void _Process(double delta)
    {
        if (!AutoAdvance || _session == null || _faulted)
            return;

        _worldTimeRemainderMilli += delta * 1000.0;
        var wholeWorldTimeMilli = (long)Math.Floor(_worldTimeRemainderMilli);
        if (wholeWorldTimeMilli <= 0)
            return;

        _worldTimeRemainderMilli -= wholeWorldTimeMilli;
        AdvanceWorldTime(wholeWorldTimeMilli);
    }

    /// <summary>
    /// Advances Jar by the owning Space world's already-authorized simulation-time delta.
    /// Production integration should disable AutoAdvance and call this exactly once
    /// for each Space world advance; UI visibility and wall-clock time are not authorities.
    /// </summary>
    public bool AdvanceWorldTime(long deltaWorldTimeMilli)
    {
        if (deltaWorldTimeMilli < 0)
            throw new ArgumentOutOfRangeException(nameof(deltaWorldTimeMilli));

        if (deltaWorldTimeMilli == 0 || _session == null || _faulted || _disposed)
            return false;

        try
        {
            var advance = _session.AdvanceWorld(deltaWorldTimeMilli);
            if (advance.RuntimeFaulted)
            {
                LatchFault(advance.FaultReason ?? "World v2 Core entered a runtime fault state", "core");
                EmitSignal(SignalName.SnapshotChanged);
                return false;
            }

            EmitSignal(SignalName.SnapshotChanged);
            return true;
        }
        catch (Exception ex)
        {
            TrySynchronizeCoreFault();
            if (!_faulted)
                LatchFault(ex.Message, "host advance");
            EmitSignal(SignalName.SnapshotChanged);
            return false;
        }
    }

    /// <summary>
    /// Materialize one selected order as a Jar demand. The caller supplies only Jar-owned
    /// specification data plus the opaque order key; Space effect definitions stay in Space.
    /// </summary>
    public int AddJarDemand(
        string type,
        string area,
        long cooldownDurationLogicalMilli,
        string orderDefinitionKey,
        GArray requirements)
    {
        if (string.IsNullOrWhiteSpace(type))
            throw new ArgumentException("Order type cannot be empty", nameof(type));
        if (string.IsNullOrWhiteSpace(orderDefinitionKey))
            throw new ArgumentException("orderDefinitionKey cannot be empty", nameof(orderDefinitionKey));
        if (cooldownDurationLogicalMilli < 0)
            throw new ArgumentOutOfRangeException(nameof(cooldownDurationLogicalMilli));
        if (requirements == null || requirements.Count == 0)
            throw new ArgumentException("Order requirements cannot be empty", nameof(requirements));

        if (!Enum.TryParse<DemandAreaKind>(area, ignoreCase: false, out var demandArea) ||
            !Enum.IsDefined(demandArea))
            throw new ArgumentException("Order area must be Active or Passive", nameof(area));

        var inputs = new System.Collections.Generic.List<WorldV2RequirementInput>(requirements.Count);
        foreach (var raw in requirements)
        {
            var requirement = raw.AsGodotDictionary();
            var shape = requirement.ContainsKey("shape")
                ? requirement["shape"].AsString()
                : "";
            if (string.IsNullOrWhiteSpace(shape))
                throw new ArgumentException("Every order requirement must identify a shape", nameof(requirements));
            var liquid = requirement.ContainsKey("liquid")
                ? requirement["liquid"].AsString()
                : "";
            inputs.Add(new WorldV2RequirementInput(shape, string.IsNullOrWhiteSpace(liquid) ? null : liquid));
        }

        var request = new WorldV2AddJarDemandRequest(
            inputs, type, demandArea, cooldownDurationLogicalMilli, orderDefinitionKey);
        var demandId = RequireOperationalSession().AddJarDemand(request);
        EmitSignal(SignalName.SnapshotChanged);
        return demandId;
    }

    /// <summary>
    /// Materialize a demand from the current world's Core-owned immutable order template.
    /// Space supplies only the template key and scheduling metadata, never Jar requirements.
    /// </summary>
    public int AddJarDemandFromTemplate(
        string templateName,
        string area,
        long cooldownDurationLogicalMilli,
        string orderDefinitionKey)
    {
        if (string.IsNullOrWhiteSpace(templateName))
            throw new ArgumentException("Order template name cannot be empty", nameof(templateName));
        if (string.IsNullOrWhiteSpace(orderDefinitionKey))
            throw new ArgumentException("orderDefinitionKey cannot be empty", nameof(orderDefinitionKey));
        if (cooldownDurationLogicalMilli < 0)
            throw new ArgumentOutOfRangeException(nameof(cooldownDurationLogicalMilli));
        if (!Enum.TryParse<DemandAreaKind>(area, ignoreCase: false, out var demandArea) ||
            !Enum.IsDefined(demandArea))
            throw new ArgumentException("Order area must be Active or Passive", nameof(area));

        var demandId = RequireOperationalSession().AddJarDemandFromTemplate(
            templateName, demandArea, cooldownDurationLogicalMilli, orderDefinitionKey);
        EmitSignal(SignalName.SnapshotChanged);
        return demandId;
    }

    /// <summary>
    /// Imports completed empty Jars produced by a Space-owned parser. The batch ID is
    /// idempotent in Jar Core and survives its execution checkpoint.
    /// </summary>
    public GDictionary ImportProducedJars(string operationId, GDictionary jarCounts)
    {
        if (string.IsNullOrWhiteSpace(operationId))
            throw new ArgumentException("Production batch ID cannot be empty", nameof(operationId));
        if (jarCounts == null)
            throw new ArgumentNullException(nameof(jarCounts));

        var copiedCounts = new System.Collections.Generic.Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var key in jarCounts.Keys)
        {
            var shape = key.AsString();
            if (string.IsNullOrWhiteSpace(shape) || copiedCounts.ContainsKey(shape))
                throw new ArgumentException("Produced Jar shape keys must be unique non-empty names", nameof(jarCounts));
            copiedCounts.Add(shape, checked((int)jarCounts[key].AsInt64()));
        }

        var result = RequireOperationalSession().ImportProducedJars(operationId, copiedCounts);
        EmitSignal(SignalName.SnapshotChanged);
        return new GDictionary
        {
            ["wasDuplicate"] = result.WasDuplicate,
            ["submittedJarCount"] = result.SubmittedJarCount,
            ["storedJarCount"] = result.StoredJarCount,
            ["discardedJarCount"] = result.DiscardedJarCount
        };
    }

    public void PauseWorld()
    {
        RequireOperationalSession().PauseWorld();
        EmitSignal(SignalName.SnapshotChanged);
    }

    public void ResumeWorld()
    {
        RequireOperationalSession().ResumeWorld();
        EmitSignal(SignalName.SnapshotChanged);
    }

    public void SetWorldSpeedRatio(double ratio)
    {
        RequireOperationalSession().SetWorldSpeedRatio(ratio);
        EmitSignal(SignalName.SnapshotChanged);
    }
    /// <summary>
    /// Space-side production adapter: atomically replace the complete configured rate table
    /// for one Jar producer. Jar retains ownership of production progress and inventory.
    /// </summary>
    public void UpdateProducerRates(string producerName, GDictionary rates)
    {
        if (string.IsNullOrWhiteSpace(producerName))
            throw new ArgumentException("Producer name cannot be empty", nameof(producerName));
        if (rates == null)
            throw new ArgumentNullException(nameof(rates));

        var copiedRates = new System.Collections.Generic.Dictionary<string, double>(StringComparer.Ordinal);
        foreach (var key in rates.Keys)
        {
            var shape = key.AsString();
            if (string.IsNullOrWhiteSpace(shape) || copiedRates.ContainsKey(shape))
                throw new ArgumentException("Producer rate keys must be unique non-empty shape names", nameof(rates));
            copiedRates.Add(shape, rates[key].AsDouble());
        }

        RequireOperationalSession().UpdateProducerRates(producerName, copiedRates);
        EmitSignal(SignalName.SnapshotChanged);
    }

    /// <summary>
    /// Capture the complete Jar execution/resource checkpoint at a Space step boundary.
    /// This excludes Space parser state and the Host's fractional-millisecond remainder.
    /// </summary>
    internal string CaptureExecutionCheckpointJson() =>
        RequireOperationalSession().CaptureExecutionCheckpointJson();

    /// <summary>
    /// Restore a Jar checkpoint into the already initialized, not-yet-mutated world.
    /// The Bridge validates the checkpoint against the exact options used at initialization.
    /// </summary>
    internal bool RestoreExecutionCheckpointJson(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
            throw new ArgumentException("Execution checkpoint JSON cannot be empty", nameof(json));
        if (_worldOptions == null)
            throw new InvalidOperationException("World V2 configuration is unavailable for checkpoint restore");

        try
        {
            RequireOperationalSession().RestoreExecutionCheckpointJson(_worldOptions, json);
            EmitSignal(SignalName.SnapshotChanged);
            return true;
        }
        catch (Exception ex)
        {
            LatchFault(ex.Message, "checkpoint restore");
            EmitSignal(SignalName.SnapshotChanged);
            return false;
        }
    }

    public GDictionary GetWorldSnapshot()
    {
        var snapshot = RequireSession().GetWorldSnapshot();
        if (snapshot.RuntimeFaulted)
            LatchFault(snapshot.FaultReason ?? "World v2 Core entered a runtime fault state", "core snapshot");
        var effectiveFaulted = _faulted || snapshot.RuntimeFaulted;
        var effectiveFaultReason = _faultReason ?? snapshot.FaultReason ?? "";
        return new GDictionary
        {
            ["worldTimeMilli"] = snapshot.WorldTimeMilli,
            ["logicalTimeMilli"] = snapshot.LogicalTimeMilli,
            ["speedRatioMilli"] = snapshot.SpeedRatioMilli,
            ["isPaused"] = snapshot.IsPaused,
            ["runtimeFaulted"] = effectiveFaulted,
            ["faultReason"] = effectiveFaultReason,
            ["resourceJars"] = ToGodotArray(snapshot.ResourceJars, jar => (Variant)new GDictionary
            {
                ["id"] = jar.Id.HasValue ? Variant.From(jar.Id.Value) : default,
                ["shape"] = jar.Shape,
                ["liquid"] = jar.Liquid ?? "",
                ["isMarked"] = jar.IsMarked
            }),
            // The central warehouse and ship liquid inventory are separate accounts.
            // Expose both explicitly; callers must not infer ship stock from the warehouse.
            ["resourceLiquids"] = ToGodotDictionary(snapshot.ResourceLiquids),
            ["shipLiquidInventory"] = ToShipLiquidInventoryDictionary(snapshot.ShipLiquidInventory),
            ["master"] = ToWorkshopDictionary(snapshot.Master),
            ["slave"] = ToWorkshopDictionary(snapshot.Slave),
            ["demands"] = ToGodotArray(snapshot.Demands, demand => (Variant)new GDictionary
            {
                ["id"] = demand.Id,
                ["area"] = demand.Area.ToString(),
                ["type"] = demand.SpecificationType,
                ["requirements"] = ToGodotArray(demand.Requirements, item => (Variant)new GDictionary
                {
                    ["shape"] = item.Shape,
                    ["liquid"] = item.Liquid ?? ""
                }),
                ["cooldownDurationLogicalMilli"] = demand.CooldownDurationLogicalMilli,
                ["cooldownRemainingLogicalMilli"] = demand.CooldownRemainingLogicalMilli,
                ["isCoolingDown"] = demand.IsCoolingDown,
                ["orderDefinitionKey"] = demand.OrderDefinitionKey ?? "",
                ["cycleSequence"] = demand.CycleSequence
            }),
            ["activeSessions"] = ToGodotArray(snapshot.ActiveSessions, session => (Variant)new GDictionary
            {
                ["demandId"] = session.DemandId,
                ["stage"] = session.Stage,
                ["unitDurationLogicalMilli"] = session.UnitDurationLogicalMilli,
                ["unitElapsedLogicalMilli"] = session.UnitElapsedLogicalMilli,
                ["completedMasterSteps"] = session.CompletedMasterSteps,
                ["completedSlaveSteps"] = session.CompletedSlaveSteps,
                ["isTerminal"] = session.IsTerminal,
                ["succeeded"] = session.Succeeded,
                ["reason"] = session.Reason ?? ""
            }),
            ["reservationCount"] = snapshot.ReservationCount,
            ["replacement"] = ToReplacementDictionary(snapshot.Replacement)
        };
    }

    /// <summary>
    /// Returns detached pending Jar order-cycle facts for the Space effect dispatcher.
    /// Reading does not consume events; callers must acknowledge only after their
    /// effect state and processed-event identity have been persisted.
    /// </summary>
    public GArray GetPendingOrderCycleEvents()
    {
        var events = RequireSession().GetPendingOrderCycleEvents();
        return ToGodotArray(events, item => (Variant)new GDictionary
        {
            ["eventId"] = item.EventId,
            ["worldInstanceId"] = item.WorldInstanceId,
            ["demandId"] = item.DemandId,
            ["orderDefinitionKey"] = item.OrderDefinitionKey,
            ["cycleSequence"] = item.CycleSequence
        });
    }

    /// <summary>Confirm a pending event after Space has durably applied it.</summary>
    public bool AcknowledgeOrderCycleEvent(string eventId)
    {
        if (string.IsNullOrWhiteSpace(eventId))
            throw new ArgumentException("EventId 不能为空", nameof(eventId));
        return RequireOperationalSession().AcknowledgeOrderCycleEvent(eventId);
    }

    public override void _ExitTree()
    {
        // Leaving the SceneTree is terminal for this Runtime node, even if
        // releasing the owned session reports an error.
        _disposed = true;
        var session = _session;
        _session = null;

        try
        {
            session?.Dispose();
        }
        catch (Exception ex)
        {
            LatchFault(ex.Message, "session disposal");
        }
        finally
        {
            _worldTimeRemainderMilli = 0;
            _worldOptions = null;
        }
    }

    private WorldV2BridgeSession RequireSession() =>
        _session ?? throw new InvalidOperationException("World v2 Runtime 尚未初始化");

    /// <summary>Reject mutations after either host or Core runtime fault.</summary>
    private WorldV2BridgeSession RequireOperationalSession()
    {
        var session = RequireSession();
        TrySynchronizeCoreFault();
        if (_faulted)
            throw new InvalidOperationException("World v2 Runtime 已故障，禁止继续修改世界: " + (_faultReason ?? "未知原因"));
        return session;
    }

    private void TrySynchronizeCoreFault()
    {
        if (_session == null || _faulted)
            return;

        try
        {
            var snapshot = _session.GetWorldSnapshot();
            if (snapshot.RuntimeFaulted)
                LatchFault(snapshot.FaultReason ?? "World v2 Core entered a runtime fault state", "core snapshot");
        }
        catch (Exception ex)
        {
            LatchFault(ex.Message, "core fault inspection");
        }
    }

    private void LatchFault(string reason, string source)
    {
        if (_faulted)
            return;

        _faulted = true;
        _faultReason = reason;
        GD.PushError("[WorldV2Runtime] " + source + " fault: " + reason);
        EmitSignal(SignalName.RuntimeFaulted, reason);
    }

    private static GArray ToGodotArray<T>(System.Collections.Generic.IEnumerable<T> source, Func<T, Variant> convert)
    {
        var result = new GArray();
        foreach (var item in source)
            result.Add(convert(item));
        return result;
    }

    private static GDictionary ToGodotDictionary(System.Collections.Generic.IReadOnlyDictionary<string, int> source)
    {
        var result = new GDictionary();
        foreach (var pair in source)
            result[pair.Key] = pair.Value;
        return result;
    }

    private static GDictionary ToShipLiquidInventoryDictionary(WorldV2ShipLiquidInventoryDto? source)
    {
        if (source == null)
            return new GDictionary();

        return new GDictionary
        {
            ["capacity"] = source.Capacity,
            ["usedCapacity"] = source.UsedCapacity,
            ["availableCapacity"] = source.AvailableCapacity,
            ["balances"] = ToGodotDictionary(source.Balances)
        };
    }

    private static GDictionary ToWorkshopDictionary(WorldV2WorkshopDto? workshop)
    {
        if (workshop == null)
            return new GDictionary();

        return new GDictionary
        {
            ["name"] = workshop.Name,
            ["maxJars"] = workshop.MaxJars,
            ["maxLiquids"] = workshop.MaxLiquids,
            ["baseMarks"] = ToGodotArray(workshop.BaseMarks, x => (Variant)x),
            ["additionalMarks"] = ToGodotArray(workshop.AdditionalMarks, x => (Variant)x),
            ["ban"] = ToGodotArray(workshop.Ban, x => (Variant)x),
            ["jars"] = ToGodotArray(workshop.Jars, jar => (Variant)new GDictionary
            {
                ["id"] = jar.Id.HasValue ? Variant.From(jar.Id.Value) : default,
                ["shape"] = jar.Shape,
                ["liquid"] = jar.Liquid ?? "",
                ["isMarked"] = jar.IsMarked
            }),
            ["liquids"] = ToGodotDictionary(workshop.Liquids)
        };
    }

    private static GDictionary ToReplacementDictionary(WorldV2WorkshopReplacementDto? replacement)
    {
        if (replacement == null)
            return new GDictionary();

        return new GDictionary
        {
            ["role"] = replacement.Role.ToString(),
            ["oldWorkshopName"] = replacement.OldWorkshopName,
            ["targetWorkshopName"] = replacement.TargetWorkshopName,
            ["phaseDurationLogicalMilli"] = replacement.PhaseDurationLogicalMilli,
            ["phaseElapsedLogicalMilli"] = replacement.PhaseElapsedLogicalMilli,
            ["isFinished"] = replacement.IsFinished,
            ["succeeded"] = replacement.Succeeded,
            ["interruptionCommitted"] = replacement.InterruptionCommitted,
            ["interruptionOutcomeUncertain"] = replacement.InterruptionOutcomeUncertain,
            ["completedPhases"] = replacement.CompletedPhases,
            ["failureReason"] = replacement.FailureReason ?? "",
            ["commitWarning"] = replacement.CommitWarning ?? ""
        };
    }
}
