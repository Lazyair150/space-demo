# 2026-11-26 跨仓库探针生命周期与诊断修正

## 基线

- Space 仓库：`Lazyair150/space-demo`
- Space 分支：`world-v2/phase-4.10b-hangar-ui`
- Core 仓库：`Lazyair150/jar-system-dotnet`
- Core 精确依赖：`391f318a24fde724a66054e771d0590f0e20c231`
- Core 用户本地测试：上一轮已报告 `1038 / 1038` 通过；本轮没有重复执行。
- 本轮依据：用户提交的 `verify-world-v2-cross-repo.sh` 完整本地输出。
- 本轮工作方式：集中修复探针夹具、生命周期时序和验证门禁，代码及记录成组提交；新代码尚待用户本地集中运行。

## 一、最近一次本地联合验证事实

用户从 Space 仓库运行：

```powershell
bash .\scripts\ci\verify-world-v2-cross-repo.sh
```

输出以如下标记结束：

```
CROSS-REPO-WORLD-V2-OK core=391f318a24fde724a66054e771d0590f0e20c231
```

按当时脚本的控制流程，只有 Core Bridge 构建、Space 构建、Godot 导入、HUD、Domain contracts、Parser ingress、World V2 runtime/lifecycle/fault/disposal/snapshot isolation 和 battle navigation 各子步骤返回成功且输出预期完成标记后，才会打印总成功标记。

该次输出确认：

- Core World V2 Bridge 构建成功。
- Space C# 项目以兄弟仓库 Bridge 构建成功。
- Godot 4.7.1 .NET 项目导入和脚本扫描完成。
- HUD 检查为 `21 checks, 0 failures`。
- Hangar / Board / Progression / Domain contracts 探针完成。
- Parser → Core ingress 输出 `parsed=1`、`duplicate_receipt_retained=1`、`duplicate_capacity_outcome=exact_per_shape`。
- World V2 Runtime、Lifecycle、Fault、Disposed Commands、Faulted Commands、Snapshot Isolation 探针均输出各自的通过标记。
- Battle navigation 探针输出 `passed terminal-menu-transition=true`。

先前 Parser 探针中使用 `Dictionary.is_empty()` 判断逐形状丢弃映射为空的断言问题已消失；当前运行时的 total-map 契约继续保留每个形状的零值键。

该输出没有打印 Space 的 `git rev-parse HEAD`。因此这份记录只固定 Core SHA，不推测用户当次本地 Space commit。下一次运行前必须显式输出并留存 Space HEAD。

## 二、暂停控制器错误：修正探针时序，不误改生产导航

### 运行时观察

该次日志在最后的 battle navigation 探针中出现：

```
ERROR: Parent node is busy adding/removing children, remove_child() can't be called at this time.
```

读取 `SpaceBattlePauseControllerProbe.gd`、`SpaceBattlePauseController.gd` 和 `GameFlow.gd` 后确认：

- 探针在自己的 `_ready()` 中创建控制器，并在同一个 `_ready()` 调用栈内直接执行 `controller._on_primary_action()`。
- 该动作进入 `GameFlow.return_to_menu()`，同步调用 `SceneTree.change_scene_to_file()`，替换当前场景。
- 正常玩家操作由 Button 的 `pressed` 信号触发，发生在场景初始 `_ready()` / 子节点挂载流程之后。

所以现有证据证明的是**测试探针在 SceneTree 正在挂载节点时发起场景切换**，并不能据此断言玩家正常点击按钮也会触发同一个错误。此次没有改写 `GameFlow` 的状态回滚或生产导航语义。

### 修正

`SpaceBattlePauseControllerProbe.gd` 在最后一次真实主菜单切换前等待：

```gdscript
await get_tree().process_frame
controller._on_primary_action()
```

这样测试仍然走真实 `GameFlow.return_to_menu()` 和真实主菜单场景，但不在探针的初始节点挂载阶段启动场景替换。

验证脚本新增对 `Parent node is busy adding/removing children` 的明确失败检测。若该错误再次出现，脚本将不再因最后 marker 已输出而漏过它。

## 三、StatusEffectManager 警告：补齐真实测试依赖

### 根因

此前 `SpaceBattleEffectStateStoreProbe._probe_effect_manager_restore()` 直接 new 了两个 `StatusEffectManager`，但没有将 `StatCalculator` 传入 `bind_stats()`。管理器因此按设计发出：

```
StatusEffectManager 没有绑定 StatCalculator，修正器不会生效
```

这是该测试夹具没有提供属性计算器，不能作为正式战斗运行时没有绑定属性计算器的证据。先前探针也没有实际验证 Buff 修正器是否登记、恢复或撤销。

### 修正

现在该探针：

1. 创建独立的 source / restored `StatCalculator` 和 `StatusEffectManager`。
2. 显式调用两个管理器的 `bind_stats()`。
3. 使用带有 FLAT +5 修正器的版本化 Buff 定义，并声明 `ADD_STACK`。
4. 通过两个不同事件将 Buff 叠到 2 层，检查属性值从基值 20 变为 30。
5. 捕获、恢复运行时状态，检查事件去重记录、剩余时间、层数和恢复后的修正器结果。
6. 对非有限持续时间、错误 Definition 版本、无法解析的稳定目标执行拒绝恢复，并确认原有运行状态和属性修正未被部分覆盖。
7. 重放已处理事件，确认不会重复叠层或重复登记修正器。
8. 推进至到期，确认实例和 StatCalculator 修正器一并移除。
9. 通过统一清理函数清空并释放探针创建的 Node，覆盖成功和失败返回路径。

这不仅消除了测试夹具缺少依赖造成的警告，还把原本只检查 Buff 数据恢复的测试提升为检查真实修正器生命周期。

## 四、ObjectDB / Resource 退出诊断

最近一次运行仍报告：

- `108 ObjectDB instances were leaked at exit`
- `44 resources still in use at exit`

它们出现在 Domain contracts 和 Parser ingress 的独立 Godot 进程退出阶段。当前日志没有列出足以确定所有权的对象类型和创建栈，因此不能直接把这两个数字归因为单一场景、某个资源或某个管理器。

本轮已经显式释放 Effect State Store Probe 创建的四个 Node（两个管理器、两个属性计算器）。这只处理已确认由该探针直接拥有的对象；是否能显著降低 108 / 44，必须以新的运行结果为准。

验证脚本现支持：

```powershell
$env:GODOT_VERBOSE = "1"
```

该开关只对 `space-domain-contracts` 和 `parser-ingress` 两个相关进程添加 Godot `--verbose`，用于缩小退出时的 ObjectDB / Resource 诊断范围。没有将尚未定位的泄漏当成正常现象，也没有通过关闭泄漏检查掩盖问题。

## 五、本批代码变更

本轮在 Space 分支集中提交：

- `SpaceBattlePauseControllerProbe.gd`：场景替换前等待 SceneTree 完成当前帧的挂载阶段。
- `SpaceBattleEffectStateStoreProbe.gd`：绑定真实 StatCalculator，覆盖 Buff 修正器叠层、恢复、幂等、拒绝恢复与到期撤销，并显式释放探针节点。
- `scripts/ci/verify-world-v2-cross-repo.sh`：
  - 将 SceneTree busy 错误加入失败检查；
  - 支持只对两个高优先级探针启用 verbose 诊断。

对应代码提交：

- `5cc9be6a92f91279d6eedfcfdb2318498e302f7f`
- `e900de7ad1b2707384d5dfb07c6bc3c92523ff60`
- `122e83f42ab100c565ed62c47c3d6634a449caf2`

本记录产生后，分支 HEAD 会进一步推进。下一次本地运行应以拉取后的 `git rev-parse HEAD` 为准，而不是沿用这三个中间提交中的任意一个。

## 六、验证边界与下一步

### 已有证据

- 用户给出的前次 Core xUnit：`1038 / 1038` 通过。
- Core 精确提交：`391f318a24fde724a66054e771d0590f0e20c231`。
- 用户给出的最近一次 Space 跨仓库脚本输出到达 `CROSS-REPO-WORLD-V2-OK`。
- Parser/Core 精确重复回执、HUD、Domain、Runtime 与大部分生命周期探针在这次输出中均有明确通过标记。

### 尚待验证

- 上述三个新代码提交尚未在用户本地运行。
- 暂停探针修正后，SceneTree busy 错误必须消失。
- Effect State Store Probe 新增的 StatCalculator 断言必须通过，且对应未绑定警告应消失。
- verbose 模式下重新检查 ObjectDB 108 / Resource 44 的具体分配与退出信息。
- 真实桌面 GUI 的主菜单、机库、开战、暂停、恢复、故障退出及连续进入战斗仍未由这次 Headless 输出验收。

### 集中运行指令

先更新两个仓库，并记录精确 HEAD：

```powershell
cd D:\godot\programs\jar-system-dotnet
git fetch origin --prune
git switch architecture/core-liquid-identity-consolidation
git pull --ff-only origin architecture/core-liquid-identity-consolidation
git rev-parse HEAD

cd D:\godot\programs\space-demo
git fetch origin --prune
git switch world-v2/phase-4.10b-hangar-ui
git pull --ff-only origin world-v2/phase-4.10b-hangar-ui
git rev-parse HEAD
```

确认 Core HEAD 仍是 `391f318a24fde724a66054e771d0590f0e20c231` 后，在 Space 根目录运行：

```powershell
$env:CORE_REPO_DIR = (Resolve-Path ..\jar-system-dotnet).Path.Replace('\\','/')
$env:CORE_EXPECTED_SHA = "391f318a24fde724a66054e771d0590f0e20c231"
$env:GODOT_BIN = "godot"
$env:GODOT_VERBOSE = "1"
bash .\scripts\ci\verify-world-v2-cross-repo.sh
```

此次不重复 Core 的 1038 项 xUnit；集中验证 Space 新改动和泄漏诊断。若总脚本失败，按首个真实失败点修复，不把预期拒绝日志误判为失败，也不因总 marker 出现而忽略后续诊断日志。

## 七、当前未关闭事项

|事项|状态|
|---|---|
|Parser/Core 导入精确回执|本地前次完整脚本通过；新 HEAD 仍需回归|
|供给只读对账与 HUD|本地前次探针通过；新 HEAD 仍需回归|
|暂停导航 SceneTree 时序|探针已修正，待本地验证|
|Buff / StatCalculator 恢复链|探针已增强，待本地验证|
|ObjectDB / Resource 退出泄漏|仍未定位，需 verbose 证据|
|Core 逐 Jar 来源谱系|尚未设计实现；不得以账户余额差值猜来源|
|Parser / Core 事件驱动 XP 结算|待供给事实链稳定后设计|
|正式 XP 数值和平衡配置|仍应由版本化内容数据提供|
|桌面 GUI 试玩|未验收|
