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
  String get typeAMessage => '输入消息…';

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
  String get hermesActivity => 'Hermes 活动';

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
}
