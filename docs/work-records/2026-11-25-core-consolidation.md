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
