using System;
using Godot;
using GDictionary = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

namespace SpaceDemo.Industrial.WorldV2;

[GlobalClass]
public partial class WorldV2ShipHost : Node
{
    [Signal] public delegate void ShipWorldFaultedEventHandler(string message);

    [Export] public string WorldConfigPath { get; set; } =
        "res://data/industrial/world_v2_sandbox.json";

    private enum HostState { Absent, Created, Active, Paused, Suspended, Disposed, Faulted }
    private WorldV2RuntimeNode? _runtime;
    private HostState _state = HostState.Absent;
    private double _fractionalWorldTimeMilli;
    private bool _hasPreparedSpaceStep;
    private long _preparedSpaceStepMilliseconds;
    private string _faultReason = "";
    private bool _worldHasAdvanced;
    private bool _ordersMaterialized;

    public string LifecycleState => _state.ToString();
    public bool IsShipWorldActive => _state == HostState.Active;
    public bool IsFaulted => _state == HostState.Faulted;
    public string FaultReason => _faultReason;

    public bool BeginShipWorld() => BeginShipWorldInternal(null);

    /// <summary>
    /// Starts a ship world from a validated, frozen battle-loadout configuration.
    /// Unlike the sandbox probe entry point, this path never falls back to WorldConfigPath.
    /// </summary>
    public bool BeginShipWorldFromJson(string worldOptionsJson)
    {
        if (_state == HostState.Active || _state == HostState.Paused)
            return false;
        if (string.IsNullOrWhiteSpace(worldOptionsJson))
            throw new ArgumentException("Frozen World V2 configuration JSON cannot be empty", nameof(worldOptionsJson));
        return BeginShipWorldInternal(worldOptionsJson);
    }

    private bool BeginShipWorldInternal(string? worldOptionsJson)
    {
        if (_state == HostState.Active || _state == HostState.Paused)
            return true;
        if (_state == HostState.Created || _state == HostState.Suspended || _state == HostState.Faulted)
            return false;

        _state = HostState.Created;
        _fractionalWorldTimeMilli = 0;
        _hasPreparedSpaceStep = false;
        _preparedSpaceStepMilliseconds = 0;
        _worldHasAdvanced = false;
        _ordersMaterialized = false;
        _faultReason = "";
        var runtime = new WorldV2RuntimeNode
        {
            Name = "WorldV2Runtime",
            WorldConfigPath = WorldConfigPath,
            AutoAdvance = false,
            InitializeOnReady = false
        };
        _runtime = runtime;
        AddChild(runtime);

        var initialized = worldOptionsJson == null
            ? runtime.InitializeWorld()
            : runtime.InitializeWorldFromJson(worldOptionsJson, "frozen battle loadout");
        if (!initialized || !runtime.IsInitialized || runtime.IsFaulted)
        {
            LatchFault(ReadRuntimeFault(runtime, "World V2 Runtime initialization failed"));
            return false;
        }

        _state = HostState.Active;
        GD.Print("[WorldV2ShipHost] Jar runtime active; external Space clock enabled");
        return true;
    }

    public void PauseShipWorld()
    {
        if (_state == HostState.Active)
            _state = HostState.Paused;
    }

    public void ResumeShipWorld()
    {
        if (_state == HostState.Paused)
            _state = HostState.Active;
    }

    public void SuspendShipWorld()
    {
        if (_state == HostState.Active || _state == HostState.Paused || _state == HostState.Created)
            _state = HostState.Suspended;
        _fractionalWorldTimeMilli = 0;
        _hasPreparedSpaceStep = false;
        _preparedSpaceStepMilliseconds = 0;
    }

    public void EndShipWorld()
    {
        if (_state == HostState.Disposed || _state == HostState.Absent)
        {
            _state = HostState.Disposed;
            return;
        }

        _state = HostState.Suspended;
        _fractionalWorldTimeMilli = 0;
        _hasPreparedSpaceStep = false;
        _preparedSpaceStepMilliseconds = 0;
        var runtime = _runtime;
        _runtime = null;
        if (runtime != null)
        {
            if (runtime.GetParent() == this)
                RemoveChild(runtime); // _ExitTree disposes the Bridge session.
            runtime.QueueFree();
        }
        _state = HostState.Disposed;
    }

    /// <summary>
    /// Sole production time ingress. Convert the already-scaled owning Space simulation delta
    /// into the exact whole logical milliseconds forwarded to Jar. The fractional remainder
    /// is owned only by this Host; Space-owned systems may process the returned delta before
    /// calling AdvanceSpaceSimulationMilliseconds.
    /// </summary>
    public long AccumulateSpaceSimulationDelta(double deltaSeconds)
    {
        if (double.IsNaN(deltaSeconds) || double.IsInfinity(deltaSeconds) || deltaSeconds < 0)
            throw new ArgumentOutOfRangeException(nameof(deltaSeconds));
        if (_state != HostState.Active)
            return 0;
        if (_hasPreparedSpaceStep)
            throw new InvalidOperationException("The previous Space time step has not been forwarded to Jar");

        if (deltaSeconds > 0)
            _worldHasAdvanced = true;
        var accumulated = _fractionalWorldTimeMilli + deltaSeconds * 1000.0;
        if (accumulated > long.MaxValue)
        {
            LatchFault("Space simulation delta exceeds the supported Jar world-time range");
            return 0;
        }

        var wholeMilliseconds = (long)Math.Floor(accumulated);
        _fractionalWorldTimeMilli = accumulated - wholeMilliseconds;
        _preparedSpaceStepMilliseconds = wholeMilliseconds;
        _hasPreparedSpaceStep = true;
        return wholeMilliseconds;
    }

    /// <summary>
    /// Advance Jar by the exact integer delta returned from AccumulateSpaceSimulationDelta.
    /// Space can process parser output and import completed Jars between these two calls.
    /// </summary>
    public bool AdvanceSpaceSimulationMilliseconds(long deltaWorldTimeMilli)
    {
        if (deltaWorldTimeMilli < 0)
            throw new ArgumentOutOfRangeException(nameof(deltaWorldTimeMilli));
        if (_state != HostState.Active)
            return false;
        if (!_hasPreparedSpaceStep || deltaWorldTimeMilli != _preparedSpaceStepMilliseconds)
            throw new InvalidOperationException("Jar must receive exactly the delta prepared by AccumulateSpaceSimulationDelta");
        _hasPreparedSpaceStep = false;
        _preparedSpaceStepMilliseconds = 0;
        if (_runtime == null || !_runtime.IsInitialized || _runtime.IsDisposed)
        {
            LatchFault("Active ship-world has no operational World V2 Runtime");
            return false;
        }
        if (deltaWorldTimeMilli == 0)
            return true;

        _runtime.AdvanceWorldTime(deltaWorldTimeMilli);
        if (_runtime.IsFaulted)
        {
            LatchFault(ReadRuntimeFault(_runtime, "World V2 Runtime faulted during Space time forwarding"));
            return false;
        }
        return true;
    }

    /// <summary>
    /// Convenience path for callers with no Space-owned pre-advance processing.
    /// </summary>
    public bool AdvanceSpaceSimulation(double deltaSeconds)
    {
        var wholeMilliseconds = AccumulateSpaceSimulationDelta(deltaSeconds);
        return AdvanceSpaceSimulationMilliseconds(wholeMilliseconds);
    }

    /// <summary>
    /// Read pending Jar order-cycle events at the Space world-step boundary.
    /// Repeated reads return the same events until explicitly acknowledged.
    /// </summary>
    /// <summary>
    /// Adds the frozen loadout's selected Jar orders before the first simulation step.
    /// Any partial materialization failure disposes the not-yet-started ship world.
    /// </summary>
    public GDictionary MaterializeSelectedOrders(GArray selectedOrders)
    {
        if (_state != HostState.Active || _runtime == null || !_runtime.IsInitialized)
            return new GDictionary { ["success"] = false, ["error"] = "Ship world is not active" };
        if (_worldHasAdvanced)
            return new GDictionary { ["success"] = false, ["error"] = "Orders must be materialized before the first world step" };
        if (_ordersMaterialized)
            return new GDictionary { ["success"] = false, ["error"] = "Selected orders have already been materialized" };
        if (selectedOrders == null)
            return new GDictionary { ["success"] = false, ["error"] = "Selected orders cannot be null" };

        var demandIds = new GArray();
        var orderKeys = new System.Collections.Generic.HashSet<string>(StringComparer.Ordinal);
        try
        {
            foreach (var rawOrder in selectedOrders)
            {
                var order = rawOrder.AsGodotDictionary();
                if (!order.ContainsKey("orderDefinitionKey") || !order.ContainsKey("jarOrder"))
                    throw new InvalidOperationException("Selected order is missing orderDefinitionKey or jarOrder");

                var orderKey = order["orderDefinitionKey"].AsString();
                if (string.IsNullOrWhiteSpace(orderKey) || !orderKeys.Add(orderKey))
                    throw new InvalidOperationException("Selected orderDefinitionKey is empty or duplicated");
                var jarOrder = order["jarOrder"].AsGodotDictionary();
                var requirements = jarOrder.ContainsKey("requirements")
                    ? jarOrder["requirements"].AsGodotArray()
                    : new GArray();
                var demandId = _runtime.AddJarDemand(
                    jarOrder.ContainsKey("type") ? jarOrder["type"].AsString() : "",
                    jarOrder.ContainsKey("area") ? jarOrder["area"].AsString() : "",
                    jarOrder.ContainsKey("cooldownDurationLogicalMilli")
                        ? jarOrder["cooldownDurationLogicalMilli"].AsInt64()
                        : -1,
                    orderKey,
                    requirements);
                demandIds.Add(demandId);
            }

            _ordersMaterialized = true;
            return new GDictionary { ["success"] = true, ["demandIds"] = demandIds };
        }
        catch (Exception ex)
        {
            EndShipWorld();
            LatchFault("Selected order materialization failed: " + ex.Message);
            return new GDictionary { ["success"] = false, ["error"] = ex.Message };
        }
    }

    /// <summary>
    /// Update a configured time-driven Jar Producer. This is not the finite energy-stone parser
    /// ingress; completed parser output must use ImportProducedJars.
    /// </summary>
    public bool UpdateJarProducerRates(string producerName, GDictionary rates)
    {
        if (_state != HostState.Active || _runtime == null ||
            !_runtime.IsInitialized || _runtime.IsDisposed)
            return false;

        _runtime.UpdateProducerRates(producerName, rates);
        return true;
    }
    /// <summary>
    /// Imports a completed batch of empty Jars from the Space-owned energy-stone parser.
    /// This is a discrete resource handoff, not a time-based Producer rate update.
    /// </summary>
    public GDictionary ImportProducedJars(string operationId, GDictionary jarCounts)
    {
        if (_state != HostState.Active || _runtime == null ||
            !_runtime.IsInitialized || _runtime.IsDisposed)
            return new GDictionary { ["success"] = false, ["error"] = "Ship world is not active" };

        var result = _runtime.ImportProducedJars(operationId, jarCounts);
        result["success"] = true;
        return result;
    }

    /// <summary>
    /// Read pending Jar order-cycle events at the Space world-step boundary.
    /// Repeated reads return the same events until explicitly acknowledged.
    /// </summary>
    public GArray GetPendingOrderCycleEvents()
    {
        if (_runtime == null || !_runtime.IsInitialized || _runtime.IsDisposed)
            return new GArray();
        return _runtime.GetPendingOrderCycleEvents();
    }

    /// <summary>
    /// Acknowledge only after Space has persisted the effect and processed-event identity.
    /// </summary>
    public bool AcknowledgeOrderCycleEvent(string eventId)
    {
        if (_runtime == null || !_runtime.IsInitialized || _runtime.IsDisposed)
            return false;
        return _runtime.AcknowledgeOrderCycleEvent(eventId);
    }

    /// <summary>
    /// Capture Jar's checkpoint only between complete Space steps. The fractional Space
    /// clock remainder is captured separately by CaptureSpaceClockRemainderMilli.
    /// </summary>
    public string CaptureExecutionCheckpointJson()
    {
        if (_state != HostState.Active || _runtime == null ||
            !_runtime.IsInitialized || _runtime.IsDisposed)
            throw new InvalidOperationException("Ship world is not active");
        if (_hasPreparedSpaceStep)
            throw new InvalidOperationException("Cannot capture Jar checkpoint while a Space step is prepared");
        return _runtime.CaptureExecutionCheckpointJson();
    }

    /// <summary>
    /// Restore Jar state before any world advance or selected-order materialization.
    /// The checkpoint already contains demands, active sessions, inventory and ledger receipts.
    /// </summary>
    public bool RestoreExecutionCheckpointJson(string json)
    {
        if (_state != HostState.Active || _runtime == null ||
            !_runtime.IsInitialized || _runtime.IsDisposed ||
            _worldHasAdvanced || _hasPreparedSpaceStep || _ordersMaterialized)
            return false;
        var restored = _runtime.RestoreExecutionCheckpointJson(json);
        if (!restored || _runtime.IsFaulted)
        {
            LatchFault(ReadRuntimeFault(_runtime, "Jar execution checkpoint restore failed"));
            return false;
        }
        _ordersMaterialized = true;
        return true;
    }

    /// <summary>Capture the Host-owned fractional-millisecond remainder at a step boundary.</summary>
    public double CaptureSpaceClockRemainderMilli()
    {
        if (_state != HostState.Active || _hasPreparedSpaceStep)
            throw new InvalidOperationException("Space clock remainder is available only at an active step boundary");
        return _fractionalWorldTimeMilli;
    }

    /// <summary>
    /// Restore the fractional-millisecond remainder before the first simulation step.
    /// This value is Space clock state, not part of Jar's execution checkpoint.
    /// </summary>
    public bool RestoreSpaceClockRemainderMilli(double remainderMilli)
    {
        if (_state != HostState.Active || _worldHasAdvanced || _hasPreparedSpaceStep ||
            double.IsNaN(remainderMilli) || double.IsInfinity(remainderMilli) ||
            remainderMilli < 0.0 || remainderMilli >= 1.0)
            return false;
        _fractionalWorldTimeMilli = remainderMilli;
        return true;
    }

    public GDictionary GetWorldSnapshot()
    {
        if (_runtime == null || !_runtime.IsInitialized)
            return new GDictionary { ["available"] = false, ["lifecycleState"] = _state.ToString() };
        var snapshot = _runtime.GetWorldSnapshot();
        snapshot["available"] = true;
        snapshot["lifecycleState"] = _state.ToString();
        return snapshot;
    }

    public override void _ExitTree() => EndShipWorld();

    private void LatchFault(string message)
    {
        if (_state == HostState.Faulted)
            return;
        _faultReason = message;
        _state = HostState.Faulted;
        GD.PushError("[WorldV2ShipHost] " + message);
        EmitSignal(SignalName.ShipWorldFaulted, message);
    }

    private static string ReadRuntimeFault(WorldV2RuntimeNode runtime, string fallback)
    {
        try
        {
            var snapshot = runtime.GetWorldSnapshot();
            var reason = snapshot.ContainsKey("faultReason") ? snapshot["faultReason"].AsString() : "";
            return string.IsNullOrWhiteSpace(reason) ? fallback : reason;
        }
        catch
        {
            return fallback;
        }
    }
}
