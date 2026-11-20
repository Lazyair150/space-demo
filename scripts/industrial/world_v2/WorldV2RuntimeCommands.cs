using System;
using Godot;
using JarSystem.Core.World;
using JarSystem.Core.World.Demands;
using GDictionary = Godot.Collections.Dictionary;

namespace SpaceDemo.Industrial.WorldV2;

/// <summary>
/// GDScript-facing command adapter for the World v2 Runtime.
/// Keep Godot-friendly primitive arguments here; Core request/DTO types stay behind this boundary.
/// </summary>
public partial class WorldV2RuntimeNode
{
    /// <summary>
    /// Sandbox command for adding a demand with one requirement.
    /// This deliberately starts with a narrow, easy-to-verify GDScript contract;
    /// multi-requirement input will be added when a concrete caller needs it.
    /// </summary>
    public int AddSingleRequirementDemand(
        string shape,
        string liquid,
        string specificationType,
        string area,
        long cooldownDurationLogicalMilli)
    {
        if (string.IsNullOrWhiteSpace(shape))
            throw new ArgumentException("罐子形状不能为空", nameof(shape));
        if (string.IsNullOrWhiteSpace(specificationType))
            throw new ArgumentException("订单类型不能为空", nameof(specificationType));
        if (!Enum.TryParse(area, ignoreCase: true, out DemandAreaKind areaKind) ||
            !Enum.IsDefined(typeof(DemandAreaKind), areaKind))
        {
            throw new ArgumentException("订单区域必须是 Active 或 Passive", nameof(area));
        }

        var request = new WorldV2AddJarDemandRequest(
            new[]
            {
                new WorldV2RequirementInput(
                    shape,
                    string.IsNullOrWhiteSpace(liquid) ? null : liquid)
            },
            specificationType,
            areaKind,
            cooldownDurationLogicalMilli);

        var demandId = RequireSession().AddJarDemand(request);
        EmitSignal(SignalName.SnapshotChanged);
        return demandId;
    }

    /// <summary>Move an existing demand to Active or Passive. Returns false if it was not found.</summary>
    public bool MoveDemand(int demandId, string targetArea)
    {
        if (!Enum.TryParse(targetArea, ignoreCase: true, out DemandAreaKind areaKind) ||
            !Enum.IsDefined(typeof(DemandAreaKind), areaKind))
        {
            throw new ArgumentException("目标区域必须是 Active 或 Passive", nameof(targetArea));
        }

        var moved = RequireSession().MoveDemand(demandId, areaKind);
        if (moved)
            EmitSignal(SignalName.SnapshotChanged);
        return moved;
    }

    /// <summary>Explicitly start an Active-area demand and return a detached result dictionary.</summary>
    public GDictionary StartActiveDemand(int demandId)
    {
        var result = RequireSession().StartActiveDemand(demandId);
        EmitSignal(SignalName.SnapshotChanged);
        return new GDictionary
        {
            ["success"] = result.Success,
            ["reason"] = result.Reason ?? ""
        };
    }
}
