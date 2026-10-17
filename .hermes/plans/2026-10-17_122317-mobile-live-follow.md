# 手机端「重连续接 + 实时跟随」实施计划

> 目标读者：对本仓库零上下文的实现者。按任务顺序执行；每个任务都有锚点、代码与验证命令。
> 交叉参考（只读，不要修改）：本机 Hermes 源码 `C:\Users\LKX\AppData\Local\hermes\hermes-agent\`（桌面端与官方服务端实现）。

---

## 0. Goal（一句话）

让手机端在**（a）离开聊天页再回来、（b）后台冻结后回前台、（c）被系统杀掉后冷启动**三种情况下，自动重新挂上正在运行的回合、**持续实时显示进度**（流式文本/工具/终态）、自动收尾，不再需要手动点刷新或去列表页猜完成状态。

不涉及：后台保活（前台服务）、推送、开机自启 —— 那是独立的后续工作（本计划与之解耦）。

## 1. 背景与已核实事实（实现前必读）

### 1.1 仓库与门禁（与 CI 逐字一致）

- 仓库：`D:\work\app\flutter\hermes-android`（Flutter fork；当前 `2.1.19+2159`）。
- 本机跑测试前必须（git-bash）：

```bash
export NO_PROXY="127.0.0.1,localhost"; export no_proxy="127.0.0.1,localhost"
```

- 门禁命令（每条改动都要跑）：

```bash
flutter analyze --no-pub --fatal-infos     # 期望："No issues found!"
flutter test --no-pub                      # 期望："All tests passed!"（基线 1288 个）
```

- **不要动** `pubspec.yaml` 的版本号与 `pr-quality.yml` 的版本门禁（CI 校验）。不要 `git add -A`（会卷入 `.hermes/plans/`），commit 用显式路径。
- 提交信息风格：`feat: ...` / `test: ...` / `fix: ...`（英文一行）。

### 1.2 关键文件地图（改动目标）

| 文件 | 角色（关键行号） |
|---|---|
| `lib/core/services/ws_client.dart` | WS 传输层。心跳 15s/45s（L292-293）；按会话监听表 `_sessionStreams`（L247）；单槽 `onStreamEvent`；`submitPrompt()`（L904-982）通过 `_sessionStreams` 收本地提交的流；事件帧解析（含 `seq`，L729-761）；ready 帧 `_gatewayReady*`（L306-316 附近）。 |
| `lib/core/services/desktop_gateway_client.dart` | 每连接客户端。`_resumeOrCreateSingle`（L~390-424，`session.resume`）；`_rememberBinding`（L426-480：open_requests 重投递 + inflight **只判错**）；`_openSocket`/`_scheduleReconnect`（L263-357）；`_rebindStoredSessions`（L364+）；**异步桥允许清单 `_asyncEventTypes`（L67-86，不含 delta）**；单槽 `setAsyncEventListener`（L660+）。 |
| `lib/core/screens/chat_screen.dart` | `initState` 建 client（L571-583）+ `_ensureDesktopSession()`（L972-996）；`dispose` 关 client（L693-755，L722 `_desktopGateway?.close()`）；提交路径渲染 `_handleDesktopGatewayEvent`（L3255-3389）；异步桥 `_handleDesktopAsyncEvent`（L3398-3462，只认交互/终态/通知/子代理）；终态消费 L3464-3519；`_pendingReattachResync` 补拉机制（L1542-1770，武装条件窄）；刷新按钮 → `_fetchMessages()`（L4308-4313）。 |
| `lib/core/services/gateway_turn_application_controller.dart` | app 级 owner 的**先行范式**（草稿会话 + 通知里答审批）；L111-136 "keeps the coordinator, socket ... alive until the whole application is disposed"。 |
| `lib/main.dart` | L211 建 `_turnApplicationController`；L335/346/382 下发到 Workspace/SessionList；L391 dispose。**registry 将复制这条下发链**。 |
| `lib/l10n/app_en.arb`（模板） + `app_zh.arb` + `app_zh_Hans.arb` | 文案。新 key 三档都要加；改完 `flutter gen-l10n`；**≥2 占位符必须写 `@key` metadata**（否则参数被字母序重排）。禁止硬编码英文。 |
| `test/ws_client_server_requests_test.dart` | 假 WS 服务器测试的**范本**（先读它再写传输层测试）。 |
| `test/desktop_gateway_cwd_binding_test.dart` | `_FakeGateway`（REST+WS）范本，写 inflight 用例时扩展它。 |

### 1.3 服务端契约（官方 Hermes；本机源码已逐行核实，勿改服务端）

- **resume 会挂载**：对活着的会话 `session.resume` → `tui_gateway/methods_session.py::_resume_reuse_live`（原话 *"attaches this caller alongside the client(s) already streaming"*）→ 新 socket 加入会话 fanout（`tui_gateway/session_transports.py`），之后事件同时推给所有挂载端（`tui_gateway/server.py::write_json` 按 session 路由）。
- **resume 载荷**（`tui_gateway/contracts/sessions.py::LiveSessionSnapshot` / `InflightTurn`）：`running`、`status`、`inflight{assistant, streaming, user, corrections, correction_offsets, error, error_surface, status}`、`queued`、`open_requests`、`pending_approval`。inflight 注释原话：*"the live (or retained failed) turn a reconnecting client rebuilds its bubbles from"* —— **inflight 是 text-only**（无工具状态）。
- **补发**：`session.events.since {session_id, last_seen}` → `{epoch, events[], latest_seq, truncated}`；事件帧带 per-session 单调 `seq`；服务端环形缓冲约 512 条（`tui_gateway/event_replay.py`）。
- **桌面端参考实现**（本机源码，只读对照）：
  - `apps/shared/src/json-rpc-gateway.ts` → `fetchReplay()` / `fetchSessionReplay()` / `dispatchIfNewer()` / `skipTruncatedWindow()`：seq 水位、补发、**补发期间压住实时帧**、epoch 变化弃水位、truncated 跳过交由历史重读兜底。
  - `apps/desktop/src/app/session/hooks/use-session-actions/utils.ts` → `appendLiveSessionProjection()`：把 resume 的 inflight 投影成气泡 + 防重复规则（"仅当最新权威 user 行不是同一轮"才补投影）。
  - `apps/desktop/src/app/session/hooks/use-message-stream/`：会话级事件归约 + 一整套重复投递测试。
  - 测试参照：`apps/shared/src/json-rpc-gateway-replay.test.ts`、`apps/desktop/src/app/session/hooks/warm-resume-replay-barrier.test.tsx`、`.../resume-occurrences.test.tsx`。

### 1.4 已确认的三个缺口（本计划要补的）

1. **传输层无补发**：App 全仓无 `session.events.since`；`seq` 只在"仅草稿会话"的 v2 协调器里用过，通用路径无水位、无去重。
2. **inflight 不重建**：resume 拿到的部分正文只用来判"失败没有"。
3. **渲染层排除流式事件**：`_asyncEventTypes` 白名单不含 `message.delta`/`tool.*`；本地提交流之外的流永远不渲染。

## 2. 架构决议（"生命周期"答案，用户已确认要做）

**决议 A —— 连接所有权（核心）**：每个连接（`SavedConnection`）有 **一个应用级** `DesktopGatewayClient`，由新 `GatewayClientRegistry` 持有（`main.dart` 创建、随 App dispose 关闭；连接删除时关闭对应实例）。聊天页进入时取共享实例 + 注册监听，**离开时只解绑、不关闭**；草稿/通知 controller 也改用同一共享实例（消除同连接双 socket）。断线重连、seq 水位、会话挂载跨页面存活。进程死后不持久化水位（YAGNI）——由 `resume + inflight + 历史` 覆盖。

**决议 B —— 去重与顺序**：在 `WsClient` 事件分发点做**集中 seq 门**（live + 补发同过闸）；补发期间**压住**该会话实时帧（照抄桌面 `replayHold`），避免"先见 7 再补 5、6 导致 5、6 被门挡掉"的丢帧；本地提交流与异步桥的重复由"本地提交进行中跳过异步流式帧"处理（见 Phase 4）。

**决议 C —— inflight 语义**：inflight 是重建"进行中一轮"的权威；工具进度不在其中，仅能靠补发/历史补齐；补发窗口截断时接受"进行中工具态缺口"（与桌面一致）。

**不做（YAGNI，明确写进代码注释）**：前台服务/保活、推送、开机自启、水位持久化、通知策略变更、**Go FFI 动态库**（结论：传输不是瓶颈、断链是 Android 进程存亡问题，FFI 不解决且引入第二份会话状态；继续纯 Dart）。

## 3. 分阶段任务（TDD；每 Phase 末跑全门禁 + commit）

### Phase 0 — 基线

**T0.1** 跑门禁确认基线：

```bash
export NO_PROXY="127.0.0.1,localhost"; export no_proxy="127.0.0.1,localhost"
flutter analyze --no-pub --fatal-infos && flutter test --no-pub
```

期望：analyze 0，test 全绿（约 1288）。若红，先停下研究，不要带病开工。

**T0.2** 对照阅读（清单，读完向自己复述一遍再继续）：
`tui_gateway/methods_session.py`（`_resume_reuse_live`、`_resume_response`）、`tui_gateway/session_transports.py`、`tui_gateway/server.py::write_json`、`apps/shared/src/json-rpc-gateway.ts` 的 `fetchReplay` 段、`apps/desktop/.../utils.ts` 的 `appendLiveSessionProjection` 段。

---

### Phase 1 — 传输层：seq 门 + 补发（`lib/core/services/ws_client.dart`）

**T1.1（RED）** 先读范本 `test/ws_client_server_requests_test.dart` 的假服务器写法。新建 `test/ws_client_event_replay_test.dart`，写 5 个用例：

1. **重复丢**：同一会话 `seq=5` 的事件帧连发两次 → 监听者只收到一次。
2. **重连补发**：第一段 socket 收到 seq 1..3 → 断开 → 重连；服务器记录到 `session.events.since` 请求，断言参数 `{session_id: <sid>, last_seen: 3}`；应答 `{events:[seq4, seq5], latest_seq:5}` → 监听者按序收到 4、5。
3. **补发期间压住实时帧**：在 since 请求"未应答"期间发来实时 seq=7 → 断言 7 不先于补发的 5、6 派发；桥接完后 7 正常派发（最终顺序 5,6,7）。
4. **epoch 变化清水位**：重连 ready 帧带新的 `replay_epoch` → 不再为旧水位发 since 请求。
5. **truncated 跳过**：响应 `{truncated:true, latest_seq:9, events:[...]}` → 不派发任何补发事件，水位置 9，并触发"需回读"回调（Phase 5 消费）。

运行：`flutter test --no-pub test/ws_client_event_replay_test.dart` → 应全红（编译失败或断言失败）。

**T1.2（GREEN）** 在 `ws_client.dart` 实现：

```dart
// 新增字段（放在 _sessionStreams 附近）
final Map<String, int> _lastSeenSeq = {};       // sessionId -> 已派发最大 seq（跨重连存活）
final Map<String, List<StreamEvent>> _replayHold = {}; // 补发期间压住的实时帧
final Set<String> _replaying = {};              // 正在补发的会话
String? _replayEpoch;
void Function(String sessionId)? onReplayTruncated; // Phase 5 用

/// 集中闸门：false = 该事件已见过，丢弃。
bool _passSeqGate(StreamEvent event) {
  final sid = event.sessionId;
  final seq = event.seq;
  if (sid == null || sid.isEmpty || seq == null) return true; // 无 seq 的帧不设顺序契约
  final last = _lastSeenSeq[sid] ?? 0;
  if (seq <= last) return false;
  _lastSeenSeq[sid] = seq;
  return true;
}

/// 把"解析好的事件"送到两个扇出点（原先 _handleMessage 内联的那段抽出来）。
void _deliverEvent(StreamEvent event) { /* 原 _sessionStreams 循环 + onStreamEvent?.call(event) + isComplete 清理逻辑，原样搬入 */ }
```

- 在 `_handleMessage` 事件分支（找 `rawSeq` 解析处，L729 附近；派发点搜 `_sessionStreams[` / `onStreamEvent`）改为：

```dart
if (event.sessionId != null && _replaying.contains(event.sessionId)) {
  final buf = _replayHold.putIfAbsent(event.sessionId!, () => []);
  if (buf.length < 256) buf.add(event);   // 有界，防病态积压
  return;
}
if (!_passSeqGate(event)) return;
_deliverEvent(event);
```

- ready 帧处理处（搜 `_serverRequestsAdvertised` / `_advertiseServerRequests`）：解析 `payload['replay_epoch']`；若已有非空值且不同 → `_lastSeenSeq.clear()`；记录新值。

```dart
/// 连接建立后（heartbeat 启动处，搜 `_startHeartbeat(`）调用。
void _fetchReplay() {
  if (_lastSeenSeq.isEmpty) return;
  final entries = List<MapEntry<String, int>>.from(_lastSeenSeq.entries);
  for (final e in entries) { _replaying.add(e.key); }
  for (final e in entries) { unawaited(_fetchSessionReplay(e.key, e.value)); }
}

Future<void> _fetchSessionReplay(String sid, int lastSeen) async {
  try {
    final result = await send('session.events.since', {'session_id': sid, 'last_seen': lastSeen})
        .timeout(const Duration(seconds: 10));
    final epoch = result['epoch']?.toString();
    final resultEpoch = result['result'] is Map ? (result['result'] as Map) : result; // 先核对 send() 返回是 raw result 还是已解包
    // ——实现时先读 send() 的返回约定（搜 `Future<Map<String, dynamic>> send(`）——
    final truncated = resultEpoch['truncated'] == true;
    if (epoch != null && epoch.isNotEmpty && _replayEpoch != null && epoch != _replayEpoch) {
      _lastSeenSeq.clear();
      return; // adoptReplayEpoch 语义：旧水位作废
    }
    if (truncated) {
      final latest = resultEpoch['latest_seq'] as int? ?? lastSeen;
      _lastSeenSeq[sid] = latest;
      onReplayTruncated?.call(sid);
      return; // 不派发残缺窗口（历史回读兜底）
    }
    final events = resultEpoch['events'];
    if (events is List) {
      for (final raw in events.whereType<Map>()) {
        final ev = _streamEventFromReplayFrame(Map<String, dynamic>.from(raw));
        if (ev != null && _passSeqGate(ev)) _deliverEvent(ev);
      }
    }
  } catch (_) {
    // 补发是尽力而为：旧服务端 -32601、超时都吞掉，下次重连再试
  } finally {
    _replaying.remove(sid);
    final held = _replayHold.remove(sid);
    if (held != null) {
      for (final ev in held) { if (_passSeqGate(ev)) _deliverEvent(ev); }
    }
  }
}
```

- `_streamEventFromReplayFrame`：把补发帧 `{type, session_id, payload, seq, ...}` 转成 `StreamEvent`（与 `_handleMessage` 的构造保持一致；**实现前先对照 `tui_gateway/event_replay.py` 与 `apps/shared/src/json-rpc-gateway-replay.test.ts` 核对方形**）。
- 已知细节：`send()` 返回约定、超时参数是否原生支持（搜 `Future<Map<String, dynamic>> send(`），按实际情况用 `.timeout` 或原生参数。

**T1.3** `flutter analyze --no-pub --fatal-infos && flutter test --no-pub` 全绿 → commit：

```bash
git add lib/core/services/ws_client.dart test/ws_client_event_replay_test.dart
git commit -m "feat(ws): seq-gated dispatch + session.events.since replay on reconnect"
```

---

### Phase 2 — 生命周期：多路监听 + `GatewayClientRegistry`

**T2.1（RED）** 新建 `test/gateway_client_registry_test.dart`：

- 同一 connection 调两次 `clientFor` 返回同一实例；不同 connection 不同实例。
- `closeConnection(id)` 后再次 `clientFor` 得到新实例。
- 语义测试（`test/desktop_gateway_listener_multiplex_test.dart`）：向同一个 `DesktopGatewayClient` 注册两个 async listener（token 式），一条事件两者都收到；移除其一后只剩一个；sessionBound 监听同理。

**T2.2（GREEN）** `desktop_gateway_client.dart` 单槽 → 多路：

```dart
final Map<Object, DesktopAsyncEventCallback> _asyncListeners = {};
final Map<Object, DesktopAsyncEventSessionPredicate> _asyncListenerAccepts = {};
Object addAsyncEventListener(DesktopAsyncEventCallback cb, {DesktopAsyncEventSessionPredicate? acceptsSession}) {
  final token = Object();
  _asyncListeners[token] = cb;
  if (acceptsSession != null) _asyncListenerAccepts[token] = acceptsSession;
  return token;
}
void removeAsyncEventListener(Object token) { _asyncListeners.remove(token); _asyncListenerAccepts.remove(token); }
void _dispatchAsyncEvent(String sid, StreamEvent event) {
  for (final entry in List.of(_asyncListeners.entries)) {
    final accepts = _asyncListenerAccepts[entry.key];
    if (accepts != null && !accepts(sid)) continue;
    try { entry.value(sid, event); } catch (_) {}
  }
}
```

- 把 `_installAsyncEventBridge` 里的 `_asyncEventListener?.call(...)` 全部改走 `_dispatchAsyncEvent`；`setAsyncEventListener(null)` 语义用迁移层保留或直接迁移调用点（见下）。**`_sessionBoundListener` 同样多路化**（`addSessionBoundListener`/token）。
- 迁移调用点：`chat_screen.dart` L574/576（改为存 token，dispose 处 720/721 用 token 移除）、`gateway_turn_application_controller.dart` 的 `_syncAsyncEventDispatcher`、`main.dart` 审批路径（若直接引用）。

**T2.3（GREEN）** 新文件 `lib/core/services/gateway_client_registry.dart`：

```dart
import 'dart:async';
import '../models/saved_connection.dart'; // 按实际路径调整
import 'desktop_gateway_client.dart';

/// 应用级连接持有者：每个连接一个共享的 DesktopGatewayClient。
/// 聊天页只借用（attach/detach 监听），绝不 close；进程退出/删除连接时才关闭。
class GatewayClientRegistry {
  final Map<String, DesktopGatewayClient> _clients = {};
  bool _closed = false;

  DesktopGatewayClient clientFor(SavedConnection connection) {
    if (_closed) throw StateError('GatewayClientRegistry is closed.');
    return _clients.putIfAbsent(connection.id, () => DesktopGatewayClient.fromConnection(connection));
  }

  /// 已存在则返回，不存在则 null（测试/只读场景用）。
  DesktopGatewayClient? existingFor(String connectionId) => _clients[connectionId];

  void closeConnection(String connectionId) { _clients.remove(connectionId)?.close(); }

  Future<void> close() async {
    _closed = true;
    for (final c in List.of(_clients.values)) { c.close(); }
    _clients.clear();
  }
}
```

**T2.4（GREEN）** `main.dart`：仿 `_turnApplicationController` 的下发链（L211 创建、L335/346/382 传入、L391 dispose 关闭）把 `GatewayClientRegistry` 一路传到 `workspace_screen.dart`（L877 附近）→ `session_list_screen.dart`（L521/1008/1149/1671）→ `chat_screen.dart`（构造器 L263/339 区域，新增 `this.gatewayRegistry` 字段，可空）。

**T2.5（GREEN）** `chat_screen.dart`：

- L571 改为：

```dart
final registry = widget.gatewayRegistry;
final shared = registry?.clientFor(widget.connection);
_desktopGateway = shared ?? DesktopGatewayClient.fromConnection(widget.connection);
_ownsClient = shared == null;
```

- 监听注册改为 token 保存；dispose（L720-722）改为**只解绑**：

```dart
final asyncToken = _desktopAsyncListenerToken;
if (asyncToken != null) _desktopGateway?.removeAsyncEventListener(asyncToken);
final boundToken = _desktopBoundListenerToken;
if (boundToken != null) _desktopGateway?.removeSessionBoundListener(boundToken);
if (_ownsClient) _desktopGateway?.close();   // 仅测试/无 registry 回退时关闭
```

- **保留** `_releaseClientAfterStreamSettles()`（它管的是 legacy SSE 的 `_client`，与本计划无关）。

**T2.6（GREEN）** `gateway_turn_application_controller.dart`：默认真实工厂改为 `registry.clientFor(connection)`（构造器加 `GatewayClientRegistry? registry` 注入）；`_CoordinatorGatewayTurnApplicationSession` 加 `final bool _ownsClient`，其 `close()` 里**仅当 `_ownsClient` 才 `_client.close()`**（其余清理照旧）。**审计点**：`enableTurnRecoveryCoordinator` 及 `closeAll()` 在共享 client 上的语义——跑 `ls test/ | grep -i turn_application` 找到相关测试并全跑。若发现共享耦合太重，允许把本任务降级为"controller 暂留独立 client"并记录 TODO（见风险 §5.1）。

**T2.7** 跑全量 `flutter test --no-pub`，修复受影响测试（预期波及：chat_screen dispose 行为断言、`desktop_gateway_cwd_binding_test`、通知 wiring 测试）。**注意**：不要为了让测试过而弱化断言；为"离开页面不再关闭共享连接"新增一条正向断言。

**T2.8** 门禁全绿 → commit：

```bash
git add lib/core/services/desktop_gateway_client.dart lib/core/services/gateway_client_registry.dart \
  lib/core/services/gateway_turn_application_controller.dart lib/main.dart \
  lib/core/screens/chat_screen.dart lib/core/screens/workspace_screen.dart lib/core/screens/session_list_screen.dart \
  test/gateway_client_registry_test.dart test/desktop_gateway_listener_multiplex_test.dart
git commit -m "feat(lifecycle): app-scoped gateway client registry + multiplexed listeners"
```

---

### Phase 3 — 会话层：inflight 投影 + 跟随状态机

**T3.1（RED）** 新建 `test/gateway_live_turn_test.dart`：纯单测投影解析（running/streaming/assistant/error 组合、空负载返回 null）；并在 `test/desktop_gateway_cwd_binding_test.dart` 的 `_FakeGateway` 的 resume 应答里加 `running:true, inflight:{assistant:'partial', streaming:true, user:'hi'}` → 断言新监听器收到投影。

**T3.2（GREEN）** 新文件 `lib/core/services/gateway_live_turn.dart`：

```dart
class LiveTurnProjection {
  final bool running;
  final String? status;
  final String user;
  final String assistant;
  final bool streaming;
  final String error;
  final bool failed;
  const LiveTurnProjection({required this.running, this.status, this.user = '',
      this.assistant = '', this.streaming = false, this.error = '', this.failed = false});

  bool get isLive => running || streaming || assistant.isNotEmpty;

  static const _terminalFailures = {'error','failed','interrupted','cancelled','canceled'};

  static LiveTurnProjection? fromResume(Map<String, dynamic> payload) {
    final inflight = payload['inflight'];
    final map = inflight is Map ? Map<String, dynamic>.from(inflight) : const <String, dynamic>{};
    final running = payload['running'] == true;
    final status = (map['status'] ?? payload['status'])?.toString().trim().toLowerCase();
    final user = map['user']?.toString() ?? '';
    final assistant = map['assistant']?.toString() ?? '';
    final streaming = map['streaming'] == true;
    final error = map['error']?.toString().trim() ?? '';
    final failed = error.isNotEmpty || (status != null && _terminalFailures.contains(status));
    if (!running && !streaming && user.isEmpty && assistant.isEmpty && error.isEmpty) return null;
    return LiveTurnProjection(running: running, status: status, user: user,
        assistant: assistant, streaming: streaming, error: error, failed: failed);
  }
}
```

**T3.3（GREEN）** `desktop_gateway_client.dart`：加 `final Map<String, LiveTurnProjection> _liveProjections = {}` + 多路 `LiveTurnListener`（token 式，同 T2.2 模式）；`_rememberBinding`（L426-480）末尾：由 `binding.resumed` 构建投影（注意 `ws_client.dart` 的 `ResumedGatewaySession` 若未捕获 `running`，在 L1144 解析段补上），存 map 并通知监听器；暴露 `LiveTurnProjection? liveTurnProjectionFor(String mobileSessionId)`。

**T3.4（GREEN）** `chat_screen.dart` 接入：

- `initState`（L577 附近 `_ensureDesktopSession()` 之后）注册 live-turn 监听：`if (p != null) _enterFollowMode(p);`
- `_ensureDesktopSession()`（L985-995）`await gateway.ensureSession(...)` 之后补：`final p = gateway.liveTurnProjectionFor(widget.session.id); if (p != null) _enterFollowMode(p);`
- 新方法：

```dart
bool _followLiveTurn = false;

void _enterFollowMode(LiveTurnProjection p) {
  if (!mounted) return;
  final assistant = _lastAssistantMessage();
  final hasLocalPending = assistant != null && assistant['_gateway_pending_response'] == true;
  setState(() {
    _followLiveTurn = true;
    _streaming = true;
    _gatewayTurnStatus = GatewayTurnStatus(kind: 'recovery', text: context.l10n.live_turn_following);
    if (!hasLocalPending) {
      final userText = p.user.trim();
      final lastUser = _messages.lastWhere((m) => m['role'] == 'user', orElse: () => const {});
      if (userText.isNotEmpty && (lastUser['content']?.toString() ?? '').trim() != userText) {
        _messages.add({'role': 'user', 'content': userText});
      }
      _messages.removeWhere((m) => m['_follow_projection'] == true);
      _messages.add({'role': 'assistant', 'content': p.assistant,
        '_gateway_pending_response': true, '_follow_projection': true});
    }
  });
  _scheduleStreamingFollow();
}

void _exitFollowMode() {
  if (!_followLiveTurn) return;
  setState(() {
    _followLiveTurn = false;
    _streaming = false;
    _sending = false;
    if (_gatewayTurnStatus?.kind == 'recovery') _gatewayTurnStatus = null;
    _messages.removeWhere((m) => m['_follow_projection'] == true);
  });
  unawaited(_fetchMessages());   // 用落库终稿替换投影
}
```

- 终态收尾：跟随中收到 `message.complete`/`turn.end`/`error`（异步路径，Phase 4 打通后）触发 `_exitFollowMode()`；若下一轮 resume 发现 `p == null` 也退出。

**T3.5** 门禁 + commit（`feat(follow): live turn projection from resume + follow state machine`）。

---

### Phase 4 — 渲染层：异步桥放行流式事件 + 去重

**T4.1（RED）** 新建 `test/chat_live_follow_test.dart`（假 gateway 驱动）：

1. 冷进入 + resume 带 inflight → 显示"运行中"chip + 部分正文气泡。
2. 随后异步 `message.delta` 追加文本。
3. 同一 seq 重投递 → 不重复。
4. 异步 `tool.*` 事件 → 工具卡出现。
5. `message.complete` → 退出跟随 + 触发一次历史重拉。
6. **双路径不重复**：本地提交进行中（`_localSubmitActive`），同一帧经提交路径与异步桥 → 只渲染一次。

**T4.2（GREEN）** `desktop_gateway_client.dart` 桥放行：

```dart
static bool _shouldBridgeAsync(String type) =>
    _asyncEventTypes.contains(type) ||
    type == 'message.delta' || type == 'message.interim' ||
    type == 'reasoning.delta' || type == 'thinking.delta' || type == 'reasoning.available' ||
    type.startsWith('tool.');
// _installAsyncEventBridge 中：if (!_shouldBridgeAsync(event.type)) return;
```

（`reasoning.*`/`thinking.*` 的准确事件名以 `lib/core/models/gateway_turn_contract.dart` 与 `test/chat_reasoning_replace_test.dart` 为准，核实后再写。）

**T4.3（GREEN）** `chat_screen.dart` `_handleDesktopAsyncEvent`（L3398）最前面插入：

```dart
const streamTypes = {'message.delta','message.interim','reasoning.delta','thinking.delta','reasoning.available'};
final isStream = streamTypes.contains(event.type) || event.type.startsWith('tool.');
if (isStream && _followLiveTurn && !_localSubmitActive) {
  _handleDesktopGatewayEvent(event, _responseGeneration);
  return;
}
```

- 新增字段 `bool _localSubmitActive = false;`：在提交方法里乐观气泡入列处（L2988-2996 区域）置 true，在其 `finally`（L3024-3026 区域）置 false。**不要**复用 `_sending/_streaming`（跟随模式会占用它们）。
- 终态：在 `_handlePendingReattachTerminalEvent`（L3464）之前加跟随分支：`if (_followLiveTurn && terminalTypes.contains(event.type)) { _exitFollowMode(); return true; }`（失败时同样退出并提示）。

**T4.4（GREEN）** l10n：`app_en.arb` 加 `"live_turn_following": "Running · auto-syncing"`（无占位符，无需 @metadata）；`app_zh.arb` = `"运行中 · 自动同步中"`；`app_zh_Hans.arb` 同。跑 `flutter gen-l10n`，提交生成件。使用处：`_enterFollowMode` 的 chip。

**T4.5** 门禁 + commit（`feat(follow): render streamed events while following + dedupe`）。

---

### Phase 5 — 收尾场景：截断回读 + 冷启动 + 冲突守卫

**T5.1（RED+GREEN）** 截断回读：`ws_client` 的 `onReplayTruncated` → `desktop_gateway_client` 转发（多路，同 T2.2）→ `chat_screen` 若挂载且 sid 匹配 → `unawaited(_fetchMessages());`。测试：传输层断言回调参数；chat 层断言 `_fetchMessages` 被调。

**T5.2（RED+GREEN）** 冷启动用例（`chat_live_follow_test.dart` 补场景）：无任何历史状态，直接以 running 的 resume 进入 → 跟随生效、完成后收尾。

**T5.3（RED+GREEN）冲突守卫**：既有 `_pendingReattachResync` 路径与新跟随并存时不得双渲染/闪回。场景：提交后断线 → 重连（旧机制武装 + 新跟随激活）→ 断言气泡最终内容唯一、终态后只有一次历史重拉。若出现冲突，修法是 `_onDesktopConnectionChanged` 里 `_markPendingReattachResync()` 前加 `if (_followLiveTurn) { ...仅保留跟随... }`（以测试钉住具体行为）。

**T5.4** 门禁 + commit（`test: pin truncation backfill, cold start and resync-conflict cases`）。

---

### Phase 6 — 文档与收尾

**T6.1** 更新 `AGENTS.md`：overlay 表加一行（"重连续接 + 实时跟随"）+ §新增说明（参照桌面文件、行为矩阵）。⚠️ AGENTS.md 是受保护文件，**需用户在场批准**（不要绕道；用户批准词拿到后才写）。

**T6.2** 全量门禁最后一遍 + 推 fork：

```bash
git push git@github.com:linkaixiang4883/hermes-android.git main
git ls-remote fork refs/heads/main   # 与本地 sha 对上再报成功
```

**T6.3** 真机 QA 清单（手动；MIUI 注意锁屏/USB）：
1. 回合进行中 → 离开聊天页去列表 → 返回：应自动显示最新进度并持续刷新。
2. 回合进行中 → 后台 10 分钟 → 回前台：自动重连 + 接上 + 续显。
3. 回合进行中 → 划掉 App → 重新打开进会话：应显示进行中状态并续显；完成自动收尾。
4. 回合在你回来前已结束：进入会话直接看到终稿（无需手动刷新）。
5. 断网 30 秒再恢复：补发/回读后内容无缝。

## 4. 验收标准（行为矩阵）

| 场景 | 期望 |
|---|---|
| 离开聊天页→返回（回合运行中） | resume → inflight 重建 → attach → 实时续显 → 完成自动收尾 |
| 后台（进程活）→返回 | 心跳判死（≤45s）→ 重连 → rebind → 补发（或截断回读）→ 续显 |
| 被杀→冷启动 | resume → inflight 重建 → 续显；历史由 fetch 补齐 |
| 回合已结束 | 一次 fetch 展示终稿，无需手动刷新 |
| 本地提交的回合 | 提交路径渲染；异步桥不重复；行为与现状一致 |
| 同一事件 live+补发+重投递 | 只渲染一次（seq 门） |

## 5. 风险、取舍与开放问题

1. **Phase 2 是最大风险面**（registry + controller 合一）。缓解：TDD、保留旧构造回退、先跑 `test/` 相关组。若 controller 合一发现深度耦合：降级为"screens 用 registry、controller 暂留独立 client"，记录 TODO 另开任务；**契约不变**（其余 Phase 不受影响）。
2. **补发与实时的时序**：已按桌面语义加 `_replaying` 压帧；若仍见乱序/丢帧，对照 `json-rpc-gateway-replay.test.ts` 的边界用例补齐。
3. **inflight 是 text-only**：工具进度无法从 inflight 重建；补发窗口被截断时存在"进行中工具态缺口"（与桌面一致，接受）。
4. **水位不持久**（跨进程死亡无补发）：冷启动依赖 resume+inflight+历史；若实测有缺口，再单开"水位持久化"任务（YAGNI 先不做）。
5. **`send()` 返回约定/超时参数**：实现 `_fetchSessionReplay` 前必须读 `ws_client.dart` 的 `send()` 实现确认（计划里标了锚点），不要猜。
6. **补发帧形状**：以 `tui_gateway/event_replay.py` + 桌面 replay 测试为准；客户端转换函数必须与 `_handleMessage` 的 `StreamEvent` 构造一致。
7. 开放问题（记录，不在本期实现）：`queued`（排队中的下一轮 prompt）与 `corrections`（中途纠偏）的完整投影对齐；`open_requests`/审批在跟随期间的 UI 呈现细化。

## 6. 参考文件对照表（桌面端 → 手机端）

| 桌面端（只读参考） | 手机端落点 |
|---|---|
| `apps/shared/src/json-rpc-gateway.ts`（fetchReplay/fetchSessionReplay/dispatchIfNewer/skipTruncatedWindow） | `lib/core/services/ws_client.dart`（Phase 1） |
| `apps/desktop/src/app/session/hooks/use-session-actions/utils.ts`（appendLiveSessionProjection） | `lib/core/services/gateway_live_turn.dart` + `chat_screen.dart`（Phase 3） |
| `apps/desktop/src/app/session/hooks/use-message-stream/*`（会话级归约 + 去重测试） | `chat_screen.dart` `_handleDesktopGatewayEvent/_handleDesktopAsyncEvent`（Phase 4） |
| `apps/shared/src/json-rpc-gateway-replay.test.ts`、`warm-resume-replay-barrier.test.tsx`、`resume-occurrences.test.tsx` | 手机端对应新测试的用例清单（Phase 1/3/4/5） |
| `tui_gateway/contracts/sessions.py::InflightTurn`、`methods_session.py::_resume_reuse_live` | 契约依据（勿改） |
