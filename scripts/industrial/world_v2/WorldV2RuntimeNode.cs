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

    public bool IsInitialized => _session?.HasWorld == true;
    public bool IsFaulted => _faulted;

    public override void _Ready() => InitializeWorld();

    public bool InitializeWorld()
    {
        if (_session != null)
            throw new InvalidOperationException("World v2 Runtime 已经初始化");

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
            EmitSignal(SignalName.RuntimeReady);
            EmitSignal(SignalName.SnapshotChanged);
            GD.Print("[WorldV2Runtime] initialized: ", WorldConfigPath);
            return true;
        }
        catch (Exception ex)
        {
            _faulted = true;
            GD.PushError("[WorldV2Runtime] initialization failed: " + ex);
            EmitSignal(SignalName.RuntimeFaulted, ex.Message);
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
            _session.AdvanceWorld(wholeWorldTimeMilli);
            EmitSignal(SignalName.SnapshotChanged);
        }
        catch (Exception ex)
        {
            _faulted = true;
            GD.PushError("[WorldV2Runtime] advance failed: " + ex);
            EmitSignal(SignalName.RuntimeFaulted, ex.Message);
        }
    }

    public void PauseWorld()
    {
        RequireSession().PauseWorld();
        EmitSignal(SignalName.SnapshotChanged);
    }

    public void ResumeWorld()
    {
        RequireSession().ResumeWorld();
        EmitSignal(SignalName.SnapshotChanged);
    }

    public void SetWorldSpeedRatio(double ratio)
    {
        RequireSession().SetWorldSpeedRatio(ratio);
        EmitSignal(SignalName.SnapshotChanged);
    }

    public GDictionary GetWorldSnapshot()
    {
        var snapshot = RequireSession().GetWorldSnapshot();
        return new GDictionary
        {
            ["worldTimeMilli"] = snapshot.WorldTimeMilli,
            ["logicalTimeMilli"] = snapshot.LogicalTimeMilli,
            ["speedRatioMilli"] = snapshot.SpeedRatioMilli,
            ["isPaused"] = snapshot.IsPaused,
            ["runtimeFaulted"] = snapshot.RuntimeFaulted,
            ["faultReason"] = snapshot.FaultReason ?? "",
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
        _session?.Dispose();
        _session = null;
    }

    private WorldV2BridgeSession RequireSession() =>
        _session ?? throw new InvalidOperationException("World v2 Runtime 尚未初始化");

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
