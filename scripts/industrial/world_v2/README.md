# space-demo World v2 Runtime（4.10a）

这是新 World v2 在 space-demo 中的独立运行时适配层。它不依赖旧 IndustrialRuntime 的回合、奖励、钱包、存档或伤害语义，也不定义 Jar 系统与太空战玩法之间的关系。

## 依赖

当前 jar-system-dotnet 的 World v2 Bridge 位于 PR #26（Draft，尚未合并）。本阶段使用两个并列仓库的本地工作副本：

    D:/godot/programs/
    ├── space-demo/
    └── jar-system-dotnet/
        └── hosts/godot/WorldV2Bridge/

先在 jar-system-dotnet 工作副本切换到 world-v2/phase-4-godot-host-project。space-demo 的 space-demo.csproj 通过相对路径引用 Bridge，不引用旧 Core 项目路径。

## 4.10a 职责

- 创建并拥有一个 WorldV2BridgeSession。
- 从独立的 world_v2_sandbox.json 读取和校验世界配置。
- 把 Godot 墙钟秒转换为世界毫秒，保留不足 1ms 的余数。
- 不乘流速倍率；暂停和倍率由 Core WorldClock 处理。
- 向 GDScript 提供脱离式 Godot Dictionary 快照。
- 节点退出时释放会话。

本阶段不实现订单 UI、太空战伤害、奖励、钱包、旧存档迁移或旧模块删除。

## 本地验证

1. 确保两个仓库位于上述并列目录。
2. 在 Godot 4.7.1 .NET 打开 space-demo。
3. 通过「运行当前场景」打开 scenes/industrial/WorldV2RuntimeProbe.tscn。
4. 输出应出现 [WorldV2Runtime] initialized 和 [WorldV2Probe] runtime ready。
5. 每秒观察 world 与 logical 数值增长；主台/从台应分别显示“主台”“从台”。
6. 关闭场景/项目，不应出现 Dispose 异常。

这是 Runtime 冒烟测试场景，不替换项目主场景，也不修改旧 IndustrialMain。

## 4.10d 生命周期探针

新增独立场景：`scenes/industrial/WorldV2LifecycleProbe.tscn`。

运行方式：在 Godot 4.7.1 .NET 中打开该场景并运行当前场景（F6）。

探针覆盖：

- D1：对已初始化 Runtime 重复调用 `InitializeWorld()`，应返回 false，保留原会话和时钟，不把健康 Runtime 标记为故障。
- D2：使用 `world_v2_invalid.json` 初始化，应触发 `RuntimeFaulted`，且不保留 World session。
- D4：修正配置路径后，在同一个节点再次初始化，应成功并清除故障状态。
- D3/D5：将节点从 SceneTree 移除，应执行 `_ExitTree()`、释放 Bridge session、清空会话所有权，并将 `IsDisposed` 置为 true。
- D6：退出后的节点不可复活；再次初始化必须被拒绝。

该探针使用独立 Runtime 节点和 `AutoAdvance=false`，不干扰时间/命令探针，也不替换项目主场景。测试通过时应输出：

```text
[WorldV2LifecycleProbe] lifecycle probe passed initialization_faults=1 recovery=true duplicate_rejected=true disposed=true post_exit_rejected=true
```

D6：退出 SceneTree 后再次调用 `InitializeWorld()` 必须返回 false；`IsDisposed` 保持 true，且不得重新创建会话。

注意：探针场景内移除节点用于验证退出树时的释放路径；仍建议在完成探针后关闭运行窗口，确认整个项目退出时没有额外 Dispose 异常。
