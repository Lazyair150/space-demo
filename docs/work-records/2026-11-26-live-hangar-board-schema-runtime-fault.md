# 2026-11-26 真实 Hangar Board 身份校验故障

## 用户现场证据

Godot 4.7.1 桌面运行后，Hangar 选择器日志显示：

```text
[HangarDiag] screen ready ... connected=true item_count=1
```

点击建造后，调用链进入：

```text
SpaceHangarScreen._on_build_pressed
  -> SpaceHangarBattleLauncher.launch_new_battle
  -> Game._ready
  -> Game._begin_ship_world
  -> WorldV2ShipHost.BeginShipWorldFromJson
  -> WorldV2RuntimeNode.InitializeWorldFromJson
  -> Core WorldV2Options.Validate
```

Core 拒绝配置，Game 随后终止战斗初始化并显示 BATTLE FAULT。由此可排除“单选项 OptionButton 没触发”和“按钮没有进入启动流程”这两个猜测。故障发生在 World 配置 ingress，不是战斗 UI 或暂停层。

## 已核实的版本契约

Space 的 `SpaceHangarBoardDefinition.build_frozen_snapshot()` 当前输出：

- Board Definition `schemaVersion = 2`
- 生产区解析器槽位使用 `areaId = production`、`subAreaId = decomposition`

Assignment Snapshot 本身仍使用 schema 1。其内嵌 Board Definition schema 2 是合法的版本组合。

Core 旧校验曾把 `BoardDefinition.SchemaVersion != 1` 归入统一的错误：

```text
boardRuleProfile assignment snapshot identity does not match its frozen Board
```

因此这条错误文本不能证明 BoardId、DefinitionVersion 或 fingerprint 真的不一致；它也可能只是内嵌 Board Definition schema 不受支持。

## Core 修复与验证证据

Core 修复：
- `de95fe80012f0c7b9abb7b50c3de9f01e3d587cb`：Board Definition schema 接受 1 或 2；Assignment Snapshot 仍严格要求 schema 1。
- `bc5e642020852b38f6e03a84b4585241da502e60`：增加 schema 1 Assignment Snapshot 内嵌 schema 2 Board Definition 的正向测试。
- 后续测试夹具排序修复与工作记录更新进入 Core 当前集成头 `a19ac237673233cd5d43ba6acd67bffd3c4adac3`。

Core 精确头验证：
- Workflow run `45851900079`：SUCCESS。
- 该头包含 schema 2 兼容修复及测试夹具按稳定 SlotId 排序后再计算 fingerprint 的修正。

另一个较早的 Core run `45850044366` 失败原因是新测试夹具未按稳定 SlotId 排序，不是生产校验逻辑失败；该夹具问题已在后续提交修正，不能把较早失败当作当前头状态。

## 对本次桌面日志的结论边界

用户本次仅提供了 Godot 运行日志，没有提供本地 Core HEAD、Bridge 实际构建来源或运行时冻结 JSON。因此当前可确定：
- 真实启动链已经运行到 Core World 配置校验。
- Space 产生的 Board Definition schema 2 是当前源码设计。
- 远端 Core 已有 schema 2 兼容实现，并在精确头验证通过。

当前不能仅凭统一错误文本断言本次唯一原因一定是本地旧 DLL。若本地实际加载的 Bridge 仍来自旧 Core，schema 2 会触发该错误；若已加载修复版 Core，则必须继续检查 BoardId、DefinitionVersion、AssignmentFingerprint、内嵌 BoardDefinition 身份及 DisplayName 的实际值。

## 本地复验步骤

关闭 Godot 后，在 PowerShell 中先将 Core 更新到已验证的精确头：

```powershell
cd D:\godot\programs\jar-system-dotnet
git switch architecture/core-liquid-identity-consolidation
git pull --ff-only
git checkout a19ac237673233cd5d43ba6acd67bffd3c4adac3
git rev-parse HEAD
```

然后在 Space 仓库执行精确依赖构建与集成验证：

```powershell
cd D:\godot\programs\space-demo
git switch world-v2/phase-4.10b-hangar-ui
git pull --ff-only

$env:CORE_REPO_DIR = "D:\godot\programs\jar-system-dotnet"
$env:CORE_EXPECTED_SHA = "a19ac237673233cd5d43ba6acd67bffd3c4adac3"
$env:GODOT_BIN = "godot"
$env:GODOT_VERBOSE = "1"
bash .\scripts\ci\verify-world-v2-cross-repo.sh
```

脚本成功后，再启动桌面项目复验 Hangar → 建造 → 进入战斗。若仍出现同一错误，下一步应在 Core ingress 输出各 identity 字段及独立校验失败项；不得放宽 Board 身份或 fingerprint 校验。

## 验收状态

- Core schema 兼容修复：已提交。
- Core 精确头 CI：已通过。
- Space 跨仓库构建/探针使用该精确 Core 头：待本地执行。
- 桌面 Hangar 实际进入战斗：待复验。
