# World V2 Host、GameFlow 与战斗生命周期

## 1. 所有权

- `GameFlow`：应用屏幕导航与 battle phase。
- `Game`：战斗组合根、唯一 Space 仿真步协调者。
- `SpaceBattlePauseController`：玩家暂停输入与 SceneTree pause gate。
- `WorldV2ShipHost`：一个 active Jar World 的唯一宿主、时间/命令边界。
- `WorldV2RuntimeNode`：Godot Node 对 Core Bridge Session 的适配与错误映射。
- Jar Core：实际世界、规则、求解、执行、逻辑时间和账本。

## 2. 启动状态序列

```text
Hangar freezes Loadout
  -> Launcher configures Game before SceneTree attachment
  -> GameFlow.begin_battle_preparation
  -> Game enters SceneTree
  -> Game._ready
  -> Game._begin_ship_world
  -> WorldV2ShipHost.BeginShipWorldFromJson
  -> WorldV2RuntimeNode.InitializeWorldFromJson
  -> Core WorldV2Options.Validate
  -> Bridge creates World
  -> Game materializes selected orders / parser
  -> GameFlow.mark_battle_running
```

只有 Core 初始化和后续订单/Parser 准备全部成功，Game 才进入 Running。失败必须 latch fault、释放本次 Host 资源、unpause SceneTree，并禁止战斗继续。

## 3. 时间推进

生产路径唯一：

`Game._physics_process(delta) → Host.AccumulateSpaceSimulationDelta → Space-owned parser/effect work → Host.AdvanceSpaceSimulationMilliseconds(same delta) → Runtime.AdvanceWorldTime → Core WorldClock`

Host 持有小数毫秒余数，并强制 accumulate/advance 成对执行。禁止同时启用 Runtime AutoAdvance 和 Host 外部推进。

## 4. Pause / Resume / Exit

- Pause：先 Pause Host，再设置 SceneTree.paused。
- Resume：在同一同步边界释放 SceneTree gate 并恢复 Host。
- Focus Lost：自动暂停；Focus Gained 不自动恢复。
- Return Main Menu：必须释放 Host、清除 SceneTree pause、结束 Battle phase，再切换根场景。
- 再次进入战斗：必须获得新 Host session；不得复用上一次的 faulted/disposed runtime。

## 5. 故障边界

错误日志应包含 subsystem、operation、source label、schema、身份、字段级错误。Host 只能将 Core 异常映射为 Space 可处理的 fault；不得吞掉错误或继续使用部分初始化状态。

配置 ingress 失败是 P0：Game 不应继续创建敌人、推进时钟或显示可操作战斗 UI。错误面板应提供清晰原因和返回菜单操作。

## 6. 验证层级

1. C# Bridge build。
2. Headless Runtime init/fault/disposal probes。
3. SceneTree pause/resume/menu-transition probes。
4. Desktop GUI 实际启动与再次进入。
5. 目标 OS/GPU 手动验收。

Headless 通过不等于桌面 GUI 通过。具体暂停契约见 [11 — Runtime Lifecycle](11-game-runtime-lifecycle-pause-and-scene-tree.md)，源码见 `WorldV2ShipHost.cs`、`WorldV2RuntimeNode.cs`、`Game.gd`、`GameFlow.gd`。
