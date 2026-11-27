using System;
using Godot;

namespace SpaceDemo.Industrial.WorldV2;

public partial class WorldV2SnapshotIsolationProbe : Node
{
    public override void _Ready()
    {
        try
        {
            GD.Print("[WorldV2SnapshotIsolationProbe] started");

            var runtime = new WorldV2RuntimeNode { AutoAdvance = false };
            AddChild(runtime);
            Ensure(runtime.IsInitialized, "Runtime must initialize");

            var demandId = runtime.AddSingleRequirementDemand(
                "圆罐", "", "A", "Passive", 0);

            var first = runtime.GetWorldSnapshot();
            Ensure(int.Parse(first["worldTimeMilli"].ToString()) == 0,
                "initial world time must be zero");

            // Mutate root-level values and nested dictionaries/arrays returned to Godot.
            first["worldTimeMilli"] = 987654;
            first["runtimeFaulted"] = true;

            var firstLiquids = first["resourceLiquids"].AsGodotDictionary();
            Ensure(firstLiquids.ContainsKey("酒"), "warehouse snapshot must expose the configured liquid key");
            var expectedWarehouseWine = firstLiquids["酒"].AsInt32();
            firstLiquids["酒"] = 999;

            var firstShipInventory = first["shipLiquidInventory"].AsGodotDictionary();
            var firstShipBalances = firstShipInventory["balances"].AsGodotDictionary();
            var expectedShipWine = firstShipBalances["酒"].AsInt32();
            Ensure(expectedShipWine == 10, "initialLiquidStock must remain in the ship inventory account");
            firstShipBalances["酒"] = 999;

            var firstMaster = first["master"].AsGodotDictionary();
            firstMaster["name"] = "MUTATED";
            var firstMarks = firstMaster["baseMarks"].AsGodotArray();
            Ensure(firstMarks.Count > 0, "master base marks must not be empty");
            firstMarks[0] = "MUTATED";

            var firstDemands = first["demands"].AsGodotArray();
            var firstDemand = FindDemand(firstDemands, demandId);
            firstDemand["area"] = "MUTATED";
            var firstRequirements = firstDemand["requirements"].AsGodotArray();
            Ensure(firstRequirements.Count > 0, "demand must contain a requirement");
            var firstRequirement = firstRequirements[0].AsGodotDictionary();
            firstRequirement["shape"] = "MUTATED";

            var second = runtime.GetWorldSnapshot();
            Ensure(int.Parse(second["worldTimeMilli"].ToString()) == 0,
                "root scalar mutation must not affect a later snapshot");
            Ensure(!(bool)second["runtimeFaulted"].AsBool(),
                "root boolean mutation must not affect a later snapshot");

            var secondLiquids = second["resourceLiquids"].AsGodotDictionary();
            Ensure(secondLiquids["酒"].AsInt32() == expectedWarehouseWine,
                "nested warehouse dictionary mutation must not affect Core state");
            var secondShipInventory = second["shipLiquidInventory"].AsGodotDictionary();
            var secondShipBalances = secondShipInventory["balances"].AsGodotDictionary();
            Ensure(secondShipBalances["酒"].AsInt32() == expectedShipWine,
                "nested ship inventory dictionary mutation must not affect Core state");

            var secondMaster = second["master"].AsGodotDictionary();
            Ensure(secondMaster["name"].AsString() == "主台",
                "nested workshop dictionary mutation must not affect Core state");
            var secondMarks = secondMaster["baseMarks"].AsGodotArray();
            Ensure(secondMarks[0].AsString() == "圆罐",
                "nested workshop array mutation must not affect Core state");

            var secondDemand = FindDemand(second["demands"].AsGodotArray(), demandId);
            Ensure(secondDemand["area"].AsString() == "Passive",
                "demand dictionary mutation must not affect Core state");
            var secondRequirement = secondDemand["requirements"].AsGodotArray()[0].AsGodotDictionary();
            Ensure(secondRequirement["shape"].AsString() == "圆罐",
                "deeply nested requirement mutation must not affect Core state");

            // Mutating the second snapshot must likewise leave a third snapshot intact.
            secondLiquids["酒"] = 123;
            secondShipBalances["酒"] = 321;
            secondMarks[0] = "SECOND_MUTATION";
            secondRequirement["shape"] = "SECOND_MUTATION";

            var third = runtime.GetWorldSnapshot();
            Ensure(third["resourceLiquids"].AsGodotDictionary()["酒"].AsInt32() == expectedWarehouseWine,
                "warehouse snapshot dictionaries must be independent between calls");
            Ensure(third["shipLiquidInventory"].AsGodotDictionary()["balances"].AsGodotDictionary()["酒"].AsInt32() == expectedShipWine,
                "ship inventory snapshot dictionaries must be independent between calls");
            Ensure(third["master"].AsGodotDictionary()["baseMarks"].AsGodotArray()[0].AsString() == "圆罐",
                "snapshot arrays must be independent between calls");
            var thirdDemand = FindDemand(third["demands"].AsGodotArray(), demandId);
            Ensure(thirdDemand["requirements"].AsGodotArray()[0].AsGodotDictionary()["shape"].AsString() == "圆罐",
                "deep nested snapshot containers must be independent between calls");

            runtime.QueueFree();

            GD.Print(
                "[WorldV2SnapshotIsolationProbe] detached snapshot mutation passed",
                " root=true dictionary=true array=true nested=true cross_snapshot=true");
            GD.Print("[WorldV2SnapshotIsolationProbe] passed");
        }
        catch (Exception ex)
        {
            GD.PushError("[WorldV2SnapshotIsolationProbe] FAILED: " + ex);
            GetTree().Quit(1);
        }
    }

    private static Godot.Collections.Dictionary FindDemand(
        Godot.Collections.Array demands,
        int demandId)
    {
        foreach (var item in demands)
        {
            var demand = item.AsGodotDictionary();
            if (demand["id"].AsInt32() == demandId)
                return demand;
        }

        throw new InvalidOperationException("Demand was not found in snapshot: " + demandId);
    }

    private static void Ensure(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }
}
