// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Hermes Agent';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get refresh => 'Refresh';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get unknown => 'unknown';

  @override
  String get youHeader => '## You';

  @override
  String get hermesHeader => '## Hermes';

  @override
  String get chooseImage => 'Choose image';

  @override
  String get chooseImages => 'Choose images';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get chooseFiles => 'Choose files';

  @override
  String get fileTypeHint => 'Documents, archives, audio, video, or data';

  @override
  String get unableToPrepareImage =>
      'Unable to prepare this image. Try another one.';

  @override
  String get imageSelectionInterrupted =>
      'Image selection was interrupted. Try again.';

  @override
  String unableToPrepareImageNamed(String name) {
    return 'Unable to prepare $name.';
  }

  @override
  String get configureDesktopGatewayForFiles =>
      'Configure a valid Desktop Gateway URL before attaching files.';

  @override
  String maxAttachmentDrafts(int count) {
    return 'You can attach up to $count items.';
  }

  @override
  String filesSkipped(int count) {
    return '$count file(s) skipped: limit, size, unreadable, or sensitive filename.';
  }

  @override
  String get unableToPrepareFile =>
      'Unable to prepare this file. Try another one.';

  @override
  String retryingAttachment(String name) {
    return 'Retrying $name…';
  }

  @override
  String get fileAttachedPendingCatalog =>
      'File attached; document catalog registration is pending.';

  @override
  String retryFailed(String name) {
    return 'Retry failed for $name. The draft and prompt were kept.';
  }

  @override
  String get configureDesktopGatewayForModel =>
      'Configure Desktop Gateway URL and Dashboard credentials to choose a chat model.';

  @override
  String get modelAndThinkingForChat => 'Model and thinking for this chat';

  @override
  String get profileDefaultLabel => 'profile default';

  @override
  String get thisChatLabel => 'this chat';

  @override
  String profileDefaultWithModel(String model) {
    return 'Profile default: $model';
  }

  @override
  String get thinkingEffort => 'Thinking effort';

  @override
  String get applyToThisChat => 'Apply to this chat';

  @override
  String couldNotLoadModels(String error) {
    return 'Could not load models for this profile: $error';
  }

  @override
  String modelAppliesToChat(String model, String effort) {
    return '$model • $effort now apply only to this chat.';
  }

  @override
  String modelNotChanged(String error) {
    return 'Model was not changed: $error';
  }

  @override
  String get responding => 'Responding…';

  @override
  String get chatActions => 'Chat actions';

  @override
  String get exportShare => 'Export / share';

  @override
  String get chooseChatModel => 'Choose chat model';

  @override
  String get attachmentDrafts => 'Attachment drafts';

  @override
  String get addAttachment => 'Add attachment';

  @override
  String get attachImageOrFile => 'Attach image or file';

  @override
  String get message => 'Message';

  @override
  String get typeAMessage => 'Message Hermes…';

  @override
  String get spokenReplies => 'Spoken replies';

  @override
  String get spokenRepliesOn => 'Spoken replies on';

  @override
  String get spokenRepliesOff => 'Spoken replies off';

  @override
  String get stopResponse => 'Stop response';

  @override
  String get sendMessage => 'Send message';

  @override
  String get send => 'Send';

  @override
  String get failedToLoadMessages => 'Failed to load messages';

  @override
  String get messageCopied => 'Message copied';

  @override
  String get copyMessage => 'Copy message';

  @override
  String get messageActions => 'Message actions';

  @override
  String get you => 'You';

  @override
  String get readAloud => 'Read aloud';

  @override
  String get editAndResend => 'Edit and resend';

  @override
  String get regenerateResponse => 'Regenerate response';

  @override
  String get regenerateFromPreceding => 'Regenerate from the preceding prompt';

  @override
  String voiceSetupFailed(String error) {
    return 'Voice setup failed: $error';
  }

  @override
  String get speechRecognitionUnavailable =>
      'Speech recognition is unavailable';

  @override
  String get speechRecognitionNoService =>
      'Speech recognition service unavailable — use the keyboard\'s voice input instead';

  @override
  String get readingResponseAloud => 'Reading response aloud';

  @override
  String get readAloudUnavailable => 'Read aloud is unavailable on this device';

  @override
  String get responseReady => 'Response ready';

  @override
  String get turnCompleted => 'Turn completed';

  @override
  String get recoveringHermes => 'Recovering Hermes…';

  @override
  String hermesRecoveryUnavailable(String error) {
    return 'Hermes recovery is unavailable: $error';
  }

  @override
  String get hermesWaitingInput => 'Hermes is waiting for input…';

  @override
  String get hermesResponding => 'Hermes is responding…';

  @override
  String get recoveryStoppedSafely =>
      'Hermes stopped recovery safely. No prompt was resent.';

  @override
  String get deliveryUncertainRecovering =>
      'Delivery is uncertain; recovering without resending…';

  @override
  String get legacyTransportNotice =>
      'Background recovery unavailable — legacy transport';

  @override
  String get startingHermes => 'Starting Hermes…';

  @override
  String get preparingAttachments => 'Preparing attachments…';

  @override
  String uploadingAttachment(int index, int total, String name) {
    return 'Uploading $index/$total: $name';
  }

  @override
  String attachedFileLabel(String name) {
    return '[Attached file: $name]';
  }

  @override
  String get desktopGatewayNotConfigured =>
      'Desktop Gateway is not configured for this connection.';

  @override
  String couldNotDenyCommand(String error) {
    return 'Could not deny the command: $error';
  }

  @override
  String get couldNotSkipQuestion => 'Could not skip the Hermes question.';

  @override
  String get responseStopped => 'Response stopped.';

  @override
  String get responseClosedNoTurn =>
      'Response closed locally; no active gateway turn was found.';

  @override
  String responseClosedStopFailed(String error) {
    return 'Response closed locally; gateway stop failed: $error';
  }

  @override
  String sendFailed(String error) {
    return 'Send failed: $error';
  }

  @override
  String get thinkingEffortNone => 'Off (no thinking)';

  @override
  String get thinkingEffortMinimal => 'Minimal';

  @override
  String get thinkingEffortLow => 'Low';

  @override
  String get thinkingEffortMedium => 'Medium';

  @override
  String get thinkingEffortHigh => 'High';

  @override
  String get thinkingEffortXhigh => 'Extra High';

  @override
  String get thinkingEffortMax => 'Max';

  @override
  String get thinkingEffortUltra => 'Ultra';

  @override
  String get addConnection => 'Add Connection';

  @override
  String get editConnection => 'Edit Connection';

  @override
  String get addGatewayConnection => 'Add Gateway Connection';

  @override
  String get editGatewayConnection => 'Edit Gateway Connection';

  @override
  String get noConnections => 'No connections';

  @override
  String get restoreConfiguration => 'Restore configuration';

  @override
  String get tapPlusToAdd =>
      'Tap + to add a remote Hermes Gateway\n(API Server, port 8642)';

  @override
  String get connectionLabel => 'Label';

  @override
  String get hostField => 'Host';

  @override
  String get hostHint =>
      '192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net';

  @override
  String get portField => 'Port';

  @override
  String get portHint => '8642 (API Server)';

  @override
  String get apiKeyField => 'API Key';

  @override
  String get apiKeyHint => 'API_SERVER_KEY from ~/.hermes/.env';

  @override
  String get serverRequiresApiKey =>
      'Server requires an API key. Enter your API_SERVER_KEY.';

  @override
  String get updateApiKey => 'Update API Key';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get key => 'Key';

  @override
  String get dashboardProxySettings => 'Dashboard / Proxy Settings';

  @override
  String get gatewayPathPrefix => 'Gateway path prefix';

  @override
  String get dashboardPathPrefix => 'Dashboard path prefix';

  @override
  String get dashboardBehindProxy => 'Dashboard behind proxy';

  @override
  String get dashboardPort => 'Dashboard Port';

  @override
  String get dashboardPortHint => 'Leave blank for default (9119)';

  @override
  String get customProxyDetails => 'Custom proxy and dashboard details';

  @override
  String get egGatewayPrefix => 'e.g. /profile/peter';

  @override
  String get egDashboardPrefix => 'e.g. /dashboard';

  @override
  String get gatewayPrefixHint =>
      'e.g. /profile/peter (proxy path before /api/ and /v1/)';

  @override
  String get dashboardPrefixHint => 'e.g. /dashboard (proxy path before /api/)';

  @override
  String get proxyInjectsAuth => 'Proxy injects auth; app sends clean requests';

  @override
  String get nginxInjectsAuth =>
      'Nginx injects auth — app sends clean requests';

  @override
  String get usernameOptional => 'Username (optional)';

  @override
  String get passwordOptional => 'Password (optional)';

  @override
  String get invalidPortNumber => 'Invalid port number.';

  @override
  String get invalidApiKey401 => 'Invalid API key. Server returned 401.';

  @override
  String get apiKeyNotStoredSecurely =>
      'The API key could not be stored securely.';

  @override
  String get dashboardCredsNotStoredSecurely =>
      'The dashboard credentials could not be stored securely.';

  @override
  String get connectionNotStoredSecurely =>
      'The connection could not be stored securely.';

  @override
  String get connectionNotDeletedSafely =>
      'The connection could not be deleted safely.';

  @override
  String cannotReachHostPort(String host, int port) {
    return 'Cannot reach $host:$port.';
  }

  @override
  String couldNotReachGatewayAt(String host, int port, String prefix) {
    return 'Could not reach/authenticate the Gateway API at $host:$port$prefix.';
  }

  @override
  String couldNotReachDashboardAt(String host, int port) {
    return 'Could not reach/authenticate the dashboard at $host:$port. Check the port and credentials.';
  }

  @override
  String cannotReachHostPortCheck(String host, int port) {
    return 'Cannot reach $host:$port. Check the host and port.';
  }

  @override
  String get gatewayOkDashboardFailed =>
      'Gateway connected, but the dashboard could not be reached or authenticated. Check the dashboard details, or clear them to skip.';

  @override
  String get dashboardDetailsHelp =>
      'Used for hosted path prefixes and for the Settings, Memory, Skills and Cron tabs. Leave username/password blank for an open dashboard, or enable proxied mode when your reverse proxy injects dashboard auth.';

  @override
  String get dashboardPortHelp =>
      'Optional. For the Memory/Cron/Skills/Settings tabs. Leave blank for the default (9119).';

  @override
  String get rename => 'Rename';

  @override
  String get newChat => 'New Chat';

  @override
  String get switchProfile => 'Switch profile';

  @override
  String get profile => 'Profile';

  @override
  String get renameChat => 'Rename chat';

  @override
  String couldNotRenameChat(String error) {
    return 'Could not rename chat: $error';
  }

  @override
  String get branchChat => 'Branch chat';

  @override
  String sessionTitleBranch(String title) {
    return '$title branch';
  }

  @override
  String get createBranch => 'Create branch';

  @override
  String get noMessagesInDesktopSession =>
      'This chat has no messages available in the Desktop session yet.';

  @override
  String couldNotBranchChat(String error) {
    return 'Could not branch chat: $error';
  }

  @override
  String get branchCreated => 'Branch created in Hermes history.';

  @override
  String get untitledSession => 'Untitled session';

  @override
  String get deleteSessionTitle => 'Delete session?';

  @override
  String deleteSessionConfirm(String title) {
    return 'Delete \"$title\" from the remote Hermes history? This cannot be undone.';
  }

  @override
  String get sessionDeleted => 'Session deleted from remote Hermes.';

  @override
  String couldNotDeleteSession(String error) {
    return 'Could not delete session: $error';
  }

  @override
  String get memoryTab => 'Memory';

  @override
  String get cronJobsTab => 'Cron Jobs';

  @override
  String get skillsTab => 'Skills';

  @override
  String get settingsTab => 'Settings';

  @override
  String connectingTo(String url) {
    return 'Connecting to $url...';
  }

  @override
  String get gatewayMustBeRunning =>
      'Make sure the Gateway API Server is running\n(hermes gateway status)';

  @override
  String get connectionIssue => 'Connection issue';

  @override
  String get noSessionsYet => 'No sessions yet';

  @override
  String get tapPlusNewChat => 'Tap the + button to start a new chat';

  @override
  String get searchChats => 'Search chats';

  @override
  String get searchHintAi => 'Ask AI to find a conversation';

  @override
  String get searchHintServer => 'Search all message content';

  @override
  String get searchHintLocal => 'Search loaded chats';

  @override
  String get branch => 'Branch';

  @override
  String sessionMeta(int count, String model, String time) {
    return '$count msgs • $model • $time';
  }

  @override
  String get voice => 'Voice';

  @override
  String profileDefaultSetTo(String model) {
    return 'Profile default set to $model. Chats with their own model keep that override.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get failedToLoadSettings => 'Failed to load settings';

  @override
  String get profileDefaultModel => 'Profile default model';

  @override
  String changesDefaultFor(String label) {
    return 'Changes the default for $label. Use the selector in a chat to override only that conversation.';
  }

  @override
  String get currentProfileDefault => 'Current profile default';

  @override
  String contextTokens(int tokens) {
    return 'Context: $tokens tokens';
  }

  @override
  String get provider => 'Provider';

  @override
  String get model => 'Model';

  @override
  String get setProfileDefault => 'Set profile default';

  @override
  String get appearance => 'Appearance';

  @override
  String get sessionSources => 'Session Sources';

  @override
  String get connection => 'Connection';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get about => 'About';

  @override
  String get hermesAgentForAndroid => 'Hermes Agent for Android';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'Browse and manage your Hermes Agent sessions from your phone. Connects to a Hermes dashboard running on your local network.';

  @override
  String get verboseMode => 'Verbose Mode';

  @override
  String get showToolCalls => 'Show tool calls, thinking, and message metadata';

  @override
  String get systemTheme => 'System';

  @override
  String get darkTheme => 'Dark';

  @override
  String get lightTheme => 'Light';

  @override
  String get noTtsVoices =>
      'No TTS voices found.\nInstall Google Text-to-Speech and download voice data.';

  @override
  String get autoDeviceDefault => 'Auto (device default)';

  @override
  String get sessionSourceAutonomous => 'Autonomous agents';

  @override
  String get sessionSourceExternalApi => 'External API clients';

  @override
  String get sessionSourceCli => 'Command-line chats';

  @override
  String get sessionSourceScheduled => 'Scheduled tasks';

  @override
  String get sessionSourceDesktop => 'Desktop app';

  @override
  String get sessionSourceDiscord => 'Discord chats';

  @override
  String get sessionSourceGatewayApi => 'Gateway API access';

  @override
  String get sessionSourcePhone => 'Phone or tablet';

  @override
  String get sessionSourceSignal => 'Signal messages';

  @override
  String get sessionSourceSlack => 'Slack chats';

  @override
  String failed(String error) {
    return 'Failed: $error';
  }

  @override
  String get untitled => 'Untitled';

  @override
  String get jobResumed => 'Job resumed';

  @override
  String get jobPaused => 'Job paused';

  @override
  String get deleteCronJob => 'Delete Cron Job';

  @override
  String deleteJobConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String deletedJob(String name) {
    return 'Deleted \"$name\"';
  }

  @override
  String deleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get jobTriggered => 'Job triggered';

  @override
  String get addCronJob => 'Add Cron Job';

  @override
  String get add => 'Add';

  @override
  String get cronJobAdded => 'Cron job added';

  @override
  String failedToAddJob(String error) {
    return 'Failed to add job: $error';
  }

  @override
  String get editCronJob => 'Edit Cron Job';

  @override
  String get cronJobUpdated => 'Cron job updated';

  @override
  String failedToUpdateJob(String error) {
    return 'Failed to update job: $error';
  }

  @override
  String get name => 'Name';

  @override
  String get egDailyBackup => 'e.g., Daily backup';

  @override
  String get prompt => 'Prompt';

  @override
  String get whatShouldAgentDo => 'What should the agent do?';

  @override
  String get schedule => 'Schedule';

  @override
  String get egCronSchedule => 'e.g., 0 9 * * * or every 2h';

  @override
  String get scriptOnly => 'Script only (no agent)';

  @override
  String get scriptOnlyHelp => 'Use for cron jobs backed by scripts.';

  @override
  String get requiredFields => 'Name, prompt, and schedule are required';

  @override
  String get cronJobs => 'Cron Jobs';

  @override
  String get addNewCronJob => 'Add new cron job';

  @override
  String get failedToLoadCronJobs => 'Failed to load cron jobs';

  @override
  String get noCronJobs => 'No cron jobs';

  @override
  String get triggerNow => 'Trigger now';

  @override
  String get edit => 'Edit';

  @override
  String get resume => 'Resume';

  @override
  String get pause => 'Pause';

  @override
  String lastRun(String time) {
    return 'Last: $time';
  }

  @override
  String nextRun(String time) {
    return 'Next: $time';
  }

  @override
  String get memory => 'Memory';

  @override
  String sourceLabel(String source) {
    return 'Source: $source';
  }

  @override
  String get failedToLoadMemory => 'Failed to load memory';

  @override
  String get noMemoryEntries => 'No memory entries';

  @override
  String get memoryHelp =>
      'Memory entries are cross-session facts the agent remembers.\nThey are configured in ~/.hermes/config.yaml';

  @override
  String skillsCount(int count) {
    return 'Skills ($count)';
  }

  @override
  String get failedToLoadSkills => 'Failed to load skills';

  @override
  String get noSkillsFound => 'No skills found';

  @override
  String get telegramMessages => 'Telegram messages';

  @override
  String get developerToolCalls => 'Developer tool calls';

  @override
  String get terminalSessions => 'Terminal sessions';

  @override
  String get whatsappMessages => 'WhatsApp messages';

  @override
  String attachmentOf(int index, int total) {
    return 'Attachment $index of $total';
  }

  @override
  String get uploadFailedTapRetry => 'Upload failed • tap retry';

  @override
  String get moveAttachmentPrevious => 'Move attachment previous';

  @override
  String get moveAttachmentNext => 'Move attachment next';

  @override
  String get retryUpload => 'Retry upload';

  @override
  String get removeAttachment => 'Remove attachment';

  @override
  String get readyToUpload => 'Ready to upload';

  @override
  String get uploading => 'Uploading';

  @override
  String get uploaded => 'Uploaded';

  @override
  String get uploadFailed => 'Upload failed';

  @override
  String newCount(int count) {
    return '$count new';
  }

  @override
  String get latest => 'Latest';

  @override
  String get noNewMessages => 'No new messages';

  @override
  String get oneNewMessage => '1 new message';

  @override
  String newMessages(int count) {
    return '$count new messages';
  }

  @override
  String get goToEnd => 'Go to end';

  @override
  String failuresSummary(int failures, int total) {
    return '$failures failed • $total total';
  }

  @override
  String completedCount(int count) {
    return '$count completed';
  }

  @override
  String get hermesActivity => 'Tool activity';

  @override
  String couldNotSendApproval(String error) {
    return 'Could not send the approval: $error';
  }

  @override
  String get allowOnce => 'Allow once';

  @override
  String get allowForSession => 'Allow for this session';

  @override
  String get confirmAlwaysAllow => 'Confirm always allow';

  @override
  String get alwaysAllow => 'Always allow';

  @override
  String get deny => 'Deny';

  @override
  String get runOnlyThisCommand => 'Run only this command.';

  @override
  String get allowMatchingCommands =>
      'Allow matching commands until this Hermes session ends.';

  @override
  String get savePermanentRule =>
      'Save a permanent rule in the Hermes configuration.';

  @override
  String get doNotRunCommand => 'Do not run this command.';

  @override
  String get approvalNeeded => 'Approval needed';

  @override
  String get command => 'Command';

  @override
  String get permanentRuleWarning =>
      'This creates a permanent rule in Hermes. Review the full command before confirming.';

  @override
  String get couldNotAcceptAnswer =>
      'Hermes could not accept the answer. Please try again.';

  @override
  String get hermesNeedsInput => 'Hermes needs your input';

  @override
  String get selectOneOrMore => 'Select one or more options, then continue.';

  @override
  String get selectOneOrEnterOther =>
      'Select one option, or enter another answer.';

  @override
  String get otherAnswer => 'Other answer';

  @override
  String get yourAnswer => 'Your answer';

  @override
  String get skip => 'Skip';

  @override
  String get continueLabel => 'Continue';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get hermesReasoningDetails => 'Hermes reasoning details';

  @override
  String delegatedTasksCompleted(int count) {
    return '$count delegated task(s) completed';
  }

  @override
  String delegatedTasksActive(int count) {
    return '$count delegated task(s) active';
  }

  @override
  String get hermesDidNotAcceptResponse =>
      'Hermes did not accept the response. Please try again.';

  @override
  String get sensitiveValueNotice =>
      'The value is sent directly to the active Hermes gateway and is not saved by this Android app.';

  @override
  String get textSize => 'Text size';

  @override
  String get textSizeHelp =>
      'Explicit choices adjust Android accessibility text size; System leaves it unchanged.';

  @override
  String get textSizePreview => 'Text size preview';

  @override
  String get preview => 'Preview';

  @override
  String get textScalingActive =>
      'Hermes keeps Android accessibility text scaling active.';

  @override
  String listeningElapsed(String elapsed) {
    return 'Listening, elapsed $elapsed';
  }

  @override
  String get stopVoiceInput => 'Stop voice input';

  @override
  String get stop => 'Stop';

  @override
  String get cancelVoiceInput => 'Cancel voice input';

  @override
  String get startVoiceInput => 'Start voice input';

  @override
  String get speakToHermes => 'Speak to Hermes';

  @override
  String get usingOneTool => 'Hermes is using a tool';

  @override
  String usingTools(int count) {
    return 'Hermes is using $count tools';
  }

  @override
  String get dashboardUsernameOptional => 'Dashboard Username (optional)';

  @override
  String get dashboardPasswordOptional => 'Dashboard Password (optional)';

  @override
  String get desktopGatewayUrlOptional => 'Desktop Gateway URL (optional)';

  @override
  String get desktopGatewayHelper =>
      'Enables file attachments through the Desktop remote gateway.';

  @override
  String get toolRunning => 'Running';

  @override
  String get toolPreparing => 'Preparing';

  @override
  String get toolWorking => 'Working';

  @override
  String get toolCompleted => 'Completed';

  @override
  String toolCompletedIn(String duration) {
    return 'Completed in $duration';
  }

  @override
  String get toolFailed => 'Failed';

  @override
  String toolFailedAfter(String duration) {
    return 'Failed after $duration';
  }

  @override
  String get backgroundTaskCompleted => 'Background task completed';

  @override
  String backgroundTaskIdCompleted(String taskId) {
    return 'Background task $taskId completed';
  }

  @override
  String get hermesReview => 'Hermes review';

  @override
  String get adminPasswordNeeded => 'Administrator password needed';

  @override
  String get sudoPasswordDescription =>
      'Hermes needs a sudo password for the pending terminal command.';

  @override
  String get sudoPasswordField => 'Sudo password';

  @override
  String get secretNeeded => 'Secret needed';

  @override
  String get secretDescription =>
      'Hermes needs a secret for the pending skill.';

  @override
  String get secretValueField => 'Secret value';

  @override
  String get dictationReady => 'Dictation ready to edit';

  @override
  String get approvalFallbackDescription => 'Hermes wants to run a command.';

  @override
  String get clarifyFallbackDescription =>
      'Hermes needs more information to continue.';

  @override
  String get homeUnreachable => 'Could not reach Hermes';

  @override
  String get homeUnreachableHint =>
      'Home needs your recent chats to know what deserves your attention. Check that the gateway is reachable, then try again.';

  @override
  String get homeNothingNeedsYou => 'Nothing needs you';

  @override
  String get homeAllClearHint =>
      'No chat is blocked, running, or waiting to be resumed. Start a new one whenever you are ready.';

  @override
  String get offlineShowingLastKnown =>
      'Offline — showing the last known activity.';

  @override
  String get untitledChat => 'Untitled chat';

  @override
  String get activityUnreadable => 'Could not read activity';

  @override
  String get activityJournalHint =>
      'Activity reads the durable turn journal to know what Hermes is doing. Check that the gateway is reachable, then try again.';

  @override
  String get inboxClear => 'Inbox is clear';

  @override
  String get activityNothingRunning => 'Nothing is running';

  @override
  String get activityNoAttention => 'No turn needs your input or has failed.';

  @override
  String get activityEmptyHint =>
      'No turn is blocked, in flight, or recently finished. Work you start will show up here.';

  @override
  String andCountMore(int count) {
    return 'and $count more';
  }

  @override
  String get homeSectionNeedsYou => 'Needs you';

  @override
  String get homeSectionRunning => 'Running now';

  @override
  String get homeSectionWorking => 'Continue working';

  @override
  String get homeSectionCompleted => 'Recently completed';

  @override
  String get activityGroupFailed => 'Failed';

  @override
  String get activityGroupCompleted => 'Completed';

  @override
  String get turnRecoveryFailed => 'Turn recovery failed';

  @override
  String get turnWaitingInput => 'Waiting for your input';

  @override
  String get turnFailedState => 'The turn failed';

  @override
  String get turnStopped => 'Stopped';

  @override
  String get turnStalled => 'Stalled — no update from Hermes';

  @override
  String get turnSubmitted => 'Submitted, waiting for Hermes';

  @override
  String get turnRunningState => 'Running';

  @override
  String get moreSectionWorkspace => 'Workspace';

  @override
  String get unassignedChats => 'Unassigned chats';

  @override
  String get unassignedChatsDesc => 'Chats that are not assigned to a Project';

  @override
  String get archivedQuickChats => 'Archived quick chats';

  @override
  String get archivedQuickChatsDesc =>
      'Review or promote quick chats past their retention period';

  @override
  String get files => 'Files';

  @override
  String get filesDesc => 'Browse the miniserver folders behind your projects';

  @override
  String get assets => 'Assets';

  @override
  String get assetsDesc => 'Artifacts, attachments, and generated media';

  @override
  String get moreSectionOrganization => 'Organization';

  @override
  String get pinBatchUndo => 'Pin, batch and undo';

  @override
  String get pinBatchUndoDesc =>
      'Cross-device ordering and reversible bulk organization';

  @override
  String get aiFiling => 'AI-assisted filing';

  @override
  String get aiFilingDesc => 'Suggest Projects and learn from your corrections';

  @override
  String get moreSectionAutomation => 'Automation';

  @override
  String get cronDesc => 'Scheduled jobs and their last runs';

  @override
  String get skillsTools => 'Skills and tools';

  @override
  String get skillsToolsDesc => 'What Hermes knows how to do';

  @override
  String get memoryDesc => 'Durable facts Hermes keeps about you';

  @override
  String get moreSectionSystem => 'System';

  @override
  String get settingsDesc => 'Connection, appearance, and device preferences';

  @override
  String get openDashboard => 'Open the Hermes dashboard';

  @override
  String get openDashboardDesc =>
      'Everything not yet native, in the authenticated web dashboard';

  @override
  String get comingNext => 'Coming next';

  @override
  String get moreNeedsDashboard =>
      'Needs a reachable Hermes dashboard. Check the host, port, and credentials of this connection.';

  @override
  String get moreNeedsAssets =>
      'Needs a server-authoritative Assets index in the Hermes Gateway.';

  @override
  String get moreNeedsPinUndo =>
      'Needs durable pin ordering, batch mutation, and undo contracts in the Hermes Gateway.';

  @override
  String get moreNeedsFiling =>
      'Needs a correction-aware filing contract in the Hermes Gateway.';

  @override
  String get cronRowTitle => 'Cron';

  @override
  String archiveProjectTitle(String name) {
    return 'Archive $name?';
  }

  @override
  String get archiveHintPane =>
      'The Project will move to Archived. Its chats and files stay intact, and you can restore it at any time.';

  @override
  String get archiveHintDetail =>
      'The Project will move to Archived. Its chats and files stay intact, and you can restore it later.';

  @override
  String get projectsUnreachableHint =>
      'Check that the gateway is running and reachable, then try again.';

  @override
  String get noProjectsYet => 'No projects yet';

  @override
  String get noProjectsHint =>
      'Projects group related chats, files, and activity, and stay in sync with Hermes on your computer.';

  @override
  String get createProjectAction => 'Create a project';

  @override
  String get projectsTitle => 'Projects';

  @override
  String get reviewLocalSpaces => 'Review local spaces';

  @override
  String get archivedSection => 'Archived';

  @override
  String get compatExplanation =>
      'This Hermes gateway is older than server-side projects, so chats stay grouped on this device only. Update Hermes to share the same projects across your devices.';

  @override
  String get compatModeTitle => 'Compatibility mode';

  @override
  String get noSpacesOnDevice => 'No spaces on this device';

  @override
  String get noSpacesHint =>
      'Chats from this gateway are not grouped yet. Grouping stays on this phone until the gateway can host projects.';

  @override
  String get onThisDevice => 'On this device';

  @override
  String get projectsOffline => 'Offline — showing the last known projects.';

  @override
  String get activeChip => 'Active';

  @override
  String get projectActions => 'Project actions';

  @override
  String get renameProjectItem => 'Rename project';

  @override
  String get archiveProjectItem => 'Archive project';

  @override
  String get restoreProjectItem => 'Restore project';

  @override
  String get deleteProjectItem => 'Delete project';

  @override
  String get enterName => 'Enter a name';

  @override
  String get nameField => 'Name';

  @override
  String get oneChat => '1 chat';

  @override
  String countChats(int count) {
    return '$count chats';
  }

  @override
  String get createAction => 'Create';

  @override
  String get moveConversation => 'Move conversation';

  @override
  String renameProjectTitle(String name) {
    return 'Rename $name';
  }

  @override
  String deleteProjectTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteHintDetail =>
      'This permanently deletes the Project. Chats will not be deleted; they’ll return to Unassigned.';

  @override
  String movedToProject(String label) {
    return 'Moved to $label';
  }

  @override
  String get newProject => 'New project';

  @override
  String get spaceUnassigned => 'Unassigned';

  @override
  String get moveToSpace => 'Move to space';

  @override
  String get moveChat => 'Move chat';

  @override
  String projectActionFailed(String action, String error) {
    return 'Could not $action the project: $error';
  }

  @override
  String get projectChatsUnavailable => 'Project chats unavailable';

  @override
  String get projectChatsUnavailableHint =>
      'This Hermes gateway does not support opening a project yet. Update Hermes on the server to browse a project from your phone.';

  @override
  String get couldNotOpenProject => 'Could not open this project';

  @override
  String get couldNotOpenProjectHint =>
      'Check that the gateway is running and reachable, then try again.';

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get noChatsYetHint =>
      'Chats you start in this project will appear here, on every device signed in to this Hermes.';

  @override
  String get noMatches => 'No matches';

  @override
  String noMatchesHint(String query) {
    return 'No chats in this project match “$query”.';
  }

  @override
  String get chatsTab => 'Chats';

  @override
  String get overviewTab => 'Overview';

  @override
  String get activityTab => 'Activity';

  @override
  String get conversationsInProject => 'Conversations in this project';

  @override
  String get repositoriesHeader => 'Repositories';

  @override
  String get locationHeader => 'Location';

  @override
  String get noFoldersYet => 'No folders yet';

  @override
  String get noFoldersHint =>
      'The server has not reported folders for this project yet. Global Files stays available from More.';

  @override
  String get foldersHeader => 'Folders';

  @override
  String get assetsUnavailable => 'Assets unavailable';

  @override
  String get assetsUnavailableHint =>
      'Assets need a server-authoritative Assets index in the Hermes Gateway before they can be shown per project.';

  @override
  String get noActivityYet => 'No activity yet';

  @override
  String get noActivityHint =>
      'Chats in this project will show their state and last activity here.';

  @override
  String get runningStateLabel => 'Running';

  @override
  String get doneStateLabel => 'Done';

  @override
  String get chatsOffline => 'Offline — showing the last known chats';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get archiveAction => 'Archive';

  @override
  String get moveConversationFailed => 'Couldn’t move conversation';

  @override
  String get deleteProjectFailed => 'Couldn’t delete project';

  @override
  String couldNotActionProject(String action) {
    return 'Couldn’t $action project';
  }

  @override
  String get aiSearchModelTitle => 'AI search model';

  @override
  String get aiSearchModelHint =>
      'The model only rewrites your question into a short full-text query. Hermes uses the provider credentials already configured on the host.';

  @override
  String get chooseAiModelFirst =>
      'Choose an AI search model before using AI search.';

  @override
  String searchFailed(String error) {
    return 'Session search failed: $error';
  }

  @override
  String get chooseDestinationSpace => 'Choose its destination space';

  @override
  String get spaceFallback => 'Space';

  @override
  String get useOnDevice => 'Use on-device';

  @override
  String get searchModeLocal => 'On-device';

  @override
  String get searchModeLocalDesc => 'Titles, previews, and models';

  @override
  String get searchModeServer => 'Full-text';

  @override
  String get searchModeServerDesc => 'All stored message content';

  @override
  String get searchModeAi => 'AI + full-text';

  @override
  String get searchModeAiDesc => 'Choose a small model to rewrite queries';

  @override
  String get changeAiSearchModel => 'Change AI search model';

  @override
  String get searchMode => 'Search mode';

  @override
  String aiSearchedFor(String query) {
    return 'AI searched for: $query';
  }

  @override
  String get spaceEmptyHint =>
      'No chats in this space yet. Tap + to start one.';

  @override
  String get unassignedEmptyHint => 'No unassigned chats.';

  @override
  String get searchNoContentMatches => 'No message-content matches';

  @override
  String get spacesTitle => 'Spaces';

  @override
  String get newSpace => 'New space';

  @override
  String get renameSpace => 'Rename space';

  @override
  String get chooseSpaceDestination => 'Choose its destination space';

  @override
  String get spaceActions => 'Space actions';

  @override
  String get createSpaceHint =>
      'Create a space to separate related conversations.';

  @override
  String lastActivityDate(int month, int day, int year) {
    return 'Last activity $month/$day/$year';
  }

  @override
  String get workspaceNavHint => 'Projects, Activity — new navigation';

  @override
  String get spaceAllChats => 'All chats';

  @override
  String aiModelsLoadFailed(String error) {
    return 'Could not load AI search models: $error';
  }

  @override
  String downloadedFile(String filename) {
    return '$filename downloaded';
  }

  @override
  String saveFileTitle(String filename) {
    return 'Save $filename';
  }

  @override
  String get folderEmpty => 'Folder is empty';

  @override
  String get folderEmptyHint =>
      'There are no visible files in this server folder.';

  @override
  String get previewTruncated => 'Preview truncated';

  @override
  String get projectsUnavailable => 'Projects unavailable';

  @override
  String get projectsNeedDesktopHint =>
      'Projects need a Desktop Gateway connection. Add the Desktop Gateway URL to this connection to organize chats across your devices.';

  @override
  String get createProjectChatFailed => 'Couldn’t create Project chat';

  @override
  String get loadConversationsFailed => 'Could not load conversations';

  @override
  String get loadConversationsHint => 'Check the connection and try again.';

  @override
  String get searchConversations => 'Search conversations';

  @override
  String get archivedViewEmpty =>
      'Quick chats appear here after their retention period.';

  @override
  String get newAction => 'New';

  @override
  String get openInbox => 'Open inbox';

  @override
  String openInboxCount(int n) {
    return 'Open inbox ($n)';
  }

  @override
  String get binaryPreviewUnavailable =>
      'Binary preview is unavailable. Download the file to open it.';

  @override
  String get previewUnavailable => 'Preview unavailable';

  @override
  String get previewFailed => 'Could not preview file';

  @override
  String get previewFailedHint =>
      'Check the Dashboard connection and try again.';

  @override
  String get inboxTitle => 'Inbox';

  @override
  String get openDashboardFailed => 'Could not open the Hermes dashboard.';

  @override
  String get searchAllChats => 'Search all chats';

  @override
  String get downloadAction => 'Download';

  @override
  String get fileRefAdded => 'File reference added to chat';

  @override
  String get addToChat => 'Add to chat';

  @override
  String get promotedToProject => 'Promoted to a Project';

  @override
  String get promoteConversationFailed => 'Couldn’t promote conversation';

  @override
  String get promoteToProject => 'Promote to project';

  @override
  String get unassignedViewEmpty =>
      'Every conversation is already assigned to a Project.';

  @override
  String get noViewMatches => 'No conversation matches this view.';

  @override
  String get spaceCountOne => '1 space';

  @override
  String spaceCountMany(int count) {
    return '$count spaces';
  }

  @override
  String get projectsToCreateNone => 'no new projects needed';

  @override
  String get projectsToCreateOne => '1 project to create';

  @override
  String projectsToCreateMany(int count) {
    return '$count projects to create';
  }

  @override
  String migrationResultSummary(int linked, int created) {
    return '$linked chats migrated · $created projects created';
  }

  @override
  String migrationUnlinkedHint(int count) {
    return '$count chats stayed in local Spaces and can be retried safely.';
  }

  @override
  String get assignedChatOne => '1 assigned chat';

  @override
  String assignedChatsMany(int count) {
    return '$count assigned chats';
  }

  @override
  String migrationNoMatchHint(String assigned) {
    return 'No server project matches this name · $assigned';
  }

  @override
  String migrationMatchHint(String name, String assigned) {
    return 'Matches $name · $assigned';
  }

  @override
  String get continueAction => 'Continue';

  @override
  String get migrationNothingToDo => 'Nothing to migrate';

  @override
  String get migrationNoSpacesHint =>
      'No local spaces were found for this connection, so Projects are already the only organization in use here.';

  @override
  String get migrationPreviewTitle => 'Migration preview';

  @override
  String get migrationDryRunHint =>
      'Nothing has moved yet — this is only what a migration would do.';

  @override
  String get migrationComplete => 'Migration complete';

  @override
  String get migrationIncomplete => 'Migration incomplete';

  @override
  String get migrationFailedHint =>
      'Migration failed. Local Spaces were kept unchanged.';

  @override
  String get migratingAction => 'Migrating…';

  @override
  String get migrateAction => 'Migrate';

  @override
  String get migrationMatched => 'Matched';

  @override
  String get closeAction => 'Close';

  @override
  String get loadingLabel => 'Loading';

  @override
  String get offLabel => 'Off';

  @override
  String get quickChatRetention => 'Auto-archives after 72 hours';

  @override
  String get modeProjectChat => 'Project chat';

  @override
  String get modeProjectChatDesc =>
      'Durable work inside one of your projects, shared with Desktop.';

  @override
  String get modeQuickChat => 'Quick chat';

  @override
  String get modeQuickChatDesc =>
      'A one-off question. Archives itself after 72 hours; anything worth keeping is still remembered.';

  @override
  String get stillLoadingProjects => 'Still loading your projects.';

  @override
  String get gatewayNoProjectsHint =>
      'This gateway does not host projects yet. Update the gateway to organize chats across your devices.';

  @override
  String get createProjectFirst =>
      'Create a project first, then chats can live inside it.';

  @override
  String get startSomethingNew => 'Start something new';

  @override
  String get whichProject => 'Which project?';

  @override
  String get shareToHermes => 'Share to Hermes';

  @override
  String get shareNoText => 'No text shared';

  @override
  String get shareAttachmentOne => '1 attachment';

  @override
  String shareAttachmentsMany(int count) {
    return '$count attachments';
  }

  @override
  String get shareActionTitle => 'Action';

  @override
  String get shareUseAsIs => 'Use as is';

  @override
  String get shareSummarize => 'Summarize';

  @override
  String get shareExplain => 'Explain';

  @override
  String get shareResearch => 'Research';

  @override
  String get shareExtractTasks => 'Extract tasks';

  @override
  String get shareRemember => 'Remember';

  @override
  String get shareFillFromDoc => 'Fill from document';

  @override
  String get shareDestinationTitle => 'Destination';

  @override
  String get chooseActiveProjectNext => 'Choose an active Project next';

  @override
  String get noActiveProjects => 'No active Projects on this Gateway';

  @override
  String get enterPassphrase => 'Enter a passphrase.';

  @override
  String get enterBackupPassphrase => 'Enter the passphrase for this backup.';

  @override
  String get useEightChars => 'Use at least 8 characters.';

  @override
  String get passphrasesMismatch => 'The two passphrases do not match.';

  @override
  String get protectBackupTitle => 'Protect this backup';

  @override
  String get protectBackupDesc =>
      'The file contains your API keys and dashboard password, so it is encrypted. Without this passphrase the backup cannot be restored.';

  @override
  String get passphraseField => 'Passphrase';

  @override
  String get confirmPassphraseField => 'Confirm passphrase';

  @override
  String get showPassphrase => 'Show passphrase';

  @override
  String get hidePassphrase => 'Hide passphrase';

  @override
  String get backupExportFailed => 'The backup could not be exported.';

  @override
  String get exportAction => 'Export';

  @override
  String get importAction => 'Import';

  @override
  String get restoreBackup => 'Restore';

  @override
  String get mergeAction => 'Merge';

  @override
  String get mergeDesc =>
      'Add and update connections from the backup, keep the rest.';

  @override
  String get replaceAction => 'Replace';

  @override
  String get replaceDesc => 'Delete connections that are not in the backup.';

  @override
  String get backupRestoreTitle => 'Backup & restore';

  @override
  String get backupCardDesc =>
      'Save your connections and settings to an encrypted file, then restore them after reinstalling or on another device.';

  @override
  String backupExportedTo(String destination) {
    return 'Backup exported — $destination';
  }

  @override
  String get nothingHereView => 'Nothing here';

  @override
  String get noMatchesView => 'No matches';

  @override
  String get projectFallback => 'Project';

  @override
  String get archivedFilterEmpty => 'Archived conversations appear here.';

  @override
  String get recentFilterEmpty => 'Nothing changed in the last seven days.';

  @override
  String get loadFilesFailed => 'Could not load files';

  @override
  String get prepareSharedFilesFailed => 'Couldn’t prepare the shared files.';

  @override
  String downloadFailed(String error) {
    return 'Download failed: $error';
  }
}
