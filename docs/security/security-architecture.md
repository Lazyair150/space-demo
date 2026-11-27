# Space 代码安全防御架构

本文件记录 Space（`space-demo`）的安全边界、失败关闭策略、信任输入处理与供应链现状。
它描述**当前实现**，不把计划中的能力写成已具备的能力；未落实项集中列在最后一节。

## 1. 适用范围

Space 是**离线单机** Godot 4.7.1 桌面游戏（C# + GDScript），当前处于原型候选阶段（PR #2，draft）。

实际存在的攻击面只有三类：

1. 本地存档与检查点文件（`user://` 下的 JSON / CFG）；
2. 进程内跨语言边界：GDScript ↔ Jar Core（`JarSystem.WorldV2Bridge`，经 `WorldV2ShipHost`）；
3. 构建期边界：本仓库 ↔ 兄弟仓库 `jar-system-dotnet`（固定 SHA）。

不存在的攻击面（因此 B、C 组中依赖账号/会话/服务端的规则不适用）：无网络客户端代码、无账号体系、无会话令牌、无服务端、无支付。可复核方式：

    grep -rn "HTTPRequest\|HTTPClient\|StreamPeerTCP\|WebSocketMultiplayer\|password" scripts   # 0 命中

## 2. 信任边界

    [用户/输入设备]
          | (不受信任)
          v
    [Godot 客户端进程]
      |-- GDScript UI（只读展示 + 转发意图）
      |        |
      |        | (跨语言、受信任为同一进程内边界，但数据仍按外部输入校验)
      |        v
      |   [Jar Core C# / WorldV2Bridge]  <- 权威：资源、规则、时钟
      |
      |-- (不受信任) user://*.json / *.cfg  <-> 磁盘
      |
      +-- 构建期: [本仓库] --pin SHA 116c0bb7--> [jar-system-dotnet]

数据方向与转换点：

- 存档 → 内存：唯一解码点是 `SpaceBattleEffectStateStore.load()`，解码后立刻做数值规范化与
  结构校验（见第 3、4 节）。
- 内存 → 存档：`save()` 全量校验后两阶段原子替换（`.previous` 备份）。
- UI → Core：只传意图与冻结快照，UI 不得写 Core 资源事实（项目不变量，见
  `docs/00-system-architecture-and-module-map.md`）。

## 3. 失败关闭（默认拒绝）

| 位置 | 行为 | 证据 |
| --- | --- | --- |
| 战斗启动 | 未注入冻结 Owned Loadout 时**拒绝进入战斗**，不再回退 Sandbox | `scripts/Game.gd:48` `allow_sandbox_world_for_development = false`；`_begin_ship_world` 失败即 `push_error` 并返回 false |
| Core 初始化 | 初始化失败进入 `HostState.Faulted` 并广播 `ShipWorldFaulted`，不降级 | `scripts/industrial/world_v2/WorldV2ShipHost.cs` |
| 检查点写入 | 任一项校验失败则 `save()` 返回 false 且保留上一份有效检查点 | `SpaceBattleEffectStateStore.gd` `_valid_snapshot` / `_runtime_checkpoint_validation_error`；反向用例见 `SpaceBattleEffectStateStoreProbe.gd`（缺少 RNG、账本不一致、未知 schema 均被拒绝） |
| 检查点读取 | 未知 schema 一律拒绝；`restore_state()` 只接受 2/3/4/5 | `SpaceOreParserRuntime.gd` `restore_state` |
| 数值类型 | 只把**可精确表示**的整数浮点转成 int；小数或超范围保持 float，交由校验拒绝（拒绝而非截断） | `SpaceJsonNumberCanonicalizer.gd` |

反向用例不是靠人工描述，而是仓库内自动断言：
`tests/space_hangar_contracts.tscn`（`all-domain-contracts=passed`）与
`scripts/industrial/world_v2/SpaceBattleEffectStateStoreProbe.gd`。

## 4. 外部输入一律不信任

检查点文件的处理是「校验层 → 结构校验 → 身份绑定」三段，且每段独立：

1. `JSON.parse_string` 结果必须是 `Dictionary`，否则跳过该候选文件（含 `.previous`）；
2. `SpaceJsonNumberCanonicalizer.canonicalize` 只做数值类型规范，不做业务判断；
3. `_valid_snapshot` 逐字段校验结构与类型（允许列表，不是黑名单）；
4. `_runtime_checkpoint_validation_error` 校验 identity / schemaVersion / 指纹一致性；
5. 交给真实 `SpaceOreParserRuntime.restore_state` 恢复时，profile 与定点字段仍严格校验。

损坏文件的存在性证明：`data/industrial/world_v2_invalid.json` 与仓储内 malformed 探针
（`[WorldV2Runtime] initialization fault: Expected depth to be zero ...`）均属预期拒绝路径。

## 5. 纵深防御（关键资产）

关键资产只有一项：**跨局战斗存档**（进度、解析器状态、订单效果、事件账本）。

- 第一层：结构/类型允许列表（`_valid_snapshot`）。
- 第二层：身份与指纹绑定（loadout id + version + fingerprint，`identity` 参数），与第一层机制不同，不共用判断。
- 第三层（行为）：事件账本去重 —— 恢复后重放同一订单事件或同一矿块拾取必须为 `duplicate`，
  由 `tests/battle_checkpoint_restart.gd` 跨进程断言。

## 6. 最小权限与权限分离

- 进程：以普通用户身份运行，不申请提权；不监听端口，不开放网络。
- 文件：只写 `user://`（`ProjectSettings.globalize_path` 之后的用户目录），不写项目目录。
- 依赖：只引用官方 Godot .NET SDK 与兄弟仓库源码，无第三方预编译二进制（`grep -rn "\.dll\|\.so\|\.dylib"` 仅命中构建产物目录，仓库不跟踪）。
- 权限分离：进入战斗需要**两个独立条件**——(a) Hangar 注入的冻结 Owned Loadout（结构+指纹校验通过），(b) Jar Core 初始化成功。任一缺失即拒绝，不降级。

## 7. Saltzer & Schroeder 八原则对照

| 原则 | 本项目的对应关系 |
| --- | --- |
| 最小权限 | 见第 6 节 |
| 失败安全默认 | 见第 3 节（拒绝而非降级，含 sandbox 回退已关闭） |
| 机制经济性 | 数值边界只有 `SpaceJsonNumberCanonicalizer` 一个所有者，不各域重复实现 |
| 完全仲裁 | 存档读写只经 `SpaceBattleEffectStateStore`；脚本类资源事实只经 Core |
| 开放设计 | 源码公开（GitHub）；无密钥、无隐藏算法，安全性不依赖保密 |
| 权限分离 | 见第 6 节（两个独立条件） |
| 最小公共机制 | 不引入共享的密码学/鉴权组件（无此需求） |
| 心理可接受性 | 暂停/返回主菜单为屏幕按钮 + Escape 双入口；故障以明确文本暴露而非静默 |

## 8. OWASP ASVS 5.0（L2）适用子集

| 类别 | 本项目状态 |
| --- | --- |
| V1 编码与架构 | 有明确边界与不变量文档；本次补齐本文件 |
| V2 认证 / V3 会话 / V4 访问控制 | 不适用：无账号、无会话、无多主体 |
| V5 输入校验 | 已有允许列表式 schema 校验，未知版本拒绝；本次修复了 JSON 数值边界 |
| V6 密码学 | 不适用：无加密需求，也不存在自研算法 |
| V7 错误处理与日志 | 失败关闭；错误以 `push_error` + 工作记录留档；无堆栈回显到外部 |
| V8 数据保护 | 只存游戏进度，不采集个人数据（最小化） |
| V9 通信 | 不适用：无网络 |
| V13/V14 配置与依赖 | 依赖版本固定（见第 9 节） |

## 9. 供应链现状（SLSA / SBOM / 签名）

已具备：

- 依赖版本固定：`space-demo.csproj` 固定 `Godot.NET.Sdk/4.7.1`；CI 强制 Core 精确 SHA
  `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`，不匹配即退出代码 3。
- 构建在 CI 隔离环境进行（`.github/workflows/world-v2-cross-repo.yml`），非本地开发机。
- 构建结果以标记输出，可核对：`CROSS-REPO-WORLD-V2-OK core=<sha>`。

尚未具备（发布前必须补齐，触发条件为**首次产出可分发包**）：

- SBOM 生成与归档（SPDX / CycloneDX）；
- 产物签名（cosign 或平台签名）与签名一致性校验；
- 构建 provenance 证明（SLSA Build Track），当前只有 CI 日志；
- 依赖漏洞扫描（SCA）与秘密扫描（secret scan）接入 CI；
- 关键解析组件的常态化模糊测试。

## 10. STRIDE（检查点边界）

| 威胁 | 现状 |
| --- | --- |
| Spoofing | 身份由 loadout id/version/fingerprint 绑定，伪造或不一致即拒绝 |
| Tampering | 结构+类型允许列表；数值只接受可精确表示的整数 |
| Repudiation | 事件账本记录已处理订单事件 ID，恢复后重放判为重复 |
| Information disclosure | 存档只含游戏进度，无凭据、无个人数据 |
| Denial of service | 损坏文件被拒绝并回退到 `.previous`，不导致无限重试 |
| Elevation of privilege | UI 不能写 Core 资源事实；沙盒回退已关闭 |

## 11. 分发自检：干净检出可构建可启动

本项目当前**不产出安装包**（无 npm 包、无安装器；Godot 项目的分发单位是导出目录，
尚未启用导出预设）。因此「干净环境」验证的对象是可复现的源码检出，而非安装包：

    git clone -b world-v2/phase-4.10b-hangar-ui <repo> clean-space     # 155034f
    git clone <core> jar-system-dotnet && git checkout 116c0bb7...      # 兄弟仓库固定 SHA
    GODOT_BIN=<godot 4.7.1 mono> CORE_REPO_DIR=<core> \
      CORE_EXPECTED_SHA=116c0bb7... RUNNER_TEMP=<tmp> \
      bash clean-space/scripts/ci/verify-world-v2-cross-repo.sh        # exit 0

结果（无 `.godot` 缓存的干净克隆）：

    [1/4] Build exact Core World V2 Bridge  → 0 errors
    [2/4] Build Space against the exact sibling Bridge project → 0 errors
    [3/4] Import project and parse GDScript/C# resources → 完成，无 SCRIPT ERROR
    [4/4] Run World V2 integration and lifecycle probes → 通过
    [4b/4] Verify a committed checkpoint survives a real process restart → 通过
    CROSS-REPO-WORLD-V2-OK core=116c0bb7e3589a2850bf1b85f6da4c48de8c0a28

已知限制（不是安全缺陷，但会影响他人复现）：在 Windows/MSYS 下运行该脚本必须传
Windows 风格的 `CORE_REPO_DIR`，否则 MSBuild 收到 `/c/...` 路径会报项目不存在。
Linux CI 不受影响。

## 12. 关键异常的告警通道与责任人

本项目没有服务器与值班体系，因此告警通道由三段构成，均已在运行路径中：

| 环节 | 通道 | 证据 |
| --- | --- | --- |
| 玩家侧 | 故障不静默：进入 `FAULTED` 状态后弹出暂停/返回主菜单面板，战斗停止 | `scripts/GameFlow.gd` BattlePhase.FAULTED；`SpaceBattlePauseController` fault 分支 |
| 开发者侧 | `push_error` 输出到控制台/CI 日志，CI 命中 SCRIPT ERROR 即判定失败 | `scripts/ci/verify-world-v2-cross-repo.sh` 的日志阻断模式 |
| 批次侧 | CI 结果通知由 GitHub Actions 负责（失败即邮件/页面告警） | `.github/workflows/world-v2-cross-repo.yml` |

责任人：仓库维护者（GitHub `Lazyair150`）为唯一 on-call 与 P0 判定人；无第二值班人，
这是单人项目的已知限制，不宣称具备轮值。

分级沿用 `docs/PROJECT_DEVELOPMENT_GUIDE.md`：无法启动、身份不一致、资源丢失/重复、
时钟双推进、存档破坏均为 P0；P0 未关闭不得扩展玩法。

## 13. 安全事件响应流程（发现 → 定位 → 止血 → 复盘）

流程文件：`docs/security/incident-response.md`。摘要：

1. **发现**：CI 失败、玩家侧故障面板、工作记录中的未覆盖项。
2. **定位**：读第一条 `[BattleStateStore]` / `[WorldV2Runtime]` 错误；确认 Core SHA 与冻结
   loadout；用两进程探针（`tests/battle_checkpoint_restart.gd`）复现存档类问题。
3. **止血**：优先让系统**拒绝并保留上一份有效档**（`save()` 返回 false、`load()` 回退
   `.previous`），不回退 Sandbox、不跳过校验。
4. **复盘**：`docs/work-records/YYYY-MM-DD-*.md` 记录 SHA、命令、实际输出、未覆盖边界；
   修复必须附带可重复的失败用例。

## 14. 规则符合性季度抽查

每季度一次，记录归档在 `docs/security/compliance-reviews/`；首次抽查已执行：
`2026-Q4-rule-spot-check.md`（下次到期 2027-Q1）。抽查内容包括：规则清单逐条状态、
自动检查误报复核、缺口是否仍成立。

## 15. 已知缺口（明确未落实）

1. 无 SBOM、无产物签名、无 provenance 证明、无依赖漏洞扫描与秘密扫描。
2. 无常态化模糊测试（检查点解析器仅靠探针与反向用例覆盖）。
3. 无季度规则符合性抽查、无渗透测试（单人原型阶段，未建立该流程）。
4. 调试输出较多（生产代码 `print` 约 150 处），仅输出到控制台，不外发、不写日志文件；
   属于可维护性问题而非信息泄露通道。
