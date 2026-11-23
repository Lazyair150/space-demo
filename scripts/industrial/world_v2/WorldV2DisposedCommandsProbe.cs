using System;
using Godot;

namespace SpaceDemo.Industrial.WorldV2;

/// <summary>
/// Verifies that a Runtime node becomes permanently unusable after leaving
/// the SceneTree and releasing its owned Bridge session.
/// </summary>
public partial class WorldV2DisposedCommandsProbe : Node
{
    private int _faultSignalCount;

    public override void _Ready()
    {
        try
        {
            GD.Print("[WorldV2DisposedCommandsProbe] started");

            var runtime = new WorldV2RuntimeNode
            {
                AutoAdvance = false
            };
            var connectResult = runtime.Connect(
                new StringName("RuntimeFaulted"),
                Callable.From<string>(OnRuntimeFaulted));
            Ensure(connectResult == Error.Ok, "could not connect RuntimeFaulted signal");

            AddChild(runtime);
            Ensure(runtime.IsInitialized, "Runtime must initialize before disposal");
            Ensure(!runtime.IsFaulted, "healthy Runtime must not be faulted before disposal");
            Ensure(runtime.CanAcceptCommands, "healthy Runtime must accept commands");

            RemoveChild(runtime);

            Ensure(runtime.IsDisposed, "Runtime must be marked disposed after leaving SceneTree");
            Ensure(!runtime.IsInitialized, "disposed Runtime must release its session");
            Ensure(!runtime.IsFaulted, "normal disposal must not be reported as a runtime fault");
            Ensure(!runtime.CanAcceptCommands, "disposed Runtime must close its command gate");

            ExpectDisposed("PauseWorld", runtime.PauseWorld);
            ExpectDisposed("ResumeWorld", runtime.ResumeWorld);
            ExpectDisposed("SetWorldSpeedRatio", () => runtime.SetWorldSpeedRatio(1.0));
            ExpectDisposed("UpdateProducerRates", () => runtime.UpdateProducerRates(
                "陶工", new Godot.Collections.Dictionary
                {
                    ["圆罐"] = 1.0,
                    ["方罐"] = 0.0
                }));
            ExpectDisposed("AddSingleRequirementDemand",
                () => runtime.AddSingleRequirementDemand("圆罐", "酒", "A", "Passive", 0));
            ExpectDisposed("MoveDemand", () => runtime.MoveDemand(1, "Active"));
            ExpectDisposed("StartActiveDemand", () => runtime.StartActiveDemand(1));
            ExpectDisposed("GetWorldSnapshot", () => runtime.GetWorldSnapshot());

            Ensure(!runtime.InitializeWorld(), "disposed Runtime must not be reinitialized");
            Ensure(runtime.IsDisposed && !runtime.IsInitialized,
                "rejected reinitialization must preserve terminal disposal state");
            Ensure(!runtime.IsFaulted, "rejected reinitialization must not create a runtime fault");
            Ensure(_faultSignalCount == 0,
                $"normal disposal and rejected post-disposal calls must not emit RuntimeFaulted; got {_faultSignalCount}");

            runtime.QueueFree();

            GD.Print(
                "[WorldV2DisposedCommandsProbe] all post-disposal operations rejected",
                " operation_count=8 disposed=true reinitialize_rejected=true fault_signal_count=0");
            GD.Print("[WorldV2DisposedCommandsProbe] passed");
        }
        catch (Exception ex)
        {
            GD.PushError("[WorldV2DisposedCommandsProbe] FAILED: " + ex);
            GetTree().Quit(1);
        }
    }

    private void OnRuntimeFaulted(string message)
    {
        _faultSignalCount++;
        GD.Print("[WorldV2DisposedCommandsProbe] unexpected runtime fault signal: ", message);
    }

    private static void ExpectDisposed(string operation, Action action)
    {
        try
        {
            action();
        }
        catch (InvalidOperationException ex)
        {
            Ensure(ex.Message.Contains("尚未初始化", StringComparison.Ordinal),
                $"{operation} was rejected for the wrong reason: {ex.Message}");
            GD.Print("[WorldV2DisposedCommandsProbe] rejected: ", operation);
            return;
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"{operation} threw unexpected exception type {ex.GetType().Name}: {ex.Message}", ex);
        }

        throw new InvalidOperationException($"{operation} remained callable after Runtime disposal");
    }

    private static void Ensure(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }
}
