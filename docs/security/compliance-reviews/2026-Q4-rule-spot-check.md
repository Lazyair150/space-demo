# 2026-Q4 规则符合性抽查

- 抽查日期：2026-11-27
- 抽查人：仓库维护者（GitHub `Lazyair150`）
- 抽查对象：`space-demo` @ `155034f`（分支 `world-v2/phase-4.10b-hangar-ui`），
  依赖 Core `jar-system-dotnet` @ `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`
- 下次到期：2027-Q1

## 抽查范围与方法

1. 规则清单逐条复核：对照 `docs/security/security-architecture.md` 的 ASVS 适用子集与
   已知缺口表，确认每条声明仍能被当前代码/脚本支撑。
2. 实际命令复核（不是只看文档）：
   - 干净检出验证：`git clone` 到空目录 + 兄弟仓库 clone 到固定 SHA，跑
     `scripts/ci/verify-world-v2-cross-repo.sh` → exit 0，`CROSS-REPO-WORLD-V2-OK`。
   - 上传面检索：`grep -rn "HTTPRequest|HTTPClient|WebSocket|WebSocketPeer|TCPServer|PacketPeerUDP|FileDialog|OS\.shell_open"` → 0 命中。
   - 文件写入检索：`grep -rn "FileAccess.open(" scripts` → 仅 3 处，全部指向 `user://`
     下的存档/探针路径，无用户可控路径拼接，无执行路径复用。
3. 自动检查误报复核。

## 本次结论

| 项 | 状态 |
| --- | --- |
| 干净环境可构建、可启动 | 通过（干净检出实测） |
| 失败关闭（不回退 Sandbox、检查点拒绝保留旧档） | 通过（代码 + 探针断言） |
| 外部输入不信任（存档/检查点 JSON 校验 + 数字规范化） | 通过（`SpaceJsonNumberCanonicalizer` + 两进程探针） |
| 文件上传校验（E-07） | 不适用：无上传面，检索 0 命中 |
| 告警通道与责任人（H-04） | 已建立（故障面板 + CI 阻断 + 维护者 on-call） |
| 事件响应流程（H-05） | 已建立（`docs/security/incident-response.md`） |
| SBOM / cosign 签名 | 未落实（无发布产物，列入缺口） |
| SLSA Build L3 | 未落实（CI 构建无签名、无隔离证明，列入缺口） |
| 渗透测试 / 红蓝对抗（I-06） | 未落实（单人原型阶段） |

## 自动检查误报

评审工具的 J-04 自动检查报「检测到要产出安装包，但没有找到 package.json」。
复核结果：仓库根无 `export_presets.cfg`、无 `dist/`、无任何打包脚本，`space-demo.csproj`
只是 Godot .NET 的编译项目，不产出安装包。该检查把 .csproj/构建产物误判为 npm 分发包。
处理：不伪造 `package.json`，在此留档，等待工具豁免由项目所有者决定。

## 本次新增/变更的规则文档

- `docs/security/security-architecture.md`：新增第 12（告警通道与责任人）、13（事件响应
  摘要）、14（季度抽查）节。
- `docs/security/incident-response.md`：新建。
