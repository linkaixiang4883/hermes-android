# hermes-android 汉化维护手册

本仓库在 upstream（rusty4444/hermes-android）基础上做了**中文界面汉化（i18n）**，使用 Flutter 标准 gen-l10n 方案。以下内容供任何会话在本目录工作时自动加载。

## 本地化基础设施

- `l10n.yaml` — gen-l10n 配置（生成文件输出到 `lib/l10n/`，**必须提交**，CI 的 analyze 用 `--no-pub`）
- `lib/l10n/app_en.arb` — 英文模板（618 条 key：main 基线 612 + exp 用量条 4 + 项目归组 2，含 `@key` placeholder 元数据）
- `lib/l10n/app_zh.arb` — 中文翻译
- `lib/l10n/l10n.dart` — `context.l10n` 扩展（`AppLocalizations.of(this)` 的便捷封装）
- `lib/l10n/app_localizations*.dart` — 生成文件，改 ARB 后运行 `flutter gen-l10n` 重新生成

### 文案修改流程

1. 改 `app_en.arb`（模板）+ `app_zh.arb`（中文）
2. 带参数的 key 需要在 en 模板加 `@key` placeholders 元数据（int/String 类型）
3. `flutter gen-l10n`
4. `flutter analyze --no-pub --fatal-infos` + `flutter test --no-pub` 验证（与 CI 完全一致的命令）
5. **提交生成文件**（CI 用 `--no-pub`，不依赖重新生成）

### 铁律

- 新增 UI 文案必须走 `context.l10n.xxx`，**禁止硬编码英文**（除非是品牌名/协议字段/日志）
- 服务端下发的数据（消息内容、工具名、模型名）**不翻译**
- 模型层 getter 保持英文（测试断言依赖），UI 显示用 `Localized` 变体（如 `statusLabelLocalized`）
- 测试文件 pump widget 时需要 l10n 包裹：`test/support/l10n_test_utils.dart` 的 `l10nTestDelegates`/`l10nTestSupportedLocales`

## 汉化改动范围（基线 v2.1.0，2026-09-05 re-i18n 六批做完，612 key；2026-09-14 功能修复后 618 key）

- v2.0.x 旧屏（chat/cron/memory/session_list/settings/skills + main.dart）
- v2.1.0 新屏全量：Workspace 壳/Home/Activity/More pane/Projects pane + 项目详情/Chats 搜索 + Spaces/文件屏/各类 sheet 与卡片/消息代码块
- 枚举状态标签本地化变体（gateway_activity/insight/sensitive_prompt + HomeSectionKind/ActivityGroupKind/NewChatMode/ShareFavoriteAction/TextSizePreference 的 `xxxLocalized`，模型层英文 getter 不动）
- 纯函数 builder 传 `required AppLocalizations l10n`（buildMoreSections/buildActivityFeed/buildNewChatOptions；测试用同步 `lookupAppLocalizations(Locale('en'))`，sync test 零改异步）
- voice_composer_controller 注入 `AppLocalizations? l10n`（null 时保持英文，测试兼容）
- main.dart：`HermesApp.getLocale/setLocale` + 设置页语言切换器（System/English/中文，prefs key `app_locale`，默认跟随系统）
- 35 个测试文件加 l10n delegates（上游新增测试若 pump 用到 `context.l10n` 的 widget 也必须加）+ `test/arb_parity_test.dart`（en/zh key 对等 + 占位符元数据）+ `test/zh_smoke_test.dart`（zh 真泵冒烟）
- 门禁：`analyze --fatal-infos` 0 + `flutter test` **1019** 全绿（2026-09-14；main 基线 1002 + 项目归组/思考块修复新增 17）
- **实验分支 `exp/context-usage-display`（已合并到 main，`803c7bd`）**：聊天输入框用量条（WS `session.context_breakdown` 主路径 + REST 流尾 triple fallback，不持久化），ARB 612→616；压缩按钮曾落地 6 commit，真机端到端走通过，后因复杂度超支整段回退（`acad605`，reflog 可捞 90 天），结论归档于 `.hermes/plans/2026-09-06_024500-compress-button.md` 尾部"调研结论归档"；分支现仅保留用量条，用量 plan 见 `.hermes/plans/2026-09-05_233700-token-usage-display.md`
- **已知未翻（有意）**：底部导航 5 词（YAGNI，翻要改 shell 签名+语义断言）、`relative_time` 紧凑格式、发往模型的 prompt 模板、存库 `Session.title`、服务端数据/日志/协议字段
- **本地语音增强（非上游，STT/TTS）**：`TtsVoiceConfig` 跟随系统引擎按 App 语言（`df72878`）；STT 无服务弹键盘语音引导（`4c4670a`同步/异步+`a46f5c1`自动关闭+`02fd875`有结果不提示）；`AndroidManifest` 已补 `RecognitionService` queries（小米 8 实锤系统组件残缺）；记忆屏 Chip 深底显式白字（`bd31115`，hermesTheme 下默认深色字会糊进背景）

## 项目归组 & 思考块修复（2026-09-14，commit `2d189c4` + `8b81a7d`）

**背景**：上游 App 的项目归组调 `projects.assign_session`——官方 Hermes **从未实现**该 RPC（`projects.*` 全集里没有它；全仓 33752 commit pickaxe 零命中），所以「新建聊天」在项目里必失败；移动会话/快聊提升/Spaces 迁移同一条死路。官方语义是：**会话属于哪个项目，由它的工作目录推导**（`project_for_path`）。

**现在的实现（改这四类行为前先读这段）**：

| 场景 | 走哪条 RPC | 备注 |
|---|---|---|
| 新建项目聊天 | `session.create {cwd: 项目目录}`（仅 create 分支带 cwd，**resume 分支不带**） | 会话出生即锚定项目目录；首轮系统提示词据此注入项目 AGENTS.md 链（与桌面端同机制） |
| 移动已有会话 / 快聊提升 / Spaces 迁移 | `session.workspace.move {session_key, cwd}` | 用会话的 **stored id**（来自服务端列表）；立刻改工作目录/终端/项目树 |
| 移动到「Unassigned」 | 同上，cwd = `config.get{key:'project'}` 返回的网关默认工作区 | 语义 = 桌面端的游离会话 |
| ~~`projects.assign_session`~~ | **已从 App 全链路删除**（`ProjectsGatewayClient.assignSession` 与仓库同名方法） | 上游 merge 时**不要把它带回来**；相关测试与 mock 也已换成 `session.workspace.move` |

**系统提示词换血时机（别承诺"移动后立刻带上下文"）**：move 只改 `session["cwd"]` + 终端 pin + DB 行 + 项目树；系统提示词每会话只构建一次并落库复用，**新项目的文档要等该会话下次「压缩上下文」或「运行时重建后重开」才加载**（`conversation_compression.py` 压缩边界重建；`_stored_prompt_matches_runtime` 按 cwd 漂移判定重建；活会话 resume 走 `_resume_reuse_live` 复用，不重建）。UI 文案 `projectMoveContextPending` 就是在说这件事。

**思考块**：服务端 `reasoning.available` 装的是**回答正文前 500 字**（`agent/turn_response_intake.py` `_relay_thinking`），App 原先按 replace 处理会把流式真思考盖掉。现在 `GatewayReasoningUpdate.isAnswerPreview` 判定"实为回答摘要"就丢弃该更新（`test/chat_reasoning_replace_test.dart` 钉住）。

**QA / 门禁**：`analyze --no-pub --fatal-infos` 0 + `flutter test --no-pub` 1019 全绿。真机验收两种：① 手点三步（Projects → 项目 → 新建聊天 → 发消息）后查库 `SELECT id,cwd FROM sessions ORDER BY started_at DESC LIMIT 3`，**cwd 必须等于项目目录**；② `flutter test integration_test/project_chat_filing_test.dart -d <id>`（自动点完整个流程），但**该命令每次都卸载重装 dev 包 → App 数据（连接+密钥）被清空**，跑完需重建连接，且 MIUI 锁屏时会静默拦截 USB 安装。完整记录见 `.hermes/plans/2026-09-13_122432-reasoning-and-project-chat-fix.md`（含机制证据、实施记录、收尾步骤）。

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

- 新增文件（l10n.yaml、lib/l10n/、test/support/l10n_test_utils.dart）零冲突
- 冲突集中在屏幕/组件文件的"英文串 vs l10n 调用"区域（机械冲突，保留 l10n 调用即可）
- merge 后必须：`flutter gen-l10n` → `flutter analyze --no-pub --fatal-infos` → `flutter test --no-pub` → 全绿再构建（与 CI 三道门禁逐字一致）
- 上游若修改了 ARB key 或新增文案，需要在 `app_zh.arb` 补对应翻译
- CI 另有 versionCode 门禁（当前要求 base=2141，`pubspec.yaml` 的 `2.1.1+2141` 别动；release.yml 只在打 tag 时跑签名构建，#96 起无 signing block 直接失败）
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
