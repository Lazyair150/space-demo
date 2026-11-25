# 2026-11-25 Space / Jar Core 收敛协作记录

## 当前 Space 基线
- PR #2：Draft/Open，尚未合并。
- 基线 head：`5a03c259f733eb1ef9f06439ff8f0a805d8e42c0`。
- Core 集成采用 sibling ProjectReference：
  `../jar-system-dotnet/hosts/godot/WorldV2Bridge/JarSystem.WorldV2Bridge.csproj`。
- CI 通过 MSBuild 属性 `JarSystemWorldV2BridgeProject` 覆盖该引用。

## 发现
- Space 的 WorldOptions 允许任意两个非空液体身份，并用这些身份作为库存/生产键。
- Core 当前候选实现仍将 `酒` / `蜜` 硬编码为 Cathode / Anode，且部分求解/规则路径枚举静态常量。
- 该错误发生于 Core 的液体身份与极性模型不通用，不应由 Space 添加名称别名解决。
- 资源名称属于 Space/World 配置；二元互斥极性属于 Core 领域结构；二者必须通过显式世界目录契约关联。

## 本次文档与工程设置
- 更新 Space 根 `.gitignore`，补充本机诊断/Profiler产物忽略规则。
- 新增本工作记录专区，正式工作记录保留在 Git。
- 未更改 Space 的 Core ProjectReference，待 Core 主线收敛后统一指向正式 Core 路径/版本。
- 未关闭或删除 PR #2；其仍包含机库与战斗 UI 代码。

## 尚未完成
- Core 二元液体目录与极性上下文 API。
- Core 主线 PR 收敛及旧堆叠 PR 清理。
- Space 的 Core pin / ProjectReference 正式版本策略。
- Space 与 Core 完整 CI、Headless 和本地 GUI 回归。

## 截图故障的实际定位与修正

- 玩家战斗运行时出现 `Liquid has no registered Jar polarity: 燃料`。
- 追查到 `data/hangar/demo_catalog_bundle.tres` 中两个战斗世界都声明了 `liquids = [冷却液, 燃料]`，但没有任何身份→极性映射；Core 旧实现只认识硬编码的 `酒/蜜`。
- 已在两个战斗世界显式声明：
  - `冷却液` → `Cathode`
  - `燃料` → `Anode`
- Space 的 `SpaceJarWorldResourceProfile` 现在要求两种液体都有显式且一一对应的极性映射；自定义身份不得从名称或数组顺序猜测。
- 冻结战斗 Loadout schema 升为 3；对 schema 2 仅提供一条严格迁移：只有确切的旧 Space 身份集合 `{冷却液, 燃料}` 才能补上上述映射，其他自定义身份拒绝自动猜测。
- 新增 Probe：校验自定义映射保留、缺失映射拒绝、默认装配成功，并验证 schema 2 的精确迁移。
- 相关 Space commits：`851a0c9d20374a99c90bdfcb801dd83181c08813`（demo worlds）、`c74c29b96c46b800389bbd0a1d0229f123b7ef53`（frozen loadout validation）、`03b8b1dcbee4b3f42058801dd7ec7d5f730f4631`（schema migration）、`4f5a84ebf63b96be0f1f2e9b29f4fcfd87677aab` / `f5fdffe9e958422f0c3c6612b22d75ead3ae5561`（regression probes）。
- 以上提交仍待 Space 跨仓库 CI 以整合后的 Core 精确 SHA 验证；尚不标记为运行通过。


## 2026-11-25 第三轮：Space 配置回归与 Core fixture 联动

- Space CI run 45576616148 对提交 f704d730bd609373edcf0bb712578b3eda59f8de 成功。
- 失败 run 45575852409 的真实失败原因是 SpaceOreParserCatalogProbe 的合成 loadout fixture 仍使用旧的酒/蜜液体集合，却未声明 liquidPolarities；这不是生产目录 bundle 的配置错误。
- 已为该合成 fixture 明确增加 酒→Cathode、蜜→Anode，提交 f704d730bd609373edcf0bb712578b3eda59f8de；随后 run 45576616148 通过。
- 此成功仅证明 Space 当前分支的 Godot CI/Headless 合约验证通过；不代表本地 GUI 试玩通过，也不代表它已使用 Core 整合分支的最新 DLL/桥接项目。
- 仍需在 Core PR #63 形成可用且通过 CI 的 head 后，确认 Space 的 ProjectReference/CI 属性实际指向该 Core 版本，再跑跨仓库验证。


## 2026-11-25 第四轮：切换到统一 Jar Core World V2 源

- Space PR #2 当前代码 head：`a8daee73df55bf30125960a9a6231ea93e706d4f`。
- Space 继续使用 sibling ProjectReference：`../jar-system-dotnet/hosts/godot/WorldV2Bridge/JarSystem.WorldV2Bridge.csproj`，不再复制 Core 实现。
- Core 整合分支 `architecture/core-liquid-identity-consolidation` 的生产代码 head `fd0b3761babe3af7f7d770483004ef1a454021f8` 已取得两个精确 verify run SUCCESS：`45587631031`、`45587642292`。
- 已更新 `.github/workflows/world-v2-cross-repo.yml` 的 checkout ref 与 `CORE_EXPECTED_SHA`，两者均固定为该 Core SHA；workflow 更新提交：`8675ea9beb9ad83c77d8fa55101a9d66bef12c5b`。
- 已更新 `docs/execution/2026-11-24-cross-repo-integration.txt`，明确旧 Core pin `b342259fe04363386085dc9a4ca995112954ed43` 的历史成功不能替代新 Core 验证。
- 新跨仓库 workflow run `45588333902` 正在执行；等待 Godot 4.7.1 .NET 下载、Core Bridge / Space 构建、项目导入及全部运行时 probes 完成。
- 该 CI 只提供 Headless 自动化证据；本地 GUI 试玩、视觉验收和目标 GPU 行为仍需用户机器确认。


## 2026-11-25 第五轮：固定到 Core PR #63 最新绿色精确 head

- Core PR #63 最新 head `5023b38b75ad4cf66d953e3bb3fa4c490076d4d7` 的两个 exact-head verify runs `45588065611` / `45588076128` 均 SUCCESS；包含 854 项基础回归、World 单一词表约束、checkpoint schema v3 以及旧 schema v2 拒绝测试。
- 将 Space cross-repo workflow 的 Core checkout ref 与 `CORE_EXPECTED_SHA` 从 `fd0b3761babe3af7f7d770483004ef1a454021f8` 更新到 `5023b38b75ad4cf66d953e3bb3fa4c490076d4d7`。
- 同步更新当前集成说明中的 Core source pin。旧 Core pin `b342259fe04363386085dc9a4ca995112954ed43` 的成功 run 仅保留为历史证据，不再作为本轮验收依据。
- 本次工作流与文档合并为一个提交；新 Space cross-repo run 的结果待执行。
