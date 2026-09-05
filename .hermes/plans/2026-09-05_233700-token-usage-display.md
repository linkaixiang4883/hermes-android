# 会话 Token 用量显示 Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** 聊天输入框上方显示上下文用量（当前占用 used/max/percent；无 breakdown 时 REST fallback 显示本轮），数据源以服务端实发为准、无数据不撒谎、不持久化。

**Architecture:** 主路径 WS 的 `session.context_breakdown` RPC（used/max/percent/categories/model 一次拿全；`session.usage` 为轻量备选，Task 0 二选一）。`DesktopGatewayClient` 新增透传（mobile→gateway session 映射仿 `interruptPrompt`），chat_screen 在开聊与 turn 结束时拉取刷新。显示走输入区上方 hint bar（单行，tap 弹 dialog；右侧为未来压缩按钮预留槽）。REST 流尾 triple 仅作 fallback（本轮数）。服务端无持久化，App 亦不存（stale 比空更坏，与桌面 GUI 同策略）。不动服务端、不改通道、不做客户端估算。

**Tech Stack:** Flutter StatefulWidget + setState（本仓库架构）、gen-l10n、flutter_test（l10n delegates 包裹）。

> 修订 v2（2026-09-06）：方向重写。v1 的“REST 流尾累加”作废——逐行验证发现 `session.context_breakdown` 现成 RPC（used/max/percent 全有），累加逻辑删除，% 问题连带解决（服务端自带窗口表），持久化经验证后明确不做。

---

## 数据流（生命周期）

```text
开聊 / turn 结束
  └─ WS（主路径）: DesktopGatewayClient.getContextUsage(sessionId)
        → 映射 mobile→gateway session（_gatewaySessionIds，仿 interruptPrompt）
        → send('session.context_breakdown')［Task 0 若字段不足改用 session.usage］
        → 全零（无 live agent，methods_session.py:1138-1145）视为无数据 → 隐藏
        → 有数 → _contextUsage → hint bar（used/max · percent%）
  └─ REST（fallback）: 流尾帧 usage triple → _lastTurnUsage（本轮覆写，无累加）
        → 仅 dialog 本轮行；breakdown 有数时 dialog 以 breakdown 为准
```

## 数据源对照表（勘察结论，执行不用重查）

| 来源 | usage 在哪 | App 现状 | 裁决 |
|---|---|---|---|
| WS `session.context_breakdown` | `context_used/max/percent/categories/model` 一次拿全（`methods_session.py:1136-1152`；现算，非持久化） | 无调用 | ✅ 主路径 |
| WS `session.usage` | 轻量 snapshot（`calls/input/output/total` + 快照期 context_*，`:1124-1133`） | 无调用 | ✅ 备选（Task 0：breakdown 字段不足时用它） |
| REST SSE 流尾帧 | triple 本 turn 量（`api_server_openai_routes.py:652`） | `parseSseFrame`（`connection_manager.dart:878`）丢掉 | ✅ fallback（仅本轮行，无累加） |
| REST 同步 `/api/sessions/{id}/chat` | 会话累计 total（lifetime 花费口径，非当前占用） | App 不走此接口发消息 | ❌ 不切通道（破坏流式体验；且累计≠占用） |
| Runs SSE `run.completed` | 带 `usage` | App 不走此通道 | ❌ 不切通道（大手术） |
| Dashboard 会话接口 | 仅 `message_count`，无 token 字段 | 零解析 | ❌ 已排除 |
| App prefs 持久化 | — | — | ❌ 不做（服务端内存属性+无DB列；网关重启真值清零，prefs 旧数变脏数据；桌面 GUI 同策略） |

## 口径说明（防误解，执行者必读）

- 流尾 `total_tokens` = 本 turn 的量；同步接口 `total_tokens` = lifetime 累计花费；**两者都不等于当前窗口占用**，只有 `context_breakdown` 的 used/percent 是。
- 无 live agent（新开会话未对话、网关刚重启）→ 服务端回全零 → App 视为无数据隐藏，与桌面 GUI 行为一致（非 bug）。

## 显示文案（定死，执行不纠结）

- 紧凑数字双语共用，不翻译（参照 `relative_time` 不翻先例）：`90k/200k · 45%`。
- hint 单行：`已用 90k/200k · 45%` / en `90k of 200k · 45%`（breakdown 口径；无 breakdown 有 triple 时显示本轮行文案）。
- 新增 ARB key（612→616），带参 key 按铁律加 `@key` placeholders：
  - `usageBarSummary(used:String, max:String, percent:int)`：`已用 {used}/{max} · {percent}%` / `{used} of {max} · {percent}%`
  - `usageThisTurn`：`本轮 {value} tokens` / `This turn: {value} tokens`（仅 fallback）
  - `usageModelName(model:String)`：`模型 {model}` / `Model: {model}`
  - `usageTitle`：`用量统计` / `Token usage`（dialog 标题）
- tap hint 弹普通 dialog：breakdown 有数时显示用量行 + 模型行；无 breakdown 时只显示本轮行（此时 hint 单行即本轮文案）。

## 安全/隐私 guardrail

- Task 0 只记录 RPC 返回 **keys 列表**与用量数值，禁止粘贴消息正文、API key、session id 以外标识。
- 测试 fixture 用合成数字，不得出现真实网关返回体。

---

### Task 0: 调通 breakdown RPC（二选一，唯一 pause 点）

**Objective:** 确认 `session.context_breakdown`（或备选 `session.usage`）在真机链路上可用，记录返回 keys。

**Files:** 只读：App 侧 `lib/core/services/ws_client.dart:536`（通用 `send`）、`lib/core/services/desktop_gateway_client.dart:351-359`（session 映射）；服务端 `tui_gateway/methods_session.py:1124-1152`。

**Step 1:** 真机/模拟器连网关（用户配合打开一个聊过天的会话），经 App WS 发 `session.context_breakdown` 与 `session.usage` 各一次，记录返回 keys（desensitize 后）与无 agent 会话的零值行为。
**Step 2:** 判定：breakdown 含 `context_used/max/percent` → 主路径用它；否则字段全则用 `session.usage`（显示文案不换，Task 2 按实际 keys 取值）；两者皆无 → 整单暂停并汇报（极低概率，桌面端天天在用）。

**Gate:** 暂停仅此一处；有数则 Task 2 按选定 RPC 落码。

**结论（静态验证完成，无需真机，2026-09-06）：选 `session.context_breakdown`。** 证据链：桌面端 `use-context-breakdown.ts:41` 天天调它（参数 `{session_id}`，忙时不刷、按 session key 旧数、失败吞掉）；返回形 `UsageStats{context_used/max/percent 可选，calls/input/output/total 必需}`（`apps/desktop/src/types/hermes.ts:737-750`）+ breakdown `{categories, context_max/percent/used, estimated_total, model}`（`methods_session.py:1136-1152`）；无 agent 回全零（`:1138-1145`，即“重启 GUI 不显示”的机制）。`session.usage` 降为纯备选。

---

### Task 1: 用量模型（TDD）

**Objective:** 两个不可变小模型，各吃各的口径，缺字段返回 null。

**Files:**
- Create: `lib/core/models/session_context.dart`（`SessionContext{used,max,percent,model}` + `fromBreakdown(Map)`：全零/us/max 缺失→null）
- Modify: `lib/core/models/turn_usage.dart`（沿用 v1 设计：`TurnUsage` + `fromJson` triple 解析 + `formatCompact`；**累加 `add` 已删除**，无累计逻辑）
- Test: `test/session_context_test.dart`、`test/turn_usage_test.dart`

**Step 1: Write failing tests** — breakdown 全字段解析；全零→null；缺 max→null；triple fixture（形如 `{"usage":{"prompt_tokens":120,"completion_tokens":45,"total_tokens":165}}`，合成数字）解析；空 map→null；k-format（1280→`1.3k`，2500000→`2.5M`）。
Run: `export NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost"; flutter test --no-pub test/session_context_test.dart test/turn_usage_test.dart`
Expected: FAIL — file not found。

**Step 2: Write minimal implementation** — 按 Objective 落码（`formatCompact`：≥1M→`x.xM`，≥1k→`x.xk`，否则原数；` tokens` 后缀由调用方拼文案 key）。
Run: 同上命令。Expected: PASS。

**Step 3: Commit** — `git add lib/core/models/session_context.dart lib/core/models/turn_usage.dart test/session_context_test.dart test/turn_usage_test.dart && git commit -m "feat: session context models with breakdown and stream-triple parsing"`。

---

### Task 2: App 透传 + 拉取刷新

**Objective:** WS 新增 breakdown 透传；chat_screen 在开聊与 turn 结束时刷新；REST 流尾 triple 进本轮行。

**Files:**
- Modify: `lib/core/services/desktop_gateway_client.dart`（新增 `getContextUsage({required String sessionId})`：映射仿 `interruptPrompt:351-359`，无映射/未连接 return null；经 `_ws.send('session.context_breakdown')` 取 result，Task 0 选 usage 则换名）
- Modify: `lib/core/services/connection_manager.dart:878`（`parseSseFrame` 加可选 `onUsage` 回调，仿既有 `onToolProgress` 透传；顶层 `parsed['usage']` 非空 Map 即回调）+ `sendMessageStreaming` 同名透传
- Modify: `lib/core/screens/chat_screen.dart`（state `_contextUsage/_lastTurnUsage/_usageSessionId` + `_refreshContextUsage()` + REST 回调 + dialog，约 +70 行）
- Test: 复用 Task 5 覆盖；可测性仿 `test/chat_turn_notification_wiring_test.dart` double 风格（`_refreshContextUsage` 必须在 fake 下可跑，否则提为可注入 fetcher）

**Step 1:** 透传方法（无映射/未连接→null；异常→null，不抛）。
**Step 2:** `_refreshContextUsage()`：`final m = await _desktopGateway?.getContextUsage(sessionId: widget.session.id); if (!mounted) return; setState(() { if (_usageSessionId != widget.session.id) { _contextUsage = null; _lastTurnUsage = null; _usageSessionId = widget.session.id; } _contextUsage = SessionContext.fromBreakdown(m); });` 调用点：开聊历史加载后 + turn 结束（REST onDone 处与 WS settle 处各一）。
**Step 3:** REST 回调：`onUsage: (m) { final u = TurnUsage.fromJson(m); if (u == null || !mounted) return; setState(() => _lastTurnUsage = u); }`（覆写，无累加）。
**Step 4:** header 不动；dialog 按“显示文案”节渲染（breakdown 行优先，本轮行仅 fallback）。
**Step 5:** Run `flutter analyze --no-pub --fatal-infos`。Expected: No issues。
**Step 6: Commit** — `git commit -m "feat: context usage fetch with breakdown RPC and stream fallback"`。

---

### Task 3: composer 上方 hint bar（UI，右侧为压缩按钮预留槽）

**Objective:** 有数据出现单行用量条，无数据不占位；header 文件不动。

**Files:**
- Modify: `lib/core/screens/chat_screen.dart:2861-2862`（model 选择行 `Align` 结束 `),` 之后、`if (_attachmentDrafts.isNotEmpty)` 之前插入，约 +30 行）
- Test: `test/chat_usage_hint_test.dart`（见 Task 5）

**Step 1:** 插入条件行 `if (_contextUsage != null || _lastTurnUsage != null)` + 可 tap 条：`InkWell(key: const Key('usage-hint-bar'), onTap: _showUsageDialog, child: Padding(padding: fromLTRB(4,2,4,2), child: Row(children: [Expanded(child: Text(_hintLabel(), maxLines: 1, overflow: ellipsis, bodySmall)), Icon(Icons.chevron_right, size: 14, muted)])))`，圆角/margin 向 2788-2819 turn-status 条看齐；`_hintLabel()`：breakdown 优先（`usageBarSummary`），否则本轮（`usageThisTurn`）；Row 尾预留压缩按钮槽（本次空着，留 `// TODO(compress):` 注释标位）。
**Step 2:** `_showUsageDialog` 用普通 AlertDialog（按“显示文案”节）。
**Step 3:** Run `flutter analyze --no-pub --fatal-infos`。Expected: No issues。
**Step 4: Commit** — `git commit -m "feat: usage hint bar above composer (slot reserved for compress)"`。

---

### Task 4: ARB 加 key + gen-l10n

**Objective:** 4 个 key 双语落地（本仓库铁律：改 ARB 必跑 gen-l10n 并提交生成文件）。

**Files:**
- Modify: `lib/l10n/app_en.arb`、`lib/l10n/app_zh.arb`（文案见上“显示文案”节，带参 key 加 placeholders 元数据：String/int 按类型）
- Regenerate: `lib/l10n/app_localizations*.dart`

**Step 1:** 加 key。**Step 2:** Run `flutter gen-l10n`。Expected: 无报错。**Step 3:** Run `flutter test --no-pub test/arb_parity_test.dart`（对等守护自动覆盖新 key）。Expected: PASS。
**Step 4: Commit** — `git commit -m "i18n: context usage keys (en/zh) + regen"`。

---

### Task 5: widget 测试 + 全量门禁 + push

**Objective:** hint bar 显示/隐藏/dialog 行有泵测覆盖，全绿后推 fork。

**Files:**
- Create: `test/chat_usage_hint_test.dart`（`l10nTestDelegates`/`l10nTestSupportedLocales` 包裹；不断言具体数字；用例：breakdown 有数→hint 显示 summary；全零→缺席；triple 仅本轮→hint 显示本轮文案；tap→dialog 行渲染；切会话清零由 Task 2 逻辑 + 单测覆盖，此处覆盖 UI 侧隐藏）
- Modify: 无（源文件不动）

**Step 1: Write tests** — 按上列 5 用例。
**Step 2:** Run `export NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost"; flutter test --no-pub test/chat_usage_hint_test.dart test/session_context_test.dart test/turn_usage_test.dart`。Expected: 全 PASS。
**Step 3:** 全量门禁（与 CI 逐字一致）：`flutter analyze --no-pub --fatal-infos`（No issues）+ `flutter test --no-pub`（目标 961+新增全绿）。
**Step 4:** 分路径提交并推 fork（`.hermes/` 未被忽略，禁用 `git add -A` 以免把 plan 文件卷入）：`git add lib test && git commit -m "test: usage hint widget tests" && git push fork main`。

---

## Open questions（执行中遇到再定，不阻塞开工）

- categories 分段显示（服务端已返回，桌面端 panel 有参考实现 `context-usage-panel.tsx`）：下次迭代，另起一单。
- 百分比口径以服务端为准，App 不自己算、不维护窗口表。
- REST 流异常中断（无尾帧）→ hint bar 保持旧值，不回退、不标注（YAGNI）。

## Future: 一键压缩按钮（本单不做，证据已齐，开新单直接用）

- 服务端能力存在：`slash.exec` RPC（`tui_gateway/methods_tools.py:859-884`），`worker.run("/compress")` 真执行（非 mirror；`_mirror_slash_side_effects` 仅补副作用，`:350`）。
- 约束：turn 运行中调 compress 会被拒（`session busy — /interrupt the current turn before running /compress`，`methods_slash.py:358-362`）→ 按钮启用条件 `!_sending && !_streaming`（沿用 composer 区既有 disable 模式），或先 interrupt 再压。
- 通道限制：仅 WS（slash.exec 是 WS RPC）；REST 用户隐藏该按钮。
- App 缺口：`DesktopGatewayClient`/`ws_client` 无 slash 透传（已 grep 确认无）→ 新增 `slashExec(command)` 方法（仿 `interruptPrompt`/`interruptSession`），落点同文件。
- 落点：本单 Task 3 hint bar 右侧预留槽（`// TODO(compress):`）。
- 无独立压缩 REST 接口（`api_server.py` 无 compress 路由；`/compress` 本质是 CLI slash 经 worker 执行；自动压缩是服务端阈值触发的默认行为，无需按钮）。

## Review checklist（执行完对照）

- [ ] Task 0 结论已记录（breakdown/usage 二选一），两者皆无则整单暂停
- [ ] 无 App 侧累加逻辑（TurnUsage 无 add；累计口径只认服务端）
- [ ] 无 prefs/DB 持久化（内存 state；切会话清零有测试覆盖）
- [ ] 任务顺序 Task 0→1→4→2→3→5；Task 1 与 Task 4 无依赖，可并行
- [ ] 每个文件路径精确到行号区段
- [ ] 验证命令含 `NO_PROXY` 前缀（本机代理坑）与 `--no-pub`（CI 一致）
- [ ] 无服务端改动、无通道切换、无客户端估算、无新依赖
