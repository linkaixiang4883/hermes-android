// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Hermes 智能体';

  @override
  String get cancel => '取消';

  @override
  String get retry => '重试';

  @override
  String get dismiss => '关闭';

  @override
  String get refresh => '刷新';

  @override
  String get on => '开';

  @override
  String get off => '关';

  @override
  String get unknown => '未知';

  @override
  String get youHeader => '## 你';

  @override
  String get hermesHeader => '## Hermes';

  @override
  String get chooseImage => '选择图片';

  @override
  String get chooseImages => '选择多张图片';

  @override
  String get takePhoto => '拍照';

  @override
  String get chooseFiles => '选择文件';

  @override
  String get fileTypeHint => '文档、压缩包、音频、视频或数据';

  @override
  String get unableToPrepareImage => '无法处理这张图片，请换一张试试。';

  @override
  String get imageSelectionInterrupted => '图片选择被中断，请重试。';

  @override
  String unableToPrepareImageNamed(String name) {
    return '无法处理「$name」。';
  }

  @override
  String get configureDesktopGatewayForFiles =>
      '请先配置有效的 Desktop Gateway 地址，再添加附件。';

  @override
  String maxAttachmentDrafts(int count) {
    return '最多可附加 $count 个项目。';
  }

  @override
  String filesSkipped(int count) {
    return '已跳过 $count 个文件：超出数量限制、文件过大、无法读取或文件名敏感。';
  }

  @override
  String get unableToPrepareFile => '无法处理这个文件，请换一个试试。';

  @override
  String retryingAttachment(String name) {
    return '正在重试 $name…';
  }

  @override
  String get fileAttachedPendingCatalog => '文件已附加；文档目录登记中。';

  @override
  String retryFailed(String name) {
    return '重试 $name 失败，草稿和消息已保留。';
  }

  @override
  String get configureDesktopGatewayForModel =>
      '请先配置 Desktop Gateway 地址和 Dashboard 凭据，才能选择聊天模型。';

  @override
  String get modelAndThinkingForChat => '本会话的模型与思考强度';

  @override
  String get profileDefaultLabel => '配置文件默认';

  @override
  String get thisChatLabel => '仅本会话';

  @override
  String profileDefaultWithModel(String model) {
    return '配置文件默认：$model';
  }

  @override
  String get thinkingEffort => '思考强度';

  @override
  String get applyToThisChat => '应用于本会话';

  @override
  String couldNotLoadModels(String error) {
    return '无法加载此配置文件的模型：$error';
  }

  @override
  String modelAppliesToChat(String model, String effort) {
    return '$model • $effort 现在仅应用于本会话。';
  }

  @override
  String modelNotChanged(String error) {
    return '模型未更改：$error';
  }

  @override
  String get responding => '正在响应…';

  @override
  String get chatActions => '聊天操作';

  @override
  String get exportShare => '导出 / 分享';

  @override
  String get chooseChatModel => '选择聊天模型';

  @override
  String get attachmentDrafts => '附件草稿';

  @override
  String get addAttachment => '添加附件';

  @override
  String get attachImageOrFile => '附加图片或文件';

  @override
  String get message => '消息';

  @override
  String get typeAMessage => '给 Hermes 发消息…';

  @override
  String get spokenReplies => '语音回复';

  @override
  String get spokenRepliesOn => '语音回复已开启';

  @override
  String get spokenRepliesOff => '语音回复已关闭';

  @override
  String get stopResponse => '停止响应';

  @override
  String get sendMessage => '发送消息';

  @override
  String get send => '发送';

  @override
  String get failedToLoadMessages => '消息加载失败';

  @override
  String get messageCopied => '消息已复制';

  @override
  String get copyMessage => '复制消息';

  @override
  String get messageActions => '消息操作';

  @override
  String get you => '你';

  @override
  String get readAloud => '朗读';

  @override
  String get editAndResend => '编辑并重发';

  @override
  String get regenerateResponse => '重新生成回复';

  @override
  String get regenerateFromPreceding => '根据上一条消息重新生成';

  @override
  String voiceSetupFailed(String error) {
    return '语音设置失败：$error';
  }

  @override
  String get speechRecognitionUnavailable => '语音识别不可用';

  @override
  String get speechRecognitionNoService => '语音识别服务不可用，请使用输入法键盘上的语音按钮';

  @override
  String get readingResponseAloud => '正在朗读回复…';

  @override
  String get readAloudUnavailable => '此设备不支持朗读';

  @override
  String get responseReady => '回复已就绪';

  @override
  String get turnCompleted => '回合已完成';

  @override
  String get recoveringHermes => '正在恢复 Hermes…';

  @override
  String hermesRecoveryUnavailable(String error) {
    return 'Hermes 恢复不可用：$error';
  }

  @override
  String get hermesWaitingInput => 'Hermes 正在等待输入…';

  @override
  String get hermesResponding => 'Hermes 正在响应…';

  @override
  String get recoveryStoppedSafely => 'Hermes 已安全停止恢复，未重新发送消息。';

  @override
  String get deliveryUncertainRecovering => '投递状态不确定，正在恢复且不会重发…';

  @override
  String get legacyTransportNotice => '后台恢复不可用——旧版传输';

  @override
  String get startingHermes => '正在启动 Hermes…';

  @override
  String get preparingAttachments => '正在准备附件…';

  @override
  String uploadingAttachment(int index, int total, String name) {
    return '正在上传 $index/$total：$name';
  }

  @override
  String attachedFileLabel(String name) {
    return '[附件：$name]';
  }

  @override
  String get desktopGatewayNotConfigured => '此连接未配置 Desktop Gateway。';

  @override
  String couldNotDenyCommand(String error) {
    return '无法拒绝该命令：$error';
  }

  @override
  String get couldNotSkipQuestion => '无法跳过 Hermes 的提问。';

  @override
  String get responseStopped => '响应已停止。';

  @override
  String get responseClosedNoTurn => '响应已在本地关闭；未找到活动的网关回合。';

  @override
  String responseClosedStopFailed(String error) {
    return '响应已在本地关闭；停止网关失败：$error';
  }

  @override
  String sendFailed(String error) {
    return '发送失败：$error';
  }

  @override
  String get thinkingEffortNone => '关闭（不思考）';

  @override
  String get thinkingEffortMinimal => '最低';

  @override
  String get thinkingEffortLow => '低';

  @override
  String get thinkingEffortMedium => '中';

  @override
  String get thinkingEffortHigh => '高';

  @override
  String get thinkingEffortXhigh => '极高';

  @override
  String get thinkingEffortMax => '最大';

  @override
  String get thinkingEffortUltra => '超强';

  @override
  String get addConnection => '添加连接';

  @override
  String get editConnection => '编辑连接';

  @override
  String get addGatewayConnection => '添加网关连接';

  @override
  String get editGatewayConnection => '编辑网关连接';

  @override
  String get noConnections => '暂无连接';

  @override
  String get restoreConfiguration => '恢复配置';

  @override
  String get tapPlusToAdd => '点击 + 添加远程 Hermes 网关\n(API Server，端口 8642)';

  @override
  String get connectionLabel => '名称';

  @override
  String get hostField => '主机';

  @override
  String get hostHint =>
      '192.168.1.50、100.x.y.z 或 hermes-machine.tailnet.ts.net';

  @override
  String get portField => '端口';

  @override
  String get portHint => '8642（API Server）';

  @override
  String get apiKeyField => 'API 密钥';

  @override
  String get apiKeyHint => '来自 ~/.hermes/.env 的 API_SERVER_KEY';

  @override
  String get serverRequiresApiKey => '服务器需要 API 密钥，请输入你的 API_SERVER_KEY。';

  @override
  String get updateApiKey => '更新 API 密钥';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get key => '密钥';

  @override
  String get dashboardProxySettings => 'Dashboard / 代理设置';

  @override
  String get gatewayPathPrefix => '网关路径前缀';

  @override
  String get dashboardPathPrefix => 'Dashboard 路径前缀';

  @override
  String get dashboardBehindProxy => 'Dashboard 位于代理之后';

  @override
  String get dashboardPort => 'Dashboard 端口';

  @override
  String get dashboardPortHint => '留空使用默认值（9119）';

  @override
  String get customProxyDetails => '自定义代理与 Dashboard 详情';

  @override
  String get egGatewayPrefix => '例如 /profile/peter';

  @override
  String get egDashboardPrefix => '例如 /dashboard';

  @override
  String get gatewayPrefixHint => '例如 /profile/peter（/api/ 和 /v1/ 之前的代理路径）';

  @override
  String get dashboardPrefixHint => '例如 /dashboard（/api/ 之前的代理路径）';

  @override
  String get proxyInjectsAuth => '代理注入认证；应用发送纯净请求';

  @override
  String get nginxInjectsAuth => 'Nginx 注入认证——应用发送纯净请求';

  @override
  String get usernameOptional => '用户名（可选）';

  @override
  String get passwordOptional => '密码（可选）';

  @override
  String get invalidPortNumber => '端口号无效。';

  @override
  String get invalidApiKey401 => 'API 密钥无效，服务器返回 401。';

  @override
  String get apiKeyNotStoredSecurely => 'API 密钥无法安全存储。';

  @override
  String get dashboardCredsNotStoredSecurely => 'Dashboard 凭据无法安全存储。';

  @override
  String get connectionNotStoredSecurely => '连接无法安全存储。';

  @override
  String get connectionNotDeletedSafely => '连接无法安全删除。';

  @override
  String cannotReachHostPort(String host, int port) {
    return '无法连接 $host:$port。';
  }

  @override
  String couldNotReachGatewayAt(String host, int port, String prefix) {
    return '无法连接/认证网关 API $host:$port$prefix。';
  }

  @override
  String couldNotReachDashboardAt(String host, int port) {
    return '无法连接/认证 Dashboard $host:$port。请检查端口与凭据。';
  }

  @override
  String cannotReachHostPortCheck(String host, int port) {
    return '无法连接 $host:$port。请检查主机与端口。';
  }

  @override
  String get gatewayOkDashboardFailed =>
      '网关已连接，但 Dashboard 无法访问或认证。请检查 Dashboard 设置，或清除后跳过。';

  @override
  String get dashboardDetailsHelp =>
      '用于托管路径前缀以及设置、记忆、技能和定时任务标签页。开放 Dashboard 请留空用户名/密码，或在反向代理注入认证时启用代理模式。';

  @override
  String get dashboardPortHelp => '可选。用于记忆/定时任务/技能/设置标签页。留空使用默认端口（9119）。';

  @override
  String get rename => '重命名';

  @override
  String get newChat => '新建聊天';

  @override
  String get switchProfile => '切换配置文件';

  @override
  String get profile => '配置文件';

  @override
  String get renameChat => '重命名聊天';

  @override
  String couldNotRenameChat(String error) {
    return '无法重命名聊天：$error';
  }

  @override
  String get branchChat => '分支聊天';

  @override
  String sessionTitleBranch(String title) {
    return '$title 分支';
  }

  @override
  String get createBranch => '创建分支';

  @override
  String get noMessagesInDesktopSession => '该聊天在 Desktop 会话中还没有可用消息。';

  @override
  String couldNotBranchChat(String error) {
    return '无法分支聊天：$error';
  }

  @override
  String get branchCreated => '已在 Hermes 历史中创建分支。';

  @override
  String get untitledSession => '未命名会话';

  @override
  String get deleteSessionTitle => '删除会话？';

  @override
  String deleteSessionConfirm(String title) {
    return '从远程 Hermes 历史中删除「$title」？此操作无法撤销。';
  }

  @override
  String get sessionDeleted => '已从远程 Hermes 删除会话。';

  @override
  String couldNotDeleteSession(String error) {
    return '无法删除会话：$error';
  }

  @override
  String get memoryTab => '记忆';

  @override
  String get cronJobsTab => '定时任务';

  @override
  String get skillsTab => '技能';

  @override
  String get settingsTab => '设置';

  @override
  String connectingTo(String url) {
    return '正在连接 $url…';
  }

  @override
  String get gatewayMustBeRunning =>
      '请确保 Gateway API Server 正在运行\n(hermes gateway status)';

  @override
  String get connectionIssue => '连接问题';

  @override
  String get noSessionsYet => '暂无会话';

  @override
  String get tapPlusNewChat => '点击 + 按钮开始新聊天';

  @override
  String get searchChats => '搜索聊天';

  @override
  String get searchHintAi => '让 AI 帮你找对话';

  @override
  String get searchHintServer => '搜索全部消息内容';

  @override
  String get searchHintLocal => '搜索已加载的对话';

  @override
  String get branch => '分支';

  @override
  String sessionMeta(int count, String model, String time) {
    return '$count 条消息 • $model • $time';
  }

  @override
  String get voice => '语音';

  @override
  String profileDefaultSetTo(String model) {
    return '配置文件默认模型已设为 $model。已单独设置模型的聊天保持其覆盖。';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String get failedToLoadSettings => '设置加载失败';

  @override
  String get profileDefaultModel => '配置文件默认模型';

  @override
  String changesDefaultFor(String label) {
    return '更改 $label 的默认模型。在聊天中使用选择器可仅覆盖该对话。';
  }

  @override
  String get currentProfileDefault => '当前配置文件默认';

  @override
  String contextTokens(int tokens) {
    return '上下文：$tokens tokens';
  }

  @override
  String get provider => '提供商';

  @override
  String get model => '模型';

  @override
  String get setProfileDefault => '设为配置文件默认';

  @override
  String get appearance => '外观';

  @override
  String get sessionSources => '会话来源';

  @override
  String get connection => '连接';

  @override
  String get baseUrl => '基础 URL';

  @override
  String get about => '关于';

  @override
  String get hermesAgentForAndroid => 'Hermes Agent Android 版';

  @override
  String versionLabel(String version) {
    return '版本 $version';
  }

  @override
  String get aboutDescription =>
      '在手机上浏览和管理你的 Hermes Agent 会话。连接运行在本地网络中的 Hermes dashboard。';

  @override
  String get verboseMode => '详细模式';

  @override
  String get showToolCalls => '显示工具调用、思考和消息元数据';

  @override
  String get systemTheme => '跟随系统';

  @override
  String get darkTheme => '深色';

  @override
  String get lightTheme => '浅色';

  @override
  String get noTtsVoices => '未找到 TTS 语音。\n请安装 Google Text-to-Speech 并下载语音数据。';

  @override
  String get autoDeviceDefault => '自动（设备默认）';

  @override
  String get sessionSourceAutonomous => '自主智能体';

  @override
  String get sessionSourceExternalApi => '外部 API 客户端';

  @override
  String get sessionSourceCli => '命令行聊天';

  @override
  String get sessionSourceScheduled => '定时任务';

  @override
  String get sessionSourceDesktop => '桌面应用';

  @override
  String get sessionSourceDiscord => 'Discord 聊天';

  @override
  String get sessionSourceGatewayApi => '网关 API 访问';

  @override
  String get sessionSourcePhone => '手机或平板';

  @override
  String get sessionSourceSignal => 'Signal 消息';

  @override
  String get sessionSourceSlack => 'Slack 聊天';

  @override
  String failed(String error) {
    return '失败：$error';
  }

  @override
  String get untitled => '未命名';

  @override
  String get jobResumed => '任务已恢复';

  @override
  String get jobPaused => '任务已暂停';

  @override
  String get deleteCronJob => '删除定时任务';

  @override
  String deleteJobConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String deletedJob(String name) {
    return '已删除「$name」';
  }

  @override
  String deleteFailed(String error) {
    return '删除失败：$error';
  }

  @override
  String get jobTriggered => '任务已触发';

  @override
  String get addCronJob => '添加定时任务';

  @override
  String get add => '添加';

  @override
  String get cronJobAdded => '定时任务已添加';

  @override
  String failedToAddJob(String error) {
    return '添加任务失败：$error';
  }

  @override
  String get editCronJob => '编辑定时任务';

  @override
  String get cronJobUpdated => '定时任务已更新';

  @override
  String failedToUpdateJob(String error) {
    return '更新任务失败：$error';
  }

  @override
  String get name => '名称';

  @override
  String get egDailyBackup => '例如：每日备份';

  @override
  String get prompt => '提示词';

  @override
  String get whatShouldAgentDo => '智能体应该做什么？';

  @override
  String get schedule => '计划';

  @override
  String get egCronSchedule => '例如：0 9 * * * 或 every 2h';

  @override
  String get scriptOnly => '仅脚本（无智能体）';

  @override
  String get scriptOnlyHelp => '用于由脚本支撑的定时任务。';

  @override
  String get requiredFields => '名称、提示词和计划为必填项';

  @override
  String get cronJobs => '定时任务';

  @override
  String get addNewCronJob => '添加新定时任务';

  @override
  String get failedToLoadCronJobs => '定时任务加载失败';

  @override
  String get noCronJobs => '暂无定时任务';

  @override
  String get triggerNow => '立即触发';

  @override
  String get edit => '编辑';

  @override
  String get resume => '恢复';

  @override
  String get pause => '暂停';

  @override
  String lastRun(String time) {
    return '上次：$time';
  }

  @override
  String nextRun(String time) {
    return '下次：$time';
  }

  @override
  String get memory => '记忆';

  @override
  String sourceLabel(String source) {
    return '来源：$source';
  }

  @override
  String get failedToLoadMemory => '记忆加载失败';

  @override
  String get noMemoryEntries => '暂无记忆条目';

  @override
  String get memoryHelp => '记忆条目是智能体跨会话记住的事实。\n它们在 ~/.hermes/config.yaml 中配置。';

  @override
  String skillsCount(int count) {
    return '技能（$count）';
  }

  @override
  String get failedToLoadSkills => '技能加载失败';

  @override
  String get noSkillsFound => '未找到技能';

  @override
  String get telegramMessages => 'Telegram 消息';

  @override
  String get developerToolCalls => '开发者工具调用';

  @override
  String get terminalSessions => '终端会话';

  @override
  String get whatsappMessages => 'WhatsApp 消息';

  @override
  String attachmentOf(int index, int total) {
    return '附件 $index / $total';
  }

  @override
  String get uploadFailedTapRetry => '上传失败 • 点击重试';

  @override
  String get moveAttachmentPrevious => '上移附件';

  @override
  String get moveAttachmentNext => '下移附件';

  @override
  String get retryUpload => '重试上传';

  @override
  String get removeAttachment => '移除附件';

  @override
  String get readyToUpload => '准备上传';

  @override
  String get uploading => '上传中';

  @override
  String get uploaded => '已上传';

  @override
  String get uploadFailed => '上传失败';

  @override
  String newCount(int count) {
    return '$count 条新消息';
  }

  @override
  String get latest => '最新';

  @override
  String get noNewMessages => '没有新消息';

  @override
  String get oneNewMessage => '1 条新消息';

  @override
  String newMessages(int count) {
    return '$count 条新消息';
  }

  @override
  String get goToEnd => '跳到末尾';

  @override
  String failuresSummary(int failures, int total) {
    return '$failures 个失败 • 共 $total 个';
  }

  @override
  String completedCount(int count) {
    return '$count 个已完成';
  }

  @override
  String get hermesActivity => '工具动态';

  @override
  String couldNotSendApproval(String error) {
    return '无法发送审批：$error';
  }

  @override
  String get allowOnce => '允许一次';

  @override
  String get allowForSession => '本次会话允许';

  @override
  String get confirmAlwaysAllow => '确认始终允许';

  @override
  String get alwaysAllow => '始终允许';

  @override
  String get deny => '拒绝';

  @override
  String get runOnlyThisCommand => '仅运行此命令。';

  @override
  String get allowMatchingCommands => '在此 Hermes 会话结束前允许匹配的命令。';

  @override
  String get savePermanentRule => '在 Hermes 配置中保存永久规则。';

  @override
  String get doNotRunCommand => '不运行此命令。';

  @override
  String get approvalNeeded => '需要审批';

  @override
  String get command => '命令';

  @override
  String get permanentRuleWarning => '这将在 Hermes 中创建永久规则。确认前请检查完整命令。';

  @override
  String get couldNotAcceptAnswer => 'Hermes 无法接受该回答，请重试。';

  @override
  String get hermesNeedsInput => 'Hermes 需要你的输入';

  @override
  String get selectOneOrMore => '选择一个或多个选项，然后继续。';

  @override
  String get selectOneOrEnterOther => '选择一个选项，或输入其他回答。';

  @override
  String get otherAnswer => '其他回答';

  @override
  String get yourAnswer => '你的回答';

  @override
  String get skip => '跳过';

  @override
  String get continueLabel => '继续';

  @override
  String get reasoning => '思考过程';

  @override
  String get hermesReasoningDetails => 'Hermes 思考详情';

  @override
  String delegatedTasksCompleted(int count) {
    return '$count 个委派任务已完成';
  }

  @override
  String delegatedTasksActive(int count) {
    return '$count 个委派任务进行中';
  }

  @override
  String get hermesDidNotAcceptResponse => 'Hermes 未接受该回复，请重试。';

  @override
  String get sensitiveValueNotice =>
      '该值将直接发送到当前活动的 Hermes 网关，此 Android 应用不会保存它。';

  @override
  String get textSize => '文字大小';

  @override
  String get textSizeHelp => '明确选择会调整 Android 无障碍文字大小；跟随系统则不更改。';

  @override
  String get textSizePreview => '文字大小预览';

  @override
  String get preview => '预览';

  @override
  String get textScalingActive => 'Hermes 保持 Android 无障碍文字缩放开启。';

  @override
  String listeningElapsed(String elapsed) {
    return '正在聆听 • $elapsed';
  }

  @override
  String get stopVoiceInput => '停止语音输入';

  @override
  String get stop => '停止';

  @override
  String get cancelVoiceInput => '取消语音输入';

  @override
  String get startVoiceInput => '开始语音输入';

  @override
  String get speakToHermes => '对 Hermes 说话';

  @override
  String get usingOneTool => 'Hermes 正在使用工具';

  @override
  String usingTools(int count) {
    return 'Hermes 正在使用 $count 个工具';
  }

  @override
  String get dashboardUsernameOptional => 'Dashboard 用户名（可选）';

  @override
  String get dashboardPasswordOptional => 'Dashboard 密码（可选）';

  @override
  String get desktopGatewayUrlOptional => 'Desktop Gateway 地址（可选）';

  @override
  String get desktopGatewayHelper => '通过 Desktop 远程网关启用文件附件功能。';

  @override
  String get toolRunning => '运行中';

  @override
  String get toolPreparing => '准备中';

  @override
  String get toolWorking => '执行中';

  @override
  String get toolCompleted => '已完成';

  @override
  String toolCompletedIn(String duration) {
    return '用时 $duration 完成';
  }

  @override
  String get toolFailed => '失败';

  @override
  String toolFailedAfter(String duration) {
    return '执行 $duration 后失败';
  }

  @override
  String get backgroundTaskCompleted => '后台任务已完成';

  @override
  String backgroundTaskIdCompleted(String taskId) {
    return '后台任务 $taskId 已完成';
  }

  @override
  String get hermesReview => 'Hermes 审查';

  @override
  String get adminPasswordNeeded => '需要管理员密码';

  @override
  String get sudoPasswordDescription => 'Hermes 需要 sudo 密码以执行待处理的终端命令。';

  @override
  String get sudoPasswordField => 'Sudo 密码';

  @override
  String get secretNeeded => '需要密钥';

  @override
  String get secretDescription => 'Hermes 需要密钥以执行待处理的技能。';

  @override
  String get secretValueField => '密钥值';

  @override
  String get dictationReady => '听写完成，可编辑';

  @override
  String get approvalFallbackDescription => 'Hermes 想要运行一条命令。';

  @override
  String get clarifyFallbackDescription => 'Hermes 需要更多信息才能继续。';

  @override
  String get homeUnreachable => '无法连接到 Hermes';

  @override
  String get homeUnreachableHint => 'Home 需要读取你的最近聊天来判断轻重缓急，请确认网关可达后重试。';

  @override
  String get homeNothingNeedsYou => '暂无待办';

  @override
  String get homeAllClearHint => '没有被阻塞、进行中或待恢复的聊天，随时可以新建一个。';

  @override
  String get offlineShowingLastKnown => '离线——显示上次已知的内容。';

  @override
  String get untitledChat => '未命名聊天';

  @override
  String get activityUnreadable => '活动记录读取失败';

  @override
  String get activityJournalHint =>
      'Activity 通过持久化回合日志来掌握 Hermes 的动态，请确认网关可达后重试。';

  @override
  String get inboxClear => '暂无事项';

  @override
  String get activityNothingRunning => '没有正在运行的任务';

  @override
  String get activityNoAttention => '没有需要你处理或失败的回合。';

  @override
  String get activityEmptyHint => '没有被阻塞、进行中或刚完成的回合，你发起的任务会显示在这里。';

  @override
  String andCountMore(int count) {
    return '还有 $count 项';
  }

  @override
  String get homeSectionNeedsYou => '需要你处理';

  @override
  String get homeSectionRunning => '进行中';

  @override
  String get homeSectionWorking => '继续处理';

  @override
  String get homeSectionCompleted => '最近完成';

  @override
  String get activityGroupFailed => '失败';

  @override
  String get activityGroupCompleted => '已完成';

  @override
  String get turnRecoveryFailed => '回合恢复失败';

  @override
  String get turnWaitingInput => '等待你的输入';

  @override
  String get turnFailedState => '该回合失败了';

  @override
  String get turnStopped => '已停止';

  @override
  String get turnStalled => '停滞——Hermes 长时间无更新';

  @override
  String get turnSubmitted => '已提交，等待 Hermes 响应';

  @override
  String get turnRunningState => '进行中';

  @override
  String get moreSectionWorkspace => '工作区';

  @override
  String get unassignedChats => '未归档聊天';

  @override
  String get unassignedChatsDesc => '尚未归入任何项目的聊天';

  @override
  String get archivedQuickChats => '已归档的闪聊';

  @override
  String get archivedQuickChatsDesc => '查看或转正超过保留期的闪聊';

  @override
  String get files => '文件';

  @override
  String get filesDesc => '浏览项目背后的 miniserver 目录';

  @override
  String get assets => '素材';

  @override
  String get assetsDesc => '产物、附件与生成的媒体';

  @override
  String get moreSectionOrganization => '整理';

  @override
  String get pinBatchUndo => '置顶、批量与撤销';

  @override
  String get pinBatchUndoDesc => '跨设备排序与可撤销的批量整理';

  @override
  String get aiFiling => 'AI 辅助归档';

  @override
  String get aiFilingDesc => '推荐项目并从你的纠正中学习';

  @override
  String get moreSectionAutomation => '自动化';

  @override
  String get cronDesc => '计划任务及其上次运行';

  @override
  String get skillsTools => '技能与工具';

  @override
  String get skillsToolsDesc => 'Hermes 会的技能';

  @override
  String get memoryDesc => 'Hermes 记住的关于你的长期事实';

  @override
  String get moreSectionSystem => '系统';

  @override
  String get settingsDesc => '连接、外观与设备偏好';

  @override
  String get openDashboard => '打开 Hermes Dashboard';

  @override
  String get openDashboardDesc => '尚未原生化的功能都在已认证的网页 Dashboard 里';

  @override
  String get comingNext => '即将到来';

  @override
  String get moreNeedsDashboard => '需要可达的 Hermes Dashboard，请检查该连接的主机、端口和凭据。';

  @override
  String get moreNeedsAssets => '需要 Hermes 网关提供 Assets 索引。';

  @override
  String get moreNeedsPinUndo => '需要 Hermes 网关提供置顶排序、批量操作与撤销能力。';

  @override
  String get moreNeedsFiling => '需要 Hermes 网关提供归档学习能力。';

  @override
  String get cronRowTitle => '定时任务';

  @override
  String archiveProjectTitle(String name) {
    return '归档 $name？';
  }

  @override
  String get archiveHintPane => '项目将移入“已归档”，其中的聊天和文件保持不变，可随时恢复。';

  @override
  String get archiveHintDetail => '项目将移入“已归档”，其中的聊天和文件保持不变，之后仍可恢复。';

  @override
  String get projectsUnreachableHint => '请确认网关正在运行且可达，然后重试。';

  @override
  String get noProjectsYet => '暂无项目';

  @override
  String get noProjectsHint => '项目把相关的聊天、文件和动态收在一起，并与电脑上的 Hermes 保持同步。';

  @override
  String get createProjectAction => '新建项目';

  @override
  String get projectsTitle => '项目';

  @override
  String get reviewLocalSpaces => '查看本地空格';

  @override
  String get archivedSection => '已归档';

  @override
  String get compatExplanation =>
      '该 Hermes 网关版本过旧，不支持服务端项目，聊天只在本机分组。请升级 Hermes，以便在各设备间共享同一批项目。';

  @override
  String get compatModeTitle => '兼容模式';

  @override
  String get noSpacesOnDevice => '本机没有空格';

  @override
  String get noSpacesHint => '该网关的聊天尚未分组。在网关支持项目之前，分组只保留在本机。';

  @override
  String get onThisDevice => '本机';

  @override
  String get projectsOffline => '离线——显示上次已知的项目。';

  @override
  String get activeChip => '进行中';

  @override
  String get projectActions => '项目操作';

  @override
  String get renameProjectItem => '重命名项目';

  @override
  String get archiveProjectItem => '归档项目';

  @override
  String get restoreProjectItem => '恢复项目';

  @override
  String get deleteProjectItem => '删除项目';

  @override
  String get enterName => '输入名称';

  @override
  String get nameField => '名称';

  @override
  String get oneChat => '1 个聊天';

  @override
  String countChats(int count) {
    return '$count 个聊天';
  }

  @override
  String get createAction => '创建';

  @override
  String get moveConversation => '移动对话';

  @override
  String renameProjectTitle(String name) {
    return '重命名 $name';
  }

  @override
  String deleteProjectTitle(String name) {
    return '删除 $name？';
  }

  @override
  String get deleteHintDetail => '这将永久删除项目，其中的聊天不会被删除，会回到“未归档”。';

  @override
  String movedToProject(String label) {
    return '已移到 $label';
  }

  @override
  String get newProject => '新项目';

  @override
  String get spaceUnassigned => '未归档';

  @override
  String get moveToSpace => '移到空间';

  @override
  String get moveChat => '移动聊天';

  @override
  String projectActionFailed(String action, String error) {
    return '项目操作失败（$action）：$error';
  }

  @override
  String get projectChatsUnavailable => '项目聊天不可用';

  @override
  String get projectChatsUnavailableHint =>
      '该 Hermes 网关尚不支持在手机上打开项目，请升级服务端的 Hermes。';

  @override
  String get couldNotOpenProject => '无法打开该项目';

  @override
  String get couldNotOpenProjectHint => '请确认网关正在运行且可达，然后重试。';

  @override
  String get noChatsYet => '暂无聊天';

  @override
  String get noChatsYetHint => '在此项目发起的聊天会显示在这里，所有登录该 Hermes 的设备可见。';

  @override
  String get noMatches => '无匹配';

  @override
  String noMatchesHint(String query) {
    return '该项目中没有聊天匹配“$query”。';
  }

  @override
  String get chatsTab => '聊天';

  @override
  String get overviewTab => '概览';

  @override
  String get activityTab => '动态';

  @override
  String get conversationsInProject => '该项目中的对话';

  @override
  String get repositoriesHeader => '仓库';

  @override
  String get locationHeader => '位置';

  @override
  String get noFoldersYet => '暂无文件夹';

  @override
  String get noFoldersHint => '服务端尚未上报该项目的文件夹，可先去 More 用全局文件。';

  @override
  String get foldersHeader => '文件夹';

  @override
  String get assetsUnavailable => '素材不可用';

  @override
  String get assetsUnavailableHint => '需要 Hermes 网关提供 Assets 索引，才能按项目展示素材。';

  @override
  String get noActivityYet => '暂无动态';

  @override
  String get noActivityHint => '该项目中的聊天会在这里显示状态和上次动态。';

  @override
  String get runningStateLabel => '进行中';

  @override
  String get doneStateLabel => '已完成';

  @override
  String get chatsOffline => '离线——显示上次已知的聊天';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get archiveAction => '归档';

  @override
  String get moveConversationFailed => '移动对话失败';

  @override
  String get deleteProjectFailed => '删除项目失败';

  @override
  String couldNotActionProject(String action) {
    return '项目$action失败';
  }

  @override
  String get aiSearchModelTitle => 'AI 搜索模型';

  @override
  String get aiSearchModelHint => '该模型只把你的问题改写为简短的全文查询，使用主机上已配置的 provider 凭据。';

  @override
  String get chooseAiModelFirst => '使用 AI 搜索前请先选择 AI 搜索模型。';

  @override
  String searchFailed(String error) {
    return '会话搜索失败：$error';
  }

  @override
  String get chooseDestinationSpace => '选择目标空间';

  @override
  String get spaceFallback => '空间';

  @override
  String get useOnDevice => '使用本机搜索';

  @override
  String get searchModeLocal => '本机';

  @override
  String get searchModeLocalDesc => '标题、预览和模型';

  @override
  String get searchModeServer => '全文';

  @override
  String get searchModeServerDesc => '全部已存消息内容';

  @override
  String get searchModeAi => 'AI+全文';

  @override
  String get searchModeAiDesc => '选一个小模型来改写查询';

  @override
  String get changeAiSearchModel => '更换 AI 搜索模型';

  @override
  String get searchMode => '搜索模式';

  @override
  String aiSearchedFor(String query) {
    return 'AI 实际搜索：$query';
  }

  @override
  String get spaceEmptyHint => '该空间还没有聊天，点 + 新建一个。';

  @override
  String get unassignedEmptyHint => '没有未归档聊天。';

  @override
  String get searchNoContentMatches => '没有匹配的消息内容';

  @override
  String get spacesTitle => '空间';

  @override
  String get newSpace => '新建空间';

  @override
  String get renameSpace => '重命名空间';

  @override
  String get chooseSpaceDestination => '选择目标空间';

  @override
  String get spaceActions => '空间操作';

  @override
  String get createSpaceHint => '新建空间，把相关的对话分开存放。';

  @override
  String lastActivityDate(int month, int day, int year) {
    return '上次活跃 $month/$day/$year';
  }

  @override
  String get workspaceNavHint => '项目、动态——新导航';

  @override
  String get spaceAllChats => '全部聊天';

  @override
  String aiModelsLoadFailed(String error) {
    return 'AI 搜索模型加载失败：$error';
  }

  @override
  String downloadedFile(String filename) {
    return '$filename 已下载';
  }

  @override
  String saveFileTitle(String filename) {
    return '保存 $filename';
  }

  @override
  String get folderEmpty => '文件夹为空';

  @override
  String get folderEmptyHint => '该服务器文件夹中没有可见文件。';

  @override
  String get previewTruncated => '预览已截断';

  @override
  String get projectsUnavailable => '项目不可用';

  @override
  String get projectsNeedDesktopHint =>
      '项目需要 Desktop Gateway 连接，请给该连接加上 Desktop Gateway URL，以便跨设备整理聊天。';

  @override
  String get createProjectChatFailed => '项目聊天创建失败';

  @override
  String get loadConversationsFailed => '对话加载失败';

  @override
  String get loadConversationsHint => '请检查连接后重试。';

  @override
  String get searchConversations => '搜索对话';

  @override
  String get archivedViewEmpty => '超过保留期的闪聊会显示在这里。';

  @override
  String get newAction => '新建';

  @override
  String get openInbox => '打开收件箱';

  @override
  String openInboxCount(int n) {
    return '打开收件箱（$n）';
  }

  @override
  String get binaryPreviewUnavailable => '二进制预览不可用，请下载文件后打开。';

  @override
  String get previewUnavailable => '无预览';

  @override
  String get previewFailed => '文件预览失败';

  @override
  String get previewFailedHint => '请检查 Dashboard 连接后重试。';

  @override
  String get inboxTitle => '收件箱';

  @override
  String get openDashboardFailed => '无法打开 Hermes Dashboard';

  @override
  String get searchAllChats => '搜索全部聊天';

  @override
  String get downloadAction => '下载';

  @override
  String get fileRefAdded => '文件引用已加入聊天';

  @override
  String get addToChat => '加入聊天';

  @override
  String get promotedToProject => '已转正为项目聊天';

  @override
  String get promoteConversationFailed => '对话转正失败';

  @override
  String get promoteToProject => '转正为项目聊天';

  @override
  String get unassignedViewEmpty => '所有对话都已归入项目。';

  @override
  String get noViewMatches => '没有对话符合该视图。';

  @override
  String get nothingHereView => '空空如也';

  @override
  String get noMatchesView => '无匹配';

  @override
  String get projectFallback => '项目';

  @override
  String get archivedFilterEmpty => '已归档对话显示在这里。';

  @override
  String get recentFilterEmpty => '过去七天没有任何变化。';

  @override
  String get loadFilesFailed => '文件加载失败';

  @override
  String get prepareSharedFilesFailed => '分享文件准备失败';

  @override
  String downloadFailed(String error) {
    return '下载失败：$error';
  }
}
