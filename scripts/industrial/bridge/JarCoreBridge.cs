using System;
using System.Collections.Generic;
using System.Text.Json;
using Godot;
using JarSystem.Core.Abstractions;
using JarSystem.Core.Config;
using JarSystem.Core.Domain;
using JarSystem.Core.Presentation;
using JarSystem.Core.Sessions;
using CoreSystem = JarSystem.Core.JarSystem;
using GodotDict = Godot.Collections.Dictionary;

namespace SpaceDemo.Industrial;

/// <summary>
/// Core 与 Godot 之间的**唯一适配层**（阶段 4 产物）。
///
/// 职责边界（指导书硬规则）：
/// <list type="bullet">
/// <item>只做三件事：调 Core 的意图方法、把 DTO 转成 GDScript 能直接用的 Dictionary、把异常收成统一信封。</item>
/// <item>**不重实现**任何 Core 规则：可行性、搬运、产出、判胜、回合预算全部原样转手。</item>
/// <item>不含任何玩法状态：世界只存在于 <see cref="CoreSystem"/> 里；本类只持有它的引用与"这一局的配置快照"。</item>
/// </list>
///
/// 统一返回信封（指导书规定）：<c>{ success: bool, message: string, data: Variant, error_code: string }</c>。
/// <c>error_code</c> 只有四类：<c>invalid_arg</c> / <c>invalid_config</c> / <c>illegal_state</c> / <c>internal</c>
/// （另有 <c>not_initialized</c>，表示还没调 <see cref="initialize"/>）。
///
/// 线程约定：全部方法都在 Godot 主线程调用；Godot 的输入/帧回调天然单线程，
/// 因此这里不加锁，也不做"后台线程推进"——工业 tick 何时推进由 Runtime（阶段 5）决定。
///
/// DTO 的键名与 Web 端逐字一致：Core 的 DTO 用 <c>[JsonPropertyName]</c> 固定键名，
/// 序列化再用 camelCase 策略（与 <c>JsonArgs.Options</c> 相同），所以字段名不会因为改用 Godot 而变。
/// </summary>
[GlobalClass]
public partial class JarCoreBridge : Node, IPresentationSink
{
    /// <summary>与 Web 端 <c>JsonArgs.Options</c> 保持一致的序列化选项；不要在这里额外加 IgnoreNull，<c>liquid: null</c> 是有意义的值。</summary>
    private static readonly JsonSerializerOptions ContractJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    /// <summary>缓冲帧上限：表现层消费不完时成批丢最旧（与 Core 的 ProcessJournal 同一手法），并在 <c>poll_events</c> 里报告缺口。</summary>
    private const int MaxBufferedEvents = 512;

    private readonly GodotSystemLog _log = new();

    /// <summary>自上次 <see cref="poll_events"/> 以来攒下的帧（每帧附一份该帧时刻的过程日志快照）。</summary>
    private readonly List<Dictionary<string, object?>> _events = new();

    private CoreSystem? _system;
    private WorldOptions? _world;
    private int? _seed;
    private int _droppedEvents;

    // ------------------------------------------------------------------
    // 生命周期
    // ------------------------------------------------------------------

    /// <summary>
    /// 装配一局工业世界。失败即返回错误信封，**不会**留下半初始化的世界。
    /// </summary>
    /// <param name="worldJson">世界配置 JSON 文本（调用方用 FileAccess 读 <c>res://data/industrial/*.json</c> 后传进来）。</param>
    /// <param name="seed">随机种子；传负数表示不固定（那样无法回放，存档后不可复现）。</param>
    public GodotDict initialize(string worldJson, int seed)
    {
        return Guard(() =>
        {
            var world = WorldOptionsJson.FromJson(worldJson ?? "");
            var report = world.Validate();
            if (!report.IsValid)
                throw new BridgeError("invalid_config",
                    "世界配置校验失败：" + string.Join("；", report.Errors));

            _seed = seed < 0 ? null : seed;
            _world = world;

            // 换世界时先与旧世界解绑：Core 的帧流是同步派发的，留着旧订阅会被旧世界继续回调。
            _system?.Presentation.Unsubscribe(this);
            _system = new CoreSystem(log: _log, randomSeed: _seed, world: world);
            _system.Presentation.Subscribe(this);
            _events.Clear();
            _droppedEvents = 0;

            return (object?)new { seed = _seed, workshops = world.Workshops.Count, producers = world.Producers.Count };
        });
    }

    /// <summary>是否已装配世界（GDScript 侧调用前先问一次，避免拿到一堆 not_initialized）。</summary>
    public bool is_ready() => _system != null;

    /// <summary>本局使用的世界配置原文（存档要用它复现同一份世界；未初始化时返回空串）。</summary>
    public string get_world_json() => _world == null ? "" : WorldOptionsJson.ToJson(_world);

    // ------------------------------------------------------------------
    // 存档：世界配置 + 种子 + 命令日志（Core 提供的 Event Sourcing 原语）
    // ------------------------------------------------------------------

    /// <summary>
    /// 导出这一局的存档数据：世界配置、随机种子、以及全部意图命令。
    /// </summary>
    /// <remarks>
    /// 存的是**意图**不是结果：读档时用"同配置 + 同种子 + 同命令序"重放出同样的世界。
    /// 因此 <c>seed</c> 为 null（未固定种子）时存档不保证逐字节一致 —— Core 明说了这条边界。
    /// </remarks>
    /// <summary>
    /// 存档数据的**原始 JSON 文本**。
    /// </summary>
    /// <remarks>
    /// 刻意不走 Godot 的 Variant：Godot 的 JSON 把所有数字读成 float，再写回时命令里的
    /// <c>intA</c> 这类整数字段会变成 <c>5.0</c>，C# 反序列化到 <c>int?</c> 立刻失败（实测踩过）。
    /// 存档是"原样搬运"，就让它保持文本。
    /// </remarks>
    public string save_state_json()
    {
        try
        {
            var system = Require();
            return JsonSerializer.Serialize(new
            {
                world = WorldOptionsJson.ToJson(system.World),
                seed = system.RandomSeed,
                commands = new List<WorldCommand>(system.CommandLog),
            }, ContractJson);
        }
        catch (BridgeError)
        {
            return "";
        }
    }

    /// <summary>用 <see cref="save_state"/> 的数据重建世界；成功即替换当前世界并重新订阅帧流。</summary>
    public GodotDict restore_state(string json)
    {
        return Guard(() =>
        {
            if (string.IsNullOrWhiteSpace(json))
                throw new BridgeError("invalid_arg", "存档内容为空");

            SavePayload? payload;
            try
            {
                payload = JsonSerializer.Deserialize<SavePayload>(json, ContractJson);
            }
            catch (JsonException ex)
            {
                throw new BridgeError("invalid_config", "存档不是合法 JSON：" + ex.Message);
            }

            if (payload == null || string.IsNullOrWhiteSpace(payload.World))
                throw new BridgeError("invalid_config", "存档里没有世界配置");

            var world = WorldOptionsJson.FromJson(payload.World);
            var report = world.Validate();
            if (!report.IsValid)
                throw new BridgeError("invalid_config", "存档里的世界配置校验失败：" + string.Join("；", report.Errors));

            var commands = payload.Commands ?? new List<WorldCommand>();

            // 回放必须走独立的 ID 源，否则罐子/订单 id 会与原来那次不同（Core 的明文前置条件）。
            var restored = new CoreSystem(
                log: _log,
                randomSeed: payload.Seed,
                world: world,
                jarIds: new SequentialIdGenerator(),
                orderIds: new SequentialIdGenerator());

            var applied = SessionReplay.Into(restored, commands);
            if (applied != commands.Count)
                throw new BridgeError("internal",
                    $"存档回放不完整：{applied}/{commands.Count} 条命令生效");

            _system?.Presentation.Unsubscribe(this);
            _world = world;
            _seed = payload.Seed;
            _system = restored;
            _system.Presentation.Subscribe(this);
            _events.Clear();
            _droppedEvents = 0;

            return (object?)new { commands = applied, seed = payload.Seed };
        });
    }

    /// <summary>存档 JSON 的形状。字段名是外部契约（写进 user:// 后要能读回来）。</summary>
    private sealed class SavePayload
    {
        [System.Text.Json.Serialization.JsonPropertyName("world")] public string? World { get; init; }
        [System.Text.Json.Serialization.JsonPropertyName("seed")] public int? Seed { get; init; }
        [System.Text.Json.Serialization.JsonPropertyName("commands")] public List<WorldCommand>? Commands { get; init; }
    }

    // ------------------------------------------------------------------
    // 读：状态、词表、过程日志
    // ------------------------------------------------------------------

    /// <summary>完整状态快照（契约见 <c>docs/industrial/02-core-api-map.md</c> §5）。</summary>
    public GodotDict get_state() => Guard(() => (object?)Require().GetState());

    /// <summary>词表（形状 / 液体）。只下发一次即可，用于界面做下拉与图例。</summary>
    public GodotDict get_world_meta() => Guard(() => (object?)Require().WorldMeta());

    /// <summary>过程日志（记录栏的数据源）：谁、第几步、做了什么。</summary>
    /// <remarks>
    /// **必须在过程还在册时取**：Core 在过程结算后会淘汰主体映射，那时返回空数组的含义是
    /// "没有**保留的**步骤"，不是"没发生过"（见 <c>JarSystem.StepsFor</c> 的注释）。
    /// 所以在过一次 tick 之后再查已经来不及 —— 记录栏请用 <see cref="poll_events"/> 带出来的帧快照。
    /// </remarks>
    public GodotDict get_steps(string subject, int subjectId)
        => Guard(() => (object?)Require().StepsFor(subject, subjectId));

    /// <summary>
    /// 取出自上次调用以来 Core 发出的全部表现层帧（每帧附该时刻的过程日志快照），取完即清空。
    ///
    /// 为什么要有它：一次 <c>tick</c> 里过程可能整个跑完，等 tick 返回再查 <see cref="get_steps"/>
    /// 已经查不到（主体映射被淘汰）。帧是在过程推进**当场**派发的，所以"过程可见"必须靠这里。
    /// 返回 <c>{ frames: [...], dropped: N }</c>，帧字段：
    /// <c>seq / kind(WorldChanged|ProcessChanged|TimePaused|TimeResumed) / op / subject / subjectId / tick / revision / steps[]</c>。
    /// <c>steps[]</c> 是 Core 的 <c>JournalEntry</c> 原样投影（seq/tick/kind/stepIndex/operation/summary…）。
    /// <c>dropped</c> &gt; 0 表示缓冲已裁剪，早先的帧没保留 —— 消费方必须把"没有这一帧"读成"没有**保留的**这一帧"。
    /// </summary>
    public GodotDict poll_events()
    {
        try
        {
            Require();

            // 先序列化成 JSON 再解析成 Variant：这条路上不经过 Guard 的统一 ToVariant，
            // 否则匿名对象里嵌一个已经转好的 Variant，System.Text.Json 会把它当字典键去处理而报错。
            var frames = Json.ParseString(JsonSerializer.Serialize(_events, ContractJson));
            var dropped = _droppedEvents;
            _droppedEvents = 0;
            _events.Clear();

            var data = new GodotDict
            {
                ["frames"] = frames,
                ["dropped"] = dropped,
            };
            return Envelope(true, "", "", data);
        }
        catch (BridgeError ex)
        {
            return Envelope(false, ex.Message, ex.Code, default);
        }
        catch (Exception ex)
        {
            _log.Error("JarCoreBridge.poll_events 失败", ex);
            return Envelope(false, ex.Message, "internal", default);
        }
    }

    // ------------------------------------------------------------------
    // 表现层：Core 的帧流（同步派发，因此这里只记录、绝不反查世界以外的动作）
    // ------------------------------------------------------------------

    /// <summary>
    /// Core 的帧回调。<b>纪律（Core 明文要求）：不得抛异常、不得改世界、不得阻塞。</b>
    /// 这里只做一件事：把帧记进缓冲，并当场把该主体此刻的过程日志快照附上
    /// （此刻过程还在册，才拿得到 —— 这正是 <see cref="get_steps"/> 在 tick 后取不到的原因）。
    /// </summary>
    public void OnFrame(in PresentationFrame frame)
    {
        try
        {
            if (_system == null) return;

            var record = new Dictionary<string, object?>
            {
                ["seq"] = frame.Seq,
                ["kind"] = frame.Kind.ToString(),
                ["op"] = frame.Op,
                ["subject"] = frame.Subject,
                ["subjectId"] = frame.SubjectId,
                ["tick"] = frame.Tick,
                ["revision"] = frame.Revision,
            };

            if (frame.Subject != null && frame.SubjectId.HasValue)
                record["steps"] = _system.StepsFor(frame.Subject, frame.SubjectId.Value);

            if (_events.Count >= MaxBufferedEvents)
            {
                int drop = Math.Min(Math.Max(1, MaxBufferedEvents / 2), _events.Count);
                _events.RemoveRange(0, drop);
                _droppedEvents += drop;
            }

            _events.Add(record);
        }
        catch (Exception ex)
        {
            // 表现层出错不能影响世界推进：吞掉并留下诊断，不向 Core 抛。
            _log.Error("JarCoreBridge.OnFrame 记录失败（已忽略）", ex);
        }
    }

    // ------------------------------------------------------------------
    // 写：装配台位、订单、执行
    // ------------------------------------------------------------------

    /// <summary>换主台。</summary>
    public GodotDict set_master(int index) => Guard(() =>
    {
        Require().SetMasterIndex(index);
        return (object?)null;
    });

    /// <summary>换从台；<paramref name="index"/> 传负数表示撤掉从台。</summary>
    public GodotDict set_slave(int index) => Guard(() =>
    {
        Require().SetSlaveIndex(index < 0 ? null : index);
        return (object?)null;
    });

    /// <summary>随机派一单（首版唯一的派单入口）。</summary>
    public GodotDict create_random_order() => Guard(() =>
    {
        var (ok, error) = Require().CreateRandomOrder();
        if (!ok) throw new BridgeError("illegal_state", error ?? "随机派单失败");
        return (object?)null;
    });

    /// <summary>按世界配置里的订单模板派单（首版"关卡预置订单"的来源，模板名见 <c>orderTemplates[].name</c>）。</summary>
    public GodotDict create_order_from_template(string templateName) => Guard(() =>
    {
        var (ok, error) = Require().CreateOrderFromTemplate(templateName);
        if (!ok) throw new BridgeError("invalid_arg", error ?? "模板派单失败");
        return (object?)null;
    });

    /// <summary>
    /// 世界配置里声明的订单模板（首版"关卡预置订单"的唯一来源）。
    /// 只转手 <c>JarSystem.OrderTemplates</c>，不推断可行性、不改模板内容。
    /// </summary>
    public GodotDict get_order_templates() => Guard(() =>
    {
        var templates = new List<object?>();
        foreach (var template in Require().OrderTemplates.Templates)
        {
            var requirements = new List<object?>();
            foreach (var requirement in template.Requirements)
                requirements.Add(new { shape = requirement.Shape, liquid = requirement.Liquid });

            templates.Add(new
            {
                name = template.Name,
                type = template.Type,
                requirements,
            });
        }

        return (object?)new { templates };
    });

    /// <summary>删除订单（Core 要的是**下标**，不是订单 id）。</summary>
    public GodotDict delete_order(int index) => Guard(() =>
    {
        var (ok, error) = Require().DeleteOrder(index);
        if (!ok) throw new BridgeError("invalid_arg", error ?? "删除订单失败");
        return (object?)null;
    });

    /// <summary>调整订单顺序（Core 要的是**订单 id**）。</summary>
    public GodotDict move_order(int orderId, int dir) => Guard(() =>
    {
        if (!Require().MoveOrder(orderId, dir))
            throw new BridgeError("invalid_arg", "订单不存在，或该方向已到边界");
        return (object?)null;
    });

    /// <summary>单条可行性分析；结果同时会写回订单的 <c>feasibilityResult</c>。</summary>
    public GodotDict check_feasibility(int orderIndex)
        => Guard(() => (object?)Require().CheckFeasibility(orderIndex));

    /// <summary>全量可行性分析。</summary>
    public GodotDict check_all_feasibility()
        => Guard(() => (object?)Require().CheckAllFeasibility());

    /// <summary>
    /// 开始执行（异步轨：只登记过程，之后由世界 tick 驱动，每 2 刻一个单位）。
    /// 首版**不提供**同步轨 <c>ExecuteOrder</c>：同一单出现两条执行路径会让验收无法收敛。
    /// </summary>
    public GodotDict start_order(int orderIndex) => Guard(() =>
    {
        var (started, error, processId) = Require().StartOrder(orderIndex);
        if (!started) throw new BridgeError("illegal_state", error ?? "无法开始这一单");
        return (object?)new { processId };
    });

    /// <summary>取消一个执行中的过程。**已完成的部分不会回滚**，订单按失败收尾。</summary>
    public GodotDict cancel_process(int processId) => Guard(() =>
    {
        var (cancelled, error) = Require().CancelProcess(processId, "玩家取消");
        if (!cancelled) throw new BridgeError("invalid_arg", error ?? "取消失败");
        return (object?)null;
    });

    // ------------------------------------------------------------------
    // 写：产线速率、时间、重置
    // ------------------------------------------------------------------

    /// <summary>设置某个生产者在某个形状上的每回合速率（上下界由 Core 校验）。</summary>
    public GodotDict update_producer_rate(string producerName, string shape, double rate) => Guard(() =>
    {
        Require().UpdateProducerRate(producerName, shape, rate);
        return (object?)null;
    });

    /// <summary>设置某种液体的每回合自产速率。</summary>
    public GodotDict update_liquid_rate(string liquid, double rate) => Guard(() =>
    {
        Require().UpdateLiquidProductionRate(liquid, rate);
        return (object?)null;
    });

    /// <summary>
    /// 推进 count 个逻辑刻（首版 UI 只传 1）。
    /// 注意：回合耗尽 / 结局已定时 Core 会**抛异常**（不是返回错误码），这里转成 <c>illegal_state</c>。
    /// 另外 <c>Tick</c> 的返回值恒为 0，推进了几刻请看 <c>state.turns.used</c>。
    /// </summary>
    public GodotDict tick(int count) => Guard(() =>
    {
        Require().Tick(count);
        return (object?)null;
    });

    /// <summary>冻结世界时间（暂停期间 Tick 静默返回 0，不推进不产出）。</summary>
    public GodotDict pause_time() => Guard(() => (object?)new { changed = Require().PauseTime() });

    /// <summary>恢复世界时间（幂等：本来在流动时返回 changed=false）。</summary>
    public GodotDict resume_time() => Guard(() => (object?)new { changed = Require().ResumeTime() });

    /// <summary>把世界推回默认装配（清过程、清账本、重装初始库存）。</summary>
    public GodotDict reset_world() => Guard(() =>
    {
        // 先清缓冲再 Reset：Reset 本身会重新发帧（初始库存入账），那些帧是"重置之后"的新事实，不能一起丢掉。
        _events.Clear();
        _droppedEvents = 0;
        Require().Reset();
        return (object?)null;
    });

    /// <summary>节点离树时与 Core 解绑（帧流是同步派发的，留着订阅会让已释放的宿主继续被回调）。</summary>
    public override void _ExitTree()
    {
        _system?.Presentation.Unsubscribe(this);
    }

    // ------------------------------------------------------------------
    // 内部：信封、变体转换、异常归类
    // ------------------------------------------------------------------

    /// <summary>本类自己的错误（带 error_code），避免把 Core 的异常类型透给 GDScript。</summary>
    private sealed class BridgeError : Exception
    {
        public BridgeError(string code, string message) : base(message) => Code = code;
        public string Code { get; }
    }

    /// <summary>Core 的诊断出口 → Godot 控制台。约定：**绝不抛异常**、绝不回调 Core。</summary>
    private sealed class GodotSystemLog : ISystemLog
    {
        public void Error(string message, Exception? ex = null)
            => GD.PushError(ex == null ? message : $"{message} :: {ex.GetType().Name}: {ex.Message}");

        public void Info(string message) => GD.Print($"[industrial] {message}");
    }

    private CoreSystem Require()
        => _system ?? throw new BridgeError("not_initialized", "工业世界尚未初始化（先调用 initialize）");

    /// <summary>把 body 的结果包成成功信封；任何异常都归成四类错误码之一。</summary>
    private GodotDict Guard(Func<object?> body)
    {
        try
        {
            return Envelope(true, "", "", ToVariant(body()));
        }
        catch (BridgeError ex)
        {
            return Envelope(false, ex.Message, ex.Code, default);
        }
        catch (DomainValidationException ex)
        {
            // 回合耗尽、结局已定、参数越界、未知液体…… 都是"世界拒绝这次意图"，不是程序故障。
            return Envelope(false, ex.Message, "illegal_state", default);
        }
        catch (JsonException ex)
        {
            return Envelope(false, "世界配置不是合法 JSON：" + ex.Message, "invalid_config", default);
        }
        catch (ArgumentException ex)
        {
            return Envelope(false, ex.Message, "invalid_arg", default);
        }
        catch (Exception ex)
        {
            _log.Error("JarCoreBridge 未预期异常", ex);
            return Envelope(false, ex.Message, "internal", default);
        }
    }

    private static GodotDict Envelope(bool success, string message, string errorCode, Variant data)
    {
        var dict = new GodotDict();
        dict["success"] = success;
        dict["message"] = message;
        dict["error_code"] = errorCode;
        dict["data"] = data;
        return dict;
    }

    /// <summary>DTO → Godot Variant：走 JSON 往返，这样键名与 Web 契约逐字一致，也不用为每个 DTO 手写映射。</summary>
    private static Variant ToVariant(object? payload)
    {
        if (payload == null) return default;
        var json = JsonSerializer.Serialize(payload, ContractJson);
        return Json.ParseString(json);
    }
}
