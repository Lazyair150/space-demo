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
$env:CORE_REPO_DIR = (Resolve-Path ..\jar-system-dotnet).Path.Replace('\','/')
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


## 八、用户在 Space HEAD `c25d618c19bbbca395e632154805630fad01fefa` 的 verbose 联合运行

### 已通过的步骤

Core 依赖仍为 `391f318a24fde724a66054e771d0590f0e20c231`。用户确认 Space HEAD 为 `c25d618c19bbbca395e632154805630fad01fefa`，并设置 `GODOT_VERBOSE=1` 运行联合脚本。

本次输出显示：

- Core World V2 Bridge 构建成功。
- Space .NET 项目构建成功。
- Godot 4.7.1 Editor import / class registration 完成。
- HUD：`21 checks, 0 failures`。
- Hangar/Board/Progression domain contracts 输出 `all-domain-contracts=passed`。
- Parser → Core 精确回执/检查点恢复输出 `[SpaceOreParserJarIngressProbe] passed`，结果保留 `parsed=1`、`duplicate_receipt_retained=1`、`duplicate_capacity_outcome=exact_per_shape`。
- World V2 runtime、lifecycle、fault、disposed commands、faulted commands 和 snapshot isolation 均输出各自通过标记。
- Buff/StatusEffectManager 恢复探针输出 `battle-effect-state-store=passed`；之前因探针没有绑定 `StatCalculator` 而产生的两条“修正器不会生效”警告已消失。
- 暂停探针没有再次输出 `Parent node is busy adding/removing children`，说明延后到 SceneTree 当前挂载阶段之后执行导航的修正起效。

### 当前运行真正失败的位置

联合脚本没有打印最终 `CROSS-REPO-WORLD-V2-OK`。最后一个 battle-navigation 探针发生新的脚本错误：

```
ERROR: Parameter "data.tree" is null.
SCRIPT ERROR: Invalid access to property or key 'paused' on a base object of type 'null instance'.
SpaceBattlePauseControllerProbe.gd:85
```

根因是探针在调用 `controller._on_primary_action()` 后，真实主菜单切换已经卸载了当前 Probe 场景；旧 Probe Node 不再属于 SceneTree。探针随后调用自身的 `get_tree()` 和读取旧 controller overlay，访问了已经失效的场景节点。此错误发生在场景替换后的探针断言阶段，不是生产 `GameFlow.return_to_menu()` 返回失败；此前没有输出 SceneTree busy 错误。

已进一步修正为在触发真实场景切换之前保留 `SceneTree` 引用，切换后只通过该引用和仍存活的 `GameFlow` autoload 检查暂停闸、Screen 和 BattlePhase，不再解引用旧 Probe / Controller 节点。成功与否仍依靠 `GameFlow.return_to_menu()` 的事务式状态回滚语义区分：成功转场保留 MENU/INACTIVE，失败则恢复 FAULTED 及原暂停状态。

代码提交：

- `3bd18b384ab1e5430aea449dc641892ac4d6816e`：初次保存 SceneTree 引用并修正转场后的检查边界。
- `296fcc071580a4d74ced06835b27e85ccbe6aca4`：移除对 `current_scene` 在转场当帧的即时非空假设，只验证稳定的 SceneTree pause 与 GameFlow 状态。
  
以上导航修正尚未经过新的本地运行。

### ObjectDB / Resource 泄漏的新证据与定位

本次 verbose 输出将先前的数字从 108 / 44 缩小到：

- `99 ObjectDB instances were leaked`
- `42 resources still in use`
- `283 unclaimed string names at exit`
- 三次 `Cannot get path of node as it is not in a scene tree`
- 每个相关进程的 leaked-instance 清单均列出 3 个 `Node`，Node path 为空。

通过对 Domain contracts 的调用链及所有 `SpaceHangarPreparation.new()` 的创建路径进行静态核对，找到了恰好三处没有释放的 Node：

1. `SpaceHangarCatalogOwnershipProbe.gd` 的未配置机库路径创建 `unconfigured_preparation`。
2. 同一 Probe 的 Owned inventory 路径创建 `owned_preparation`。
3. `SpaceDemoProgressionBootstrapProbe.gd` 创建用于真实默认 Owned 装配的 `preparation`。

三者的类型都继承自 Node，但并未加入 SceneTree，也没有在探针结束时调用 `free()`。它们由 `SpaceHangarSelectionController` 引用并不意味着该 RefCounted controller 会替调用方释放 Node。该静态证据与 verbose 中恰好 3 个无路径 leaked Node 和 3 条 get_path 错误相吻合。

已修正为显式所有权：

- 将两个 Catalog Ownership 检查抽取成 helper；每条正常/拒绝路径都在 helper 末尾先释放 RefCounted controller，再释放 Node preparation。
- 将 Progression Bootstrap 的默认装配抽取成 helper；先取得独立冻结的 `SpaceBattleLoadoutSnapshot`，释放 controller 和 preparation 后再验证/迁移这个快照。
- 对可选快照局部变量显式初始化为 null。
- 不再让测试 Node 逃逸到外层调用者，也不改变生产 Hangar 运行期的 Node 所有权。

相关提交：

- `2f88ade03c4248aaef96530e97934fe0a995cdc1`：修复两个 Catalog Ownership Probe 中的 Node 所有权。
- `e57da5091e2ebfe8532dcb3e022211fef26830a6`：修复 Progression Bootstrap Probe 的 Node 所有权。
- `9f0cda14c5a70c595095a56bbacb5a7c1694ac0f`：显式初始化可选冻结快照。

验证脚本还增加了针对这些所有权回归的明确门禁：

- `Cannot get path of node as it is not in a scene tree` 会使对应 Godot 子步骤失败。
- 在 `GODOT_VERBOSE=1` 下，Domain contracts 和 Parser ingress 若仍出现 `Leaked instance: Node:`，即使业务 marker 已输出也会失败。
- 暂不把 `Resource still in use` 或 GDScript/StringName 缓存直接设为总失败条件，因为这些列表仍包含预加载脚本和作者资源，归属尚未完全确定。

该门禁提交：`44668cd131dcb0777f579fbd4fcefc476ce0db52`。


这三个修正尚未取得新 verbose 退出日志；不能提前宣称 99 个 ObjectDB 或 42 个 Resource 已清零。Resource 和 StringName 留存也尚未全部归因：verbose 中大量仍在使用的对象来自预加载的 Hangar GDScript / `demo_catalog_bundle.tres` 及其内嵌资源，必须在 Node 修复后重新观察，不能仅凭名字列表将其认定为永久泄漏或全部判作引擎正常缓存。

### 当前代码批次

在上述代码更改后，分支后续提交包括：

- `3bd18b384ab1e5430aea449dc641892ac4d6816e`
- `296fcc071580a4d74ced06835b27e85ccbe6aca4`
- `2f88ade03c4248aaef96530e97934fe0a995cdc1`
- `e57da5091e2ebfe8532dcb3e022211fef26830a6`
- `9f0cda14c5a70c595095a56bbacb5a7c1694ac0f`

新代码没有用户本地复跑结果，当前不能标记跨仓库验证通过。

### 下一步集中验证

只需拉取 Space 分支；Core 继续固定到精确 SHA `391f318a24fde724a66054e771d0590f0e20c231`，不重复运行 Core 的 1038 项 xUnit。

设置 `GODOT_VERBOSE=1` 并重跑完整脚本。关键验收点：

1. battle-navigation 输出 `passed terminal-menu-transition=true`，且不再有 `data.tree is null` / `SCRIPT ERROR`。
2. Domain contracts 与 Parser ingress 中 3 个无路径 Node、对应 3 条 `get_path` 错误消失。
3. Buff 修正器绑定警告仍然消失，增强的 Buff/StatCalculator 状态、幂等及到期撤销断言通过。
4. 继续记录 ObjectDB / Resource / StringName 数量与具体资源清单；只有证据充分时才关闭泄漏项。
5. 以最终 `CROSS-REPO-WORLD-V2-OK` 和脚本退出码作为联合验证完成条件。

桌面 GUI 的主菜单/机库/战斗/暂停/恢复/故障退出仍须单独手工验收。


## 九、2026-11-26 本地复跑：Progression Probe 类型推断阻断领域契约

### 运行证据

用户再次执行 `verify-world-v2-cross-repo.sh`，Core 固定在 `391f318a24fde724a66054e771d0590f0e20c231`，`GODOT_VERBOSE=1`。

本次确认：

- Core World V2 Bridge 构建成功。
- Space .NET 构建成功。
- Godot 4.7.1 项目初始化、类注册与 Editor import 阶段完成。
- HUD：`21 checks, 0 failures`。
- 随后的 Domain contracts 进程未通过，完整跨仓库脚本没有到达最终 `CROSS-REPO-WORLD-V2-OK`。
- 这份日志没有打印 Space `git rev-parse HEAD`，因此不能把用户当次运行绑定到某个精确 Space commit SHA；只记录本次实际报错和随后提交的修复。

### 第一个真实失败

Godot 在加载 `SpaceDemoProgressionBootstrapProbe.gd` 时报告：

```
Parse Error: Cannot infer the type of "valid_selection" variable because the value doesn't have a set type.
SpaceDemoProgressionBootstrapProbe.gd:108
```

原因是 `valid_selection` 由包含 Dictionary.get / Variant 返回值的逻辑表达式构成，使用 `:=` 让 GDScript 推断局部变量类型，无法得到确定类型。

### 后续错误的边界

之后 `SpaceHangarCatalogOwnershipProbe.gd:707` 报告：

```
Invalid call. Nonexistent function 'run' in base 'GDScript'.
```

该调用位于 `SpaceDemoProgressionBootstrapProbe.run()`。因为目标脚本此前已经解析失败，后续类方法调用也失去了可用的脚本方法表；当前把它记录为**首个解析错误之后出现的级联故障**，而不是另行改写静态类调用来绕开源头。修复后必须由新的 Godot 运行确认该调用自然恢复。

日志中的 Board Assignment fingerprint、Workshop role、revision、bundle validation 与 field-only assembly 拒绝均有相应的 `tamper-rejection=passed`、`bundle-and-inventory-fail-closed=passed`、`field-only-assembly-rejected=passed` 等契约标记。这些是负向测试主动构造的拒绝结果，不应误判为本轮首个失败。

### 修正

提交 `6ab8d8118ae84589ef58fbed7da3c1b7e7e004c7`：

- 显式将 `skillSelections` 与 `boardAssignments` 读入 `Array` 局部变量。
- 将 `valid_selection` 显式声明为 `bool`。
- 数组长度断言改为访问已明确类型化的数组。
- 没有降低 GDScript warning/error 强度，没有修改生产机库或 Board Assignment 规则。

### 当前验证状态与下一步

本补丁尚无新的本地 Godot import/parse/Headless 运行结果，也没有新的完整脚本退出码。下一次只需重跑 Space 联合脚本，Core 仍固定在上述 SHA，不重复执行 Core 的 1038 项 xUnit。

重点检查：

1. `SpaceDemoProgressionBootstrapProbe.gd` 不再出现 `valid_selection` 类型推断解析错误。
2. `SpaceHangarCatalogOwnershipProbe.gd` 能正常调用 `SpaceDemoProgressionBootstrapProbe.run()`，并继续到后续 Roguelike probe。
3. Domain contracts 输出其最终通过标记，Parser ingress 与后续 Runtime / Lifecycle / Navigation 探针继续完成。
4. Verbose 下检查 Node / ObjectDB / Resource / StringName 退出诊断；当前日志未提供足以更新上节泄漏结论的新归因证据。
5. 只有完整脚本退出码为 0 且输出 `CROSS-REPO-WORLD-V2-OK` 才能关闭本轮联合验证。


## 十、复跑确认选择字段的实际类型，并追踪最后一个 leaked Node

### 新运行结果

用户再次运行联合脚本后：

- Core Bridge 构建成功。
- Space .NET 构建成功。
- Godot Editor import / class registration 成功。
- HUD：`21 checks, 0 failures`。
- 前一轮的 `valid_selection` 类型推断解析错误已消失。
- `SpaceDemoProgressionBootstrapProbe.run()` 已执行到默认 Owned Loadout 装配 helper。
- 本次首个脚本运行错误是把 `boardAssignments` 的 Dictionary 赋给 Array：
  ```
  Trying to assign value of type 'Dictionary' to a variable of type 'Array'.
  SpaceDemoProgressionBootstrapProbe.gd:108
  ```

### 类型事实与修正

检查 `SpaceHangarSelectionController.get_view_model()`、`SpaceHangarSelectionDraft.snapshot_data()` 和 Board Assignment 构造路径后，实际结构为：

- `skillSelections`：Array，逐项记录 skill/order 选择。
- `boardAssignments`：Dictionary，以 Board Slot ID 为 key，value 为该槽位的冻结 Assignment entry。

已在提交 `4c718904204aa9b0add63a85a5998de7cd17ed96` 修正：

```gdscript
var skill_selections: Array = selection.get("skillSelections", [])
var board_assignments: Dictionary = selection.get("boardAssignments", {})
```

验证条件仍然只检查两项 skill 和至少五个 board assignment；没有改变装配规则或运行时选择内容。

### 剩余 Node 泄漏与本次错误的关系

本次 verbose Domain contracts 退出只列出一个 `Leaked instance: Node:`，且同时出现：

```
Cannot get path of node as it is not in a scene tree.
56 ObjectDB instances were leaked at exit
42 resources still in use at exit
263 unclaimed string names at exit
```

`_build_default_owned_loadout()` 在此错误之前已经创建 `SpaceHangarPreparation.new()`，而释放语句 `preparation.free()` 位于出错赋值之后。GDScript 执行在该行中止，因此该 Node 没有走到释放语句。这个调用栈与“恰好一个无 SceneTree path 的 leaked Node”相吻合，是当前最强的根因解释；修正字段类型后，预期 helper 能执行到 controller 解除引用与 preparation.free()。这仍需新 verbose 运行确认，不能提前标记 Node 泄漏已清除。

ObjectDB / Resource / StringName 总数也会因探针在中途退出而受到影响。本次没有足够依据把剩余 GDScript、资源子资源和 StringName 报告全部归为独立的永久泄漏；必须先让完整 Domain probe 跑完，再比较最终退出清单。不得通过禁用 verbose 或放松 Node 泄漏门禁绕过问题。

### 下一步

下一次运行需确认：

1. `boardAssignments` 类型赋值错误消失。
2. `SpaceDemoProgressionBootstrapProbe` 输出 `default-owned-hangar-assembly=passed`、`legacy-loadout-polarity-migration=passed`、`unknown-legacy-liquid-mapping=fail-closed`。
3. Domain contracts 继续到最终 `all-domain-contracts=passed`。
4. verbose 清单中不再有 `Leaked instance: Node:`，且不再有 detached Node 的 `get_path` 错误。
5. 再依据完整运行的 ObjectDB / Resource / StringName 清单继续归因。
6. 通过 Domain 后继续完整脚本所有后续探针，最终以退出码 0 和 `CROSS-REPO-WORLD-V2-OK` 为联合验证完成条件。

当前代码修正提交：`4c718904204aa9b0add63a85a5998de7cd17ed96`。该提交尚无新的本地运行结果。
