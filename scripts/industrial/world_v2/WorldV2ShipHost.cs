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
    /// Sole production time ingress. deltaSeconds must be the already-scaled
    /// simulation delta from the owning Space world step.
    /// </summary>
    public bool AdvanceSpaceSimulation(double deltaSeconds)
    {
        if (double.IsNaN(deltaSeconds) || double.IsInfinity(deltaSeconds) || deltaSeconds < 0)
            throw new ArgumentOutOfRangeException(nameof(deltaSeconds));
        if (_state != HostState.Active)
            return false;
        if (_runtime == null || !_runtime.IsInitialized || _runtime.IsDisposed)
        {
            LatchFault("Active ship-world has no operational World V2 Runtime");
            return false;
        }
        if (deltaSeconds == 0)
            return true;

        _worldHasAdvanced = true;
        var accumulated = _fractionalWorldTimeMilli + deltaSeconds * 1000.0;
        if (accumulated > long.MaxValue)
        {
            LatchFault("Space simulation delta exceeds the supported Jar world-time range");
            return false;
        }

        var wholeMilliseconds = (long)Math.Floor(accumulated);
        _fractionalWorldTimeMilli = accumulated - wholeMilliseconds;
        if (wholeMilliseconds <= 0)
            return true;

        // Exactly one call per Space simulation step; no _Process or wall-clock fallback.
        _runtime.AdvanceWorldTime(wholeMilliseconds);
        if (_runtime.IsFaulted)
        {
            LatchFault(ReadRuntimeFault(_runtime, "World V2 Runtime faulted during Space time forwarding"));
            return false;
        }
        return true;
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
    /// Submit Space-calculated Jar production rates before the next shared simulation advance.
    /// The Runtime/Bridge validates the complete configured shape table and serializes the mutation.
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
