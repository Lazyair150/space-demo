using System;
using System.Linq;
using System.Text.Json;
using Godot;
using JarSystem.Core.World;
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

    private WorldV2BridgeSession? _session;
    private double _worldTimeRemainderMilli;
    private bool _faulted;
    private string? _faultReason;
    private bool _disposed;

    public bool IsInitialized => _session?.HasWorld == true;
    public bool IsFaulted => _faulted;
    public bool IsDisposed => _disposed;
    public bool CanAcceptCommands => _session != null && !_faulted && !_disposed;

    public override void _Ready() => InitializeWorld();

    public bool InitializeWorld()
    {
        // A node's session is single-owner and single-initialization.
        // Reject duplicate requests without replacing or faulting the live world.
        if (_disposed)
            return false;

        if (_session != null)
        {
            GD.PushWarning("[WorldV2Runtime] initialization ignored: session already exists");
            return false;
        }

        // A new initialization attempt may recover from a previous configuration fault.
        _faulted = false;
        _faultReason = null;

        try
        {
            var json = Godot.FileAccess.GetFileAsString(WorldConfigPath);
            if (string.IsNullOrWhiteSpace(json))
                throw new InvalidOperationException("无法读取 World v2 配置: " + WorldConfigPath);

            var options = JsonSerializer.Deserialize<WorldV2Options>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
            if (options == null)
                throw new InvalidOperationException("World v2 配置反序列化结果为空");

            var validation = options.Validate();
            if (!validation.IsValid)
                throw new InvalidOperationException(
                    "World v2 配置校验失败: " + string.Join("；", validation.Errors));

            var session = new WorldV2BridgeSession();
            try
            {
                session.CreateOrReplaceWorld(options);
                _session = session;
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
            GD.Print("[WorldV2Runtime] initialized: ", WorldConfigPath);
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
        try
        {
            var advance = _session.AdvanceWorld(wholeWorldTimeMilli);
            if (advance.RuntimeFaulted)
            {
                LatchFault(advance.FaultReason ?? "World v2 Core entered a runtime fault state", "core");
                EmitSignal(SignalName.SnapshotChanged);
                return;
            }
            EmitSignal(SignalName.SnapshotChanged);
        }
        catch (Exception ex)
        {
            TrySynchronizeCoreFault();
            if (!_faulted)
                LatchFault(ex.Message, "host advance");
            EmitSignal(SignalName.SnapshotChanged);
        }
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
            ["resourceLiquids"] = ToGodotDictionary(snapshot.ResourceLiquids),
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
                ["isCoolingDown"] = demand.IsCoolingDown
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
