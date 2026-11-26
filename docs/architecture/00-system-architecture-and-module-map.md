# Space 总体架构与模块地图

状态：当前架构入口。具体字段和行为以源码、跨仓库协议与测试为准。

## 1. 系统边界

Space 是 Godot 客户端与游戏规则的拥有者；Jar Core 是资源/规则/订单运行内核。两者通过 Core 仓库的 WorldV2Bridge 连接。Space 不保留第二套 Jar Core。

## 2. 依赖拓扑

```text
MainMenu / Hangar / Combat UI
          |
          v
GameFlow / SpaceHangarPreparation / Game
          |
          v
Space Domain
  | Board + Owned Loadout
  | Ship / Parser / Devices / Skills
  | Progression / Stages / Effects
          |
          v
WorldV2ShipHost (Godot C# adapter)
          |
          v
WorldV2RuntimeNode
          |
          v
JarSystem.WorldV2Bridge
          |
          v
JarSystem.Core
```

UI 只能发起意图、显示状态。Space Domain 冻结配置并管理 Space-owned 实例。Host 管理 Core session 生命周期、时间步和命令/快照边界。Core 拥有 Jar 规则、求解、执行和资源事实。

## 3. 模块职责与源码入口

| 模块 | 主要源码 | 责任 |
|---|---|---|
| Application Flow | `globals/GameFlow.gd`, `scripts/main_menu.gd` | 菜单/机库/战斗屏幕状态和合法导航 |
| Hangar / Board | `SpaceHangarBoardDefinition.gd`, `SpaceHangarBoardAssignment.gd`, `SpaceHangarSelectionDraft.gd`, `SpaceHangarOwnedLoadoutAssembler.gd` | 槽位定义、玩家安装关系、Owned Instance 校验、冻结 |
| Loadout Snapshot | `SpaceBattleLoadoutSnapshot.gd` | 深拷贝、schema 迁移、fingerprint、冻结战斗配置 |
| World Host | `WorldV2ShipHost.cs`, `WorldV2RuntimeNode.cs` | Core session 生命周期、初始化、时间转发、命令、快照、故障 |
| Production / Parser | `SpaceOreParserRuntime.gd`, `SpaceOreParserJarIngress.gd`, `SpaceBattleJarSupplyForecast.gd` | 有限原石输入、形状队列、产出批次、Core 导入 |
| Order / Effects | `SpaceOrderEffectDispatcher.gd`, `SpaceOrderEffectCommitter.gd`, `SpaceBattleEffectStateStore.gd` | Core 订单事实到 Space 效果的可靠投递与持久化 |
| Progression | `SpacePlayerProgressionState.gd`, `SpaceProgressionGrowthService.gd`, `SpaceProgressionRewardService.gd` | 玩家 Owned Instance、成长、奖励 |
| Stage | `SpaceStageCatalog.gd`, `SpaceStageEncounterDirector.gd`, `SpaceStageObjectiveRuntime.gd` | 关卡内容、遭遇调度、目标和结算 |
| Presentation | `scripts/Hud.gd`, `SpaceJarHudObserver.gd`, `SpaceHangarScreen.gd` | 只读展示、玩家输入、状态反馈 |

## 4. 跨模块数据流

1. Catalog 提供精确 Definition ID/Version。
2. Player Progression 提供 Owned Instance ID、revision 和 growth snapshot。
3. Board 把 Owned Instance 安装到稳定 Slot ID。
4. Hangar 产生 Board Assignment Snapshot、Board Rule Profile 和子系统运行 Profile。
5. Loadout Snapshot 冻结上述数据并计算 loadout fingerprint。
6. Launcher 在 Game 加入 SceneTree 前注入冻结 Loadout。
7. Game 将精确 World Options JSON 交给 WorldV2ShipHost。
8. Host 初始化 Runtime；只有初始化成功才进入 Running 并允许战斗。
9. Parser/Space 通过 Host 提交 Core 输入；Core 快照/事件驱动 HUD 和 Space 效果。
10. 保存/恢复使用同一 loadout identity 与对应 Core/Space checkpoint。

## 5. 关键不变量

- 一个领域事实只有一个权威所有者。
- 一个 Owned Instance 同时只能安装到一个 Board Slot。
- Slot 角色属于 Board，不属于 Workshop Definition。
- 任何跨仓库 snapshot 都必须校验 schema、身份、revision 和 fingerprint。
- Core 初始化失败必须停止战斗，不得 fallback 到 Sandbox。
- Space 和 Jar 的时间步必须由同一个 Game 仿真步协调。
- HUD 不得写入或推断 Core 资源事实。
- Headless 探针不能代替桌面 GUI 验收。

## 6. 文档导航

- [项目开发指导书](../PROJECT_DEVELOPMENT_GUIDE.md)
- [Hangar 与 Board Assignment](13-hangar-board-assignment-and-loadout-pipeline.md)
- [World V2 Host 与运行时故障边界](14-world-v2-host-runtime-and-failure-boundary.md)
- [生产、Parser 与资源供给](15-production-parser-and-resource-supply.md)
- [订单、规则配置与效果分发](16-order-rule-profile-and-effect-dispatch.md)
- [成长、关卡与持久化](17-progression-stage-and-persistence.md)
- [编码规范](12-space-engineering-standard.md)
