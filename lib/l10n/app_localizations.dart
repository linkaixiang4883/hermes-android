import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Hermes Agent'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get unknown;

  /// No description provided for @youHeader.
  ///
  /// In en, this message translates to:
  /// **'## You'**
  String get youHeader;

  /// No description provided for @hermesHeader.
  ///
  /// In en, this message translates to:
  /// **'## Hermes'**
  String get hermesHeader;

  /// No description provided for @chooseImage.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get chooseImage;

  /// No description provided for @chooseImages.
  ///
  /// In en, this message translates to:
  /// **'Choose images'**
  String get chooseImages;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @chooseFiles.
  ///
  /// In en, this message translates to:
  /// **'Choose files'**
  String get chooseFiles;

  /// No description provided for @fileTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Documents, archives, audio, video, or data'**
  String get fileTypeHint;

  /// No description provided for @unableToPrepareImage.
  ///
  /// In en, this message translates to:
  /// **'Unable to prepare this image. Try another one.'**
  String get unableToPrepareImage;

  /// No description provided for @imageSelectionInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Image selection was interrupted. Try again.'**
  String get imageSelectionInterrupted;

  /// No description provided for @unableToPrepareImageNamed.
  ///
  /// In en, this message translates to:
  /// **'Unable to prepare {name}.'**
  String unableToPrepareImageNamed(String name);

  /// No description provided for @configureDesktopGatewayForFiles.
  ///
  /// In en, this message translates to:
  /// **'Configure a valid Desktop Gateway URL before attaching files.'**
  String get configureDesktopGatewayForFiles;

  /// No description provided for @maxAttachmentDrafts.
  ///
  /// In en, this message translates to:
  /// **'You can attach up to {count} items.'**
  String maxAttachmentDrafts(int count);

  /// No description provided for @filesSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) skipped: limit, size, unreadable, or sensitive filename.'**
  String filesSkipped(int count);

  /// No description provided for @unableToPrepareFile.
  ///
  /// In en, this message translates to:
  /// **'Unable to prepare this file. Try another one.'**
  String get unableToPrepareFile;

  /// No description provided for @retryingAttachment.
  ///
  /// In en, this message translates to:
  /// **'Retrying {name}…'**
  String retryingAttachment(String name);

  /// No description provided for @fileAttachedPendingCatalog.
  ///
  /// In en, this message translates to:
  /// **'File attached; document catalog registration is pending.'**
  String get fileAttachedPendingCatalog;

  /// No description provided for @retryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry failed for {name}. The draft and prompt were kept.'**
  String retryFailed(String name);

  /// No description provided for @configureDesktopGatewayForModel.
  ///
  /// In en, this message translates to:
  /// **'Configure Desktop Gateway URL and Dashboard credentials to choose a chat model.'**
  String get configureDesktopGatewayForModel;

  /// No description provided for @modelAndThinkingForChat.
  ///
  /// In en, this message translates to:
  /// **'Model and thinking for this chat'**
  String get modelAndThinkingForChat;

  /// No description provided for @profileDefaultLabel.
  ///
  /// In en, this message translates to:
  /// **'profile default'**
  String get profileDefaultLabel;

  /// No description provided for @thisChatLabel.
  ///
  /// In en, this message translates to:
  /// **'this chat'**
  String get thisChatLabel;

  /// No description provided for @profileDefaultWithModel.
  ///
  /// In en, this message translates to:
  /// **'Profile default: {model}'**
  String profileDefaultWithModel(String model);

  /// No description provided for @thinkingEffort.
  ///
  /// In en, this message translates to:
  /// **'Thinking effort'**
  String get thinkingEffort;

  /// No description provided for @applyToThisChat.
  ///
  /// In en, this message translates to:
  /// **'Apply to this chat'**
  String get applyToThisChat;

  /// No description provided for @couldNotLoadModels.
  ///
  /// In en, this message translates to:
  /// **'Could not load models for this profile: {error}'**
  String couldNotLoadModels(String error);

  /// No description provided for @modelAppliesToChat.
  ///
  /// In en, this message translates to:
  /// **'{model} • {effort} now apply only to this chat.'**
  String modelAppliesToChat(String model, String effort);

  /// No description provided for @modelNotChanged.
  ///
  /// In en, this message translates to:
  /// **'Model was not changed: {error}'**
  String modelNotChanged(String error);

  /// No description provided for @responding.
  ///
  /// In en, this message translates to:
  /// **'Responding…'**
  String get responding;

  /// No description provided for @chatActions.
  ///
  /// In en, this message translates to:
  /// **'Chat actions'**
  String get chatActions;

  /// No description provided for @exportShare.
  ///
  /// In en, this message translates to:
  /// **'Export / share'**
  String get exportShare;

  /// No description provided for @chooseChatModel.
  ///
  /// In en, this message translates to:
  /// **'Choose chat model'**
  String get chooseChatModel;

  /// No description provided for @attachmentDrafts.
  ///
  /// In en, this message translates to:
  /// **'Attachment drafts'**
  String get attachmentDrafts;

  /// No description provided for @addAttachment.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get addAttachment;

  /// No description provided for @attachImageOrFile.
  ///
  /// In en, this message translates to:
  /// **'Attach image or file'**
  String get attachImageOrFile;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @typeAMessage.
  ///
  /// In en, this message translates to:
  /// **'Message Hermes…'**
  String get typeAMessage;

  /// No description provided for @spokenReplies.
  ///
  /// In en, this message translates to:
  /// **'Spoken replies'**
  String get spokenReplies;

  /// No description provided for @spokenRepliesOn.
  ///
  /// In en, this message translates to:
  /// **'Spoken replies on'**
  String get spokenRepliesOn;

  /// No description provided for @spokenRepliesOff.
  ///
  /// In en, this message translates to:
  /// **'Spoken replies off'**
  String get spokenRepliesOff;

  /// No description provided for @stopResponse.
  ///
  /// In en, this message translates to:
  /// **'Stop response'**
  String get stopResponse;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @failedToLoadMessages.
  ///
  /// In en, this message translates to:
  /// **'Failed to load messages'**
  String get failedToLoadMessages;

  /// No description provided for @messageCopied.
  ///
  /// In en, this message translates to:
  /// **'Message copied'**
  String get messageCopied;

  /// No description provided for @copyMessage.
  ///
  /// In en, this message translates to:
  /// **'Copy message'**
  String get copyMessage;

  /// No description provided for @messageActions.
  ///
  /// In en, this message translates to:
  /// **'Message actions'**
  String get messageActions;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @readAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get readAloud;

  /// No description provided for @editAndResend.
  ///
  /// In en, this message translates to:
  /// **'Edit and resend'**
  String get editAndResend;

  /// No description provided for @regenerateResponse.
  ///
  /// In en, this message translates to:
  /// **'Regenerate response'**
  String get regenerateResponse;

  /// No description provided for @regenerateFromPreceding.
  ///
  /// In en, this message translates to:
  /// **'Regenerate from the preceding prompt'**
  String get regenerateFromPreceding;

  /// No description provided for @voiceSetupFailed.
  ///
  /// In en, this message translates to:
  /// **'Voice setup failed: {error}'**
  String voiceSetupFailed(String error);

  /// No description provided for @speechRecognitionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition is unavailable'**
  String get speechRecognitionUnavailable;

  /// No description provided for @speechRecognitionNoService.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition service unavailable — use the keyboard\'s voice input instead'**
  String get speechRecognitionNoService;

  /// No description provided for @readingResponseAloud.
  ///
  /// In en, this message translates to:
  /// **'Reading response aloud'**
  String get readingResponseAloud;

  /// No description provided for @readAloudUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Read aloud is unavailable on this device'**
  String get readAloudUnavailable;

  /// No description provided for @responseReady.
  ///
  /// In en, this message translates to:
  /// **'Response ready'**
  String get responseReady;

  /// No description provided for @turnCompleted.
  ///
  /// In en, this message translates to:
  /// **'Turn completed'**
  String get turnCompleted;

  /// No description provided for @recoveringHermes.
  ///
  /// In en, this message translates to:
  /// **'Recovering Hermes…'**
  String get recoveringHermes;

  /// No description provided for @hermesRecoveryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Hermes recovery is unavailable: {error}'**
  String hermesRecoveryUnavailable(String error);

  /// No description provided for @hermesWaitingInput.
  ///
  /// In en, this message translates to:
  /// **'Hermes is waiting for input…'**
  String get hermesWaitingInput;

  /// No description provided for @hermesResponding.
  ///
  /// In en, this message translates to:
  /// **'Hermes is responding…'**
  String get hermesResponding;

  /// No description provided for @recoveryStoppedSafely.
  ///
  /// In en, this message translates to:
  /// **'Hermes stopped recovery safely. No prompt was resent.'**
  String get recoveryStoppedSafely;

  /// No description provided for @deliveryUncertainRecovering.
  ///
  /// In en, this message translates to:
  /// **'Delivery is uncertain; recovering without resending…'**
  String get deliveryUncertainRecovering;

  /// No description provided for @legacyTransportNotice.
  ///
  /// In en, this message translates to:
  /// **'Background recovery unavailable — legacy transport'**
  String get legacyTransportNotice;

  /// No description provided for @startingHermes.
  ///
  /// In en, this message translates to:
  /// **'Starting Hermes…'**
  String get startingHermes;

  /// No description provided for @preparingAttachments.
  ///
  /// In en, this message translates to:
  /// **'Preparing attachments…'**
  String get preparingAttachments;

  /// No description provided for @uploadingAttachment.
  ///
  /// In en, this message translates to:
  /// **'Uploading {index}/{total}: {name}'**
  String uploadingAttachment(int index, int total, String name);

  /// No description provided for @attachedFileLabel.
  ///
  /// In en, this message translates to:
  /// **'[Attached file: {name}]'**
  String attachedFileLabel(String name);

  /// No description provided for @desktopGatewayNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Desktop Gateway is not configured for this connection.'**
  String get desktopGatewayNotConfigured;

  /// No description provided for @couldNotDenyCommand.
  ///
  /// In en, this message translates to:
  /// **'Could not deny the command: {error}'**
  String couldNotDenyCommand(String error);

  /// No description provided for @couldNotSkipQuestion.
  ///
  /// In en, this message translates to:
  /// **'Could not skip the Hermes question.'**
  String get couldNotSkipQuestion;

  /// No description provided for @responseStopped.
  ///
  /// In en, this message translates to:
  /// **'Response stopped.'**
  String get responseStopped;

  /// No description provided for @responseClosedNoTurn.
  ///
  /// In en, this message translates to:
  /// **'Response closed locally; no active gateway turn was found.'**
  String get responseClosedNoTurn;

  /// No description provided for @responseClosedStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Response closed locally; gateway stop failed: {error}'**
  String responseClosedStopFailed(String error);

  /// No description provided for @sendFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String sendFailed(String error);

  /// No description provided for @thinkingEffortNone.
  ///
  /// In en, this message translates to:
  /// **'Off (no thinking)'**
  String get thinkingEffortNone;

  /// No description provided for @thinkingEffortMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get thinkingEffortMinimal;

  /// No description provided for @thinkingEffortLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get thinkingEffortLow;

  /// No description provided for @thinkingEffortMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get thinkingEffortMedium;

  /// No description provided for @thinkingEffortHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get thinkingEffortHigh;

  /// No description provided for @thinkingEffortXhigh.
  ///
  /// In en, this message translates to:
  /// **'Extra High'**
  String get thinkingEffortXhigh;

  /// No description provided for @thinkingEffortMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get thinkingEffortMax;

  /// No description provided for @thinkingEffortUltra.
  ///
  /// In en, this message translates to:
  /// **'Ultra'**
  String get thinkingEffortUltra;

  /// No description provided for @addConnection.
  ///
  /// In en, this message translates to:
  /// **'Add Connection'**
  String get addConnection;

  /// No description provided for @editConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit Connection'**
  String get editConnection;

  /// No description provided for @addGatewayConnection.
  ///
  /// In en, this message translates to:
  /// **'Add Gateway Connection'**
  String get addGatewayConnection;

  /// No description provided for @editGatewayConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit Gateway Connection'**
  String get editGatewayConnection;

  /// No description provided for @noConnections.
  ///
  /// In en, this message translates to:
  /// **'No connections'**
  String get noConnections;

  /// No description provided for @restoreConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Restore configuration'**
  String get restoreConfiguration;

  /// No description provided for @tapPlusToAdd.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add a remote Hermes Gateway\n(API Server, port 8642)'**
  String get tapPlusToAdd;

  /// No description provided for @connectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get connectionLabel;

  /// No description provided for @hostField.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get hostField;

  /// No description provided for @hostHint.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net'**
  String get hostHint;

  /// No description provided for @portField.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get portField;

  /// No description provided for @portHint.
  ///
  /// In en, this message translates to:
  /// **'8642 (API Server)'**
  String get portHint;

  /// No description provided for @apiKeyField.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKeyField;

  /// No description provided for @apiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'API_SERVER_KEY from ~/.hermes/.env'**
  String get apiKeyHint;

  /// No description provided for @serverRequiresApiKey.
  ///
  /// In en, this message translates to:
  /// **'Server requires an API key. Enter your API_SERVER_KEY.'**
  String get serverRequiresApiKey;

  /// No description provided for @updateApiKey.
  ///
  /// In en, this message translates to:
  /// **'Update API Key'**
  String get updateApiKey;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @key.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get key;

  /// No description provided for @dashboardProxySettings.
  ///
  /// In en, this message translates to:
  /// **'Dashboard / Proxy Settings'**
  String get dashboardProxySettings;

  /// No description provided for @gatewayPathPrefix.
  ///
  /// In en, this message translates to:
  /// **'Gateway path prefix'**
  String get gatewayPathPrefix;

  /// No description provided for @dashboardPathPrefix.
  ///
  /// In en, this message translates to:
  /// **'Dashboard path prefix'**
  String get dashboardPathPrefix;

  /// No description provided for @dashboardBehindProxy.
  ///
  /// In en, this message translates to:
  /// **'Dashboard behind proxy'**
  String get dashboardBehindProxy;

  /// No description provided for @dashboardPort.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Port'**
  String get dashboardPort;

  /// No description provided for @dashboardPortHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for default (9119)'**
  String get dashboardPortHint;

  /// No description provided for @customProxyDetails.
  ///
  /// In en, this message translates to:
  /// **'Custom proxy and dashboard details'**
  String get customProxyDetails;

  /// No description provided for @egGatewayPrefix.
  ///
  /// In en, this message translates to:
  /// **'e.g. /profile/peter'**
  String get egGatewayPrefix;

  /// No description provided for @egDashboardPrefix.
  ///
  /// In en, this message translates to:
  /// **'e.g. /dashboard'**
  String get egDashboardPrefix;

  /// No description provided for @gatewayPrefixHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. /profile/peter (proxy path before /api/ and /v1/)'**
  String get gatewayPrefixHint;

  /// No description provided for @dashboardPrefixHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. /dashboard (proxy path before /api/)'**
  String get dashboardPrefixHint;

  /// No description provided for @proxyInjectsAuth.
  ///
  /// In en, this message translates to:
  /// **'Proxy injects auth; app sends clean requests'**
  String get proxyInjectsAuth;

  /// No description provided for @nginxInjectsAuth.
  ///
  /// In en, this message translates to:
  /// **'Nginx injects auth — app sends clean requests'**
  String get nginxInjectsAuth;

  /// No description provided for @usernameOptional.
  ///
  /// In en, this message translates to:
  /// **'Username (optional)'**
  String get usernameOptional;

  /// No description provided for @passwordOptional.
  ///
  /// In en, this message translates to:
  /// **'Password (optional)'**
  String get passwordOptional;

  /// No description provided for @invalidPortNumber.
  ///
  /// In en, this message translates to:
  /// **'Invalid port number.'**
  String get invalidPortNumber;

  /// No description provided for @invalidApiKey401.
  ///
  /// In en, this message translates to:
  /// **'Invalid API key. Server returned 401.'**
  String get invalidApiKey401;

  /// No description provided for @apiKeyNotStoredSecurely.
  ///
  /// In en, this message translates to:
  /// **'The API key could not be stored securely.'**
  String get apiKeyNotStoredSecurely;

  /// No description provided for @dashboardCredsNotStoredSecurely.
  ///
  /// In en, this message translates to:
  /// **'The dashboard credentials could not be stored securely.'**
  String get dashboardCredsNotStoredSecurely;

  /// No description provided for @connectionNotStoredSecurely.
  ///
  /// In en, this message translates to:
  /// **'The connection could not be stored securely.'**
  String get connectionNotStoredSecurely;

  /// No description provided for @connectionNotDeletedSafely.
  ///
  /// In en, this message translates to:
  /// **'The connection could not be deleted safely.'**
  String get connectionNotDeletedSafely;

  /// No description provided for @cannotReachHostPort.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach {host}:{port}.'**
  String cannotReachHostPort(String host, int port);

  /// No description provided for @couldNotReachGatewayAt.
  ///
  /// In en, this message translates to:
  /// **'Could not reach/authenticate the Gateway API at {host}:{port}{prefix}.'**
  String couldNotReachGatewayAt(String host, int port, String prefix);

  /// No description provided for @couldNotReachDashboardAt.
  ///
  /// In en, this message translates to:
  /// **'Could not reach/authenticate the dashboard at {host}:{port}. Check the port and credentials.'**
  String couldNotReachDashboardAt(String host, int port);

  /// No description provided for @cannotReachHostPortCheck.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach {host}:{port}. Check the host and port.'**
  String cannotReachHostPortCheck(String host, int port);

  /// No description provided for @gatewayOkDashboardFailed.
  ///
  /// In en, this message translates to:
  /// **'Gateway connected, but the dashboard could not be reached or authenticated. Check the dashboard details, or clear them to skip.'**
  String get gatewayOkDashboardFailed;

  /// No description provided for @dashboardDetailsHelp.
  ///
  /// In en, this message translates to:
  /// **'Used for hosted path prefixes and for the Settings, Memory, Skills and Cron tabs. Leave username/password blank for an open dashboard, or enable proxied mode when your reverse proxy injects dashboard auth.'**
  String get dashboardDetailsHelp;

  /// No description provided for @dashboardPortHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. For the Memory/Cron/Skills/Settings tabs. Leave blank for the default (9119).'**
  String get dashboardPortHelp;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get newChat;

  /// No description provided for @switchProfile.
  ///
  /// In en, this message translates to:
  /// **'Switch profile'**
  String get switchProfile;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @renameChat.
  ///
  /// In en, this message translates to:
  /// **'Rename chat'**
  String get renameChat;

  /// No description provided for @couldNotRenameChat.
  ///
  /// In en, this message translates to:
  /// **'Could not rename chat: {error}'**
  String couldNotRenameChat(String error);

  /// No description provided for @branchChat.
  ///
  /// In en, this message translates to:
  /// **'Branch chat'**
  String get branchChat;

  /// No description provided for @sessionTitleBranch.
  ///
  /// In en, this message translates to:
  /// **'{title} branch'**
  String sessionTitleBranch(String title);

  /// No description provided for @createBranch.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get createBranch;

  /// No description provided for @noMessagesInDesktopSession.
  ///
  /// In en, this message translates to:
  /// **'This chat has no messages available in the Desktop session yet.'**
  String get noMessagesInDesktopSession;

  /// No description provided for @couldNotBranchChat.
  ///
  /// In en, this message translates to:
  /// **'Could not branch chat: {error}'**
  String couldNotBranchChat(String error);

  /// No description provided for @branchCreated.
  ///
  /// In en, this message translates to:
  /// **'Branch created in Hermes history.'**
  String get branchCreated;

  /// No description provided for @untitledSession.
  ///
  /// In en, this message translates to:
  /// **'Untitled session'**
  String get untitledSession;

  /// No description provided for @deleteSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete session?'**
  String get deleteSessionTitle;

  /// No description provided for @deleteSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" from the remote Hermes history? This cannot be undone.'**
  String deleteSessionConfirm(String title);

  /// No description provided for @sessionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Session deleted from remote Hermes.'**
  String get sessionDeleted;

  /// No description provided for @couldNotDeleteSession.
  ///
  /// In en, this message translates to:
  /// **'Could not delete session: {error}'**
  String couldNotDeleteSession(String error);

  /// No description provided for @memoryTab.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memoryTab;

  /// No description provided for @cronJobsTab.
  ///
  /// In en, this message translates to:
  /// **'Cron Jobs'**
  String get cronJobsTab;

  /// No description provided for @skillsTab.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skillsTab;

  /// No description provided for @settingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTab;

  /// No description provided for @connectingTo.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {url}...'**
  String connectingTo(String url);

  /// No description provided for @gatewayMustBeRunning.
  ///
  /// In en, this message translates to:
  /// **'Make sure the Gateway API Server is running\n(hermes gateway status)'**
  String get gatewayMustBeRunning;

  /// No description provided for @connectionIssue.
  ///
  /// In en, this message translates to:
  /// **'Connection issue'**
  String get connectionIssue;

  /// No description provided for @noSessionsYet.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get noSessionsYet;

  /// No description provided for @tapPlusNewChat.
  ///
  /// In en, this message translates to:
  /// **'Tap the + button to start a new chat'**
  String get tapPlusNewChat;

  /// No description provided for @searchChats.
  ///
  /// In en, this message translates to:
  /// **'Search chats'**
  String get searchChats;

  /// No description provided for @searchHintAi.
  ///
  /// In en, this message translates to:
  /// **'Ask AI to find a conversation'**
  String get searchHintAi;

  /// No description provided for @searchHintServer.
  ///
  /// In en, this message translates to:
  /// **'Search all message content'**
  String get searchHintServer;

  /// No description provided for @searchHintLocal.
  ///
  /// In en, this message translates to:
  /// **'Search loaded chats'**
  String get searchHintLocal;

  /// No description provided for @branch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get branch;

  /// No description provided for @sessionMeta.
  ///
  /// In en, this message translates to:
  /// **'{count} msgs • {model} • {time}'**
  String sessionMeta(int count, String model, String time);

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @profileDefaultSetTo.
  ///
  /// In en, this message translates to:
  /// **'Profile default set to {model}. Chats with their own model keep that override.'**
  String profileDefaultSetTo(String model);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @failedToLoadSettings.
  ///
  /// In en, this message translates to:
  /// **'Failed to load settings'**
  String get failedToLoadSettings;

  /// No description provided for @profileDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Profile default model'**
  String get profileDefaultModel;

  /// No description provided for @changesDefaultFor.
  ///
  /// In en, this message translates to:
  /// **'Changes the default for {label}. Use the selector in a chat to override only that conversation.'**
  String changesDefaultFor(String label);

  /// No description provided for @currentProfileDefault.
  ///
  /// In en, this message translates to:
  /// **'Current profile default'**
  String get currentProfileDefault;

  /// No description provided for @contextTokens.
  ///
  /// In en, this message translates to:
  /// **'Context: {tokens} tokens'**
  String contextTokens(int tokens);

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @setProfileDefault.
  ///
  /// In en, this message translates to:
  /// **'Set profile default'**
  String get setProfileDefault;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @sessionSources.
  ///
  /// In en, this message translates to:
  /// **'Session Sources'**
  String get sessionSources;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @baseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrl;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @hermesAgentForAndroid.
  ///
  /// In en, this message translates to:
  /// **'Hermes Agent for Android'**
  String get hermesAgentForAndroid;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Browse and manage your Hermes Agent sessions from your phone. Connects to a Hermes dashboard running on your local network.'**
  String get aboutDescription;

  /// No description provided for @verboseMode.
  ///
  /// In en, this message translates to:
  /// **'Verbose Mode'**
  String get verboseMode;

  /// No description provided for @showToolCalls.
  ///
  /// In en, this message translates to:
  /// **'Show tool calls, thinking, and message metadata'**
  String get showToolCalls;

  /// No description provided for @systemTheme.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// No description provided for @noTtsVoices.
  ///
  /// In en, this message translates to:
  /// **'No TTS voices found.\nInstall Google Text-to-Speech and download voice data.'**
  String get noTtsVoices;

  /// No description provided for @autoDeviceDefault.
  ///
  /// In en, this message translates to:
  /// **'Auto (device default)'**
  String get autoDeviceDefault;

  /// No description provided for @sessionSourceAutonomous.
  ///
  /// In en, this message translates to:
  /// **'Autonomous agents'**
  String get sessionSourceAutonomous;

  /// No description provided for @sessionSourceExternalApi.
  ///
  /// In en, this message translates to:
  /// **'External API clients'**
  String get sessionSourceExternalApi;

  /// No description provided for @sessionSourceCli.
  ///
  /// In en, this message translates to:
  /// **'Command-line chats'**
  String get sessionSourceCli;

  /// No description provided for @sessionSourceScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled tasks'**
  String get sessionSourceScheduled;

  /// No description provided for @sessionSourceDesktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop app'**
  String get sessionSourceDesktop;

  /// No description provided for @sessionSourceDiscord.
  ///
  /// In en, this message translates to:
  /// **'Discord chats'**
  String get sessionSourceDiscord;

  /// No description provided for @sessionSourceGatewayApi.
  ///
  /// In en, this message translates to:
  /// **'Gateway API access'**
  String get sessionSourceGatewayApi;

  /// No description provided for @sessionSourcePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone or tablet'**
  String get sessionSourcePhone;

  /// No description provided for @sessionSourceSignal.
  ///
  /// In en, this message translates to:
  /// **'Signal messages'**
  String get sessionSourceSignal;

  /// No description provided for @sessionSourceSlack.
  ///
  /// In en, this message translates to:
  /// **'Slack chats'**
  String get sessionSourceSlack;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String failed(String error);

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitled;

  /// No description provided for @jobResumed.
  ///
  /// In en, this message translates to:
  /// **'Job resumed'**
  String get jobResumed;

  /// No description provided for @jobPaused.
  ///
  /// In en, this message translates to:
  /// **'Job paused'**
  String get jobPaused;

  /// No description provided for @deleteCronJob.
  ///
  /// In en, this message translates to:
  /// **'Delete Cron Job'**
  String get deleteCronJob;

  /// No description provided for @deleteJobConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteJobConfirm(String name);

  /// No description provided for @deletedJob.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\"'**
  String deletedJob(String name);

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(String error);

  /// No description provided for @jobTriggered.
  ///
  /// In en, this message translates to:
  /// **'Job triggered'**
  String get jobTriggered;

  /// No description provided for @addCronJob.
  ///
  /// In en, this message translates to:
  /// **'Add Cron Job'**
  String get addCronJob;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @cronJobAdded.
  ///
  /// In en, this message translates to:
  /// **'Cron job added'**
  String get cronJobAdded;

  /// No description provided for @failedToAddJob.
  ///
  /// In en, this message translates to:
  /// **'Failed to add job: {error}'**
  String failedToAddJob(String error);

  /// No description provided for @editCronJob.
  ///
  /// In en, this message translates to:
  /// **'Edit Cron Job'**
  String get editCronJob;

  /// No description provided for @cronJobUpdated.
  ///
  /// In en, this message translates to:
  /// **'Cron job updated'**
  String get cronJobUpdated;

  /// No description provided for @failedToUpdateJob.
  ///
  /// In en, this message translates to:
  /// **'Failed to update job: {error}'**
  String failedToUpdateJob(String error);

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @egDailyBackup.
  ///
  /// In en, this message translates to:
  /// **'e.g., Daily backup'**
  String get egDailyBackup;

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @whatShouldAgentDo.
  ///
  /// In en, this message translates to:
  /// **'What should the agent do?'**
  String get whatShouldAgentDo;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @egCronSchedule.
  ///
  /// In en, this message translates to:
  /// **'e.g., 0 9 * * * or every 2h'**
  String get egCronSchedule;

  /// No description provided for @scriptOnly.
  ///
  /// In en, this message translates to:
  /// **'Script only (no agent)'**
  String get scriptOnly;

  /// No description provided for @scriptOnlyHelp.
  ///
  /// In en, this message translates to:
  /// **'Use for cron jobs backed by scripts.'**
  String get scriptOnlyHelp;

  /// No description provided for @requiredFields.
  ///
  /// In en, this message translates to:
  /// **'Name, prompt, and schedule are required'**
  String get requiredFields;

  /// No description provided for @cronJobs.
  ///
  /// In en, this message translates to:
  /// **'Cron Jobs'**
  String get cronJobs;

  /// No description provided for @addNewCronJob.
  ///
  /// In en, this message translates to:
  /// **'Add new cron job'**
  String get addNewCronJob;

  /// No description provided for @failedToLoadCronJobs.
  ///
  /// In en, this message translates to:
  /// **'Failed to load cron jobs'**
  String get failedToLoadCronJobs;

  /// No description provided for @noCronJobs.
  ///
  /// In en, this message translates to:
  /// **'No cron jobs'**
  String get noCronJobs;

  /// No description provided for @triggerNow.
  ///
  /// In en, this message translates to:
  /// **'Trigger now'**
  String get triggerNow;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @lastRun.
  ///
  /// In en, this message translates to:
  /// **'Last: {time}'**
  String lastRun(String time);

  /// No description provided for @nextRun.
  ///
  /// In en, this message translates to:
  /// **'Next: {time}'**
  String nextRun(String time);

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String sourceLabel(String source);

  /// No description provided for @failedToLoadMemory.
  ///
  /// In en, this message translates to:
  /// **'Failed to load memory'**
  String get failedToLoadMemory;

  /// No description provided for @noMemoryEntries.
  ///
  /// In en, this message translates to:
  /// **'No memory entries'**
  String get noMemoryEntries;

  /// No description provided for @memoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Memory entries are cross-session facts the agent remembers.\nThey are configured in ~/.hermes/config.yaml'**
  String get memoryHelp;

  /// No description provided for @skillsCount.
  ///
  /// In en, this message translates to:
  /// **'Skills ({count})'**
  String skillsCount(int count);

  /// No description provided for @failedToLoadSkills.
  ///
  /// In en, this message translates to:
  /// **'Failed to load skills'**
  String get failedToLoadSkills;

  /// No description provided for @noSkillsFound.
  ///
  /// In en, this message translates to:
  /// **'No skills found'**
  String get noSkillsFound;

  /// No description provided for @telegramMessages.
  ///
  /// In en, this message translates to:
  /// **'Telegram messages'**
  String get telegramMessages;

  /// No description provided for @developerToolCalls.
  ///
  /// In en, this message translates to:
  /// **'Developer tool calls'**
  String get developerToolCalls;

  /// No description provided for @terminalSessions.
  ///
  /// In en, this message translates to:
  /// **'Terminal sessions'**
  String get terminalSessions;

  /// No description provided for @whatsappMessages.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp messages'**
  String get whatsappMessages;

  /// No description provided for @attachmentOf.
  ///
  /// In en, this message translates to:
  /// **'Attachment {index} of {total}'**
  String attachmentOf(int index, int total);

  /// No description provided for @uploadFailedTapRetry.
  ///
  /// In en, this message translates to:
  /// **'Upload failed • tap retry'**
  String get uploadFailedTapRetry;

  /// No description provided for @moveAttachmentPrevious.
  ///
  /// In en, this message translates to:
  /// **'Move attachment previous'**
  String get moveAttachmentPrevious;

  /// No description provided for @moveAttachmentNext.
  ///
  /// In en, this message translates to:
  /// **'Move attachment next'**
  String get moveAttachmentNext;

  /// No description provided for @retryUpload.
  ///
  /// In en, this message translates to:
  /// **'Retry upload'**
  String get retryUpload;

  /// No description provided for @removeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get removeAttachment;

  /// No description provided for @readyToUpload.
  ///
  /// In en, this message translates to:
  /// **'Ready to upload'**
  String get readyToUpload;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get uploading;

  /// No description provided for @uploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get uploaded;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get uploadFailed;

  /// No description provided for @newCount.
  ///
  /// In en, this message translates to:
  /// **'{count} new'**
  String newCount(int count);

  /// No description provided for @latest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get latest;

  /// No description provided for @noNewMessages.
  ///
  /// In en, this message translates to:
  /// **'No new messages'**
  String get noNewMessages;

  /// No description provided for @oneNewMessage.
  ///
  /// In en, this message translates to:
  /// **'1 new message'**
  String get oneNewMessage;

  /// No description provided for @newMessages.
  ///
  /// In en, this message translates to:
  /// **'{count} new messages'**
  String newMessages(int count);

  /// No description provided for @goToEnd.
  ///
  /// In en, this message translates to:
  /// **'Go to end'**
  String get goToEnd;

  /// No description provided for @failuresSummary.
  ///
  /// In en, this message translates to:
  /// **'{failures} failed • {total} total'**
  String failuresSummary(int failures, int total);

  /// No description provided for @completedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} completed'**
  String completedCount(int count);

  /// No description provided for @hermesActivity.
  ///
  /// In en, this message translates to:
  /// **'Tool activity'**
  String get hermesActivity;

  /// No description provided for @couldNotSendApproval.
  ///
  /// In en, this message translates to:
  /// **'Could not send the approval: {error}'**
  String couldNotSendApproval(String error);

  /// No description provided for @allowOnce.
  ///
  /// In en, this message translates to:
  /// **'Allow once'**
  String get allowOnce;

  /// No description provided for @allowForSession.
  ///
  /// In en, this message translates to:
  /// **'Allow for this session'**
  String get allowForSession;

  /// No description provided for @confirmAlwaysAllow.
  ///
  /// In en, this message translates to:
  /// **'Confirm always allow'**
  String get confirmAlwaysAllow;

  /// No description provided for @alwaysAllow.
  ///
  /// In en, this message translates to:
  /// **'Always allow'**
  String get alwaysAllow;

  /// No description provided for @deny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get deny;

  /// No description provided for @runOnlyThisCommand.
  ///
  /// In en, this message translates to:
  /// **'Run only this command.'**
  String get runOnlyThisCommand;

  /// No description provided for @allowMatchingCommands.
  ///
  /// In en, this message translates to:
  /// **'Allow matching commands until this Hermes session ends.'**
  String get allowMatchingCommands;

  /// No description provided for @savePermanentRule.
  ///
  /// In en, this message translates to:
  /// **'Save a permanent rule in the Hermes configuration.'**
  String get savePermanentRule;

  /// No description provided for @doNotRunCommand.
  ///
  /// In en, this message translates to:
  /// **'Do not run this command.'**
  String get doNotRunCommand;

  /// No description provided for @approvalNeeded.
  ///
  /// In en, this message translates to:
  /// **'Approval needed'**
  String get approvalNeeded;

  /// No description provided for @command.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get command;

  /// No description provided for @permanentRuleWarning.
  ///
  /// In en, this message translates to:
  /// **'This creates a permanent rule in Hermes. Review the full command before confirming.'**
  String get permanentRuleWarning;

  /// No description provided for @couldNotAcceptAnswer.
  ///
  /// In en, this message translates to:
  /// **'Hermes could not accept the answer. Please try again.'**
  String get couldNotAcceptAnswer;

  /// No description provided for @hermesNeedsInput.
  ///
  /// In en, this message translates to:
  /// **'Hermes needs your input'**
  String get hermesNeedsInput;

  /// No description provided for @selectOneOrMore.
  ///
  /// In en, this message translates to:
  /// **'Select one or more options, then continue.'**
  String get selectOneOrMore;

  /// No description provided for @selectOneOrEnterOther.
  ///
  /// In en, this message translates to:
  /// **'Select one option, or enter another answer.'**
  String get selectOneOrEnterOther;

  /// No description provided for @otherAnswer.
  ///
  /// In en, this message translates to:
  /// **'Other answer'**
  String get otherAnswer;

  /// No description provided for @yourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get yourAnswer;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @reasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get reasoning;

  /// No description provided for @hermesReasoningDetails.
  ///
  /// In en, this message translates to:
  /// **'Hermes reasoning details'**
  String get hermesReasoningDetails;

  /// No description provided for @delegatedTasksCompleted.
  ///
  /// In en, this message translates to:
  /// **'{count} delegated task(s) completed'**
  String delegatedTasksCompleted(int count);

  /// No description provided for @delegatedTasksActive.
  ///
  /// In en, this message translates to:
  /// **'{count} delegated task(s) active'**
  String delegatedTasksActive(int count);

  /// No description provided for @hermesDidNotAcceptResponse.
  ///
  /// In en, this message translates to:
  /// **'Hermes did not accept the response. Please try again.'**
  String get hermesDidNotAcceptResponse;

  /// No description provided for @sensitiveValueNotice.
  ///
  /// In en, this message translates to:
  /// **'The value is sent directly to the active Hermes gateway and is not saved by this Android app.'**
  String get sensitiveValueNotice;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @textSizeHelp.
  ///
  /// In en, this message translates to:
  /// **'Explicit choices adjust Android accessibility text size; System leaves it unchanged.'**
  String get textSizeHelp;

  /// No description provided for @textSizePreview.
  ///
  /// In en, this message translates to:
  /// **'Text size preview'**
  String get textSizePreview;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @textScalingActive.
  ///
  /// In en, this message translates to:
  /// **'Hermes keeps Android accessibility text scaling active.'**
  String get textScalingActive;

  /// No description provided for @listeningElapsed.
  ///
  /// In en, this message translates to:
  /// **'Listening, elapsed {elapsed}'**
  String listeningElapsed(String elapsed);

  /// No description provided for @stopVoiceInput.
  ///
  /// In en, this message translates to:
  /// **'Stop voice input'**
  String get stopVoiceInput;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @cancelVoiceInput.
  ///
  /// In en, this message translates to:
  /// **'Cancel voice input'**
  String get cancelVoiceInput;

  /// No description provided for @startVoiceInput.
  ///
  /// In en, this message translates to:
  /// **'Start voice input'**
  String get startVoiceInput;

  /// No description provided for @speakToHermes.
  ///
  /// In en, this message translates to:
  /// **'Speak to Hermes'**
  String get speakToHermes;

  /// No description provided for @usingOneTool.
  ///
  /// In en, this message translates to:
  /// **'Hermes is using a tool'**
  String get usingOneTool;

  /// No description provided for @usingTools.
  ///
  /// In en, this message translates to:
  /// **'Hermes is using {count} tools'**
  String usingTools(int count);

  /// No description provided for @dashboardUsernameOptional.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Username (optional)'**
  String get dashboardUsernameOptional;

  /// No description provided for @dashboardPasswordOptional.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Password (optional)'**
  String get dashboardPasswordOptional;

  /// No description provided for @desktopGatewayUrlOptional.
  ///
  /// In en, this message translates to:
  /// **'Desktop Gateway URL (optional)'**
  String get desktopGatewayUrlOptional;

  /// No description provided for @desktopGatewayHelper.
  ///
  /// In en, this message translates to:
  /// **'Enables file attachments through the Desktop remote gateway.'**
  String get desktopGatewayHelper;

  /// No description provided for @toolRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get toolRunning;

  /// No description provided for @toolPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get toolPreparing;

  /// No description provided for @toolWorking.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get toolWorking;

  /// No description provided for @toolCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get toolCompleted;

  /// No description provided for @toolCompletedIn.
  ///
  /// In en, this message translates to:
  /// **'Completed in {duration}'**
  String toolCompletedIn(String duration);

  /// No description provided for @toolFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get toolFailed;

  /// No description provided for @toolFailedAfter.
  ///
  /// In en, this message translates to:
  /// **'Failed after {duration}'**
  String toolFailedAfter(String duration);

  /// No description provided for @backgroundTaskCompleted.
  ///
  /// In en, this message translates to:
  /// **'Background task completed'**
  String get backgroundTaskCompleted;

  /// No description provided for @backgroundTaskIdCompleted.
  ///
  /// In en, this message translates to:
  /// **'Background task {taskId} completed'**
  String backgroundTaskIdCompleted(String taskId);

  /// No description provided for @hermesReview.
  ///
  /// In en, this message translates to:
  /// **'Hermes review'**
  String get hermesReview;

  /// No description provided for @adminPasswordNeeded.
  ///
  /// In en, this message translates to:
  /// **'Administrator password needed'**
  String get adminPasswordNeeded;

  /// No description provided for @sudoPasswordDescription.
  ///
  /// In en, this message translates to:
  /// **'Hermes needs a sudo password for the pending terminal command.'**
  String get sudoPasswordDescription;

  /// No description provided for @sudoPasswordField.
  ///
  /// In en, this message translates to:
  /// **'Sudo password'**
  String get sudoPasswordField;

  /// No description provided for @secretNeeded.
  ///
  /// In en, this message translates to:
  /// **'Secret needed'**
  String get secretNeeded;

  /// No description provided for @secretDescription.
  ///
  /// In en, this message translates to:
  /// **'Hermes needs a secret for the pending skill.'**
  String get secretDescription;

  /// No description provided for @secretValueField.
  ///
  /// In en, this message translates to:
  /// **'Secret value'**
  String get secretValueField;

  /// No description provided for @dictationReady.
  ///
  /// In en, this message translates to:
  /// **'Dictation ready to edit'**
  String get dictationReady;

  /// No description provided for @approvalFallbackDescription.
  ///
  /// In en, this message translates to:
  /// **'Hermes wants to run a command.'**
  String get approvalFallbackDescription;

  /// No description provided for @clarifyFallbackDescription.
  ///
  /// In en, this message translates to:
  /// **'Hermes needs more information to continue.'**
  String get clarifyFallbackDescription;

  /// No description provided for @homeUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Hermes'**
  String get homeUnreachable;

  /// No description provided for @homeUnreachableHint.
  ///
  /// In en, this message translates to:
  /// **'Home needs your recent chats to know what deserves your attention. Check that the gateway is reachable, then try again.'**
  String get homeUnreachableHint;

  /// No description provided for @homeNothingNeedsYou.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs you'**
  String get homeNothingNeedsYou;

  /// No description provided for @homeAllClearHint.
  ///
  /// In en, this message translates to:
  /// **'No chat is blocked, running, or waiting to be resumed. Start a new one whenever you are ready.'**
  String get homeAllClearHint;

  /// No description provided for @offlineShowingLastKnown.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing the last known activity.'**
  String get offlineShowingLastKnown;

  /// No description provided for @untitledChat.
  ///
  /// In en, this message translates to:
  /// **'Untitled chat'**
  String get untitledChat;

  /// No description provided for @activityUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read activity'**
  String get activityUnreadable;

  /// No description provided for @activityJournalHint.
  ///
  /// In en, this message translates to:
  /// **'Activity reads the durable turn journal to know what Hermes is doing. Check that the gateway is reachable, then try again.'**
  String get activityJournalHint;

  /// No description provided for @inboxClear.
  ///
  /// In en, this message translates to:
  /// **'Inbox is clear'**
  String get inboxClear;

  /// No description provided for @activityNothingRunning.
  ///
  /// In en, this message translates to:
  /// **'Nothing is running'**
  String get activityNothingRunning;

  /// No description provided for @activityNoAttention.
  ///
  /// In en, this message translates to:
  /// **'No turn needs your input or has failed.'**
  String get activityNoAttention;

  /// No description provided for @activityEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No turn is blocked, in flight, or recently finished. Work you start will show up here.'**
  String get activityEmptyHint;

  /// No description provided for @andCountMore.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String andCountMore(int count);

  /// No description provided for @homeSectionNeedsYou.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get homeSectionNeedsYou;

  /// No description provided for @homeSectionRunning.
  ///
  /// In en, this message translates to:
  /// **'Running now'**
  String get homeSectionRunning;

  /// No description provided for @homeSectionWorking.
  ///
  /// In en, this message translates to:
  /// **'Continue working'**
  String get homeSectionWorking;

  /// No description provided for @homeSectionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Recently completed'**
  String get homeSectionCompleted;

  /// No description provided for @activityGroupFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get activityGroupFailed;

  /// No description provided for @activityGroupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get activityGroupCompleted;

  /// No description provided for @turnRecoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Turn recovery failed'**
  String get turnRecoveryFailed;

  /// No description provided for @turnWaitingInput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your input'**
  String get turnWaitingInput;

  /// No description provided for @turnFailedState.
  ///
  /// In en, this message translates to:
  /// **'The turn failed'**
  String get turnFailedState;

  /// No description provided for @turnStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get turnStopped;

  /// No description provided for @turnStalled.
  ///
  /// In en, this message translates to:
  /// **'Stalled — no update from Hermes'**
  String get turnStalled;

  /// No description provided for @turnSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted, waiting for Hermes'**
  String get turnSubmitted;

  /// No description provided for @turnRunningState.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get turnRunningState;

  /// No description provided for @moreSectionWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get moreSectionWorkspace;

  /// No description provided for @unassignedChats.
  ///
  /// In en, this message translates to:
  /// **'Unassigned chats'**
  String get unassignedChats;

  /// No description provided for @unassignedChatsDesc.
  ///
  /// In en, this message translates to:
  /// **'Chats that are not assigned to a Project'**
  String get unassignedChatsDesc;

  /// No description provided for @archivedQuickChats.
  ///
  /// In en, this message translates to:
  /// **'Archived quick chats'**
  String get archivedQuickChats;

  /// No description provided for @archivedQuickChatsDesc.
  ///
  /// In en, this message translates to:
  /// **'Review or promote quick chats past their retention period'**
  String get archivedQuickChatsDesc;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @filesDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse the miniserver folders behind your projects'**
  String get filesDesc;

  /// No description provided for @assets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assets;

  /// No description provided for @assetsDesc.
  ///
  /// In en, this message translates to:
  /// **'Artifacts, attachments, and generated media'**
  String get assetsDesc;

  /// No description provided for @moreSectionOrganization.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get moreSectionOrganization;

  /// No description provided for @pinBatchUndo.
  ///
  /// In en, this message translates to:
  /// **'Pin, batch and undo'**
  String get pinBatchUndo;

  /// No description provided for @pinBatchUndoDesc.
  ///
  /// In en, this message translates to:
  /// **'Cross-device ordering and reversible bulk organization'**
  String get pinBatchUndoDesc;

  /// No description provided for @aiFiling.
  ///
  /// In en, this message translates to:
  /// **'AI-assisted filing'**
  String get aiFiling;

  /// No description provided for @aiFilingDesc.
  ///
  /// In en, this message translates to:
  /// **'Suggest Projects and learn from your corrections'**
  String get aiFilingDesc;

  /// No description provided for @moreSectionAutomation.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get moreSectionAutomation;

  /// No description provided for @cronDesc.
  ///
  /// In en, this message translates to:
  /// **'Scheduled jobs and their last runs'**
  String get cronDesc;

  /// No description provided for @skillsTools.
  ///
  /// In en, this message translates to:
  /// **'Skills and tools'**
  String get skillsTools;

  /// No description provided for @skillsToolsDesc.
  ///
  /// In en, this message translates to:
  /// **'What Hermes knows how to do'**
  String get skillsToolsDesc;

  /// No description provided for @memoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Durable facts Hermes keeps about you'**
  String get memoryDesc;

  /// No description provided for @moreSectionSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get moreSectionSystem;

  /// No description provided for @settingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Connection, appearance, and device preferences'**
  String get settingsDesc;

  /// No description provided for @openDashboard.
  ///
  /// In en, this message translates to:
  /// **'Open the Hermes dashboard'**
  String get openDashboard;

  /// No description provided for @openDashboardDesc.
  ///
  /// In en, this message translates to:
  /// **'Everything not yet native, in the authenticated web dashboard'**
  String get openDashboardDesc;

  /// No description provided for @comingNext.
  ///
  /// In en, this message translates to:
  /// **'Coming next'**
  String get comingNext;

  /// No description provided for @moreNeedsDashboard.
  ///
  /// In en, this message translates to:
  /// **'Needs a reachable Hermes dashboard. Check the host, port, and credentials of this connection.'**
  String get moreNeedsDashboard;

  /// No description provided for @moreNeedsAssets.
  ///
  /// In en, this message translates to:
  /// **'Needs a server-authoritative Assets index in the Hermes Gateway.'**
  String get moreNeedsAssets;

  /// No description provided for @moreNeedsPinUndo.
  ///
  /// In en, this message translates to:
  /// **'Needs durable pin ordering, batch mutation, and undo contracts in the Hermes Gateway.'**
  String get moreNeedsPinUndo;

  /// No description provided for @moreNeedsFiling.
  ///
  /// In en, this message translates to:
  /// **'Needs a correction-aware filing contract in the Hermes Gateway.'**
  String get moreNeedsFiling;

  /// No description provided for @cronRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Cron'**
  String get cronRowTitle;

  /// No description provided for @archiveProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive {name}?'**
  String archiveProjectTitle(String name);

  /// No description provided for @archiveHintPane.
  ///
  /// In en, this message translates to:
  /// **'The Project will move to Archived. Its chats and files stay intact, and you can restore it at any time.'**
  String get archiveHintPane;

  /// No description provided for @archiveHintDetail.
  ///
  /// In en, this message translates to:
  /// **'The Project will move to Archived. Its chats and files stay intact, and you can restore it later.'**
  String get archiveHintDetail;

  /// No description provided for @projectsUnreachableHint.
  ///
  /// In en, this message translates to:
  /// **'Check that the gateway is running and reachable, then try again.'**
  String get projectsUnreachableHint;

  /// No description provided for @noProjectsYet.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get noProjectsYet;

  /// No description provided for @noProjectsHint.
  ///
  /// In en, this message translates to:
  /// **'Projects group related chats, files, and activity, and stay in sync with Hermes on your computer.'**
  String get noProjectsHint;

  /// No description provided for @createProjectAction.
  ///
  /// In en, this message translates to:
  /// **'Create a project'**
  String get createProjectAction;

  /// No description provided for @projectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsTitle;

  /// No description provided for @reviewLocalSpaces.
  ///
  /// In en, this message translates to:
  /// **'Review local spaces'**
  String get reviewLocalSpaces;

  /// No description provided for @archivedSection.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archivedSection;

  /// No description provided for @compatExplanation.
  ///
  /// In en, this message translates to:
  /// **'This Hermes gateway is older than server-side projects, so chats stay grouped on this device only. Update Hermes to share the same projects across your devices.'**
  String get compatExplanation;

  /// No description provided for @compatModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Compatibility mode'**
  String get compatModeTitle;

  /// No description provided for @noSpacesOnDevice.
  ///
  /// In en, this message translates to:
  /// **'No spaces on this device'**
  String get noSpacesOnDevice;

  /// No description provided for @noSpacesHint.
  ///
  /// In en, this message translates to:
  /// **'Chats from this gateway are not grouped yet. Grouping stays on this phone until the gateway can host projects.'**
  String get noSpacesHint;

  /// No description provided for @onThisDevice.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get onThisDevice;

  /// No description provided for @projectsOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing the last known projects.'**
  String get projectsOffline;

  /// No description provided for @activeChip.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeChip;

  /// No description provided for @projectActions.
  ///
  /// In en, this message translates to:
  /// **'Project actions'**
  String get projectActions;

  /// No description provided for @renameProjectItem.
  ///
  /// In en, this message translates to:
  /// **'Rename project'**
  String get renameProjectItem;

  /// No description provided for @archiveProjectItem.
  ///
  /// In en, this message translates to:
  /// **'Archive project'**
  String get archiveProjectItem;

  /// No description provided for @restoreProjectItem.
  ///
  /// In en, this message translates to:
  /// **'Restore project'**
  String get restoreProjectItem;

  /// No description provided for @deleteProjectItem.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProjectItem;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get enterName;

  /// No description provided for @nameField.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameField;

  /// No description provided for @oneChat.
  ///
  /// In en, this message translates to:
  /// **'1 chat'**
  String get oneChat;

  /// No description provided for @countChats.
  ///
  /// In en, this message translates to:
  /// **'{count} chats'**
  String countChats(int count);

  /// No description provided for @createAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createAction;

  /// No description provided for @moveConversation.
  ///
  /// In en, this message translates to:
  /// **'Move conversation'**
  String get moveConversation;

  /// No description provided for @renameProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename {name}'**
  String renameProjectTitle(String name);

  /// No description provided for @deleteProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deleteProjectTitle(String name);

  /// No description provided for @deleteHintDetail.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the Project. Chats will not be deleted; they’ll return to Unassigned.'**
  String get deleteHintDetail;

  /// No description provided for @movedToProject.
  ///
  /// In en, this message translates to:
  /// **'Moved to {label}'**
  String movedToProject(String label);

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @spaceUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get spaceUnassigned;

  /// No description provided for @moveToSpace.
  ///
  /// In en, this message translates to:
  /// **'Move to space'**
  String get moveToSpace;

  /// No description provided for @moveChat.
  ///
  /// In en, this message translates to:
  /// **'Move chat'**
  String get moveChat;

  /// No description provided for @projectActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not {action} the project: {error}'**
  String projectActionFailed(String action, String error);

  /// No description provided for @projectChatsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Project chats unavailable'**
  String get projectChatsUnavailable;

  /// No description provided for @projectChatsUnavailableHint.
  ///
  /// In en, this message translates to:
  /// **'This Hermes gateway does not support opening a project yet. Update Hermes on the server to browse a project from your phone.'**
  String get projectChatsUnavailableHint;

  /// No description provided for @couldNotOpenProject.
  ///
  /// In en, this message translates to:
  /// **'Could not open this project'**
  String get couldNotOpenProject;

  /// No description provided for @couldNotOpenProjectHint.
  ///
  /// In en, this message translates to:
  /// **'Check that the gateway is running and reachable, then try again.'**
  String get couldNotOpenProjectHint;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @noChatsYetHint.
  ///
  /// In en, this message translates to:
  /// **'Chats you start in this project will appear here, on every device signed in to this Hermes.'**
  String get noChatsYetHint;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatches;

  /// No description provided for @noMatchesHint.
  ///
  /// In en, this message translates to:
  /// **'No chats in this project match “{query}”.'**
  String noMatchesHint(String query);

  /// No description provided for @chatsTab.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsTab;

  /// No description provided for @overviewTab.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overviewTab;

  /// No description provided for @activityTab.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTab;

  /// No description provided for @conversationsInProject.
  ///
  /// In en, this message translates to:
  /// **'Conversations in this project'**
  String get conversationsInProject;

  /// No description provided for @repositoriesHeader.
  ///
  /// In en, this message translates to:
  /// **'Repositories'**
  String get repositoriesHeader;

  /// No description provided for @locationHeader.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationHeader;

  /// No description provided for @noFoldersYet.
  ///
  /// In en, this message translates to:
  /// **'No folders yet'**
  String get noFoldersYet;

  /// No description provided for @noFoldersHint.
  ///
  /// In en, this message translates to:
  /// **'The server has not reported folders for this project yet. Global Files stays available from More.'**
  String get noFoldersHint;

  /// No description provided for @foldersHeader.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get foldersHeader;

  /// No description provided for @assetsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Assets unavailable'**
  String get assetsUnavailable;

  /// No description provided for @assetsUnavailableHint.
  ///
  /// In en, this message translates to:
  /// **'Assets need a server-authoritative Assets index in the Hermes Gateway before they can be shown per project.'**
  String get assetsUnavailableHint;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get noActivityYet;

  /// No description provided for @noActivityHint.
  ///
  /// In en, this message translates to:
  /// **'Chats in this project will show their state and last activity here.'**
  String get noActivityHint;

  /// No description provided for @runningStateLabel.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get runningStateLabel;

  /// No description provided for @doneStateLabel.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneStateLabel;

  /// No description provided for @chatsOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing the last known chats'**
  String get chatsOffline;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @archiveAction.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveAction;

  /// No description provided for @moveConversationFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t move conversation'**
  String get moveConversationFailed;

  /// No description provided for @deleteProjectFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t delete project'**
  String get deleteProjectFailed;

  /// No description provided for @couldNotActionProject.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t {action} project'**
  String couldNotActionProject(String action);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
