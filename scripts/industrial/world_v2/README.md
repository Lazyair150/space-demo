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
