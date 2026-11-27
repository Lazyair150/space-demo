# Space 安全事件响应流程

适用范围：本仓库（`space-demo`）在开发、构建与试玩过程中出现的安全相关或 P0 级故障。
单人原型阶段，流程以「可重复、可留档」为准，不设轮值。

## 角色

| 角色 | 承担者 | 职责 |
| --- | --- | --- |
| 事件责任人 | 仓库维护者（GitHub `Lazyair150`） | 判定等级、决定止血方式、签署复盘 |
| 复核人 | 无（单人项目，已知限制） | 由 PR 评审代替：改动经 PR #2 承载 |

## 触发条件

1. CI 失败（`world-v2-cross-repo.yml` 任一探针未输出期望标记）。
2. 玩家侧出现故障面板（`GameFlow` 进入 `FAULTED`）。
3. 工作记录或复查中发现「未覆盖项」被证伪。
4. `docs/PROJECT_DEVELOPMENT_GUIDE.md` 定义的 P0：无法启动、身份不一致、资源丢失或重复、
   时钟双推进、存档破坏。

## 第一步：发现与登记

- 记录时间、commit SHA、Jar Core 精确 SHA、引擎版本、操作系统与显卡驱动。
- 保存第一条错误原文，不先做归因。

## 第二步：定位

1. 读第一条错误：`[BattleStateStore]`（存档/检查点）或 `[WorldV2Runtime]`（Core 侧）。
2. 核对 Core SHA 是否为 CI 固定的那个；不一致先停下，不算复现。
3. 存档类问题用两进程探针复现：

       godot --headless --path . --scene res://tests/battle_checkpoint_restart.tscn \
         --quit-after 180 -- --mode=write
       godot --headless --path . --scene res://tests/battle_checkpoint_restart.tscn \
         --quit-after 180 -- --mode=restore

4. 能把问题写成一条失败断言，才算定位完成；否则只登记为「未定位」。

## 第三步：止血

原则是**拒绝而不是降级**：

- 检查点不可信：`save()` 返回 false 并保留上一份有效存档；`load()` 回退 `.previous`。
- Core 初始化失败：进入 `Faulted`，战斗不启动，不回退 Sandbox。
- 不允许为了「先能玩」而临时放宽校验。确需临时绕过时，登记为临时方案并写明移除条件。

## 第四步：修复与验证

- 先写可重复的失败用例，再改实现；用例留在仓库，不作为一次性脚本删除。
- 验证必须分层陈述：Godot 导入/解析、headless 场景探针、.NET 构建、桌面 GUI 试玩，
  四者不可互相替代。

## 第五步：复盘与留档

- 写入 `docs/work-records/YYYY-MM-DD-主题.md`，含：现象、根因（区分已证实与推断）、
  改动、验证命令与实际输出、仍未验证的边界。
- 更新 `docs/work-records/README.md` 索引。
- 若属于规则或流程变化，同步更新 `docs/security/security-architecture.md` 与季度抽查记录。

## 演练

本项目未做红蓝对抗或渗透测试（单人原型阶段，规则 I-06 属 L3）。替代做法是每季度抽查
（`docs/security/compliance-reviews/`）与每次修复附带的失败用例。
