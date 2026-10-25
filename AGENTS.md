# hermes-android 汉化维护手册

本仓库 fork 自 upstream（rusty4444/hermes-android），维护本地 overlay：中文体验增强 + 若干上游未覆盖的修复。**2026-10-05 起 i18n 采用上游官方体系（10 语种）**，协议侧与 Hermes 服务端（0.21.x）对齐。以下内容供任何会话在本目录工作时自动加载。

## 本地化基础设施（2026-10-05 起 = 上游官方体系）

- `l10n.yaml` — **上游的** gen-l10n 配置（arb-dir `lib/l10n`，生成文件同目录，**必须提交**，CI analyze 用 `--no-pub`）
- `lib/l10n/app_en.arb` — 上游模板 + 我们 8 条 overlay 文案 = **645 message keys**（含 3 条 `@` placeholders 元数据）
- 语种：`app_{en,zh,zh_Hans,ja,ko,es,fr,de,pt,pt_BR,ru}.arb` —— **en/zh/zh_Hans 含我们全部 8 条**；其余 8 档对缺失 key **回落英文**（可后续补译）
- `lib/core/l10n/l10n.dart` — 上游访问器（`context.l10n`；另提供 `preferredSupportedLocales()`/`resolvePreferredLocale`）。**我们旧版 `lib/l10n/l10n.dart` 已删除**——import 统一 `package:hermes_android/core/l10n/l10n.dart`
- `lib/l10n/app_localizations*.dart` — 生成文件（改 ARB 后 `flutter gen-l10n` 重新生成并提交）
- 测试工具 = 上游 `test/support/l10n_test_utils.dart`（`testAppWithL10n(child, locale:)` / `loadTestL10n([locale])`）；旧 `l10nTestDelegates`/`l10nTestSupportedLocales` **已删**，测试用 `AppLocalizations.localizationsDelegates` + `preferredSupportedLocales()`

### 文案修改流程

1. 改 `app_en.arb`（模板）+ `app_zh.arb` + `app_zh_Hans.arb`（后两个同步）
2. **带参数的 key 必须在 en 加 `@key` placeholders 元数据**——尤其 **≥2 个占位符**时：不声明元数据，gen-l10n 会把位置参数**按字母序重排**（`{used} {max} {percent}` → `(max, percent, used)`），调用语义静默错位（编译期查不出）。声明后按声明顺序 + 强类型生成（如 `usage_bar_summary(String used, String max, int percent)`）
3. `flutter gen-l10n`（会提示其它 8 语种的 untranslated 计数，属预期）
4. `flutter analyze --no-pub --fatal-infos` + `flutter test --no-pub`（与 CI 逐字一致）
5. **提交生成文件**（CI 用 `--no-pub`）

### 铁律

- 新增 UI 文案必须走 `context.l10n.xxx`，**禁止硬编码英文**（除非品牌名/协议字段/日志/上游自身遗留）
- 服务端下发的数据（消息内容、工具名、模型名）**不翻译**
- 我们新增 key 用上游 snake_case 风格；其它 8 语种缺省回落 en
- 测试 pump 用 `testAppWithL10n`，或自行 `localizationsDelegates: AppLocalizations.localizationsDelegates` + `supportedLocales: preferredSupportedLocales()`


## overlay 现状（2026-10-05，合上游 v2.1.12 后）

**已退役（被上游官方化）**：我方 640-key 体系与生成文件、"i18n 六批"全套改动、应用内语言切换器（`app_locale`）、srq 全套自建 plumbing（含 `d312bef` 能力广告——上游 #118 实现更严谨）、`ws_client_server_requests_test`/`language_switch_test`/`arb_parity_test`。
语言策略 = 上游路线：**系统 per-app language（Android 13+）/ 系统语言**；<13 设备跟随系统语言（用户 2026-10-05 决议退役切换器）。

**保留 overlay（改动前先读）**：

| overlay | 位置 | 备注 |
|---|---|---|
| 用量条 | `chat_screen`（`_contextUsage`/`_refreshContextUsage`/`_hintLabel`/`_showUsageDialog`/`usage-hint-bar` UI）+ `desktop_gateway_client.getContextUsage`（`session.context_breakdown`）+ `connection_manager`（`onUsage` REST 流尾回退）+ 模型 `session_context.dart`/`turn_usage.dart` + 4 key（`usage_title`/`usage_bar_summary`/`usage_this_turn`/`usage_model_name`） | 不持久化；刷新点：init / 回合提交成功 / 流尾 / `message.complete` |
| 思考块防覆盖 | `gateway_insight.isAnswerPreview` + `chat_screen` replace 前守卫 + `test/chat_reasoning_replace_test.dart` | 上游至今未修（v2.1.12 复检：模型文件 0 改动、测试仍钉 replace） |
| TTS 语言跟随 | `tts_voice_config.dart` + `chat_screen._readAssistantText`（`TtsVoiceConfig.apply(appLanguageCode:)`） | 上游无 `TtsVoiceConfig` |
| STT 键盘引导 | `voice_composer_controller`（`_hasReceivedResult` + `l10n` 注入）+ key `speech_recognition_use_keyboard`/`dictation_ready` | 上游 controller 无本地化 |
| FAB heroTag 修复 | `workspace_screen`/`projects_pane`（`fd04661`） | 上游 IndexedStack 保活导致双 FAB 同 tag，debug 断言刷屏（上游对聊天 FAB 用 `heroTag: null`，同款思路） |
| clarify 双-pop 守卫 | `gateway_clarify_dialog.dart`（自 pop 前查 `ModalRoute.isCurrent`）+ `test/gateway_clarify_dialog_test.dart`（`2081bb6`） | 上游 v2.1.12 竞态（本仓 QA 实测、上游未修）：`clarify.lock` → 合成 `clarify.remaining` → reconcile 先 pop 对话框、其自 pop 再弹一次 → **弹掉聊天页**；审批无此隐患（应答路径无合成事件） |
| 重连续接 + 实时跟随 | `ws_client`（seq 门/补发/`onReplayTruncated`）+ `desktop_gateway_client`（`rotateTicket` 复用/多路监听/`ensureSession(refresh:)`/`LiveTurnProjection`/`addReplayTruncatedListener`）+ `gateway_client_registry.dart`（应用级共享，main.dart 下发）+ `chat_screen`（跟随态/`_localSubmitActive`/`_acceptFollowStreamFrame`/`_reconcileFollowAfterTranscriptReplace`）+ 1 key（`live_turn_following`） | 机制全图与坑：技能 `hermes-android-client → references/connection-persistence.md` §6-§11；**硬不变量见下节**；真机 QA 已过（2026-10-18） |
| 审批卡回合终帧清场（App 侧） | `chat_screen`（`_clearTurnEndBlockingPrompts` + 两处终帧钩子 + `_approvalTurnEndDismissed` + `_expireSensitivePromptById`）+ `test/chat_turn_notification_wiring_test.dart`（+3） | 上游缺口（`4db6cd5`）：某客户端应答后其它端**不发撤销帧**；桌面端回合结束自清（窗口=剩余回合时长）、手机端此前无对等机制；服务端不补（update 会覆盖，用户决议 2026-10-18），纯 App 侧自愈；全档见技能 `hermes-android-client → references/server-requests-0.21.3.md`「跨客户端撤卡缺口」节 |
| MEDIA 卡保存到下载 + APK 安装/通知（App 侧） | `media_artifact_card`（下载按钮/非图片行点按 = 保存）+ `media_download_saver`（channel `.../downloads`，返回 `{filename, install}`）+ `isAndroidPackageFile`（`media_tags`）+ `MainActivity`（MediaStore API 29+；APK = cache 副本 + FileProvider 起系统安装器，**未授权时打开"安装未知应用"设置页**；原生通知 `hermes_media_downloads`，APK 通知带"安装"动作；日志 tag `HermesDownloads`）+ FileProvider/`REQUEST_INSTALL_PACKAGES` + `test/media_artifact_card_test`/`media_tags_test`（+5） | 上游卡只"下载→分享面板"（`d4e13bc`→`fcef7ce`→`c8a0547`）；文件落系统 Downloads 并发完成通知；**APK 存完即弹安装、未授权先开设置页、通知内可再点安装**；通知权限仅 Android 13+（首次保存时请求）；<29 回退分享；细节见技能 `pc-to-phone-media-delivery.md` 新增节 |
| YOLO 模式按钮（会话内） | `chat_screen`（AppBar `chat-yolo-button`、确认框 `yolo-confirm`、顶部 `yolo-banner`、`_toggleYolo`）+ `desktop_gateway_client.setSessionYolo`/`sessionYoloFor`（状态取自 resume 的 `info.yolo`）+ `ws_client.setSessionYolo`（`config.set{key:'yolo',value:'on'/'off',scope:'session'}`）+ 7 l10n key + `test/chat_yolo_test.dart`（+2）/`desktop_gateway_cwd_binding_test`（+1） | 服务端 `_set_yolo`：session scope 只翻本会话；返回值是**服务端 OR 结果**（`approvals.mode=off` 或 `_YOLO_MODE_FROZEN` 也会显示 on，session 关不掉全局）；桌面 Shift+Tab 同语义 |
| 上下文压缩按钮（App 侧） | `chat_screen`（usage-hint-bar 内 `compress-button` + 确认框 `compress-confirm` + `_runCompress`）+ `desktop_gateway_client.slashExec`（10 分钟超时；错误带服务端原文）+ 4 l10n key + `test/chat_compress_test.dart`（+4） | 旧压缩按钮 9 月回退的四死因按现服务端复核已消（`3342f57`）：`/compress` 经 `slash.exec→command.dispatch` **同步执行**（无 45s worker 超时）、busy=4009 错误、成功后 resume 重绑 + 重拉历史 + 刷新用量；手机端**首个 slash 命令**；细节见技能 `references/slash-commands.md` 落地记录 |

**已知未尽**：我们 8 条 key 仅 en/zh/zh_Hans（其余 8 语种回落英文）；`projects_pane` 的 `_CompatibilityMode._explanation` 为上游硬编码英文（配套 zh key 存在但未接）；服务层 move 拒绝原因串、`relative_time` 紧凑格式、prompt 模板、存库 title、服务端数据/日志照旧不翻。
**门禁基线**：`analyze --fatal-infos` 0 + `flutter test` **1488**（2026-10-25 审批可见性修复后；会话内 YOLO=1486；Activity 静默更新=1483；桌面本地群组镜像=1481；群组发现/帖子式 UI=1476；项目 cwd 修复=1473、Bot Mode 全套=1471、P2=1421、P1=1414、P0=1410，此前 1404）。

## Bot Mode / 群组 / 审批通知 / Activity（2026-10-22 完成）

> 计划：`.hermes/plans/2026-10-22_164019-bot-mode-approvals-activity-apk.md`。每包完成即更新本节；门禁基线随包递增。

**进度**
- [x] **P0 profile 维度**（`bfa87f4`，1410 测试）：`Session.profile`（null=连接默认）；`DesktopGatewayClient._sessionProfiles`（按 mobile id 记），`session.resume/create` 与 REST `/messages` 带 `profile`；`_rebindStoredSessions` 重连沿用。**决定**：不做复合映射键——对外监听 API 仍以 `Session.id` 为键，profile 只作为 per-session 事实随绑定传递（runtime id 全局唯一，反向映射无歧义）。
- [x] **P1 Bots 名册 + 单聊**（`bf461eb`，1414 测试）：More → Bots 页（`bots_screen.dart`，5s 轮询 `profiles.list`）；点 bot → `session.list{title:'Bot Chat',include_hidden:true}` → 无则 `session.create{title,hidden,idempotency_key}` → **重查收养**；`Session.profile` 全链（P0）让其聊天落在该 profile。入口放在 More（非 Chats 分段——体积考虑，后续可调）
- [x] **P1B 群组房间**（`059290a`，+33 测试）：`group_rooms_client.dart`（groups.* 全套 RPC + 容错模型）；`group_rooms_screen`（5s 列表 + 创建，`seatable_profiles` 选成员）；`group_room_screen`（`state` 取游标 → 2s `groups.log{since_seq}` 增量；user/member/turn/room 事件渲染；发送单飞 + event_id 落盘重试；approve/retry/stop/rename/disband）；入口 = Bots 页 AppBar「群组」；`DesktopGatewayClient` 仅加 `callControl()`。
- [x] **桌面本地群组只读镜像**（`a4a5460`，1481 测试）：desktop 把 legacy 群组压进 **default profile 的 `ui_meta['hermes-bots-groups']`**（源码注释明确「so mobile can show the same messages」）；`GroupRoomsClient.legacyGroups()` 调 `profiles.list{include_sessions:false}` 解析 version 3 快照（`rooms`/`deleted`/`log.from`），群组页新增「桌面本地群组（只读）」段与只读房间（帖子式、无输入框、顶部迁移提示）；镜像只在首次进入与下拉刷新时读（体积大、5s 轮询只拉 hosted rooms）。迁移动作仍是在桌面点「Start gateway group」（旧历史不迁移）。
- [x] **群组发现 + 帖子式 UI**（`43dfd0f`，1476 测试）：`GroupRoomsClient.discover()` = `groups.capabilities` + `groups.list` **全分页**（桌面 `discoverCanonicalGroups` 同款循环）；Bots 名册直接列出群组行（不再只藏在 AppBar 图标后）；房间 transcript 由聊天气泡改为**帖子卡**（作者 + `@handle` + 时间 + 轮次分隔，正文可选中）。**根因实证（2026-10-24，leveldb 拆解）**：desktop 的 `hermes.plugin.hermes-bots.group-chats` 里有 2 个本地群组（`rmtiulsv4-56jfv` 96 条、`rmvhpz399-lgucn` 104 条），而服务端 `shared-state.db.hosted_rooms` = **0 行**——所以 App 空列表是事实。桌面打开该群组 → 点「Start gateway group」才创建 canonical 房间（旧历史不迁移）；手机端空态已内置 `group_legacy_hint` 说明。**排障关键**：桌面 roster 里看到的群组可能只是 desktop plugin-storage 的 legacy 本地记录，`groups.list` 里并不存在（本机 shared-state.db 实测 0 房间）；需在桌面打开该群组点「Start gateway group」落成服务端房间，手机端才能发现。
- [x] **审批可见性三缺口修复**（`728a5c0`，1488 测试）：① 聊天页挂载/进页时**从未回放**客户端已登记的 prompt（`replayServerRequestsForSession` 只有草稿控制器在用）→ 未打开会话时到的审批只剩通知、重开也不弹；② `session.activate` 的响应被丢弃，其 `open_requests`（watcher 挂上从未打开过的会话时服务端补发的审批）没人读；③ Activity 的待处理行没有操作按钮。修法：`_rememberBinding` 回填 prompt 的 mobile id + ChatScreen 进页回放 + 监听 `pendingPrompts`（`serverRequestEventFor` 合成事件，`_showGatewayApproval(fromRegistry:true)` 跳过 active-map 门槛）+ `activateSession` 解析 `open_requests` 并登记/回填 + Activity 行内 approve/deny（`onRespondPrompt` → `respondToPendingPrompt`）+ 通知动作带 `wireRequestId` 且失败时先 `activateSession` 重放再应答。
- [x] **Activity 静默更新**（`d6cfdb3`，1483 测试）：此前 `ActivityPane` 只在首次进入/下拉刷新/从行返回时重读，活动页是快照。现 `ObservedTurnStore` 改 `ChangeNotifier`——**只在行可见字段（state/summary/title/mobile id）变化时通知**（流式 delta 只更新时间，不触发）；`ActivityPane.liveUpdates` 接 merge(observed, `client.pendingPrompts`)，变化后 **300ms 防抖**重读，读中变更排队补读，前后台 `resumed` 也重读；Activity 与 Home Inbox 共用同一信号。
- [x] **P2 审批/完成通知中央化**（`aa97c1a`，1421）：`pendingPrompts` 全会话接纳（未映射也登记；不显示才回 `4404`，绝不 `-32601`）；clarify 全锁 `4404`；同会话并发审批排队；`respondToPendingPrompt` 应用级应答；`LiveSessionWatcher`（5s `session.active_list` + `session.activate{omit_messages}`）；`PromptNotifier`/`TurnCompletionNotifier` 消费全局事件；`ChatVisibility` 抑制前台会话；ChatScreen 不再自己发审批/完成通知。
- [x] **P2-6 FGS 保活**（`9e6cd23`，+10 测试）：`HermesConnectionService`（`remoteMessaging`；SDK 29–33 退 `dataSync`），常驻通知 channel `hermes_connection`；`KeepAliveController` 默认开、设置页开关、无连接即停（main 连接删除回调已接）。
- [x] **P3 Activity**（`d99a4b9`，+6 测试）：`ObservedTurnStore`（全量扇出帧 → running/completed/failed，100 上限、持久化）+ `buildObservedActivityFeed`（stock 网关回落源 + `pendingPrompts` 待处理组）；journal 有数据时只读 journal（二选一）。
- [x] **P4 APK 自删**（`edd0027`）：安装启动落盘 `install_cleanup_v1`；下次启动版本号变大才删 MediaStore 行+缓存 APK，否则只清 ≥7 天缓存副本。
- [x] **P4B 通知卡治理**（`482d9a2`，+5 测试）：review.summary 合并一张可关闭复盘卡、background 最多 2 张、去进程级 static 缓存、review 不发系统通知。
- [x] **P5 收尾**：文档/技能更新；最终门禁 **1471**；APK 已构建补签（arm64）。

**门禁基线**：`analyze --fatal-infos` 0 + `flutter test` **1471**（2026-10-22 全部工作包后；P2=1421、P1=1414、P0=1410、此前 1404）。

## 重连续接 + 实时跟随（2026-10-17 六阶段 + 2026-10-18 QA 修复轮落地）

**目标**：离开聊天页/挂后台/被杀后回来，自动从 `session.resume` 的 `inflight` 重建「进行中那一轮」并**持续实时显示**（delta/interim/工具/思考），终态自动收尾——对齐桌面端。不依赖前台服务/推送（那是独立的后续工作）。

**提交（6 阶段 + 评审修复）**：
- P1 传输层 `c851bda` + `fd03619`：seq 门（会话/回合分域）、`session.events.since` 补发、压帧、epoch、truncated 回调。
- P2 生命周期 `832beea`（重连复用同一 WsClient + `rotateTicket`，水位存活）、`b080c7a`（listener 全 token 多路）、`f212c1b`（`GatewayClientRegistry` 应用级共享 + 聊天页借用不关 + 控制器合一）、`973c132`（连接身份变更/删除即失效缓存）、`eea88a3`（真实 socket 夹具晚写修复 + 等待窗口加固）。
- P3 会话层 `0c4c200` + `8df48f9`：`LiveTurnProjection`、`ensureSession(refresh:true)`（只 resume 不 create）、跟随进入/退出、历史回包后重放投影。
- P4 渲染层 `bf8e3b2`：桥放行流事件、跟随态路由（`_localSubmitActive` + 屏幕 seq 门）、终态收尾、停止走 `session.interrupt`、统一 `_reconcileFollowAfterTranscriptReplace`。
- P5 收尾 `f1babd6`：截断回读接线（token 监听 + 未绑定停车场）、冷启动用例、跟随×reattach 冲突守卫、M7/M8 变异钉。
- QA 修复轮 `c98a7e2`：**外部回合接驳**（陌生流帧 → 单飞 `resume(refresh)`，答案沿跟随入口）+ **跟随贴底**（首入拉起/退出收口/重入不扰）；+5 测试。

**硬不变量（改这块前必读；机制全图见技能 `hermes-android-client → references/connection-persistence.md` §6-§10）**：
1. **重连必须复用同一 `WsClient`**（`rotateTicket` 换单次票；重连/掉线路径绝不 `close()`——close = 主动销毁，会清水位/replay 代际）。
2. **每连接一个应用级共享 client**（registry 持有；聊天页 dispose 只按 token 摘监听、绝不 close；控制器借用时其 close 跳过全部 client 级动作）。
3. **连接身份字段变化或删除必须 `closeConnection`**（仅标签变化不得掐断 socket）。
4. **`ensureSession(refresh:true)` 只 resume、绝不 create**（进页/回前台用它；refresh=false 保持已映射早退）。
5. **跟随态不变量**：重建幂等；历史整体替换后必须经 `_reconcileFollowAfterTranscriptReplace` 重放投影或一致退出（禁止「状态条在、投影行没了」）；退出必 `_fetchMessages()`；本地提交进行中（`_localSubmitActive`）优先于异步桥。
6. **截断回读**：`onReplayTruncated` 从 WsClient 经 token 监听转达；未绑定报告暂存（`_unmappedReplayTruncations`）由 `_rememberBinding` 投递。
7. **外部回合接驳**：陌生流帧（非跟随、非本地提交）= 外部回合的唯一信号 → `_requestExternalTurnFollow`（单飞 `resume(refresh:true)`，答案沿跟随入口接驳）；服务端本就扇出（Fanout），缺的只是快照。
8. **跟随贴底**：`_enterFollowMode` 首入 `beginStreaming`（重入保留用户位置选择）、`_exitFollowMode` 以 `endStreaming` 收口——跟随的滚动语义 = 本地提交同款。

**测试/门禁**：`chat_live_follow*`、`ws_client_event_replay`、`ws_reconnect_replay`、`desktop_gateway_{live_turn,replay_truncated,multiplex_listeners}`、`gateway_client_registry`、`chat_gateway_client_ownership`；**基线 1387**（analyze 0；QA 修复轮 +5 = `chat_live_follow_stream_test` ×3 + `chat_history_scroll_test` ×2）。真实 socket 测试夹具坑（`client.capabilities` 静默 + safe-add、`testProjectOverviewLoader`、`isLocalDraft`、`connected→reconnecting` 同步对）见技能 §6-§11——**全量偶发挂先查夹具、再怀疑实现**，稳定性用连跑 5-10 次证明。

**已知遗留（非阻塞）**：`SessionListScreen`/`WorkspaceScreen(projects)`/`CronScreen` 仍 route-local socket；跟随终态帧未校验 `turnId`（迟到帧会结束跟随，靠下次 resume 自愈）；跟随首帧 delta 会按既有语义清状态条（停止键仍在）；截断回读在 pending resync 时让位给 resync 自读、跟随中回读会闪一次 spinner；「编辑连接时正开着聊天」的 UI 接管未特别处理。**真机 QA 已由用户执行通过**（2026-10-18：功能验收 + 修复复验 + 切列表往返；外部回合接驳与跟随贴底两个 QA 修复见提交清单与技能 §11）。



## 项目归组 & 思考块修复（2026-09-14，commit `2d189c4` + `8b81a7d`）

**背景**：上游 App 的项目归组调 `projects.assign_session`——官方 Hermes **从未实现**该 RPC（`projects.*` 全集里没有它；全仓 33752 commit pickaxe 零命中），所以「新建聊天」在项目里必失败；移动会话/快聊提升/Spaces 迁移同一条死路。官方语义是：**会话属于哪个项目，由它的工作目录推导**（`project_for_path`）。

**现在的实现（改这四类行为前先读这段）**：

| 场景 | 走哪条 RPC | 备注 |
|---|---|---|
| 新建项目聊天 | `session.create {cwd: 项目目录}`（仅 create 分支带 cwd，**resume 分支不带**） | 会话出生即锚定项目目录；首轮系统提示词据此注入项目 AGENTS.md 链（与桌面端同机制）。cwd 承载者自 2026-09-28 起是**上游**的 `_workingDirectories` + 全创建路径 `workingDirectory` 透传 |
| 移动已有会话 / 快聊提升 / Spaces 迁移 | `session.workspace.move {session_key, cwd}` | 用会话的 **stored id**（来自服务端列表）；立刻改工作目录/终端/项目树 |
| 移动到「Unassigned」 | **上游 2.1.7 起：拒绝**（返回诚实原因串，UI 提示无法回移） | 我们此前的「cwd=网关默认工作区」方案已按用户决议退役（随上游）；UI 仍列 Unassigned 目标，选中即提示 |
| ~~`projects.assign_session`~~ | **已从 App 全链路删除**（`ProjectsGatewayClient.assignSession` 与仓库同名方法） | 上游 merge 时**不要把它带回来**；**上游 2.1.7 也独立删除了它**（a68e86e），方向已一致；相关测试与 mock 全部用 `session.workspace.move` |

**2026-10-23 修复（首次发送才创建 → cwd 丢失）**：项目聊天若进页时的 `ensureSession` 被跳过/失败（draft + 旧传输 fallback 未就绪），首次发送会走 `submitPrompt → _callSessionScoped → _connect` **不带 cwd** 创建会话 → 落到项目外。现 `submitPrompt/attachFile` 均带 `workingDirectory`，且绑定网关时 `rememberWorkingDirectory()` 先记项目目录；回归 `test/desktop_gateway_cwd_binding_test.dart` +1（首次发送仍带 cwd）。**同日补 `cwd_explicit: true`**（对齐桌面 #52589 语义：显式项目目录不被 profile terminal.cwd 覆盖；旧后端按字段名降级重试一次，`7b69bd1`）。

**系统提示词换血时机（别承诺"移动后立刻带上下文"）**：move 只改 `session["cwd"]` + 终端 pin + DB 行 + 项目树；系统提示词每会话只构建一次并落库复用，**新项目的文档要等该会话下次「压缩上下文」或「运行时重建后重开」才加载**（`conversation_compression.py` 压缩边界重建；`_stored_prompt_matches_runtime` 按 cwd 漂移判定重建；活会话 resume 走 `_resume_reuse_live` 复用，不重建）。UI 文案 `projectMoveContextPending` 就是在说这件事。

**思考块**：服务端 `reasoning.available` 装的是**回答正文前 500 字**（`agent/turn_response_intake.py` `_relay_thinking`），App 原先按 replace 处理会把流式真思考盖掉。现在 `GatewayReasoningUpdate.isAnswerPreview` 判定"实为回答摘要"就丢弃该更新（`test/chat_reasoning_replace_test.dart` 钉住）。

**QA / 门禁**：`analyze --no-pub --fatal-infos` 0 + `flutter test --no-pub` 1019 全绿。真机验收两种：① 手点三步（Projects → 项目 → 新建聊天 → 发消息）后查库 `SELECT id,cwd FROM sessions ORDER BY started_at DESC LIMIT 3`，**cwd 必须等于项目目录**；② `flutter test integration_test/project_chat_filing_test.dart -d <id>`（自动点完整个流程），但**该命令每次都卸载重装 dev 包 → App 数据（连接+密钥）被清空**，跑完需重建连接，且 MIUI 锁屏时会静默拦截 USB 安装。完整记录见 `.hermes/plans/2026-09-13_122432-reasoning-and-project-chat-fix.md`（含机制证据、实施记录、收尾步骤）。

## Hermes 0.21.3+ 兼容性（0.21.3/0.21.4 修复 2026-09-16；0.21.5 门禁 §5；v2.1.12 服务端版本门禁 §6）

**背景**：v2026.9.14 窗口（#110521/#110522）把网关改成「严格契约 + 服务端反问客户端」，两处都曾让手机端功能整段失效，均已修复并真机验收。改协议/UI 前先读本节；机制细节与证据见技能 `hermes-android-client` → `references/server-requests-0.21.3.md`。

### 1) 交互提示改走 server→client 请求（手机端曾完全收不到）

| 维度 | 事实 |
|---|---|
| 帧 | 服务端发 `{"id":"srq-<12hex>","method":"approval/clarify/sudo/secret/vault.*","params":{…}}`；客户端用**同 id 响应帧**回答（**不能带 method 字段**） |
| 回包 | approval→`{choice}`；clarify 单题→`{answer}`、批量→逐题 `clarify.lock`；sudo/secret/vault→`{value}`（''=跳过） |
| 撤回/重连 | `request.cancel {id,method,reason}` → 撤卡；`session.resume` 响应里的 `open_requests[]` → 重投递卡片 |
| 超时 | 审批 `approvals.timeout`（默认 300s，超时 fail-closed）；clarify 默认 3600s |
| 实现 | `ws_client`（`GatewayServerRequest`/`respondToServerRequest`/`lockClarifyAnswer`/`open_requests` 重放）→ `desktop_gateway_client`（按会话路由）→ `chat_screen`（四类接现有对话框；**vault/桌面桥回 error 帧**快速失败；`request.cancel` 撤卡）；旧 `*.respond` 线保留兼容 ≤0.21.2 |

**判读坑**：成功路径**零日志**——别用「日志没痕迹」推断「没弹卡」；服务端判据：`tool clarify completed (600.01s)` = 没答上、**秒级完成 = 答上了**；审批看 tool 耗时（含审批往返 ≥3s vs 普通 <1s）+ 落盘结果。

### 2) 严格参数契约（未知字段直接报错）

- 症状：`invalid params for session.create: session_id: Extra inputs are not permitted` → 新建聊天（项目/闪聊）全失败 + 聊天页顶部**误报红「离线」**（实为 `_connect` 失败时连带关 socket，非真离线）
- 已修：`session.create` **不带 `session_id`**（服务端自己铸 id；用返回的 `session_id`/`stored_session_id`）；`file.attach` **不带 `source_channel`/`source_profile`**
- **改协议调用前做参数级审计**（只看「方法存在」不够）：允许字段 = `$LOCALAPPDATA/hermes/hermes-agent/tui_gateway/contracts/*.py` 里 `method("x", params=Cls)` 的 Cls **及其基类**字段（继承链要接上）；App 侧每个 `send('x', {...})` 的键必须 ⊆ 允许集
- 已知遗留（stock 网关不触发，勿误判）：turn coordinator 的 `prompt.submit` 会带 `version/client_turn_id/attachments`（仅在 turn_recovery 能力存在时启用，官方主线无此能力）；`GatewayActivityCard` 有 setState-during-build 断言（仅 debug 包出现，上游遗留）

### 3) 项目归组的 cwd 持久化（2026-09-16 `b26ac7d`；2026-09-28 已由上游接管）

- **问题（存档）**：项目文件夹（`session.create {cwd}`）曾只挂开屏 preflight，其他创建路径不带 → preflight 失败或竞态时会话以**无 cwd** 建成、项目静默丢失（上游 #102 review 的 gap②）
- **现状（2026-09-28 起）**：由**上游 2.1.7**（#106）的 `_workingDirectories` + 一切创建路径的 `workingDirectory` 透传 + single-flight 绑定承担；我们的 `_desiredCwd` 已删除。**无文件夹项目改为上游 provisioner**（name-only 项目自动建文件夹；旧「诚实提示 + 不贴标签」退役，提示文案 `projectNoFolderNotice`）
- **回归测试**：`test/desktop_gateway_cwd_binding_test.dart` 保留（参数已适配 `workingDirectory:`；「已存在会话绝不换房」用例仍直接钉住该保证）；写该类假网关测试的坑（9119 回退）见技能

### 4) 上游 merge 记录与基线（2026-09-28，`e7685b2`）

- 已合入上游 **2.1.7+2147**（46 commits / 3 releases；PR **#106 stock-compat**：断线重连 + WS 心跳（15s ping / 45s 死链）+ durable resume/分页 + stock Projects（provisioner + `session.workspace.move`）+ 传输加固；**#109** 用户安装 CA 信任（`network_security_config.xml`）；2.1.5 F-Droid 批；cron runs 与聊天列表分离；`file.attach` 字段精简（同我们 `b4247a3`）；`RecognitionService` 声明（同我们已做））；**测试 1123**（合并后 1121 + §5 的 2 条广告回归）；版本 `2.1.7+2147`（CI `REQUIRED_BASE_VERSION_CODE` 已同步 2147）
- **本次决议**：① srq 交互提示**保留并重打**（上游仍无此实现）② 用量条 / 思考块 `isAnswerPreview` / STT-TTS / i18n 全保留 ③ `_desiredCwd`、ws 层 move 栈（`WsClient.moveSessionWorkspace`/`createOrResumeSession`/`GatewaySessionHandle`）、`ProjectChatMoveOutcome`、manifest 重复 intent **退役** ④ Unassigned 回移**随上游拒绝**（用户决议）⑤ 无文件夹项目**采纳上游 provisioner**
- **merge 打法（16 文件冲突：9 lib + 7 test）**：**采上游为基 + 重打 overlay**——`git checkout --theirs`（或按 hunk 取 theirs），再对照 `pre-v217-merge`/`git show HEAD:<file>` 重打我们的块（srq/用量/STT/l10n）。踩坑四条：① 三方合并会把"跨区域相似块"错位对齐（project_detail 成功 snackbar 对齐到上游失败块、workspace `_finishNewChat` 尾部遗留我方 `chatProjectName`），**解完必须跑花括号配平扫描** ② l10n 回填走 **ARB 字典脚本**（唯一 key 自动替换；`const Text(` 包着的一并去 const；枚举声明行跳过）③ 上游新测试缺 delegates 挂 `AppLocalizations.of` null → 补 `l10nTestDelegates` 包裹（本次 4 文件 11 处）④ 测试 fixture 语义跟上游（`'primary_path': ?primaryPath` 省略空路径，否则 folderless 用例假失败）
- 完整冲突清单、逐文件重打清单与坑位见 `.hermes/plans/2026-09-28_222516-merge-upstream-v2.1.7.md`

### 4b) 上游 merge 记录与基线（2026-10-05，`f501ff3`，v2.1.8→2.1.12）

- 已合入上游 **2.1.12+2152**（43 commits / 5 releases）——两个"官方化"大项：**i18n（#115，10 语种）** 与 **srq server→client 请求（#118）**；外加会话稳健性修复（#117/#119/#120/#121/#122/#123：轻量恢复/大会话/并发回合/`is_active`/既有会话 target/活跃窗口）+ per-app language（#125）+ 占位符守卫 ×3；**72 冲突文件**（lib 39 / test 31 / l10n.yaml / pubspec.lock）
- **决议（用户 2026-10-05）**：① i18n 全面倒向上游（我方仅补 8 条 overlay key）② srq 取上游实现 ③ 语言切换器退役 ④ 思考块 overlay 保留（复检上游未修）⑤ overlay 保留：用量条/TTS/STT
- **打法**：`take-upstream 为基 + keep-list 重打`（全量 72 文件 `checkout --theirs` 后，重打 6 文件 29 处 + ARB 补 key + 测试迁移）——见 `.hermes/plans/2026-10-05_011843-merge-upstream-v2.1.12.md`（附件含 merge-tree 预演）
- **本次新坑（复用时注意）**：① **多占位符 key 必须 @metadata**（不声明 → 字母序重排位置参数，编译期无感；`usage_bar_summary` 真机前被 zh_smoke 单测抓出）② 脚本按 CRLF `split` 处理**混合换行**文件会错位插入（用正则按行匹配；本次弄坏过 `chat_reasoning_replace_test`）③ 两侧各加一次的同名 import/参数在自动合并里会**翻倍**（`localizationsDelegates` 重复、`support/l10n_test_utils.dart` 双 import——清到分析器 0 告警）④ 上游严格 fixture 已被上游自己的 srq 协商适配取代，我方 v2.1.7 的帧适配随 theirs 退役 ⑤ 测试 `+1159/-2`（新增 zh_smoke 断言先挂）→ 修到 1161 全绿；真机 QA 又修 clarify 双-pop 竞态（`2081bb6`，+1 回归）→ **1162**
- 版本/CI：`2.1.12+2152`（CI `REQUIRED_BASE_VERSION_CODE=2152`）；门禁 analyze 0 + `flutter test` **1162**（含 clarify 双-pop 回归）

### 4c) 上游 merge 记录与基线（2026-10-11，`b8d6f91`，v2.1.13→2.1.17）

- 已合入上游 **2.1.17+2157**（38 commits / 5 releases）——**桌面级通知**（#128：回合完成/审批/clarify/插件事件/额度变更 + 分类开关）、**`MEDIA:` 文件卡片**（#137）、**逐会话草稿持久化**（#131）、长按消息选文本复制（#127）、底栏标签单行（#126）、聊天页项目头修复（#132/#133）、模型选择器 API-only（#129/#138）
- **冲突面史上最小：1 文件 / 3 段**（`chat_screen` 的导入块、测试钩子字段、构造器参数——全部"两边都留"型）；merge-tree 预演预判全中；一次平推完成（无 take-upstream 大动作）
- **零 overlay 被上游取代**（复检：上游仍无 clarify 守卫/用量条/TTS/STT/heroTag/reasoning 守卫）——全部存续（预演树逐项核验 + 真机复验）
- **决议**：全部继承 v2.1.12 决议（overlay 全保留、上游新功能整体吸收、版本随上游、只推 fork）——用户 2026-10-11「好，开搞」批准计划
- **门禁**：analyze 0 + `flutter test` **1274**（1162 → +112，上游新功能测试）
- **本窗口新坑**：① **"假干净"双重坑**——`python 脚本 && … || echo 干净` 链条：脚本因 MSYS 路径喂给原生 python 没跑成（`D:\c\...`），`||` 却输出了"干净"，且随后把仍带冲突标记的文件 `git add`（伪装已解决）。正解：原生工具参数用 `C:/` 路径、关键步骤只用 `;` 分隔 + 裸命令复核、误操作后 `git reset -- <file>` 回未解重跑；② gen-l10n 后**零增量** = 自动合并的生成件已 canonical，属正常；③ 双侧自动合并文件（connection_manager/desktop_gateway_client/l10n 全套）仍需过门禁 + 抽查 overlay 区块。

### 4d) 上游 merge 记录与基线（2026-10-13，`74e9ad8`，v2.1.18→2.1.19）

- 已合入上游 **2.1.19+2159**（6 commits / 2 releases）——**composer 键盘/溢出重构**（#139：`_buildInputBar(availableHeight:)` 滚动区/固定控件分层，多行/多附件/大字号/软键盘不再把输入框顶出视口）与**本机聊天置顶**（#140：`local_chat_pin_store` 按连接本地存、不动网关、随 app 备份走）
- **冲突 14 文件**：`chat_screen`（1）+ l10n 13（en/zh/zh_Hans arb 各 1 + 10 生成件）——arb = 双方尾部追加（全留 + 逗号修补 + `json.loads` 全文件校验）；生成件以 `gen-l10n` 重生成消解
- **重要教训（本窗口新增）**：**ort 真冲突形态可能与 merge-file 预演不同**——chat_screen 预演为"双方各持内容"，真 merge 是"**ours 非空 / theirs 空**"（上游把该段整体搬迁进新方法 `_buildInputBar`）。处置模式 = **丢弃 ours 侧旧内容（重复体），把 overlay 块按新结构重插**（usage 条 +8 缩进插入新滚动列，模型行与附件块之间）；先看真标记两侧内容再写解析脚本，勿只按预演动手
- **overlay**：全数存续（usage/TTS/STT/推理守卫/heroTag/clarify 守卫/8 keys）——guard 复核通过
- **门禁**：analyze 0 + `flutter test` **1288**（1274 → +14）
- **本窗口决议**：**跳过真机 QA**（用户 2026-10-13：USB 不可用）——真机首验由用户装 release 完成

### 5) Hermes 0.21.5：server→client 请求要先"广告"能力（2026-09-29，`d312bef`，真机复验 ✅）

- **门禁（#112548）**：0.21.5 起，服务端**只在该连接发过 `client.capabilities {server_requests: true}` 时才发** clarify/approval/sudo/secret 请求；没发过 = 视为「比这半套协议更老的构建」→ 直接拒发（日志 `server request clarify for <sid> not sent: the attached client predates server→client requests`），agent 侧等同收到错误响应。会话多客户端时任一广告过即可（`session_transports.py::_session_client_answers_requests`）。
- **症状与判据**：手机端提问/审批卡片**完全不弹**（2026-09-25 起出现过，当次误判偶发）；**排查第一步 grep `not sent`**——命中即该连接没广告（或那台设备还装旧包）。成功路径依旧零日志。
- **修复**：`ws_client._advertiseServerRequests()` —— **每个全新 `gateway.ready` 发一次**（恰好每连接一次，与官方桌面端同节奏；重连后 ready 重来、close 已清 pin）；**裸帧发送、绝不带 `profile`**（该契约 `extra=forbid`，只收 `server_requests`；`send()` 的 `withProfile` 会踩雷）；fire-and-forget（旧服务端 -32601 由 pending `.ignore()` 吞掉，不影响连接）。
- **测试**：`test/ws_client_server_requests_test.dart` +2（ready 后恰一帧、params 恰 `{server_requests: true}` 且无 profile；旧服务端报错无害）。**上游严格 fixture 适配**：`gateway_turn_coordinator_test.dart` 的 `_GatewayFixture` 有 60 处帧序硬断言——把该帧当**传输级握手**在入口直接应答（try/catch 兜 socket 已关）、不进 requests/order 账本。
- 服务端源码锚点：`tui_gateway/server_requests.py`（`_unanswerable`）/ `methods_voice.py`（`client.capabilities` handler）/ `contracts/liveness.py`（params 形状）/ `session_transports.py`（门禁）。技能细节页：`hermes-android-client → references/server-requests-0.21.3.md`「0.21.5 门禁」节。
- **2026-10-05 更新**：本修复已被上游 **#118 官方实现取代**并随 v2.1.12 合入（上游版更严谨：无 handler 的 socket 不广告、`includeProfile:false`）；我方 `d312bef` 退役，行为等价。以上为历史存档。

### 6) 客户端 v2.1.12 ⇄ 服务端版本门禁：`session.resume` 的 `inline_images`（2026-10-05 实测）

- **症状**：任意会话（新建快聊/继续旧聊）**发消息即失败**：`发送失败：JsonRpcError(session.resume): invalid params for session.resume: inline_images: Extra inputs are not permitted — the client and the Hermes backend are out of sync (different versions); run hermes update and restart both`
- **机制**：客户端 v2.1.12（#117 轻量恢复）在 `session.resume` 带 `omit_messages`/`defer_history`/`inline_images` 三参；0.21.5（09-24 构建）**只缺最后一个**——`inline_images` 为服务端 `88039d73b3`（2026-09-27，"feat(tui_gateway): inline_images=false switch"，省流量：#116511）才加入（`contracts/sessions.py::SessionResumeParams`，默认 true）
- **提示来源**：那句 "run hermes update and restart both" 是**服务端严格契约校验器自带的**（`tui_gateway/contracts/registry.py`（~L107），`extra_forbidden` 时固定拼接）
- **处置**：**升级服务端**（`hermes update` + 重启；需 ≥ 含 `88039d73b3` 的构建 = 2026-09-27 之后）。客户端侧**不要**为旧服务端裁剪 resume 参数（服务端是唯一演进方，裁剪 = 永久分叉）
- **通用教训**：严格契约（§2）下"新客户端 + 旧服务端"会硬失败；`Extra inputs are not permitted` + "out of sync" 提示 = **升级服务端**的标准信号

## 拉取上游 / Merge 流程

```bash
# 1. 先提交本地改动（汉化 + AGENTS.md 属于本地分支的提交）
git add -A && git commit -m "i18n: ..."

# 2. 拉取（remotes：fork=自己的库，upstream=rusty4444；没有 origin）
git fetch upstream main

# 3. 预览上游改动
git diff HEAD..upstream/main --stat

# 4. merge
git merge upstream/main
```

- l10n 目录（`l10n.yaml`、`lib/l10n/*.arb`、生成文件、`test/support/l10n_test_utils.dart`）自 v2.1.12 起**必然冲突**（两侧同路径）——统一 **take-upstream 为基**，再把 keep-list 文案以**新增 key** 并入 en/zh/zh_Hans（带参必须 @metadata）
- 冲突集中在屏幕/组件文件的"英文串 vs l10n 调用"区域；上游大改版时按 **§4 的 take-upstream + 重打 overlay 打法**（含括号配平扫描、ARB 字典回填、新串扫描）
- merge 前先打锚点：`git tag pre-<ver>-merge HEAD`（后续 diff/计数守卫的参照）；merge 后overlay 守卫（2026-10-05 起替代 l10n 计数对照）：`git grep -cE "usage_bar_summary|isAnswerPreview|TtsVoiceConfig|speech_recognition_use_keyboard|heroTag" -- lib` 逐项仍在 + `git diff pre-<ver>-merge -- lib/ ':!lib/l10n' | grep '^+' | grep -E "Text\('|labelText: '"` 扫新增硬编码 + 花括号配平扫描
- merge 后必须：`flutter gen-l10n` → `flutter analyze --no-pub --fatal-infos` → `flutter test --no-pub` → 全绿再构建（与 CI 三道门禁逐字一致）
- 上游若修改了 ARB key 或新增文案，需要在 `app_zh.arb` 补对应翻译
- CI 另有 versionCode 门禁（当前要求 base=**2152**，`pubspec.yaml` 的 `2.1.12+2152` 别动；release.yml 只在打 tag 时跑签名构建，无 signing block 直接失败）
- release 分包：胖包 ~62MB，`flutter build apk --release --split-per-abi` 后每 ABI ~22MB（小米 8 用 arm64）

## 本机构建环境（Windows）

- 国内网络：`~/.gradle/init.d/aliyun-mirror.gradle`（阿里云镜像，勿提交到仓库）
- Windows Kotlin 缓存锁：`~/.gradle/gradle.properties` 有 `kotlin.incremental=false` + `kotlin.compiler.execution.strategy=in-process`
- release APK 无签名配置 → 用 `apksigner` + `~/.android/debug.keystore` 补签：
  ```bash
  apksigner sign --ks "C:/Users/<user>/.android/debug.keystore" --ks-pass pass:android \
    --key-pass pass:android --ks-key-alias androiddebugkey \
    --out app-<abi>-release-signed.apk app-<abi>-release.apk
  ```
- 模拟器调试：`adb` 在 `%LOCALAPPDATA%/Android/Sdk/platform-tools/`，debug 包名 `com.hermesagent.hermes_android.dev`
