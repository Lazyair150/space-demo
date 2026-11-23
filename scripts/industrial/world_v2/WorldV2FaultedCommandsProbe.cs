using System;
using System.Threading.Tasks;
using Godot;

namespace SpaceDemo.Industrial.WorldV2;

/// <summary>
/// Verifies that every currently exposed mutating/control operation is rejected
/// after a real sticky Core fault. Exceptions are caught in C# so the probe
/// does not depend on GDScript's handling of managed exceptions.
/// </summary>
public partial class WorldV2FaultedCommandsProbe : Node
{
    private int _faultSignalCount;
    private string _faultMessage = "";

    public override async void _Ready()
    {
        try
        {
            GD.Print("[WorldV2FaultedCommandsProbe] started");

            var runtime = new WorldV2RuntimeNode
            {
                AutoAdvance = false
            };

            var connectResult = runtime.Connect(
                new StringName("RuntimeFaulted"),
                Callable.From<string>(OnRuntimeFaulted));
            Ensure(connectResult == Error.Ok, "could not connect RuntimeFaulted signal");

            AddChild(runtime);
            Ensure(runtime.IsInitialized, "Runtime must initialize a real World v2 session");
            Ensure(runtime.CanAcceptCommands, "healthy Runtime must accept commands");

            // Trigger the same real checked-arithmetic fault as the 4.11a fixture.
            runtime.SetWorldSpeedRatio(9.0e15);
            runtime.AutoAdvance = true;

            var faultObserved = false;
            for (var frame = 0; frame < 120; frame++)
            {
                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
                if (runtime.IsFaulted)
                {
                    faultObserved = true;
                    break;
                }
            }

            Ensure(faultObserved, "Core WorldClock overflow did not reach Runtime");
            Ensure(_faultSignalCount == 1, $"expected one fault signal, got {_faultSignalCount}");
            Ensure(!string.IsNullOrWhiteSpace(_faultMessage), "fault signal message must be non-empty");
            Ensure(!runtime.CanAcceptCommands, "faulted Runtime command gate must be closed");

            var before = runtime.GetWorldSnapshot();
            Ensure((bool)before["runtimeFaulted"], "diagnostic snapshot must expose runtimeFaulted");
            Ensure(!string.IsNullOrWhiteSpace((string)before["faultReason"]), "fault reason must be readable");

            // The guard must run before request validation or Core domain lookup.
            ExpectFaultRejected("PauseWorld", runtime.PauseWorld);
            ExpectFaultRejected("ResumeWorld", runtime.ResumeWorld);
            ExpectFaultRejected("SetWorldSpeedRatio", () => runtime.SetWorldSpeedRatio(1.0));
            ExpectFaultRejected("UpdateProducerRates", () => runtime.UpdateProducerRates(
                "陶工", new Godot.Collections.Dictionary
                {
                    ["圆罐"] = 1.0,
                    ["方罐"] = 0.0
                }));
            ExpectFaultRejected("AddSingleRequirementDemand",
                () => runtime.AddSingleRequirementDemand("圆罐", "酒", "A", "Passive", 0));
            ExpectFaultRejected("MoveDemand", () => runtime.MoveDemand(1, "Active"));
            ExpectFaultRejected("StartActiveDemand", () => runtime.StartActiveDemand(1));

            Ensure(_faultSignalCount == 1,
                $"rejected operations must not emit another fault signal; got {_faultSignalCount}");

            var after = runtime.GetWorldSnapshot();
            Ensure((bool)after["runtimeFaulted"], "snapshot must remain readable and faulted");
            Ensure((string)after["faultReason"] == (string)before["faultReason"],
                "fault reason must remain stable");
            Ensure((long)after["worldTimeMilli"] == (long)before["worldTimeMilli"],
                "rejected operations must not advance world time");

            GD.Print(
                "[WorldV2FaultedCommandsProbe] all six operations rejected",
                " fault_signal_count=", _faultSignalCount,
                " snapshot_readable=true fault_reason_stable=true");

            // Teardown is part of the boundary: the sticky-fault session is still owned
            // by Runtime until the node leaves the SceneTree.
            RemoveChild(runtime);
            Ensure(runtime.IsDisposed, "faulted Runtime must be disposed after leaving SceneTree");
            Ensure(!runtime.IsInitialized, "faulted Runtime must release its session on exit");
            runtime.QueueFree();

            GD.Print("[WorldV2FaultedCommandsProbe] passed operations=6 disposed=true");
        }
        catch (Exception ex)
        {
            GD.PushError("[WorldV2FaultedCommandsProbe] FAILED: " + ex);
            GetTree().Quit(1);
        }
    }

    private void OnRuntimeFaulted(string message)
    {
        _faultSignalCount++;
        _faultMessage = message;
        GD.Print("[WorldV2FaultedCommandsProbe] runtime fault signal: ", message);
    }

    private static void ExpectFaultRejected(string operation, Action action)
    {
        try
        {
            action();
        }
        catch (InvalidOperationException ex)
        {
            Ensure(ex.Message.Contains("已故障", StringComparison.Ordinal),
                $"{operation} was rejected for the wrong reason: {ex.Message}");
            GD.Print("[WorldV2FaultedCommandsProbe] rejected: ", operation);
            return;
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"{operation} threw unexpected exception type {ex.GetType().Name}: {ex.Message}", ex);
        }

        throw new InvalidOperationException($"{operation} was not rejected after Runtime fault");
    }

    private static void Ensure(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }
}
