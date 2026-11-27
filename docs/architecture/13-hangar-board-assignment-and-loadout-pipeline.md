# Hangar、Board Assignment 与冻结装配流水线

## 1. 目标与边界

Hangar 的职责是把玩家选择转换成一个不可变、可验证的战斗 Loadout。它不执行 Jar 规则，不求解订单，也不创建 Core 资源事实。

主要入口：
- `SpaceHangarBoardDefinition`：Board 和 Slot 的版本化位置定义。
- `SpaceHangarSelectionDraft`：玩家当前安装关系。
- `SpaceHangarBoardAssignment`：创建、验证、冻结 Assignment Snapshot。
- `SpaceHangarOwnedLoadoutAssembler`：按 exact Definition + Owned Instance 装配。
- `SpaceRuleContributionResolver`：从已安装组件解析 Core-facing contribution。
- `SpaceBattleLoadoutSnapshot`：最终不可变快照。
- `SpaceHangarBattleLauncher`：在 SceneTree attachment 前注入 Game。

## 2. Board 与 Assignment 是两种不同事实

Board Definition 只描述位置：Slot ID、Area、SubArea、Component Kind、角色/控制区域、Required。它不拥有玩家组件。

Assignment 描述玩家把哪个 Owned Instance 安装到哪个 Slot。Assignment 必须保留：
- Slot ID；
- Area ID / SubArea ID；
- Component Kind；
- Owned Instance ID；
- Definition ID / Version；
- Source Progression Revision；
- Workshop Role 或 Skill Control Area（按类型）。

Master/Slave 是 Board Slot 角色。Workshop 个体的 marks、Ban、容量和成长不因安装位置而变成其固有角色。

## 3. 冻结流水线

```text
Board Resource + Catalog Bundle + Player Progression
                    |
                    v
             Selection Draft
                    |
                    v
        Board Assignment Snapshot
                    |
                    +----> Rule Contribution Resolver
                    |                |
                    |                v
                    |         Board Rule Profile
                    |
                    +----> Runtime Profile Set
                    |
                    v
          Owned Loadout Assembler
                    |
                    v
        SpaceBattleLoadoutSnapshot
                    |
                    v
        Game.configure_battle_loadout
                    |
                    v
        Game._begin_ship_world
                    |
                    v
        WorldV2ShipHost.BeginShipWorldFromJson
```

所有步骤都必须在进入战斗 SceneTree 前完成。任一校验失败返回明确拒绝，不允许生成半冻结 Loadout。

## 4. Assignment Snapshot schema

### schema 1
保留早期字段集合：Board identity、冻结 Board Definition、assignment entries（不包含每项 Area/SubArea）。仅用于兼容旧快照。

### schema 2（当前 Space producer）
- 外层 `schemaVersion = 2`。
- 每个 assignment entry 显式包含 `areaId` 与 `subAreaId`。
- Board Definition 也带有 schemaVersion、Board ID、Definition Version 和 slots。
- Assignment 数组按稳定 `slotId` ordinal 顺序排序。
- Fingerprint 覆盖 schema、Board identity、完整 frozen Board Definition 和完整 assignment entries；schema 2 的 Area/SubArea 必须参与哈希。

schema 2 不得被降级成 schema 1，也不得丢弃 Area/SubArea。Core 消费端必须按 schema 2 的字段集合验证和计算相同 fingerprint；schema 1 的既有哈希形状保持兼容。

## 5. 跨语言 fingerprint 契约

两端必须一致：
1. 属性名使用 JSON 协议名（camelCase）。
2. 属性序列和数组顺序固定。
3. Assignment 数组按 `slotId` 的 ordinal 排序。
4. schema 2 的 assignment entry 顺序为 `slotId, areaId, subAreaId, componentKind, ownedInstanceId, definitionId, definitionVersion, sourceRevision`，再按类型附加 `roleId` 或 `controlArea`。
5. Board Slot 序列由 Board Definition 的稳定声明顺序决定。
6. 字符串 UTF-8；数值按 JSON 整数表达；不允许一端忽略另一端纳入哈希的字段。

任何字段、默认值、排序或 schema 改动必须同步 Core DTO、fingerprint writer、Space producer、固定 golden vector、跨仓库 probe 和本文件。

## 6. 当前 P0 故障与修复

桌面运行日志中的 `boardRuleProfile assignment snapshot identity does not match its frozen Board` 不是 OptionButton 选择问题。实际 Hangar 已进入 launch 路径，Core 在 World Options ingress 拒绝配置。

根因：Space `SpaceHangarBoardAssignment.build_snapshot()` 输出外层 Assignment schema 2；Core 之前仅接受外层 schema 1。上一轮只放开了内嵌 Board Definition schema 2，遗漏了外层版本。

Core 修复已按以下契约实现（精确代码/测试 SHA 与 CI 证据见工作记录）：
- 接受 Assignment schema 1/2；
- DTO 映射 AreaId/SubAreaId；
- schema 2 校验 Assignment Area/SubArea 与对应 Board Slot 相同；
- schema 2 fingerprint 纳入这两个字段；
- schema 1 fingerprint 维持原形状；
- 把综合身份错误拆成独立可诊断错误。

Core 代码提交与 CI 状态记录在 Core 仓库的 `docs/work-records/2026-11-27-board-assignment-schema-v2-ingress-fix.md`；Space 侧现场记录位于本仓库 `docs/work-records/`。两个仓库各自维护记录，不使用跨仓库相对链接。

## 7. 失败诊断要求

错误必须分别指出：
- 外层 Assignment schema 不支持；
- Board ID 不一致；
- Definition Version 不一致；
- Assignment Fingerprint 与 Rule Profile 不一致；
- 内嵌 Board identity/schema/displayName 不合法；
- Slot 不存在或重复；
- Owned Instance 不匹配；
- Definition/Version 或 Source Revision 不匹配；
- Area/SubArea 与 Slot 不匹配；
- assignment 顺序不符合稳定 Slot ID 规范；
- canonical fingerprint 不匹配。

禁止把所有情况折叠成“identity mismatch”。

## 8. 验证

- Core xUnit：schema1 compatibility、schema2 success、schema2 hierarchy mismatch、unsupported schema diagnostics、fingerprint golden vector。
- Space Hangar domain probe：Board/Assignment/Owned Instance mapping。
- Cross-repo probe：使用真实 schema2 JSON 通过 Core World Options ingress。
- Desktop GUI：默认 Hangar 配置 → Build → 进入战斗。
