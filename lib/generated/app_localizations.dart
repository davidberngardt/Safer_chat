import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_he.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_ru.dart';
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
/// import 'generated/app_localizations.dart';
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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('he'),
    Locale('hi'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('ru'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Safer Chat'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chatSettings.
  ///
  /// In en, this message translates to:
  /// **'Chat settings'**
  String get chatSettings;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About App'**
  String get aboutApp;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyTitle;

  /// No description provided for @privacyPolicyContent.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy text will be here...'**
  String get privacyPolicyContent;

  /// No description provided for @termsOfServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfServiceTitle;

  /// No description provided for @termsOfServiceContent.
  ///
  /// In en, this message translates to:
  /// **'Terms of service text will be here...'**
  String get termsOfServiceContent;

  /// No description provided for @moveToArchive.
  ///
  /// In en, this message translates to:
  /// **'Move to Archive'**
  String get moveToArchive;

  /// No description provided for @blockChat.
  ///
  /// In en, this message translates to:
  /// **'Block Chat'**
  String get blockChat;

  /// No description provided for @unblockChat.
  ///
  /// In en, this message translates to:
  /// **'Unblock Chat'**
  String get unblockChat;

  /// No description provided for @createChannel.
  ///
  /// In en, this message translates to:
  /// **'Create channel'**
  String get createChannel;

  /// No description provided for @deleteContactError.
  ///
  /// In en, this message translates to:
  /// **'Error deleting contact'**
  String get deleteContactError;

  /// No description provided for @calls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get calls;

  /// No description provided for @callHistory.
  ///
  /// In en, this message translates to:
  /// **'Call History'**
  String get callHistory;

  /// No description provided for @noCallHistory.
  ///
  /// In en, this message translates to:
  /// **'No call history'**
  String get noCallHistory;

  /// No description provided for @clearCallHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear Call History'**
  String get clearCallHistory;

  /// No description provided for @areYouSureDeleteCallHistory.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete call history?'**
  String get areYouSureDeleteCallHistory;

  /// No description provided for @callHistoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Call history cleared'**
  String get callHistoryCleared;

  /// No description provided for @failedToClearCallHistory.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear call history'**
  String get failedToClearCallHistory;

  /// No description provided for @errorClearingCallHistory.
  ///
  /// In en, this message translates to:
  /// **'Error clearing call history'**
  String get errorClearingCallHistory;

  /// No description provided for @calling.
  ///
  /// In en, this message translates to:
  /// **'Calling...'**
  String get calling;

  /// No description provided for @failedToStartCall.
  ///
  /// In en, this message translates to:
  /// **'Failed to start call'**
  String get failedToStartCall;

  /// No description provided for @cannotCallThisUser.
  ///
  /// In en, this message translates to:
  /// **'Cannot call this user'**
  String get cannotCallThisUser;

  /// No description provided for @chatIsBlockedCannotCall.
  ///
  /// In en, this message translates to:
  /// **'Chat is blocked. Cannot make call.'**
  String get chatIsBlockedCannotCall;

  /// No description provided for @missed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get missed;

  /// No description provided for @outgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoing;

  /// No description provided for @incoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incoming;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @chooseFileType.
  ///
  /// In en, this message translates to:
  /// **'Choose file type'**
  String get chooseFileType;

  /// No description provided for @images.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// No description provided for @anyFile.
  ///
  /// In en, this message translates to:
  /// **'Any file'**
  String get anyFile;

  /// No description provided for @tapToDownload.
  ///
  /// In en, this message translates to:
  /// **'Tap to download'**
  String get tapToDownload;

  /// No description provided for @downloadFile.
  ///
  /// In en, this message translates to:
  /// **'Download file'**
  String get downloadFile;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @createFolder.
  ///
  /// In en, this message translates to:
  /// **'Create folder'**
  String get createFolder;

  /// No description provided for @editFolder.
  ///
  /// In en, this message translates to:
  /// **'Edit folder'**
  String get editFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @enterFolderName.
  ///
  /// In en, this message translates to:
  /// **'Enter folder name'**
  String get enterFolderName;

  /// No description provided for @addChats.
  ///
  /// In en, this message translates to:
  /// **'Add chats'**
  String get addChats;

  /// No description provided for @selectedChats.
  ///
  /// In en, this message translates to:
  /// **'Selected chats:'**
  String get selectedChats;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @removePhotoFirst.
  ///
  /// In en, this message translates to:
  /// **'Remove photo first'**
  String get removePhotoFirst;

  /// No description provided for @failedToSelectPhoto.
  ///
  /// In en, this message translates to:
  /// **'Failed to select photo'**
  String get failedToSelectPhoto;

  /// No description provided for @folderCreated.
  ///
  /// In en, this message translates to:
  /// **'Folder created'**
  String get folderCreated;

  /// No description provided for @folderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Folder updated'**
  String get folderUpdated;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolder;

  /// No description provided for @areYouSureYouWantToDeleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this folder?'**
  String get areYouSureYouWantToDeleteFolder;

  /// No description provided for @deleteError.
  ///
  /// In en, this message translates to:
  /// **'Delete error'**
  String get deleteError;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @selectChats.
  ///
  /// In en, this message translates to:
  /// **'Select chats'**
  String get selectChats;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'selected'**
  String get selected;

  /// No description provided for @noActiveChats.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any active chats'**
  String get noActiveChats;

  /// No description provided for @addAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAction;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get groupName;

  /// No description provided for @searchContacts.
  ///
  /// In en, this message translates to:
  /// **'Search contacts...'**
  String get searchContacts;

  /// No description provided for @noContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts'**
  String get noContacts;

  /// No description provided for @contactsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Contacts not found'**
  String get contactsNotFound;

  /// No description provided for @contactAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Contact already exists'**
  String get contactAlreadyExists;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @addedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'added successfully'**
  String get addedSuccessfully;

  /// No description provided for @failedToAddContact.
  ///
  /// In en, this message translates to:
  /// **'Failed to add contact'**
  String get failedToAddContact;

  /// No description provided for @errorAddingContact.
  ///
  /// In en, this message translates to:
  /// **'Error adding contact'**
  String get errorAddingContact;

  /// No description provided for @contactUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Contact updated successfully'**
  String get contactUpdatedSuccessfully;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'deleted'**
  String get deleted;

  /// No description provided for @groupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a group name'**
  String get groupNameRequired;

  /// No description provided for @groupCreateError.
  ///
  /// In en, this message translates to:
  /// **'Failed to create group'**
  String get groupCreateError;

  /// No description provided for @failedToDeleteContact.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete contact'**
  String get failedToDeleteContact;

  /// No description provided for @errorDeletingContact.
  ///
  /// In en, this message translates to:
  /// **'Error deleting contact'**
  String get errorDeletingContact;

  /// No description provided for @addContact.
  ///
  /// In en, this message translates to:
  /// **'Add Contact'**
  String get addContact;

  /// No description provided for @addContactFeature.
  ///
  /// In en, this message translates to:
  /// **'Add contact feature will be implemented'**
  String get addContactFeature;

  /// No description provided for @editContact.
  ///
  /// In en, this message translates to:
  /// **'Edit Contact'**
  String get editContact;

  /// No description provided for @editContactFeature.
  ///
  /// In en, this message translates to:
  /// **'Edit contact feature will be implemented'**
  String get editContactFeature;

  /// No description provided for @deleteContact.
  ///
  /// In en, this message translates to:
  /// **'Delete Contact'**
  String get deleteContact;

  /// No description provided for @deleteContactConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete contact'**
  String get deleteContactConfirm;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @selectColor.
  ///
  /// In en, this message translates to:
  /// **'Select Color'**
  String get selectColor;

  /// No description provided for @selectAvatarColor.
  ///
  /// In en, this message translates to:
  /// **'Select avatar color'**
  String get selectAvatarColor;

  /// No description provided for @photoSelected.
  ///
  /// In en, this message translates to:
  /// **'Photo selected'**
  String get photoSelected;

  /// No description provided for @photoPickError.
  ///
  /// In en, this message translates to:
  /// **'Failed to select photo'**
  String get photoPickError;

  /// No description provided for @enterGroupChannel.
  ///
  /// In en, this message translates to:
  /// **'Enter group channel'**
  String get enterGroupChannel;

  /// No description provided for @groupCreated.
  ///
  /// In en, this message translates to:
  /// **'Group created successfully'**
  String get groupCreated;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches found'**
  String get noMatches;

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search users...'**
  String get searchPlaceholder;

  /// No description provided for @completeProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete Profile'**
  String get completeProfile;

  /// No description provided for @completeProfileInfo.
  ///
  /// In en, this message translates to:
  /// **'Please complete your profile before using the application'**
  String get completeProfileInfo;

  /// No description provided for @continueText.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueText;

  /// No description provided for @cropPhoto.
  ///
  /// In en, this message translates to:
  /// **'Crop Photo'**
  String get cropPhoto;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @codeFromEmail.
  ///
  /// In en, this message translates to:
  /// **'Code from email'**
  String get codeFromEmail;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in'**
  String get resendIn;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get seconds;

  /// No description provided for @profileSaveError.
  ///
  /// In en, this message translates to:
  /// **'Profile save error'**
  String get profileSaveError;

  /// No description provided for @disableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Disable notifications'**
  String get disableNotifications;

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get enableNotifications;

  /// No description provided for @disableForever.
  ///
  /// In en, this message translates to:
  /// **'Disable forever'**
  String get disableForever;

  /// No description provided for @forever.
  ///
  /// In en, this message translates to:
  /// **'Forever'**
  String get forever;

  /// No description provided for @sevenDays.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get sevenDays;

  /// No description provided for @disableForSevenDays.
  ///
  /// In en, this message translates to:
  /// **'Disable for 7 days'**
  String get disableForSevenDays;

  /// No description provided for @twentyFourHours.
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get twentyFourHours;

  /// No description provided for @disableFor24Hours.
  ///
  /// In en, this message translates to:
  /// **'Disable for 24 hours'**
  String get disableFor24Hours;

  /// No description provided for @twelveHours.
  ///
  /// In en, this message translates to:
  /// **'12 hours'**
  String get twelveHours;

  /// No description provided for @disableFor12Hours.
  ///
  /// In en, this message translates to:
  /// **'Disable for 12 hours'**
  String get disableFor12Hours;

  /// No description provided for @threeHours.
  ///
  /// In en, this message translates to:
  /// **'3 hours'**
  String get threeHours;

  /// No description provided for @disableFor3Hours.
  ///
  /// In en, this message translates to:
  /// **'Disable for 3 hours'**
  String get disableFor3Hours;

  /// No description provided for @passwordInvalid.
  ///
  /// In en, this message translates to:
  /// **'Password contains invalid characters'**
  String get passwordInvalid;

  /// No description provided for @notificationsDisabledForever.
  ///
  /// In en, this message translates to:
  /// **'Notifications disabled forever'**
  String get notificationsDisabledForever;

  /// No description provided for @notificationsDisabledFor.
  ///
  /// In en, this message translates to:
  /// **'Notifications disabled for'**
  String get notificationsDisabledFor;

  /// No description provided for @notificationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Notifications enabled'**
  String get notificationsEnabled;

  /// No description provided for @messagePinned.
  ///
  /// In en, this message translates to:
  /// **'Message pinned'**
  String get messagePinned;

  /// No description provided for @messageUnpinned.
  ///
  /// In en, this message translates to:
  /// **'Message unpinned'**
  String get messageUnpinned;

  /// No description provided for @contactUpdated.
  ///
  /// In en, this message translates to:
  /// **'Contact updated'**
  String get contactUpdated;

  /// No description provided for @contactAdded.
  ///
  /// In en, this message translates to:
  /// **'Contact added'**
  String get contactAdded;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// No description provided for @unsubscribe.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get unsubscribe;

  /// No description provided for @subscribed.
  ///
  /// In en, this message translates to:
  /// **'You have subscribed to the channel'**
  String get subscribed;

  /// No description provided for @unsubscribed.
  ///
  /// In en, this message translates to:
  /// **'You have unsubscribed from the channel'**
  String get unsubscribed;

  /// No description provided for @contactNotFound.
  ///
  /// In en, this message translates to:
  /// **'Contact not found'**
  String get contactNotFound;

  /// No description provided for @errorLoadingContact.
  ///
  /// In en, this message translates to:
  /// **'Error loading contact'**
  String get errorLoadingContact;

  /// No description provided for @contactDeleted.
  ///
  /// In en, this message translates to:
  /// **'Contact deleted'**
  String get contactDeleted;

  /// No description provided for @cannotOpenMediaForNewChat.
  ///
  /// In en, this message translates to:
  /// **'Cannot open media for new chat'**
  String get cannotOpenMediaForNewChat;

  /// No description provided for @chatHistoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Chat history cleared'**
  String get chatHistoryCleared;

  /// No description provided for @chatUnblocked.
  ///
  /// In en, this message translates to:
  /// **'Chat unblocked'**
  String get chatUnblocked;

  /// No description provided for @chatBlocked.
  ///
  /// In en, this message translates to:
  /// **'Chat blocked'**
  String get chatBlocked;

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get addedToFavorites;

  /// No description provided for @removedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get removedFromFavorites;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{day} other{days}}'**
  String days(num count);

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{hour} other{hours}}'**
  String hours(num count);

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{minute} other{minutes}}'**
  String minutes(num count);

  /// No description provided for @pinMessage.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pinMessage;

  /// No description provided for @unpinMessage.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinMessage;

  /// No description provided for @pinnedMessages.
  ///
  /// In en, this message translates to:
  /// **'pinned'**
  String get pinnedMessages;

  /// No description provided for @failedToPinMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to pin message'**
  String get failedToPinMessage;

  /// No description provided for @failedToUnpinMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to unpin message'**
  String get failedToUnpinMessage;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @noPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos'**
  String get noPhotos;

  /// No description provided for @noVideos.
  ///
  /// In en, this message translates to:
  /// **'No videos'**
  String get noVideos;

  /// No description provided for @noAudio.
  ///
  /// In en, this message translates to:
  /// **'No audio'**
  String get noAudio;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @voiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get voiceMessage;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @notRegistered.
  ///
  /// In en, this message translates to:
  /// **'Not registered'**
  String get notRegistered;

  /// No description provided for @confirmNewEmail.
  ///
  /// In en, this message translates to:
  /// **'Confirm new email before saving'**
  String get confirmNewEmail;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @sendAgain.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get sendAgain;

  /// No description provided for @invalidEmailFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get invalidEmailFormat;

  /// No description provided for @emailAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'Email already in use'**
  String get emailAlreadyUsed;

  /// No description provided for @sendCodeError.
  ///
  /// In en, this message translates to:
  /// **'Error sending code'**
  String get sendCodeError;

  /// No description provided for @verificationCodeSentTo.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent to'**
  String get verificationCodeSentTo;

  /// No description provided for @enterVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Enter verification code'**
  String get enterVerificationCode;

  /// No description provided for @codeMustBe4Digits.
  ///
  /// In en, this message translates to:
  /// **'Code must be 4 digits'**
  String get codeMustBe4Digits;

  /// Error message for code verification failure
  ///
  /// In en, this message translates to:
  /// **'Error verifying code: {error}'**
  String verificationError(Object error);

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid code'**
  String get invalidCode;

  /// No description provided for @emailSuccessfullyChanged.
  ///
  /// In en, this message translates to:
  /// **'Email successfully changed!'**
  String get emailSuccessfullyChanged;

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// No description provided for @nothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get nothingFound;

  /// No description provided for @searchInChatsContactsChannels.
  ///
  /// In en, this message translates to:
  /// **'Search in chats, contacts and channels'**
  String get searchInChatsContactsChannels;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @clearRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'Clear recent searches'**
  String get clearRecentSearches;

  /// No description provided for @searchHere.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchHere;

  /// No description provided for @newContact.
  ///
  /// In en, this message translates to:
  /// **'New contact'**
  String get newContact;

  /// No description provided for @contactName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get contactName;

  /// No description provided for @contactEmail.
  ///
  /// In en, this message translates to:
  /// **'Contact email'**
  String get contactEmail;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @createContact.
  ///
  /// In en, this message translates to:
  /// **'Create contact'**
  String get createContact;

  /// No description provided for @contactSaved.
  ///
  /// In en, this message translates to:
  /// **'Contact successfully saved'**
  String get contactSaved;

  /// No description provided for @contactNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Contact name is required'**
  String get contactNameRequired;

  /// No description provided for @validEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get validEmailRequired;

  /// No description provided for @contactEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Contact email is required'**
  String get contactEmailRequired;

  /// No description provided for @channelLink.
  ///
  /// In en, this message translates to:
  /// **'Channel link'**
  String get channelLink;

  /// No description provided for @channelLinkRequired.
  ///
  /// In en, this message translates to:
  /// **'Channel link is required'**
  String get channelLinkRequired;

  /// No description provided for @channelLinkInvalidChars.
  ///
  /// In en, this message translates to:
  /// **'Only English letters, numbers, _ and -'**
  String get channelLinkInvalidChars;

  /// No description provided for @channelLinkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Link is unavailable'**
  String get channelLinkUnavailable;

  /// No description provided for @authTokenMissing.
  ///
  /// In en, this message translates to:
  /// **'Authorization token is missing'**
  String get authTokenMissing;

  /// No description provided for @requestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timeout (10 seconds)'**
  String get requestTimeout;

  /// No description provided for @channelCreateError.
  ///
  /// In en, this message translates to:
  /// **'Channel creation error'**
  String get channelCreateError;

  /// No description provided for @chatIsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Chat is blocked'**
  String get chatIsBlocked;

  /// No description provided for @fillAtLeastOneField.
  ///
  /// In en, this message translates to:
  /// **'Fill at least one field: Name or Nickname'**
  String get fillAtLeastOneField;

  /// No description provided for @fixErrors.
  ///
  /// In en, this message translates to:
  /// **'Fix errors before saving'**
  String get fixErrors;

  /// No description provided for @chatIsBlockedCannotSend.
  ///
  /// In en, this message translates to:
  /// **'This chat is blocked. You cannot send messages.'**
  String get chatIsBlockedCannotSend;

  /// No description provided for @chatIsBlockedWarning.
  ///
  /// In en, this message translates to:
  /// **'This chat is blocked. You cannot send messages.'**
  String get chatIsBlockedWarning;

  /// No description provided for @areYouSureYouWantToBlockChat.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to block this chat?'**
  String get areYouSureYouWantToBlockChat;

  /// No description provided for @areYouSureYouWantToUnblockChat.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to unblock this chat?'**
  String get areYouSureYouWantToUnblockChat;

  /// No description provided for @blockUserWarning.
  ///
  /// In en, this message translates to:
  /// **'You will not receive messages from this user and you will not be able to send messages to them.'**
  String get blockUserWarning;

  /// No description provided for @cannotBlockAIChat.
  ///
  /// In en, this message translates to:
  /// **'AI chats cannot be blocked'**
  String get cannotBlockAIChat;

  /// No description provided for @cannotBlockThisChat.
  ///
  /// In en, this message translates to:
  /// **'This chat cannot be blocked'**
  String get cannotBlockThisChat;

  /// No description provided for @chatHasBeenBlocked.
  ///
  /// In en, this message translates to:
  /// **'Chat has been blocked'**
  String get chatHasBeenBlocked;

  /// No description provided for @chatHasBeenUnblocked.
  ///
  /// In en, this message translates to:
  /// **'Chat has been unblocked'**
  String get chatHasBeenUnblocked;

  /// No description provided for @userHasBeenBlocked.
  ///
  /// In en, this message translates to:
  /// **'{userName} has been blocked'**
  String userHasBeenBlocked(Object userName);

  /// No description provided for @userHasBeenUnblocked.
  ///
  /// In en, this message translates to:
  /// **'{userName} has been unblocked'**
  String userHasBeenUnblocked(Object userName);

  /// No description provided for @areYouSureYouWantToBlockUser.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to block {userName}?'**
  String areYouSureYouWantToBlockUser(Object userName);

  /// No description provided for @areYouSureYouWantToUnblockUser.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to unblock {userName}?'**
  String areYouSureYouWantToUnblockUser(Object userName);

  /// No description provided for @nicknameTaken.
  ///
  /// In en, this message translates to:
  /// **'Nickname already taken'**
  String get nicknameTaken;

  /// No description provided for @fixNicknameErrors.
  ///
  /// In en, this message translates to:
  /// **'Please fix nickname errors'**
  String get fixNicknameErrors;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Profile Settings'**
  String get profileSettings;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get enterName;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @enterNickname.
  ///
  /// In en, this message translates to:
  /// **'Enter nickname'**
  String get enterNickname;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// No description provided for @notSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get notSpecified;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @selectGender.
  ///
  /// In en, this message translates to:
  /// **'Select gender'**
  String get selectGender;

  /// No description provided for @male.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// No description provided for @female.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get female;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @privacySettings.
  ///
  /// In en, this message translates to:
  /// **'Privacy Settings'**
  String get privacySettings;

  /// No description provided for @blockCalls.
  ///
  /// In en, this message translates to:
  /// **'Block calls'**
  String get blockCalls;

  /// No description provided for @blockVoiceMessages.
  ///
  /// In en, this message translates to:
  /// **'Block voice messages'**
  String get blockVoiceMessages;

  /// No description provided for @blockGroups.
  ///
  /// In en, this message translates to:
  /// **'Block adding to groups'**
  String get blockGroups;

  /// No description provided for @colorAvailableWithoutPhoto.
  ///
  /// In en, this message translates to:
  /// **'Color available without photo'**
  String get colorAvailableWithoutPhoto;

  /// No description provided for @chooseColor.
  ///
  /// In en, this message translates to:
  /// **'Choose color'**
  String get chooseColor;

  /// No description provided for @selectPhoto.
  ///
  /// In en, this message translates to:
  /// **'Select photo'**
  String get selectPhoto;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSaved;

  /// No description provided for @saveError.
  ///
  /// In en, this message translates to:
  /// **'Save error'**
  String get saveError;

  /// No description provided for @blockUser.
  ///
  /// In en, this message translates to:
  /// **'Block User'**
  String get blockUser;

  /// No description provided for @unblockUser.
  ///
  /// In en, this message translates to:
  /// **'Unblock User'**
  String get unblockUser;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @chatFolders.
  ///
  /// In en, this message translates to:
  /// **'Chat folders'**
  String get chatFolders;

  /// No description provided for @interfaceScale.
  ///
  /// In en, this message translates to:
  /// **'Interface scale'**
  String get interfaceScale;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select language'**
  String get selectLanguage;

  /// No description provided for @russian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get russian;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get spanish;

  /// No description provided for @chinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get chinese;

  /// No description provided for @korean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get korean;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// No description provided for @french.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// No description provided for @italian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get italian;

  /// No description provided for @japanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get japanese;

  /// No description provided for @hindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get hindi;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @hebrew.
  ///
  /// In en, this message translates to:
  /// **'Hebrew'**
  String get hebrew;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroup;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSize;

  /// No description provided for @fontSizeDescription.
  ///
  /// In en, this message translates to:
  /// **'Adjust font size for comfortable reading'**
  String get fontSizeDescription;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @personalData.
  ///
  /// In en, this message translates to:
  /// **'Personal data'**
  String get personalData;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// Message about feature in development
  ///
  /// In en, this message translates to:
  /// **'Feature \"{feature}\" is under development'**
  String featureInDevelopment(String feature);

  /// Search input hint text in home page
  ///
  /// In en, this message translates to:
  /// **'Search chats...'**
  String get searchChats;

  /// No description provided for @dataProcessing.
  ///
  /// In en, this message translates to:
  /// **'Data processing'**
  String get dataProcessing;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter email'**
  String get enterEmail;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter valid email'**
  String get enterValidEmail;

  /// No description provided for @emailAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'Email already registered'**
  String get emailAlreadyRegistered;

  /// No description provided for @failedToSendCode.
  ///
  /// In en, this message translates to:
  /// **'Failed to send code'**
  String get failedToSendCode;

  /// No description provided for @codeSendError.
  ///
  /// In en, this message translates to:
  /// **'Error sending code'**
  String get codeSendError;

  /// No description provided for @invalidVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid verification code'**
  String get invalidVerificationCode;

  /// No description provided for @codeVerificationError.
  ///
  /// In en, this message translates to:
  /// **'Error verifying code'**
  String get codeVerificationError;

  /// No description provided for @codeExpired.
  ///
  /// In en, this message translates to:
  /// **'Code expired'**
  String get codeExpired;

  /// No description provided for @confirmEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'Confirm email first'**
  String get confirmEmailFirst;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get enterPassword;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 10 characters'**
  String get passwordMinLength;

  /// No description provided for @passwordUppercase.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one uppercase letter'**
  String get passwordUppercase;

  /// No description provided for @passwordDigit.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one digit'**
  String get passwordDigit;

  /// No description provided for @passwordLatinOnly.
  ///
  /// In en, this message translates to:
  /// **'Password must contain only Latin letters, digits and special characters'**
  String get passwordLatinOnly;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @invalidServerResponse.
  ///
  /// In en, this message translates to:
  /// **'Invalid server response'**
  String get invalidServerResponse;

  /// No description provided for @registrationError.
  ///
  /// In en, this message translates to:
  /// **'Registration error'**
  String get registrationError;

  /// No description provided for @registrationSuccessfulLogin.
  ///
  /// In en, this message translates to:
  /// **'Registration successful, please log in'**
  String get registrationSuccessfulLogin;

  /// No description provided for @authError.
  ///
  /// In en, this message translates to:
  /// **'Authentication error'**
  String get authError;

  /// No description provided for @incorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get incorrectPassword;

  /// No description provided for @attemptsExhausted.
  ///
  /// In en, this message translates to:
  /// **'Attempts exhausted'**
  String get attemptsExhausted;

  /// No description provided for @accessTemporarilyBlocked.
  ///
  /// In en, this message translates to:
  /// **'Access temporarily blocked'**
  String get accessTemporarilyBlocked;

  /// No description provided for @tooManyFailedAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many failed attempts'**
  String get tooManyFailedAttempts;

  /// No description provided for @recoverAccess.
  ///
  /// In en, this message translates to:
  /// **'Recover access'**
  String get recoverAccess;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @agreeWith.
  ///
  /// In en, this message translates to:
  /// **'I agree with'**
  String get agreeWith;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get and;

  /// No description provided for @getCode.
  ///
  /// In en, this message translates to:
  /// **'Get code'**
  String get getCode;

  /// No description provided for @codeSentToEmail.
  ///
  /// In en, this message translates to:
  /// **'Code sent to email'**
  String get codeSentToEmail;

  /// No description provided for @verifyCode.
  ///
  /// In en, this message translates to:
  /// **'Verify code'**
  String get verifyCode;

  /// No description provided for @didntReceiveCode.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive code?'**
  String get didntReceiveCode;

  /// No description provided for @sendNewCode.
  ///
  /// In en, this message translates to:
  /// **'Send new code'**
  String get sendNewCode;

  /// No description provided for @emailVerified.
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get emailVerified;

  /// No description provided for @createPassword.
  ///
  /// In en, this message translates to:
  /// **'Create password'**
  String get createPassword;

  /// No description provided for @repeatPassword.
  ///
  /// In en, this message translates to:
  /// **'Repeat password'**
  String get repeatPassword;

  /// No description provided for @completeRegistration.
  ///
  /// In en, this message translates to:
  /// **'Complete registration'**
  String get completeRegistration;

  /// No description provided for @noAccountRegister.
  ///
  /// In en, this message translates to:
  /// **'No account? Register'**
  String get noAccountRegister;

  /// No description provided for @alreadyHaveAccountLogin.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Log in'**
  String get alreadyHaveAccountLogin;

  /// No description provided for @attemptsLeft.
  ///
  /// In en, this message translates to:
  /// **'Attempts left'**
  String get attemptsLeft;

  /// No description provided for @testChat.
  ///
  /// In en, this message translates to:
  /// **'Test Chat'**
  String get testChat;

  /// No description provided for @testMessageForDevelopment.
  ///
  /// In en, this message translates to:
  /// **'Test message for development'**
  String get testMessageForDevelopment;

  /// No description provided for @developmentGroup.
  ///
  /// In en, this message translates to:
  /// **'Development Group'**
  String get developmentGroup;

  /// No description provided for @needToTestMessageSending.
  ///
  /// In en, this message translates to:
  /// **'Need to test message sending'**
  String get needToTestMessageSending;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @welcomeToApp.
  ///
  /// In en, this message translates to:
  /// **'Welcome to the app!'**
  String get welcomeToApp;

  /// No description provided for @alexey.
  ///
  /// In en, this message translates to:
  /// **'Alexey'**
  String get alexey;

  /// No description provided for @whenWillNewVersionBeReady.
  ///
  /// In en, this message translates to:
  /// **'When will the new version be ready?'**
  String get whenWillNewVersionBeReady;

  /// No description provided for @projectTeam.
  ///
  /// In en, this message translates to:
  /// **'Project Team'**
  String get projectTeam;

  /// No description provided for @meetingTomorrowAt10.
  ///
  /// In en, this message translates to:
  /// **'Meeting tomorrow at 10:00'**
  String get meetingTomorrowAt10;

  /// No description provided for @oldProject.
  ///
  /// In en, this message translates to:
  /// **'Old Project'**
  String get oldProject;

  /// No description provided for @finishedPreviousProject.
  ///
  /// In en, this message translates to:
  /// **'Finished previous project'**
  String get finishedPreviousProject;

  /// No description provided for @supportClosed.
  ///
  /// In en, this message translates to:
  /// **'Support (closed)'**
  String get supportClosed;

  /// No description provided for @thanksForContacting.
  ///
  /// In en, this message translates to:
  /// **'Thanks for contacting!'**
  String get thanksForContacting;

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChat;

  /// No description provided for @actionCannotBeUndoneAllMessagesWillBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. All messages will be deleted.'**
  String get actionCannotBeUndoneAllMessagesWillBeDeleted;

  /// No description provided for @movedToArchive.
  ///
  /// In en, this message translates to:
  /// **'moved to archive'**
  String get movedToArchive;

  /// No description provided for @aiChatsCannotBeArchived.
  ///
  /// In en, this message translates to:
  /// **'AI chats cannot be archived'**
  String get aiChatsCannotBeArchived;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @startNewDialogOrCreateAIChat.
  ///
  /// In en, this message translates to:
  /// **'Start a new dialog or create AI chat'**
  String get startNewDialogOrCreateAIChat;

  /// No description provided for @createChat.
  ///
  /// In en, this message translates to:
  /// **'Create chat'**
  String get createChat;

  /// No description provided for @aiChat.
  ///
  /// In en, this message translates to:
  /// **'AI chat'**
  String get aiChat;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @allChats.
  ///
  /// In en, this message translates to:
  /// **'All chats'**
  String get allChats;

  /// No description provided for @myChats.
  ///
  /// In en, this message translates to:
  /// **'My chats'**
  String get myChats;

  /// No description provided for @searchFeatureWillBeImplementedLater.
  ///
  /// In en, this message translates to:
  /// **'Search feature will be implemented later'**
  String get searchFeatureWillBeImplementedLater;

  /// No description provided for @clearAllChats.
  ///
  /// In en, this message translates to:
  /// **'Clear all chats'**
  String get clearAllChats;

  /// No description provided for @allChatsIncludingArchivedWillBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'All chats, including archived ones, will be deleted'**
  String get allChatsIncludingArchivedWillBeDeleted;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @allChatsCleared.
  ///
  /// In en, this message translates to:
  /// **'All chats cleared'**
  String get allChatsCleared;

  /// No description provided for @information.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get information;

  /// No description provided for @contactsSectionWillBeImplementedLater.
  ///
  /// In en, this message translates to:
  /// **'Contacts section will be implemented later'**
  String get contactsSectionWillBeImplementedLater;

  /// No description provided for @groupCreationFeatureWillBeImplementedLater.
  ///
  /// In en, this message translates to:
  /// **'Group creation feature will be implemented later'**
  String get groupCreationFeatureWillBeImplementedLater;

  /// No description provided for @loadingYourChats.
  ///
  /// In en, this message translates to:
  /// **'Loading your chats...'**
  String get loadingYourChats;

  /// No description provided for @newAIChat.
  ///
  /// In en, this message translates to:
  /// **'New AI chat'**
  String get newAIChat;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @logoutFromAccount.
  ///
  /// In en, this message translates to:
  /// **'Logout from account'**
  String get logoutFromAccount;

  /// No description provided for @areYouSureYouWantToLogout.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get areYouSureYouWantToLogout;

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages'**
  String get noMessages;

  /// No description provided for @voiceMessages.
  ///
  /// In en, this message translates to:
  /// **'Voice messages'**
  String get voiceMessages;

  /// No description provided for @voiceMessagesMicrophonePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Voice messages require microphone permission'**
  String get voiceMessagesMicrophonePermissionRequired;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessage;

  /// No description provided for @actionCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone'**
  String get actionCannotBeUndone;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @contactManagement.
  ///
  /// In en, this message translates to:
  /// **'Contact management'**
  String get contactManagement;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @allChatHistoryWillBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'All chat history will be deleted'**
  String get allChatHistoryWillBeDeleted;

  /// No description provided for @searchInChat.
  ///
  /// In en, this message translates to:
  /// **'Search in chat'**
  String get searchInChat;

  /// No description provided for @attachedFiles.
  ///
  /// In en, this message translates to:
  /// **'Attached files'**
  String get attachedFiles;

  /// No description provided for @enterMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter message...'**
  String get enterMessage;

  /// No description provided for @enterMessageWithFiles.
  ///
  /// In en, this message translates to:
  /// **'Enter message with files...'**
  String get enterMessageWithFiles;

  /// No description provided for @failedToLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image'**
  String get failedToLoadImage;

  /// No description provided for @failedToLoadVideoTryBrowser.
  ///
  /// In en, this message translates to:
  /// **'Failed to load video. Try opening in browser'**
  String get failedToLoadVideoTryBrowser;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @clickToCopy.
  ///
  /// In en, this message translates to:
  /// **'Click to copy link'**
  String get clickToCopy;

  /// No description provided for @audioServiceNotInitialized.
  ///
  /// In en, this message translates to:
  /// **'Audio service not initialized'**
  String get audioServiceNotInitialized;

  /// No description provided for @microphonePermissionNotGranted.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission not granted'**
  String get microphonePermissionNotGranted;

  /// No description provided for @failedToStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Failed to start recording'**
  String get failedToStartRecording;

  /// No description provided for @webRequiresHTTPSAndMicrophonePermission.
  ///
  /// In en, this message translates to:
  /// **'Web requires HTTPS and microphone permission'**
  String get webRequiresHTTPSAndMicrophonePermission;

  /// No description provided for @checkMicrophonePermissionsInAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Check microphone permissions in app settings'**
  String get checkMicrophonePermissionsInAppSettings;

  /// No description provided for @errorStoppingRecording.
  ///
  /// In en, this message translates to:
  /// **'Error stopping recording'**
  String get errorStoppingRecording;

  /// No description provided for @errorDeletingRecording.
  ///
  /// In en, this message translates to:
  /// **'Error deleting recording'**
  String get errorDeletingRecording;

  /// No description provided for @recordVoiceMessageFirst.
  ///
  /// In en, this message translates to:
  /// **'Record voice message first'**
  String get recordVoiceMessageFirst;

  /// No description provided for @errorSendingVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Error sending voice message'**
  String get errorSendingVoiceMessage;

  /// No description provided for @failedToPlayVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to play voice message'**
  String get failedToPlayVoiceMessage;

  /// No description provided for @errorSelectingFiles.
  ///
  /// In en, this message translates to:
  /// **'Error selecting files'**
  String get errorSelectingFiles;

  /// No description provided for @errorSendingMessage.
  ///
  /// In en, this message translates to:
  /// **'Error sending message'**
  String get errorSendingMessage;

  /// No description provided for @errorSendingFiles.
  ///
  /// In en, this message translates to:
  /// **'Error sending files'**
  String get errorSendingFiles;

  /// No description provided for @errorLoadingVideo.
  ///
  /// In en, this message translates to:
  /// **'Error loading video'**
  String get errorLoadingVideo;

  /// No description provided for @errorLoadingMessages.
  ///
  /// In en, this message translates to:
  /// **'Error loading messages'**
  String get errorLoadingMessages;

  /// No description provided for @deleteContactQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete contact?'**
  String get deleteContactQuestion;

  /// No description provided for @areYouSureDeleteContact.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this contact?'**
  String get areYouSureDeleteContact;

  /// No description provided for @failedToForwardFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to forward file'**
  String get failedToForwardFile;

  /// No description provided for @errorForwardingMessage.
  ///
  /// In en, this message translates to:
  /// **'Error forwarding message'**
  String get errorForwardingMessage;

  /// No description provided for @forwardMessage.
  ///
  /// In en, this message translates to:
  /// **'Forward message'**
  String get forwardMessage;

  /// No description provided for @searchChat.
  ///
  /// In en, this message translates to:
  /// **'Search chat'**
  String get searchChat;

  /// No description provided for @selectChatToForward.
  ///
  /// In en, this message translates to:
  /// **'Select chat to forward'**
  String get selectChatToForward;

  /// No description provided for @chatsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Chats not found'**
  String get chatsNotFound;

  /// No description provided for @noAvailableChats.
  ///
  /// In en, this message translates to:
  /// **'No available chats'**
  String get noAvailableChats;

  /// No description provided for @lastMessage.
  ///
  /// In en, this message translates to:
  /// **'Last message'**
  String get lastMessage;

  /// No description provided for @needToTest.
  ///
  /// In en, this message translates to:
  /// **'Need to test'**
  String get needToTest;

  /// No description provided for @projectDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Project discussion'**
  String get projectDiscussion;

  /// No description provided for @weekendPlans.
  ///
  /// In en, this message translates to:
  /// **'Weekend plans'**
  String get weekendPlans;

  /// No description provided for @workChat.
  ///
  /// In en, this message translates to:
  /// **'Work chat'**
  String get workChat;

  /// No description provided for @family.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get family;

  /// No description provided for @passwordRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Password Recovery'**
  String get passwordRecoveryTitle;

  /// No description provided for @passwordRecoveryEmailPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter the email associated with your account'**
  String get passwordRecoveryEmailPrompt;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter email'**
  String get emailRequired;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get invalidEmail;

  /// No description provided for @enterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter confirmation code'**
  String get enterCode;

  /// Message showing where the code was sent
  ///
  /// In en, this message translates to:
  /// **'Code sent to {email}'**
  String codeSent(Object email);

  /// No description provided for @codeRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter confirmation code'**
  String get codeRequired;

  /// No description provided for @confirmCode.
  ///
  /// In en, this message translates to:
  /// **'Confirm Code'**
  String get confirmCode;

  /// No description provided for @didNotReceive.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive code?'**
  String get didNotReceive;

  /// No description provided for @secondsShort.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get secondsShort;

  /// No description provided for @createNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Create new password'**
  String get createNewPassword;

  /// No description provided for @codeVerified.
  ///
  /// In en, this message translates to:
  /// **'Code verified'**
  String get codeVerified;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordRequired;

  /// No description provided for @savePassword.
  ///
  /// In en, this message translates to:
  /// **'Save Password'**
  String get savePassword;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to login'**
  String get backToLogin;

  /// No description provided for @userNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get userNotFound;

  /// No description provided for @wrongCode.
  ///
  /// In en, this message translates to:
  /// **'Wrong code'**
  String get wrongCode;

  /// No description provided for @passwordChangeError.
  ///
  /// In en, this message translates to:
  /// **'Password change error'**
  String get passwordChangeError;

  /// Error message for sending code failure
  ///
  /// In en, this message translates to:
  /// **'Error sending code: {error}'**
  String sendingError(Object error);

  /// Detailed error message for password change failure
  ///
  /// In en, this message translates to:
  /// **'Error changing password: {error}'**
  String passwordChangeErrorDetailed(Object error);

  /// No description provided for @startOfNewConversation.
  ///
  /// In en, this message translates to:
  /// **'Start of a new conversation'**
  String get startOfNewConversation;

  /// No description provided for @aiAssistantGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hello! I\'m your AI assistant. How can I help you today?'**
  String get aiAssistantGreeting;

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clearChat;

  /// No description provided for @startChatWithAIAssistant.
  ///
  /// In en, this message translates to:
  /// **'Start chat with AI assistant'**
  String get startChatWithAIAssistant;

  /// No description provided for @askAboutAnything.
  ///
  /// In en, this message translates to:
  /// **'Ask about anything'**
  String get askAboutAnything;

  /// No description provided for @aiIsTyping.
  ///
  /// In en, this message translates to:
  /// **'AI is typing...'**
  String get aiIsTyping;

  /// No description provided for @allMessagesInThisChatWillBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'All messages in this chat will be deleted'**
  String get allMessagesInThisChatWillBeDeleted;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @archiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'Archive is empty'**
  String get archiveEmpty;

  /// No description provided for @archivedChatsWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Archived chats will appear here'**
  String get archivedChatsWillAppearHere;

  /// No description provided for @archivedChats.
  ///
  /// In en, this message translates to:
  /// **'Archived chats'**
  String get archivedChats;

  /// No description provided for @searchInFavorites.
  ///
  /// In en, this message translates to:
  /// **'Search in favorites'**
  String get searchInFavorites;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @chatAddedToFolder.
  ///
  /// In en, this message translates to:
  /// **'Chat added to folder'**
  String get chatAddedToFolder;

  /// No description provided for @addToFolder.
  ///
  /// In en, this message translates to:
  /// **'Add to folder'**
  String get addToFolder;

  /// No description provided for @deleteFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Delete from favorites'**
  String get deleteFromFavorites;

  /// No description provided for @deleteFromFavoritesQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete from favorites?'**
  String get deleteFromFavoritesQuestion;

  /// No description provided for @deleteFromFavoritesDescription.
  ///
  /// In en, this message translates to:
  /// **'This message will be removed from favorites'**
  String get deleteFromFavoritesDescription;

  /// No description provided for @noFavoriteMessages.
  ///
  /// In en, this message translates to:
  /// **'No favorite messages'**
  String get noFavoriteMessages;

  /// No description provided for @saveImportantMessages.
  ///
  /// In en, this message translates to:
  /// **'Save important messages'**
  String get saveImportantMessages;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @birthday.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get birthday;

  /// No description provided for @comment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get comment;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @subscribers.
  ///
  /// In en, this message translates to:
  /// **'Subscribers'**
  String get subscribers;

  /// No description provided for @channel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get channel;

  /// No description provided for @writeToChannel.
  ///
  /// In en, this message translates to:
  /// **'Write to channel...'**
  String get writeToChannel;

  /// No description provided for @fileAttached.
  ///
  /// In en, this message translates to:
  /// **'File attached'**
  String get fileAttached;

  /// No description provided for @unpinned.
  ///
  /// In en, this message translates to:
  /// **'Unpinned'**
  String get unpinned;

  /// No description provided for @addUsers.
  ///
  /// In en, this message translates to:
  /// **'Add users'**
  String get addUsers;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @searchPlaceholderUsers.
  ///
  /// In en, this message translates to:
  /// **'Search users...'**
  String get searchPlaceholderUsers;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get supportTitle;

  /// No description provided for @nameField.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameField;

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get nameHint;

  /// No description provided for @problemField.
  ///
  /// In en, this message translates to:
  /// **'Describe the problem'**
  String get problemField;

  /// No description provided for @problemHint.
  ///
  /// In en, this message translates to:
  /// **'Describe your problem or question in detail'**
  String get problemHint;

  /// No description provided for @supportEmailInfo.
  ///
  /// In en, this message translates to:
  /// **'The request will be sent from your email:'**
  String get supportEmailInfo;

  /// No description provided for @emailNotSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get emailNotSpecified;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @ticketAccepted.
  ///
  /// In en, this message translates to:
  /// **'Request accepted'**
  String get ticketAccepted;

  /// No description provided for @ticketNumber.
  ///
  /// In en, this message translates to:
  /// **'Ticket number'**
  String get ticketNumber;

  /// No description provided for @confirmationSent.
  ///
  /// In en, this message translates to:
  /// **'Confirmation email sent\nto your email'**
  String get confirmationSent;

  /// No description provided for @responseTime.
  ///
  /// In en, this message translates to:
  /// **'Response will arrive within 24 hours'**
  String get responseTime;

  /// No description provided for @errorAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'You must be logged in to contact support'**
  String get errorAuthRequired;

  /// No description provided for @errorMinCharacters.
  ///
  /// In en, this message translates to:
  /// **'Problem description must contain at least 10 characters'**
  String get errorMinCharacters;

  /// No description provided for @errorFillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all fields'**
  String get errorFillAllFields;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get errorUnknown;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get errorNetwork;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode'**
  String get lightMode;

  /// No description provided for @userInvitesYouToChannel.
  ///
  /// In en, this message translates to:
  /// **'{userName} invites you to {channelName}'**
  String userInvitesYouToChannel(Object channelName, Object userName);

  /// No description provided for @failedToSendInvitations.
  ///
  /// In en, this message translates to:
  /// **'Failed to send invitations'**
  String get failedToSendInvitations;

  /// No description provided for @errorSendingInvitations.
  ///
  /// In en, this message translates to:
  /// **'Error sending invitations'**
  String get errorSendingInvitations;

  /// No description provided for @invitationSent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent'**
  String get invitationSent;

  /// No description provided for @invitationsSent.
  ///
  /// In en, this message translates to:
  /// **'Invitations sent'**
  String get invitationsSent;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @noAIChatsYet.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any AI chats yet'**
  String get noAIChatsYet;

  /// No description provided for @startNewConversationWithAI.
  ///
  /// In en, this message translates to:
  /// **'Start your first conversation with AI assistant'**
  String get startNewConversationWithAI;

  /// No description provided for @aiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistant;

  /// No description provided for @usingLocalAIModel.
  ///
  /// In en, this message translates to:
  /// **'Using local AI model'**
  String get usingLocalAIModel;

  /// No description provided for @generatingResponse.
  ///
  /// In en, this message translates to:
  /// **'Generating response...'**
  String get generatingResponse;

  /// No description provided for @typing.
  ///
  /// In en, this message translates to:
  /// **'Typing...'**
  String get typing;

  /// No description provided for @chatPinned.
  ///
  /// In en, this message translates to:
  /// **'Chat pinned'**
  String get chatPinned;

  /// No description provided for @chatRenamedTo.
  ///
  /// In en, this message translates to:
  /// **'Chat renamed to'**
  String get chatRenamedTo;

  /// No description provided for @chatDeleted.
  ///
  /// In en, this message translates to:
  /// **'Chat deleted'**
  String get chatDeleted;

  /// No description provided for @renameChat.
  ///
  /// In en, this message translates to:
  /// **'Rename chat'**
  String get renameChat;

  /// No description provided for @enterNewChatName.
  ///
  /// In en, this message translates to:
  /// **'Enter new chat name'**
  String get enterNewChatName;

  /// No description provided for @groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @membersCount.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersCount;

  /// No description provided for @addMembers.
  ///
  /// In en, this message translates to:
  /// **'Add Members'**
  String get addMembers;

  /// No description provided for @leaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get leaveGroup;

  /// No description provided for @areYouSureLeaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to leave the group?'**
  String get areYouSureLeaveGroup;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @youLeftGroup.
  ///
  /// In en, this message translates to:
  /// **'You left the group'**
  String get youLeftGroup;

  /// No description provided for @failedToLeaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Failed to leave group'**
  String get failedToLeaveGroup;

  /// No description provided for @cannotSendMessageNotMember.
  ///
  /// In en, this message translates to:
  /// **'You cannot send messages because you are not a member of this group'**
  String get cannotSendMessageNotMember;

  /// No description provided for @youAreNotMember.
  ///
  /// In en, this message translates to:
  /// **'You are not a member of this group'**
  String get youAreNotMember;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @removeMember.
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get removeMember;

  /// No description provided for @areYouSureRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove'**
  String get areYouSureRemoveMember;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @failedToLoadVideo.
  ///
  /// In en, this message translates to:
  /// **'Failed to load video'**
  String get failedToLoadVideo;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'de',
        'en',
        'es',
        'fr',
        'he',
        'hi',
        'it',
        'ja',
        'ko',
        'ru',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'he':
      return AppLocalizationsHe();
    case 'hi':
      return AppLocalizationsHi();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
