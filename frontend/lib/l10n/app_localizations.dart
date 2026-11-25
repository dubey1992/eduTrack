import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

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
    Locale('en'),
    Locale('hi'),
  ];

  /// Bottom bar tab: the trip screen.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get busNavHome;

  /// Bottom bar tab: the crew member's profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get busNavProfile;

  /// App bar title when the signed-in name is not known yet.
  ///
  /// In en, this message translates to:
  /// **'My Trip'**
  String get busMyTripTitle;

  /// Tooltip of the sign-out button in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get busLogOut;

  /// Heading when someone who is not a driver or attendant signs in to the Bus app.
  ///
  /// In en, this message translates to:
  /// **'This app is for the bus crew'**
  String get busNotCrewTitle;

  /// Explains the account is not a bus crew account.
  ///
  /// In en, this message translates to:
  /// **'Your account signs in to the school on the web instead. Ask your school admin if you should be driving a route.'**
  String get busNotCrewBody;

  /// Button on the not-crew screen.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get busSignOut;

  /// Splash screen while loading.
  ///
  /// In en, this message translates to:
  /// **'Getting your trips ready…'**
  String get busSplashLoading;

  /// Splash screen when loading takes long.
  ///
  /// In en, this message translates to:
  /// **'Still trying to reach your school.'**
  String get busSplashSlow;

  /// Splash screen hint under Try again.
  ///
  /// In en, this message translates to:
  /// **'Check that this phone has signal, then try again.'**
  String get busSplashCheckSignal;

  /// Button or tooltip that tries something again.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get busTryAgain;

  /// Landing headline.
  ///
  /// In en, this message translates to:
  /// **'Your trip sheet, on this phone.'**
  String get busLandingHeadline;

  /// Landing intro paragraph.
  ///
  /// In en, this message translates to:
  /// **'For the driver and the attendant on the bus. Everything you need for the run, and nothing else from the school.'**
  String get busLandingIntro;

  /// Landing point title.
  ///
  /// In en, this message translates to:
  /// **'Start the run'**
  String get busLandingStartTitle;

  /// Landing point body.
  ///
  /// In en, this message translates to:
  /// **'Today\'s routes are waiting when you open the app. One tap starts the pickup or the drop.'**
  String get busLandingStartBody;

  /// Landing point title.
  ///
  /// In en, this message translates to:
  /// **'Tick each child on and off'**
  String get busLandingTickTitle;

  /// Landing point body.
  ///
  /// In en, this message translates to:
  /// **'Boarded, dropped or absent. The school sees it, and the parents are told.'**
  String get busLandingTickBody;

  /// Landing point title.
  ///
  /// In en, this message translates to:
  /// **'Works without signal'**
  String get busLandingOfflineTitle;

  /// Landing point body.
  ///
  /// In en, this message translates to:
  /// **'Marks are kept on the phone and sent the moment you are back in range. Nothing is lost on the road.'**
  String get busLandingOfflineBody;

  /// Landing point title.
  ///
  /// In en, this message translates to:
  /// **'Call a child\'s parent'**
  String get busLandingCallTitle;

  /// Landing point body.
  ///
  /// In en, this message translates to:
  /// **'One button opens the dialler. You never see the number, and the call is recorded in the log.'**
  String get busLandingCallBody;

  /// Heading of the box on a phone already set up.
  ///
  /// In en, this message translates to:
  /// **'To sign in you need'**
  String get busLandingNeedSignIn;

  /// Heading of the box on a phone not yet set up.
  ///
  /// In en, this message translates to:
  /// **'Before you start you need'**
  String get busLandingNeedSetUp;

  /// What a set-up phone needs.
  ///
  /// In en, this message translates to:
  /// **'Your mobile number and the 4-digit passcode you chose on this phone.'**
  String get busLandingNeedSignInBody;

  /// What a new phone needs.
  ///
  /// In en, this message translates to:
  /// **'Your mobile number, and an 8-digit code from your school office. The code works for 24 hours. You choose a 4-digit passcode while setting up, and after that the passcode is all you need.'**
  String get busLandingNeedSetUpBody;

  /// Landing button on a set-up phone.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get busLandingSignIn;

  /// Landing button on a new phone.
  ///
  /// In en, this message translates to:
  /// **'Set up this phone'**
  String get busLandingSetUp;

  /// Landing footnote.
  ///
  /// In en, this message translates to:
  /// **'Lost your phone, or forgotten the passcode? Your school office can unlock your account and give you a new code.'**
  String get busLandingLostPhone;

  /// Heading of the set-up form.
  ///
  /// In en, this message translates to:
  /// **'Register this phone'**
  String get busRegisterTitle;

  /// Heading of the passcode sign-in form.
  ///
  /// In en, this message translates to:
  /// **'Bus crew sign in'**
  String get busSignInTitle;

  /// Help under the set-up heading.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number, the 8-digit setup code from your school office, and choose a 4-digit passcode.'**
  String get busRegisterHelp;

  /// Help under the sign-in heading.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number and your 4-digit passcode.'**
  String get busSignInHelp;

  /// Mobile number field label.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get busMobileLabel;

  /// Setup code field label.
  ///
  /// In en, this message translates to:
  /// **'Setup code'**
  String get busSetupCodeLabel;

  /// Setup code validation error.
  ///
  /// In en, this message translates to:
  /// **'Enter the 8-digit setup code from your office'**
  String get busSetupCodeInvalid;

  /// New passcode field label.
  ///
  /// In en, this message translates to:
  /// **'New passcode'**
  String get busNewPasscodeLabel;

  /// Confirm passcode field label.
  ///
  /// In en, this message translates to:
  /// **'Confirm passcode'**
  String get busConfirmPasscodeLabel;

  /// Confirm passcode error.
  ///
  /// In en, this message translates to:
  /// **'The passcodes do not match'**
  String get busPasscodesDiffer;

  /// Passcode field label.
  ///
  /// In en, this message translates to:
  /// **'Passcode'**
  String get busPasscodeLabel;

  /// Passcode validation error.
  ///
  /// In en, this message translates to:
  /// **'Enter your 4-digit passcode'**
  String get busPasscodeInvalid;

  /// Set-up form button.
  ///
  /// In en, this message translates to:
  /// **'Register and sign in'**
  String get busRegisterButton;

  /// Sign-in form button.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get busSignInButton;

  /// Link from the set-up form to the passcode form.
  ///
  /// In en, this message translates to:
  /// **'Already set up? Sign in with your passcode'**
  String get busUsePasscode;

  /// Link from the passcode form to the set-up form.
  ///
  /// In en, this message translates to:
  /// **'Have a new setup code? Register this phone again'**
  String get busUseSetupCode;

  /// Web-only link to email sign-in.
  ///
  /// In en, this message translates to:
  /// **'Sign in with email instead'**
  String get busUseEmail;

  /// Battery warning on the routes list.
  ///
  /// In en, this message translates to:
  /// **'This phone may stop sending the bus\'s position when the screen is off.'**
  String get busBatteryWarning;

  /// Link to the battery help screen.
  ///
  /// In en, this message translates to:
  /// **'How to fix it'**
  String get busBatteryHowToFix;

  /// Empty routes list.
  ///
  /// In en, this message translates to:
  /// **'No route is assigned to you yet. Ask your school office to add you to a route.'**
  String get busNoRoutes;

  /// Routes list shown from the phone's copy.
  ///
  /// In en, this message translates to:
  /// **'No signal - showing your routes as last saved on this phone.'**
  String get busRoutesFromPhone;

  /// Link and title of the trip check screen.
  ///
  /// In en, this message translates to:
  /// **'Trip check'**
  String get busTripCheck;

  /// Snackbar after starting a trip with no signal.
  ///
  /// In en, this message translates to:
  /// **'No signal: the trip has started on this phone. Mark children as usual - the school gets it all when signal returns.'**
  String get busStartedOnPhone;

  /// Snackbar when a trip cannot start offline.
  ///
  /// In en, this message translates to:
  /// **'No signal, and this phone has not saved this route yet. Open My Trip once with signal; after that a trip can start without.'**
  String get busRouteNotSaved;

  /// The route's driver, on the route card.
  ///
  /// In en, this message translates to:
  /// **'Driver: {name}'**
  String busDriverName(String name);

  /// How many stops a route has.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop} other{{count} stops}}'**
  String busStopsCount(int count);

  /// How many students ride.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 student} other{{count} students}}'**
  String busStudentsCount(int count);

  /// Summary of a finished trip; time from server.
  ///
  /// In en, this message translates to:
  /// **'{riders} · ended {time}'**
  String busEndedAt(String riders, String time);

  /// Licence has lapsed.
  ///
  /// In en, this message translates to:
  /// **'Your driving licence expired on {date}. Tell your school office.'**
  String busLicenceExpired(String date);

  /// Licence ends today.
  ///
  /// In en, this message translates to:
  /// **'Your driving licence expires today. Tell your school office.'**
  String get busLicenceToday;

  /// Licence ends tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Your driving licence expires tomorrow. Tell your school office.'**
  String get busLicenceTomorrow;

  /// Licence ends soon.
  ///
  /// In en, this message translates to:
  /// **'Your driving licence expires in {days} days, on {date}. Tell your school office.'**
  String busLicenceInDays(int days, String date);

  /// Badge: today's trip not started.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get busNotStarted;

  /// Badge: trip running.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get busEnRoute;

  /// Badge: trip finished.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get busCompleted;

  /// Badge: trip cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get busCancelled;

  /// Trip direction: to school.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get busPickup;

  /// Trip direction: home from school.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get busDrop;

  /// Why the drop cannot start yet.
  ///
  /// In en, this message translates to:
  /// **'Starts after the pickup. The drop takes home the children the pickup brought in.'**
  String get busDropWaits;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Start pickup'**
  String get busStartPickup;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Start drop'**
  String get busStartDrop;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Continue pickup'**
  String get busContinuePickup;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Continue drop'**
  String get busContinueDrop;

  /// Button on a finished trip.
  ///
  /// In en, this message translates to:
  /// **'View trip'**
  String get busViewTrip;

  /// Title of the running-late sheet.
  ///
  /// In en, this message translates to:
  /// **'Running late?'**
  String get busRunningLateQuestion;

  /// Running-late sheet help.
  ///
  /// In en, this message translates to:
  /// **'The parents still waiting on this route are told.'**
  String get busRunningLateHelp;

  /// Running-late choice.
  ///
  /// In en, this message translates to:
  /// **'About {minutes} minutes late'**
  String busLateMinutes(int minutes);

  /// Snackbar after reporting a delay.
  ///
  /// In en, this message translates to:
  /// **'Parents told: about {minutes} minutes late.'**
  String busParentsToldLate(int minutes);

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Could not open the phone\'s dialler.'**
  String get busNoDialler;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Could not open a maps app on this phone.'**
  String get busNoMapsApp;

  /// End-trip dialog title.
  ///
  /// In en, this message translates to:
  /// **'End this trip?'**
  String get busEndTripQuestion;

  /// End-trip dialog when nobody waits.
  ///
  /// In en, this message translates to:
  /// **'Every child has been marked. The trip will be recorded as completed.'**
  String get busEndAllMarked;

  /// End-trip dialog when children are unmarked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 child has} other{{count} children have}} not been marked and will be recorded as absent.'**
  String busEndUnmarked(int count);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'End trip'**
  String get busEndTrip;

  /// End-trip dialog cancel.
  ///
  /// In en, this message translates to:
  /// **'Keep going'**
  String get busKeepGoing;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Trip ended.'**
  String get busTripEnded;

  /// Back button to the routes list.
  ///
  /// In en, this message translates to:
  /// **'My routes'**
  String get busMyRoutes;

  /// A trip started offline.
  ///
  /// In en, this message translates to:
  /// **'Started on this phone with no signal. The school sees this trip when signal returns.'**
  String get busStartedOnPhoneNoSignal;

  /// Trip shown from the phone's copy.
  ///
  /// In en, this message translates to:
  /// **'No signal - showing the trip as last saved on this phone.'**
  String get busTripFromPhone;

  /// Search found nobody.
  ///
  /// In en, this message translates to:
  /// **'No child on this trip matches \"{query}\". Check the spelling, or clear the search.'**
  String busSearchNoMatch(String query);

  /// Section for children with no stop on this trip.
  ///
  /// In en, this message translates to:
  /// **'Other riders'**
  String get busOtherRiders;

  /// The school as a place, in 'Board at school'.
  ///
  /// In en, this message translates to:
  /// **'school'**
  String get busSchoolPlace;

  /// Snackbar after boarding many; place is a stop name or 'school'.
  ///
  /// In en, this message translates to:
  /// **'{count} boarded at {place}'**
  String busBulkDoneBoarded(int count, String place);

  /// Snackbar after dropping many.
  ///
  /// In en, this message translates to:
  /// **'{count} dropped at {place}'**
  String busBulkDoneDropped(int count, String place);

  /// Snackbar after marking many with another status.
  ///
  /// In en, this message translates to:
  /// **'{count} {status} at {place}'**
  String busBulkDoneOther(int count, String status, String place);

  /// Snackbar action that takes a mark back.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get busUndo;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Taken back - nobody was marked.'**
  String get busUndoneAll;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Taken back: {count}. The rest had already been sent to the school.'**
  String busUndonePartly(int count);

  /// Bulk button at a stop.
  ///
  /// In en, this message translates to:
  /// **'Board all {count} here'**
  String busBoardAllHere(int count);

  /// Bulk button at a stop.
  ///
  /// In en, this message translates to:
  /// **'Drop all {count} here'**
  String busDropAllHere(int count);

  /// Bulk button.
  ///
  /// In en, this message translates to:
  /// **'Board all {count} at school'**
  String busBoardAllAtSchool(int count);

  /// Bulk button.
  ///
  /// In en, this message translates to:
  /// **'Drop all {count} at school'**
  String busDropAllAtSchool(int count);

  /// Snackbar after a mark.
  ///
  /// In en, this message translates to:
  /// **'{name} boarded'**
  String busMarkedBoarded(String name);

  /// Snackbar after a mark.
  ///
  /// In en, this message translates to:
  /// **'{name} dropped'**
  String busMarkedDropped(String name);

  /// Snackbar after a mark.
  ///
  /// In en, this message translates to:
  /// **'{name} absent'**
  String busMarkedAbsent(String name);

  /// Snackbar after a mark.
  ///
  /// In en, this message translates to:
  /// **'{name} pending'**
  String busMarkedPending(String name);

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Taken back - {name} is not marked.'**
  String busUndoneOne(String name);

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Already sent to the school, so it stands. Ask the office to correct it.'**
  String get busUndoTooLate;

  /// Tooltip of the voice toggle.
  ///
  /// In en, this message translates to:
  /// **'Mute the spoken prompts'**
  String get busVoiceMute;

  /// Tooltip of the voice toggle.
  ///
  /// In en, this message translates to:
  /// **'Speak the next stop'**
  String get busVoiceSpeak;

  /// Why End trip is disabled.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 child is} other{{count} children are}} still on board. Drop them off before ending the trip.'**
  String busStillOnBoard(int count);

  /// Button that opens the running-late sheet.
  ///
  /// In en, this message translates to:
  /// **'Running late'**
  String get busRunningLate;

  /// Trip header counts.
  ///
  /// In en, this message translates to:
  /// **'{boarded} on board · {waiting} waiting · {dropped} dropped · {absent} absent'**
  String busTripCounts(int boarded, int waiting, int dropped, int absent);

  /// Tooltip; stop name is data.
  ///
  /// In en, this message translates to:
  /// **'Navigate to {stop}'**
  String busNavigateTo(String stop);

  /// Badge and button for a stop.
  ///
  /// In en, this message translates to:
  /// **'Reached'**
  String get busReached;

  /// Bulk sheet title.
  ///
  /// In en, this message translates to:
  /// **'Board at {place}'**
  String busBulkTitleBoard(String place);

  /// Bulk sheet title.
  ///
  /// In en, this message translates to:
  /// **'Drop at {place}'**
  String busBulkTitleDrop(String place);

  /// Bulk sheet help.
  ///
  /// In en, this message translates to:
  /// **'Untick anyone who is not here.'**
  String get busUntickHelp;

  /// Bulk sheet button.
  ///
  /// In en, this message translates to:
  /// **'Board {count}'**
  String busBulkConfirmBoard(int count);

  /// Bulk sheet button.
  ///
  /// In en, this message translates to:
  /// **'Drop {count}'**
  String busBulkConfirmDrop(int count);

  /// Switch title.
  ///
  /// In en, this message translates to:
  /// **'Share my location'**
  String get busShareLocation;

  /// Switch subtitle.
  ///
  /// In en, this message translates to:
  /// **'Asking for your location...'**
  String get busLocAsking;

  /// Switch subtitle.
  ///
  /// In en, this message translates to:
  /// **'The school can see where the bus is while this screen is open.'**
  String get busLocOn;

  /// Switch subtitle.
  ///
  /// In en, this message translates to:
  /// **'Off - the school cannot see where the bus is.'**
  String get busLocOff;

  /// Sharing stopped.
  ///
  /// In en, this message translates to:
  /// **'Location permission was not given, so your location is not being shared.'**
  String get busLocDenied;

  /// Sharing stopped.
  ///
  /// In en, this message translates to:
  /// **'Location is blocked for this app. Allow it in the phone settings to share your location.'**
  String get busLocBlocked;

  /// Sharing stopped.
  ///
  /// In en, this message translates to:
  /// **'Location is turned off on this phone. Turn it on to share your location.'**
  String get busLocServiceOff;

  /// Sharing stopped.
  ///
  /// In en, this message translates to:
  /// **'This device cannot share its location.'**
  String get busLocUnsupported;

  /// Sharing stopped.
  ///
  /// In en, this message translates to:
  /// **'The trip is no longer running, so location sharing has stopped.'**
  String get busLocTripEnded;

  /// Heading of marks the server refused.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get busNotSent;

  /// Help on a finished trip.
  ///
  /// In en, this message translates to:
  /// **'The school did not record these. Tell your school office, who can correct the trip.'**
  String get busNotSentHelpEnded;

  /// Help on a running trip.
  ///
  /// In en, this message translates to:
  /// **'The school did not record these. Try again if something has changed, or tell your school office, who can correct the trip.'**
  String get busNotSentHelpRunning;

  /// Tooltip that removes a not-sent mark from the list.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get busDismiss;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'The microphone could not be used. Check the app\'s permission, or type the name.'**
  String get busMicFailed;

  /// Search hint while listening.
  ///
  /// In en, this message translates to:
  /// **'Listening… say the child\'s name'**
  String get busSearchListening;

  /// Search hint.
  ///
  /// In en, this message translates to:
  /// **'Find a child by name, class or number'**
  String get busSearchHint;

  /// Tooltip that clears the search.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get busClear;

  /// Tooltip of the microphone.
  ///
  /// In en, this message translates to:
  /// **'Stop listening'**
  String get busStopListening;

  /// Tooltip of the microphone.
  ///
  /// In en, this message translates to:
  /// **'Say the name'**
  String get busSayName;

  /// A child not yet marked on this trip.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get busStatusPending;

  /// Child status / mark button.
  ///
  /// In en, this message translates to:
  /// **'Boarded'**
  String get busStatusBoarded;

  /// Child status / mark button.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get busStatusDropped;

  /// Child status / mark button.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get busStatusAbsent;

  /// Who marked a child; time may follow.
  ///
  /// In en, this message translates to:
  /// **'{status} by {name}'**
  String busMarkedBy(String status, String name);

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Call parent'**
  String get busCallParent;

  /// Tooltip when no guardian number.
  ///
  /// In en, this message translates to:
  /// **'No number on record'**
  String get busNoNumber;

  /// Snackbar after SOS.
  ///
  /// In en, this message translates to:
  /// **'SOS sent. Your school has been told where you are.'**
  String get busSosSent;

  /// Screen-reader label of the SOS button.
  ///
  /// In en, this message translates to:
  /// **'SOS. Hold for two seconds to ask your school for help.'**
  String get busSosSemantics;

  /// SOS button while held.
  ///
  /// In en, this message translates to:
  /// **'Keep holding...'**
  String get busSosHolding;

  /// SOS button.
  ///
  /// In en, this message translates to:
  /// **'Hold for SOS'**
  String get busSosHold;

  /// Sync banner.
  ///
  /// In en, this message translates to:
  /// **'Sending {count, plural, =1{1 mark} other{{count} marks}}...'**
  String busMarksSending(int count);

  /// Sync banner.
  ///
  /// In en, this message translates to:
  /// **'Offline - {count, plural, =1{1 mark} other{{count} marks}} waiting to send'**
  String busMarksOffline(int count);

  /// Sync banner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mark} other{{count} marks}} waiting to send'**
  String busMarksWaiting(int count);

  /// Sync banner button.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get busSendNow;

  /// Navigation fallback.
  ///
  /// In en, this message translates to:
  /// **'Guidance inside this app needs Google\'s terms, which you did not accept. You can still use Google Maps.'**
  String get busNavTermsRefused;

  /// Navigation fallback.
  ///
  /// In en, this message translates to:
  /// **'No route to this stop could be worked out. Check your signal, or try Google Maps.'**
  String get busNavNoRoute;

  /// Navigation fallback.
  ///
  /// In en, this message translates to:
  /// **'Guidance inside this app is not switched on for your school yet. Google Maps will take you there.'**
  String get busNavUnavailable;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Open Google Maps'**
  String get busOpenGoogleMaps;

  /// Battery help title and tooltip.
  ///
  /// In en, this message translates to:
  /// **'Keep the bus on the map'**
  String get busBatteryTitle;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Done. This phone will keep reporting with the screen off.'**
  String get busBatteryDone;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Not changed. The steps below do the same thing by hand.'**
  String get busBatteryNotChanged;

  /// Heading.
  ///
  /// In en, this message translates to:
  /// **'Why the school sometimes loses the bus'**
  String get busBatteryWhy;

  /// Battery help intro.
  ///
  /// In en, this message translates to:
  /// **'While a trip is running, this phone sends its position to the school so the office and parents can see where the bus is. Most phones stop apps they think you are not using - and a phone in a cradle with its screen off looks exactly like an app nobody is using.\n\nThese two settings tell the phone this one is different. You only have to do it once.'**
  String get busBatteryIntro;

  /// Step 1 title.
  ///
  /// In en, this message translates to:
  /// **'Allow it to run in the background'**
  String get busBatteryStep1Title;

  /// Step 1 done.
  ///
  /// In en, this message translates to:
  /// **'Already allowed on this phone.'**
  String get busBatteryStep1Done;

  /// Step 1 body.
  ///
  /// In en, this message translates to:
  /// **'This is the setting Android itself controls, and the button below opens it.'**
  String get busBatteryStep1Body;

  /// Step 1 button.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get busBatteryAllow;

  /// Step 2 title.
  ///
  /// In en, this message translates to:
  /// **'Turn off your phone maker\'s battery saver for this app'**
  String get busBatteryStep2Title;

  /// Step 2 body.
  ///
  /// In en, this message translates to:
  /// **'This one is not the same on every phone, and no app can change it for you. Find your make below.'**
  String get busBatteryStep2Body;

  /// Battery help footnote.
  ///
  /// In en, this message translates to:
  /// **'If you are not sure which make your phone is, show this screen to your school office.'**
  String get busBatteryNotSure;

  /// Phone make group.
  ///
  /// In en, this message translates to:
  /// **'Xiaomi, Redmi or POCO'**
  String get busMakeXiaomi;

  /// Settings path; menu names stay as the phone shows them in English.
  ///
  /// In en, this message translates to:
  /// **'Settings > Apps > Manage apps > School365ai Driver > Battery saver > No restrictions.'**
  String get busMakeXiaomi1;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'On the same screen, turn on Autostart.'**
  String get busMakeXiaomi2;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Open Recent apps, swipe down on this app\'s card and tap the padlock so it is not cleared.'**
  String get busMakeXiaomi3;

  /// Phone make group.
  ///
  /// In en, this message translates to:
  /// **'Oppo, Realme or OnePlus'**
  String get busMakeOppo;

  /// Settings path.
  ///
  /// In en, this message translates to:
  /// **'Settings > Battery > Power saving > App battery usage (or App battery management).'**
  String get busMakeOppo1;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Find School365ai Driver and choose Allow background activity, or Don\'t optimise.'**
  String get busMakeOppo2;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Turn on Allow auto launch for this app.'**
  String get busMakeOppo3;

  /// Phone make group.
  ///
  /// In en, this message translates to:
  /// **'Vivo or iQOO'**
  String get busMakeVivo;

  /// Settings path.
  ///
  /// In en, this message translates to:
  /// **'Settings > Battery > Background power consumption management > School365ai Driver > Allow high background power consumption.'**
  String get busMakeVivo1;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Settings > Apps > Autostart, and turn it on for this app.'**
  String get busMakeVivo2;

  /// Phone make group.
  ///
  /// In en, this message translates to:
  /// **'Samsung'**
  String get busMakeSamsung;

  /// Settings path.
  ///
  /// In en, this message translates to:
  /// **'Settings > Apps > School365ai Driver > Battery > Unrestricted.'**
  String get busMakeSamsung1;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Settings > Battery > Background usage limits, and make sure this app is not in Sleeping apps or Deep sleeping apps.'**
  String get busMakeSamsung2;

  /// Phone make group.
  ///
  /// In en, this message translates to:
  /// **'Any other phone'**
  String get busMakeOther;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Settings > Apps > School365ai Driver > Battery, and choose the least restricted option offered.'**
  String get busMakeOther1;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'If there is an Autostart or Auto launch setting, turn it on.'**
  String get busMakeOther2;

  /// Trip check error.
  ///
  /// In en, this message translates to:
  /// **'The trip log could not be read.'**
  String get busTripLogUnreadable;

  /// Trip check with no log.
  ///
  /// In en, this message translates to:
  /// **'No trip has shared its location on this phone yet. Run a trip with \"Share my location\" on, then come back here.'**
  String get busTripCheckNone;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Share report'**
  String get busShareReport;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Clear the log'**
  String get busClearLog;

  /// Battery state.
  ///
  /// In en, this message translates to:
  /// **'Battery saving will not stop this app'**
  String get busBatteryExempt;

  /// Battery state.
  ///
  /// In en, this message translates to:
  /// **'Battery saving may stop this app'**
  String get busBatteryMayStop;

  /// Battery state.
  ///
  /// In en, this message translates to:
  /// **'Checking battery settings...'**
  String get busBatteryChecking;

  /// Battery card subtitle.
  ///
  /// In en, this message translates to:
  /// **'Some phones have their own setting as well - see the phone\'s battery steps.'**
  String get busBatteryOwnSetting;

  /// Button to the battery steps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get busSteps;

  /// Trip check card heading.
  ///
  /// In en, this message translates to:
  /// **'Last trip'**
  String get busLastTrip;

  /// Trip check row.
  ///
  /// In en, this message translates to:
  /// **'Positions taken'**
  String get busPositionsTaken;

  /// Trip check row.
  ///
  /// In en, this message translates to:
  /// **'Longest gap between positions'**
  String get busLongestGap;

  /// Trip check row.
  ///
  /// In en, this message translates to:
  /// **'Sent to the school'**
  String get busSentToSchool;

  /// Trip check row.
  ///
  /// In en, this message translates to:
  /// **'Still waiting on this phone'**
  String get busStillWaiting;

  /// Trip check row.
  ///
  /// In en, this message translates to:
  /// **'Refused by the server'**
  String get busRefused;

  /// Trip check row.
  ///
  /// In en, this message translates to:
  /// **'Dropped after the trip ended'**
  String get busDroppedAfterEnd;

  /// Trip check row.
  ///
  /// In en, this message translates to:
  /// **'Times the app went to the background'**
  String get busBackgrounded;

  /// Trip check verdict.
  ///
  /// In en, this message translates to:
  /// **'A gap of {gap} from {time}: the phone most likely paused the app. Follow the battery steps for this phone and run a trip again.'**
  String busGapVerdict(String gap, String time);

  /// Trip check verdict.
  ///
  /// In en, this message translates to:
  /// **'No long gaps: the phone kept sharing the whole way.'**
  String get busNoGapVerdict;

  /// Why sharing stopped; reason is a log detail.
  ///
  /// In en, this message translates to:
  /// **'Sharing stopped: {reason}'**
  String busSharingStopped(String reason);

  /// Heading of the language setting in a phone app's profile.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// Follow the phone's own language setting (Hindi when the phone is in Hindi, else English).
  ///
  /// In en, this message translates to:
  /// **'Phone\'s language'**
  String get languagePhone;

  /// The English option, always written in English.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// The Hindi option, always written in Hindi.
  ///
  /// In en, this message translates to:
  /// **'हिन्दी'**
  String get languageHindi;

  /// Confirmation after picking a language.
  ///
  /// In en, this message translates to:
  /// **'Language changed.'**
  String get languageChanged;

  /// Closes a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Button that tries a failed load again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// The phone could not reach the server.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection and try again.'**
  String get errorNoConnection;

  /// The server was reached but slow.
  ///
  /// In en, this message translates to:
  /// **'The server is taking longer than usual to answer. Try again in a moment.'**
  String get errorTimeout;

  /// An unexpected failure with nothing more to say.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorUnknown;

  /// Confirm before signing out.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get coreLogOutTitle;

  /// What signing out means.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again to get back to your school.'**
  String get coreLogOutMessage;

  /// A bus attendant has trip marks still on the phone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mark has not been sent yet. Sign out anyway? They will be lost.} other{{count} marks have not been sent yet. Sign out anyway? They will be lost.}}'**
  String coreLogOutUnsent(int count);

  /// Sign out button.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get coreLogOut;

  /// Keep the session.
  ///
  /// In en, this message translates to:
  /// **'Stay signed in'**
  String get coreStaySignedIn;

  /// The app lock screen.
  ///
  /// In en, this message translates to:
  /// **'School365ai is locked'**
  String get coreLockedTitle;

  /// How to unlock.
  ///
  /// In en, this message translates to:
  /// **'Use your fingerprint, face or phone\'s screen lock to open it.'**
  String get coreLockedHint;

  /// The phone did not confirm the owner.
  ///
  /// In en, this message translates to:
  /// **'Not unlocked. Try again.'**
  String get coreNotUnlocked;

  /// Unlock button.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get coreUnlock;

  /// Offer to turn the app lock on.
  ///
  /// In en, this message translates to:
  /// **'Lock the app with your fingerprint?'**
  String get coreLockOfferTitle;

  /// What the app lock does.
  ///
  /// In en, this message translates to:
  /// **'Anyone who picks up this phone would need your fingerprint, face or screen lock to open School365ai. You can change this later.'**
  String get coreLockOfferBody;

  /// Decline the offer.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get coreNotNow;

  /// Accept the offer.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get coreTurnOn;

  /// The app lock switch in the profile.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get coreAppLock;

  /// What the switch does.
  ///
  /// In en, this message translates to:
  /// **'Ask for your fingerprint, face or screen lock when the app opens, and after 5 minutes away'**
  String get coreAppLockHint;

  /// No description provided for @coreShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get coreShowPassword;

  /// No description provided for @coreHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get coreHidePassword;

  /// Passcode length rule.
  ///
  /// In en, this message translates to:
  /// **'The passcode must be exactly {length} digits.'**
  String corePasscodeDigits(int length);

  /// No description provided for @corePasscodeRepeated.
  ///
  /// In en, this message translates to:
  /// **'Choose a passcode that is not one digit repeated.'**
  String get corePasscodeRepeated;

  /// No 1234 or 123456.
  ///
  /// In en, this message translates to:
  /// **'Choose a passcode that is not a straight run like {example}.'**
  String corePasscodeRun(String example);

  /// Attendance mark: in school.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get familyMarkPresent;

  /// Attendance mark, or a test missed.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get familyMarkAbsent;

  /// Attendance mark: on leave.
  ///
  /// In en, this message translates to:
  /// **'On leave'**
  String get familyMarkLeave;

  /// Attendance not yet taken.
  ///
  /// In en, this message translates to:
  /// **'Not marked yet'**
  String get familyMarkNotMarked;

  /// Instalment status.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get familyFeeStatusPaid;

  /// Instalment status: partly paid.
  ///
  /// In en, this message translates to:
  /// **'Part paid'**
  String get familyFeeStatusPartPaid;

  /// Instalment status.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get familyFeeStatusDue;

  /// Instalment status: past its date.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get familyFeeStatusOverdue;

  /// Instalment status: the school let it off.
  ///
  /// In en, this message translates to:
  /// **'Waived'**
  String get familyFeeStatusWaived;

  /// How a receipt was paid.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get familyPayModeCash;

  /// How a receipt was paid.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get familyPayModeBankTransfer;

  /// How a receipt was paid.
  ///
  /// In en, this message translates to:
  /// **'Cheque'**
  String get familyPayModeCheque;

  /// How a receipt was paid.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get familyPayModeCard;

  /// How a receipt was paid.
  ///
  /// In en, this message translates to:
  /// **'Online transfer'**
  String get familyPayModeOnlineTransfer;

  /// A guardian request the school approved.
  ///
  /// In en, this message translates to:
  /// **'Approved - the school will give them a set-up letter'**
  String get familyInviteApproved;

  /// A guardian request the school declined.
  ///
  /// In en, this message translates to:
  /// **'Declined by the school'**
  String get familyInviteDeclined;

  /// A guardian request not yet answered.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the school'**
  String get familyInviteWaiting;

  /// Guardian relationship.
  ///
  /// In en, this message translates to:
  /// **'Mother'**
  String get familyRelationMother;

  /// Guardian relationship.
  ///
  /// In en, this message translates to:
  /// **'Father'**
  String get familyRelationFather;

  /// Guardian relationship.
  ///
  /// In en, this message translates to:
  /// **'Guardian'**
  String get familyRelationGuardian;

  /// Guardian relationship.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get familyRelationOther;

  /// Bus trip summary.
  ///
  /// In en, this message translates to:
  /// **'Trip cancelled'**
  String get familyTripCancelled;

  /// Bus trip summary: the morning trip got the child to school.
  ///
  /// In en, this message translates to:
  /// **'Reached school'**
  String get familyTripReachedSchool;

  /// Bus trip summary.
  ///
  /// In en, this message translates to:
  /// **'Trip ended'**
  String get familyTripEnded;

  /// Bus trip summary.
  ///
  /// In en, this message translates to:
  /// **'On the bus to school'**
  String get familyTripOnBusToSchool;

  /// Bus trip summary.
  ///
  /// In en, this message translates to:
  /// **'On the bus home'**
  String get familyTripOnBusHome;

  /// Bus trip summary.
  ///
  /// In en, this message translates to:
  /// **'Dropped at the stop'**
  String get familyTripDroppedAtStop;

  /// Bus trip summary: child marked absent on the bus.
  ///
  /// In en, this message translates to:
  /// **'Did not take the bus'**
  String get familyTripNotTaken;

  /// Bus trip summary.
  ///
  /// In en, this message translates to:
  /// **'Bus on its way'**
  String get familyTripOnItsWay;

  /// Who marked a bus moment; who = name (role).
  ///
  /// In en, this message translates to:
  /// **'Marked by {who}'**
  String familyMarkedBy(String who);

  /// Who marked a bus moment, and at which stop.
  ///
  /// In en, this message translates to:
  /// **'Marked by {who} at {stop}'**
  String familyMarkedByAt(String who, String stop);

  /// Kind of a school message with no title.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get familyKindAttendance;

  /// Kind of a school message with no title.
  ///
  /// In en, this message translates to:
  /// **'School bus'**
  String get familyKindBus;

  /// Kind of a school message with no title.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get familyKindFees;

  /// Kind of a school message with no title.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get familyKindResults;

  /// Kind of a school message with no title.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get familyKindEmergency;

  /// Kind of a school message with no title.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get familyKindNotice;

  /// Kind of a school message with no title.
  ///
  /// In en, this message translates to:
  /// **'Message from school'**
  String get familyKindMessage;

  /// Bottom tab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get familyTabHome;

  /// Bottom tab.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get familyTabAttendance;

  /// Bottom tab.
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get familyTabBus;

  /// Bottom tab.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get familyTabFees;

  /// Bottom tab: everything else.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get familyTabMore;

  /// Bell tooltip with unread notices.
  ///
  /// In en, this message translates to:
  /// **'{count} new notices'**
  String familyNewNoticesCount(int count);

  /// Bell tooltip; the notices screen.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get familyNotices;

  /// How many children the parent has (shown only when more than one).
  ///
  /// In en, this message translates to:
  /// **'{count} children'**
  String familyChildrenCount(int count);

  /// Opens the list of children.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get familySwitch;

  /// Heading of the child picker.
  ///
  /// In en, this message translates to:
  /// **'Whose day?'**
  String get familyWhoseDay;

  /// Error heading when offline.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get familyNoConnection;

  /// Error heading.
  ///
  /// In en, this message translates to:
  /// **'Could not load this'**
  String get familyCouldNotLoad;

  /// Retry button.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get familyTryAgain;

  /// Opens the explanation of a figure.
  ///
  /// In en, this message translates to:
  /// **'How is this worked out?'**
  String get familyHowWorkedOut;

  /// Above a screen showing the copy saved on the phone; when = time or date and time.
  ///
  /// In en, this message translates to:
  /// **'No connection. Showing what was true at {when}.'**
  String familyShowingSavedAt(String when);

  /// Home with no linked child.
  ///
  /// In en, this message translates to:
  /// **'No children to show'**
  String get familyNoChildrenTitle;

  /// Home with no linked child.
  ///
  /// In en, this message translates to:
  /// **'The school has no child linked to your number at the moment. Please contact the school office.'**
  String get familyNoChildrenMessage;

  /// Greeting before noon.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get familyGoodMorning;

  /// Greeting in the afternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get familyGoodAfternoon;

  /// Greeting in the evening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get familyGoodEvening;

  /// When the screen was last refreshed.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String familyUpdatedAt(String time);

  /// Home on a closed day.
  ///
  /// In en, this message translates to:
  /// **'No school today'**
  String get familyNoSchoolToday;

  /// Home on a closed day with no holiday name.
  ///
  /// In en, this message translates to:
  /// **'The school is closed today.'**
  String get familySchoolClosedToday;

  /// Attendance card; name = child's first name.
  ///
  /// In en, this message translates to:
  /// **'{name} is in school'**
  String familyChildInSchool(String name);

  /// Attendance card.
  ///
  /// In en, this message translates to:
  /// **'{name} was marked absent'**
  String familyChildMarkedAbsent(String name);

  /// Attendance card.
  ///
  /// In en, this message translates to:
  /// **'{name} is on leave today'**
  String familyChildOnLeave(String name);

  /// Attendance card.
  ///
  /// In en, this message translates to:
  /// **'Register not marked yet'**
  String get familyRegisterNotMarked;

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'Attendance today'**
  String get familyAttendanceToday;

  /// Under 'Register not marked yet'.
  ///
  /// In en, this message translates to:
  /// **'The class teacher marks it in the morning.'**
  String get familyTeacherMarksMorning;

  /// A remark the teacher wrote.
  ///
  /// In en, this message translates to:
  /// **'Note: {text}'**
  String familyNote(String text);

  /// Opens the absence note form after an absence.
  ///
  /// In en, this message translates to:
  /// **'Tell the school why'**
  String get familyTellSchoolWhy;

  /// Opens the absence note form.
  ///
  /// In en, this message translates to:
  /// **'Report sick'**
  String get familyReportSick;

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'School bus'**
  String get familySchoolBus;

  /// Bus card with no trip.
  ///
  /// In en, this message translates to:
  /// **'No trip has started today'**
  String get familyNoTripToday;

  /// Bus pick-up time.
  ///
  /// In en, this message translates to:
  /// **'pick-up {time}'**
  String familyPickupAt(String time);

  /// Bus card while the bus is live.
  ///
  /// In en, this message translates to:
  /// **'Tap to watch the bus on the map'**
  String get familyTapToWatchBus;

  /// Results heading.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get familyResults;

  /// Results card on Home.
  ///
  /// In en, this message translates to:
  /// **'Test marks and the progress report'**
  String get familyResultsCardLine;

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'Next fee'**
  String get familyNextFee;

  /// Overdue fee; label = fee name as the school wrote it.
  ///
  /// In en, this message translates to:
  /// **'{label} · was due on {date}'**
  String familyFeeWasDueOn(String label, String date);

  /// Upcoming fee.
  ///
  /// In en, this message translates to:
  /// **'{label} · due on {date}'**
  String familyFeeDueOn(String label, String date);

  /// Card heading for the newest message.
  ///
  /// In en, this message translates to:
  /// **'From the school'**
  String get familyFromTheSchool;

  /// Unread badge.
  ///
  /// In en, this message translates to:
  /// **'{count} new'**
  String familyNewCount(int count);

  /// No notices.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get familyNoMessagesYet;

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'Today\'s classes'**
  String get familyTodaysClasses;

  /// A period with no subject.
  ///
  /// In en, this message translates to:
  /// **'Period {number}'**
  String familyPeriodNumber(String number);

  /// The period on now.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get familyNow;

  /// Screen-reader label of the marks line.
  ///
  /// In en, this message translates to:
  /// **'Marks over {count} tests, from {first}% to {last}%, rising'**
  String familyTrendRisingLabel(int count, int first, int last);

  /// Screen-reader label of the marks line.
  ///
  /// In en, this message translates to:
  /// **'Marks over {count} tests, from {first}% to {last}%, falling'**
  String familyTrendFallingLabel(int count, int first, int last);

  /// Under the marks line.
  ///
  /// In en, this message translates to:
  /// **'{first}% to {last}% over {count} tests'**
  String familyTrendLine(int count, int first, int last);

  /// Button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get familyPreviousMonth;

  /// Button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get familyNextMonth;

  /// Early warning when attendance is below the school's line; name = child's first name.
  ///
  /// In en, this message translates to:
  /// **'Attendance is {rate}% over the last {days} school days, below the school\'s {line}% line. The class teacher can help if something is keeping {name} away.'**
  String familyBelowLine(String rate, String days, String line, String name);

  /// Opens the absence note form.
  ///
  /// In en, this message translates to:
  /// **'Tell the school about an absence'**
  String get familyTellAboutAbsence;

  /// Opens the absence notes already sent.
  ///
  /// In en, this message translates to:
  /// **'Notes sent'**
  String get familyNotesSent;

  /// Attendance for the whole year.
  ///
  /// In en, this message translates to:
  /// **'This school year'**
  String get familyThisSchoolYear;

  /// How the attendance percentage is worked out.
  ///
  /// In en, this message translates to:
  /// **'Days present out of the days the class register was marked. A day on leave counts as not present; a day the school did not mark the register, and a holiday, are left out.'**
  String get familyWhyAttendance;

  /// Rate card with no marked days.
  ///
  /// In en, this message translates to:
  /// **'No register marked yet.'**
  String get familyNoRegisterYet;

  /// Rate card.
  ///
  /// In en, this message translates to:
  /// **'Present {present} of {days} days'**
  String familyPresentOfDays(String present, String days);

  /// Added after the present count.
  ///
  /// In en, this message translates to:
  /// **' · absent {count}'**
  String familyAbsentPart(int count);

  /// Added after the present count.
  ///
  /// In en, this message translates to:
  /// **' · leave {count}'**
  String familyLeavePart(int count);

  /// School days with no register.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 school day not marked by the school} other{{count} school days not marked by the school}}'**
  String familyDaysNotMarked(int count);

  /// Calendar column heads, Monday first, separated by single spaces (keep seven).
  ///
  /// In en, this message translates to:
  /// **'M T W T F S S'**
  String get familyWeekdayInitials;

  /// Calendar key / missed day kind.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get familyLeave;

  /// Calendar key: a school holiday.
  ///
  /// In en, this message translates to:
  /// **'Holiday'**
  String get familyHoliday;

  /// Screen-reader word for a calendar day.
  ///
  /// In en, this message translates to:
  /// **'present'**
  String get familyDayPresent;

  /// Screen-reader word for a calendar day.
  ///
  /// In en, this message translates to:
  /// **'absent'**
  String get familyDayAbsent;

  /// Screen-reader word for a calendar day.
  ///
  /// In en, this message translates to:
  /// **'on leave'**
  String get familyDayOnLeave;

  /// Screen-reader word for a calendar day.
  ///
  /// In en, this message translates to:
  /// **'holiday'**
  String get familyDayHoliday;

  /// Screen-reader word for a calendar day.
  ///
  /// In en, this message translates to:
  /// **'no school'**
  String get familyDayNoSchool;

  /// Screen-reader word for a calendar day.
  ///
  /// In en, this message translates to:
  /// **'not marked'**
  String get familyDayNotMarked;

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'Days missed'**
  String get familyDaysMissed;

  /// No missed days.
  ///
  /// In en, this message translates to:
  /// **'None this month.'**
  String get familyNoneThisMonth;

  /// A missed day with no note.
  ///
  /// In en, this message translates to:
  /// **'No reason noted.'**
  String get familyNoReasonNoted;

  /// Bus tab when the child has no route.
  ///
  /// In en, this message translates to:
  /// **'Not on a school bus'**
  String get familyNotOnBus;

  /// Bus tab when the child has no route.
  ///
  /// In en, this message translates to:
  /// **'If your child should be, the school office can add them to a route.'**
  String get familyNotOnBusMessage;

  /// Live trip card.
  ///
  /// In en, this message translates to:
  /// **'The bus is on its way to school'**
  String get familyBusOnWayToSchool;

  /// Live trip card.
  ///
  /// In en, this message translates to:
  /// **'The bus is on its way home'**
  String get familyBusOnWayHome;

  /// Live trip card.
  ///
  /// In en, this message translates to:
  /// **'Track it on the map'**
  String get familyTrackOnMap;

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'Route and stop'**
  String get familyRouteAndStop;

  /// Pick-up time label.
  ///
  /// In en, this message translates to:
  /// **'Pick-up'**
  String get familyPickup;

  /// Drop time label.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get familyDrop;

  /// Stands in for a stop with no name.
  ///
  /// In en, this message translates to:
  /// **'your stop'**
  String get familyYourStop;

  /// A trip not yet started.
  ///
  /// In en, this message translates to:
  /// **'Not started yet'**
  String get familyNotStartedYet;

  /// A cancelled trip.
  ///
  /// In en, this message translates to:
  /// **'This trip was cancelled. The school will be in touch.'**
  String get familyTripWasCancelled;

  /// Child not on the trip's rider list.
  ///
  /// In en, this message translates to:
  /// **'{name} is not on this trip\'s list today.'**
  String familyNotOnTripList(String name);

  /// Trip step.
  ///
  /// In en, this message translates to:
  /// **'The bus set off'**
  String get familyBusSetOff;

  /// Trip step: the bus reached a stop; stop = stop name.
  ///
  /// In en, this message translates to:
  /// **'Reached {stop}'**
  String familyReachedStop(String stop);

  /// Trip step.
  ///
  /// In en, this message translates to:
  /// **'The bus left school'**
  String get familyBusLeftSchool;

  /// Trip step.
  ///
  /// In en, this message translates to:
  /// **'{name} got off'**
  String familyChildGotOff(String name);

  /// Trip step.
  ///
  /// In en, this message translates to:
  /// **'{name} boarded'**
  String familyChildBoarded(String name);

  /// Trip step when the child was marked absent.
  ///
  /// In en, this message translates to:
  /// **'Did not board'**
  String get familyDidNotBoard;

  /// Heading of the trip home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get familyTripHome;

  /// Heading of the trip to school.
  ///
  /// In en, this message translates to:
  /// **'To school'**
  String get familyTripToSchool;

  /// Button tooltip: phone someone.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get familyCall;

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'Questions about the bus'**
  String get familyBusQuestions;

  /// Who to call.
  ///
  /// In en, this message translates to:
  /// **'Bus attendant'**
  String get familyBusAttendant;

  /// Who to call.
  ///
  /// In en, this message translates to:
  /// **'Transport office'**
  String get familyTransportOffice;

  /// Who to call.
  ///
  /// In en, this message translates to:
  /// **'The school office'**
  String get familySchoolOffice;

  /// Stands in for the child's name.
  ///
  /// In en, this message translates to:
  /// **'your child'**
  String get familyYourChild;

  /// Live map when no trip is on the road.
  ///
  /// In en, this message translates to:
  /// **'The bus isn\'t on the road for {name} now'**
  String familyBusNotOnRoadFor(String name);

  /// Live map when no trip is on the road.
  ///
  /// In en, this message translates to:
  /// **'You can follow it during their trip - on the way to school or home.'**
  String get familyBusFollowDuringTrip;

  /// Live map title.
  ///
  /// In en, this message translates to:
  /// **'Where is the bus?'**
  String get familyWhereIsBus;

  /// Map marker title.
  ///
  /// In en, this message translates to:
  /// **'The bus'**
  String get familyTheBus;

  /// Live map headline.
  ///
  /// In en, this message translates to:
  /// **'The bus is on the road'**
  String get familyBusOnRoad;

  /// Live map headline, morning trip after the stop.
  ///
  /// In en, this message translates to:
  /// **'The bus has been to {stop}'**
  String familyBusHasBeenTo(String stop);

  /// Live map headline, trip home at the stop.
  ///
  /// In en, this message translates to:
  /// **'The bus has reached {stop}'**
  String familyBusHasReached(String stop);

  /// Live map headline.
  ///
  /// In en, this message translates to:
  /// **'On its way to {stop}'**
  String familyOnWayTo(String stop);

  /// How long until the bus arrives.
  ///
  /// In en, this message translates to:
  /// **'about {time}'**
  String familyAboutTime(String time);

  /// How far the bus is; distance like '450 m'.
  ///
  /// In en, this message translates to:
  /// **'{distance} away'**
  String familyDistanceAway(String distance);

  /// Stops the bus makes before the child's.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop before yours} other{{count} stops before yours}}'**
  String familyStopsBeforeYours(int count);

  /// A span of minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String familyMinutes(int count);

  /// Live map before a position.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the bus to share where it is.'**
  String get familyWaitingForBusLocation;

  /// Live map with an old position.
  ///
  /// In en, this message translates to:
  /// **'Last seen {time} ago - the bus may be out of signal.'**
  String familyLastSeenAgo(String time);

  /// Live map when a refresh failed.
  ///
  /// In en, this message translates to:
  /// **'No connection - showing the last update.'**
  String get familyOfflineLastUpdate;

  /// Fees tab with no fees.
  ///
  /// In en, this message translates to:
  /// **'No fees set yet'**
  String get familyNoFeesYet;

  /// Fees tab with no fees.
  ///
  /// In en, this message translates to:
  /// **'When the school sets this year\'s fees, they appear here.'**
  String get familyNoFeesYetMessage;

  /// Section heading.
  ///
  /// In en, this message translates to:
  /// **'Instalments'**
  String get familyInstalments;

  /// Section heading.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get familyReceipts;

  /// No receipts.
  ///
  /// In en, this message translates to:
  /// **'No payments this year yet. A receipt appears here as soon as the office records one.'**
  String get familyNoReceiptsYet;

  /// Fees heading with no year name.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get familyThisYear;

  /// Fees heading; year = school year name.
  ///
  /// In en, this message translates to:
  /// **'Fees for {year}'**
  String familyFeesFor(String year);

  /// Nothing left to pay.
  ///
  /// In en, this message translates to:
  /// **'All paid'**
  String get familyAllPaid;

  /// Amount still to pay.
  ///
  /// In en, this message translates to:
  /// **'Left to pay'**
  String get familyLeftToPay;

  /// Part of the balance past its date.
  ///
  /// In en, this message translates to:
  /// **'{amount} of it is overdue'**
  String familyOfItOverdue(String amount);

  /// Total charged this year.
  ///
  /// In en, this message translates to:
  /// **'Charged'**
  String get familyCharged;

  /// Discount given.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get familyDiscount;

  /// Money the school holds for the family.
  ///
  /// In en, this message translates to:
  /// **'Credit held'**
  String get familyCreditHeld;

  /// How the balance is worked out.
  ///
  /// In en, this message translates to:
  /// **'Left to pay is this year\'s fees, less any discount, less what the school has recorded as paid, less any instalment the school has waived. Overdue is the part of it from instalments whose due date has passed.'**
  String get familyWhyFees;

  /// After a UPI app opened.
  ///
  /// In en, this message translates to:
  /// **'Once you have paid, the school records it and the receipt appears here.'**
  String get familyUpiOpened;

  /// When no UPI app opened.
  ///
  /// In en, this message translates to:
  /// **'No UPI app opened on this phone. Copy the UPI ID and pay from your bank\'s app instead.'**
  String get familyUpiNotOpened;

  /// After copying; what = 'UPI ID' or 'Bank details'.
  ///
  /// In en, this message translates to:
  /// **'{what} copied'**
  String familyCopied(String what);

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'How to pay'**
  String get familyHowToPay;

  /// How to pay.
  ///
  /// In en, this message translates to:
  /// **'Pay the school directly. This app shows your fees; it does not take payments.'**
  String get familyPaySchoolDirectly;

  /// UPI button.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount} with any UPI app'**
  String familyPayWithUpi(String amount);

  /// Under the UPI button.
  ///
  /// In en, this message translates to:
  /// **'Opens GPay, PhonePe, Paytm or your bank\'s app with the amount and your child\'s name filled in. The school records the payment when it reaches them.'**
  String get familyUpiExplain;

  /// Counter hours label.
  ///
  /// In en, this message translates to:
  /// **'Fee counter'**
  String get familyFeeCounter;

  /// Button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy the UPI ID'**
  String get familyCopyUpiId;

  /// What was copied.
  ///
  /// In en, this message translates to:
  /// **'UPI ID'**
  String get familyUpiId;

  /// Button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy the bank details'**
  String get familyCopyBankDetails;

  /// What was copied.
  ///
  /// In en, this message translates to:
  /// **'Bank details'**
  String get familyBankDetails;

  /// Office phone label.
  ///
  /// In en, this message translates to:
  /// **'Questions about fees'**
  String get familyFeeQuestions;

  /// Button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Call the school office'**
  String get familyCallSchoolOffice;

  /// Overdue instalment.
  ///
  /// In en, this message translates to:
  /// **'Was due {date}'**
  String familyWasDueDate(String date);

  /// Instalment due date.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String familyDueDate(String date);

  /// Part-paid instalment.
  ///
  /// In en, this message translates to:
  /// **'{paid} paid of {total}'**
  String familyPaidOf(String paid, String total);

  /// A cancelled receipt.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by the office'**
  String get familyCancelledByOffice;

  /// Button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Open the receipt'**
  String get familyOpenReceipt;

  /// Statement button with no year name.
  ///
  /// In en, this message translates to:
  /// **'The year\'s statement (PDF)'**
  String get familyYearStatement;

  /// Statement button.
  ///
  /// In en, this message translates to:
  /// **'Statement for {year} (PDF)'**
  String familyStatementFor(String year);

  /// Results with no terms.
  ///
  /// In en, this message translates to:
  /// **'No terms yet'**
  String get familyNoTermsYet;

  /// Results with no terms.
  ///
  /// In en, this message translates to:
  /// **'Results appear here once the school sets up its terms.'**
  String get familyNoTermsYetMessage;

  /// Card heading for the teacher's remark.
  ///
  /// In en, this message translates to:
  /// **'From the class teacher'**
  String get familyFromClassTeacher;

  /// Results with no tests.
  ///
  /// In en, this message translates to:
  /// **'No results yet this term'**
  String get familyNoResultsThisTerm;

  /// Results with no tests.
  ///
  /// In en, this message translates to:
  /// **'A test appears here once the teacher publishes its marks.'**
  String get familyNoResultsThisTermMessage;

  /// How subject figures are worked out.
  ///
  /// In en, this message translates to:
  /// **'Each subject\'s figure is the average of its published test marks this term, as percentages - weighted when the school gave every test a weight. A test the child missed is left out. The grade comes from the school\'s own grading scale.'**
  String get familyWhyResults;

  /// Report card row; term = term name.
  ///
  /// In en, this message translates to:
  /// **'{term} progress report'**
  String familyProgressReport(String term);

  /// When the report is ready.
  ///
  /// In en, this message translates to:
  /// **'Open it, save it or share it.'**
  String get familyReportOpenSaveShare;

  /// Report not yet ready.
  ///
  /// In en, this message translates to:
  /// **'Ready when the term ends.'**
  String get familyReportReadyTermEnds;

  /// Report not yet ready.
  ///
  /// In en, this message translates to:
  /// **'Ready when the term ends, on {date}.'**
  String familyReportReadyOn(String date);

  /// Download button.
  ///
  /// In en, this message translates to:
  /// **'Get PDF'**
  String get familyGetPdf;

  /// Tests in a subject.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 test} other{{count} tests}}'**
  String familyTestsCount(int count);

  /// The class average for a subject.
  ///
  /// In en, this message translates to:
  /// **'class {percent}%'**
  String familyClassPercent(String percent);

  /// A subject grade.
  ///
  /// In en, this message translates to:
  /// **'Grade {grade}'**
  String familyGrade(String grade);

  /// The class average for a test.
  ///
  /// In en, this message translates to:
  /// **'class average {percent}%'**
  String familyClassAverage(String percent);

  /// Screen title.
  ///
  /// In en, this message translates to:
  /// **'Timetable'**
  String get familyTimetable;

  /// Timetable empty.
  ///
  /// In en, this message translates to:
  /// **'No timetable yet'**
  String get familyNoTimetableYet;

  /// Timetable empty.
  ///
  /// In en, this message translates to:
  /// **'The class\'s timetable appears here once the school sets it.'**
  String get familyNoTimetableYetMessage;

  /// Day chip for today.
  ///
  /// In en, this message translates to:
  /// **'{day} · today'**
  String familyDayToday(String day);

  /// Short weekday name; day is the lower-case English day.
  ///
  /// In en, this message translates to:
  /// **'{day, select, monday{Mon} tuesday{Tue} wednesday{Wed} thursday{Thu} friday{Fri} saturday{Sat} sunday{Sun} other{{day}}}'**
  String familyWeekdayShort(String day);

  /// Weekday name; day is the lower-case English day.
  ///
  /// In en, this message translates to:
  /// **'{day, select, monday{Monday} tuesday{Tuesday} wednesday{Wednesday} thursday{Thursday} friday{Friday} saturday{Saturday} sunday{Sunday} other{{day}}}'**
  String familyWeekday(String day);

  /// A period with no subject.
  ///
  /// In en, this message translates to:
  /// **'Free period'**
  String get familyFreePeriod;

  /// Half day note.
  ///
  /// In en, this message translates to:
  /// **'{day} is a half day.'**
  String familyHalfDay(String day);

  /// A day with no periods.
  ///
  /// In en, this message translates to:
  /// **'No classes on {day}.'**
  String familyNoClassesOn(String day);

  /// Screen title.
  ///
  /// In en, this message translates to:
  /// **'Syllabus'**
  String get familySyllabus;

  /// Syllabus empty.
  ///
  /// In en, this message translates to:
  /// **'No syllabus yet'**
  String get familyNoSyllabusYet;

  /// Syllabus empty.
  ///
  /// In en, this message translates to:
  /// **'What the class will cover appears here once the school adds it.'**
  String get familyNoSyllabusYetMessage;

  /// Screen title; homework with no subject.
  ///
  /// In en, this message translates to:
  /// **'Homework'**
  String get familyHomework;

  /// Homework empty.
  ///
  /// In en, this message translates to:
  /// **'No homework in the last two weeks'**
  String get familyNoHomework;

  /// Homework empty.
  ///
  /// In en, this message translates to:
  /// **'When a teacher sets homework for the class, it appears here that day.'**
  String get familyNoHomeworkMessage;

  /// Homework day heading for today; date as the school wrote it.
  ///
  /// In en, this message translates to:
  /// **'Today - {date}'**
  String familyTodayDash(String date);

  /// Syllabus subject with no topics.
  ///
  /// In en, this message translates to:
  /// **'No topics added yet.'**
  String get familyNoTopicsYet;

  /// Syllabus progress.
  ///
  /// In en, this message translates to:
  /// **'{covered} of {total} topics covered'**
  String familyTopicsCovered(String covered, String total);

  /// Next topics.
  ///
  /// In en, this message translates to:
  /// **'Coming up: {topics}'**
  String familyComingUp(String topics);

  /// More row; screen title.
  ///
  /// In en, this message translates to:
  /// **'Absence notes'**
  String get familyAbsenceNotes;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'Tell the school your child will be away'**
  String get familyAbsenceNotesSub;

  /// More row; screen title.
  ///
  /// In en, this message translates to:
  /// **'Add a guardian'**
  String get familyAddGuardian;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'Ask the school to add the other parent, or a relative'**
  String get familyAddGuardianSub;

  /// More row; screen title.
  ///
  /// In en, this message translates to:
  /// **'Ask the school to call you'**
  String get familyAskToCall;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'The class teacher or the office rings you back'**
  String get familyAskToCallSub;

  /// More row; screen title.
  ///
  /// In en, this message translates to:
  /// **'Admit cards'**
  String get familyAdmitCards;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'Exam date sheets to download and print'**
  String get familyAdmitCardsSub;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'The class\'s week'**
  String get familyTimetableSub;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'How far each subject has got'**
  String get familySyllabusSub;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'What the teachers set, day by day'**
  String get familyHomeworkSub;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'Messages from the school'**
  String get familyNoticesSub;

  /// More row; screen title.
  ///
  /// In en, this message translates to:
  /// **'School calendar'**
  String get familySchoolCalendar;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'Holidays and closed days'**
  String get familySchoolCalendarSub;

  /// More row; screen title.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get familyNotifications;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'Choose what comes to this app'**
  String get familyNotificationsSub;

  /// More row; screen title.
  ///
  /// In en, this message translates to:
  /// **'Your privacy'**
  String get familyYourPrivacy;

  /// More row.
  ///
  /// In en, this message translates to:
  /// **'Who sees your number, and the bus on the map'**
  String get familyYourPrivacySub;

  /// Sign out row and button.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get familySignOut;

  /// Sign out row.
  ///
  /// In en, this message translates to:
  /// **'This phone stays set up; sign in again with your passcode'**
  String get familySignOutSub;

  /// Confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get familySignOutQuestion;

  /// Confirm dialog.
  ///
  /// In en, this message translates to:
  /// **'You will need your passcode to sign in again.'**
  String get familySignOutMessage;

  /// When the dialler, WhatsApp or mail did not open.
  ///
  /// In en, this message translates to:
  /// **'This phone could not open that. Please try another way.'**
  String get familyCouldNotOpen;

  /// Card heading.
  ///
  /// In en, this message translates to:
  /// **'Contact the school'**
  String get familyContactSchool;

  /// No school phone or email.
  ///
  /// In en, this message translates to:
  /// **'The school has not added its contact details yet.'**
  String get familyNoContactDetails;

  /// Button: write to the school.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get familyEmail;

  /// Notices action.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get familyMarkAllRead;

  /// Notices empty.
  ///
  /// In en, this message translates to:
  /// **'No notices yet'**
  String get familyNoNoticesYet;

  /// Notices empty.
  ///
  /// In en, this message translates to:
  /// **'Messages from the school will appear here.'**
  String get familyNoNoticesYetMessage;

  /// Attachments on a notice.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String familyFilesCount(int count);

  /// Name of the calendar file added to the phone's calendar.
  ///
  /// In en, this message translates to:
  /// **'School holidays'**
  String get familyHolidaysCalendarName;

  /// Error snackbar.
  ///
  /// In en, this message translates to:
  /// **'The calendar file could not be shared.'**
  String get familyCalendarShareFailed;

  /// Holiday list heading.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get familyThisMonth;

  /// Holiday list empty.
  ///
  /// In en, this message translates to:
  /// **'No holidays this month.'**
  String get familyNoHolidaysThisMonth;

  /// Weekly closed days; days = weekday names joined.
  ///
  /// In en, this message translates to:
  /// **'The school is closed every {days}.'**
  String familyClosedEvery(String days);

  /// Joins weekday names: 'Saturday and Sunday'.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get familyAndJoin;

  /// Holiday list heading.
  ///
  /// In en, this message translates to:
  /// **'Coming up'**
  String get familyHolidaysComingUp;

  /// Holiday list empty.
  ///
  /// In en, this message translates to:
  /// **'No holidays planned yet.'**
  String get familyNoHolidaysPlanned;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Add these holidays to my calendar'**
  String get familyAddHolidaysToCalendar;

  /// Notification switch.
  ///
  /// In en, this message translates to:
  /// **'Absent, or on leave'**
  String get familySwitchAttendanceSub;

  /// Notification switch.
  ///
  /// In en, this message translates to:
  /// **'Boarded, dropped, did not take the bus'**
  String get familySwitchBusSub;

  /// Notification switch.
  ///
  /// In en, this message translates to:
  /// **'Reminders and receipts'**
  String get familySwitchFeesSub;

  /// Notification switch.
  ///
  /// In en, this message translates to:
  /// **'When a test result is published'**
  String get familySwitchResultsSub;

  /// Notification switch.
  ///
  /// In en, this message translates to:
  /// **'Announcements and messages from the school'**
  String get familySwitchNoticesSub;

  /// Notification switch.
  ///
  /// In en, this message translates to:
  /// **'Each evening, the day\'s homework'**
  String get familySwitchHomeworkSub;

  /// Notifications screen.
  ///
  /// In en, this message translates to:
  /// **'Emergency messages from the school always come through.'**
  String get familyEmergencyAlwaysComes;

  /// After saving a setting.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get familySaved;

  /// After asking for a call.
  ///
  /// In en, this message translates to:
  /// **'Sent. The school office will call you.'**
  String get familyCallSentOffice;

  /// After asking for a call.
  ///
  /// In en, this message translates to:
  /// **'Sent. The class teacher will call you.'**
  String get familyCallSentTeacher;

  /// Call request form; name = child's first name.
  ///
  /// In en, this message translates to:
  /// **'Who should call you about {name}?'**
  String familyWhoShouldCall(String name);

  /// Who calls back.
  ///
  /// In en, this message translates to:
  /// **'Class teacher'**
  String get familyClassTeacher;

  /// Who calls back.
  ///
  /// In en, this message translates to:
  /// **'School office'**
  String get familySchoolOfficeShort;

  /// Call reason field.
  ///
  /// In en, this message translates to:
  /// **'What is it about?'**
  String get familyWhatAbout;

  /// Call reason too short.
  ///
  /// In en, this message translates to:
  /// **'Please say a little about what it is.'**
  String get familyWhatAboutTooShort;

  /// Optional field.
  ///
  /// In en, this message translates to:
  /// **'A good time to call (optional)'**
  String get familyGoodTimeToCall;

  /// Hint in the time field.
  ///
  /// In en, this message translates to:
  /// **'e.g. After 5 pm'**
  String get familyGoodTimeHint;

  /// Send button.
  ///
  /// In en, this message translates to:
  /// **'Ask for a call'**
  String get familyAskForCall;

  /// Section heading.
  ///
  /// In en, this message translates to:
  /// **'Your requests'**
  String get familyYourRequests;

  /// An empty list.
  ///
  /// In en, this message translates to:
  /// **'None yet.'**
  String get familyNoneYet;

  /// A call request marked done.
  ///
  /// In en, this message translates to:
  /// **'Called by {who} · {when}'**
  String familyCalledBy(String who, String when);

  /// Who called, when the school gave no name.
  ///
  /// In en, this message translates to:
  /// **'the school'**
  String get familyTheSchool;

  /// Call request status.
  ///
  /// In en, this message translates to:
  /// **'Called'**
  String get familyCalled;

  /// Call request status.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get familyWaiting;

  /// Reply deadline.
  ///
  /// In en, this message translates to:
  /// **'Please answer by {date}'**
  String familyAnswerBy(String date);

  /// Reply deadline passed.
  ///
  /// In en, this message translates to:
  /// **'Answers closed on {date}'**
  String familyAnswersClosedOn(String date);

  /// Answer.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get familyYes;

  /// Answer.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get familyNo;

  /// After answering.
  ///
  /// In en, this message translates to:
  /// **'Your answer reached the school · {when}'**
  String familyAnswerReached(String when);

  /// Optional note field.
  ///
  /// In en, this message translates to:
  /// **'A note for the school (optional)'**
  String get familyNoteForSchool;

  /// Badge on a notice waiting for an answer.
  ///
  /// In en, this message translates to:
  /// **'Answer needed'**
  String get familyAnswerNeeded;

  /// Screen title; name = child's first name.
  ///
  /// In en, this message translates to:
  /// **'Absence notes for {name}'**
  String familyAbsenceNotesFor(String name);

  /// Button: write a new absence note.
  ///
  /// In en, this message translates to:
  /// **'Tell the school'**
  String get familyTellTheSchool;

  /// Absence notes empty.
  ///
  /// In en, this message translates to:
  /// **'No notes sent'**
  String get familyNoNotesSent;

  /// Absence notes empty.
  ///
  /// In en, this message translates to:
  /// **'If {name} will be away, tell the school here - the class teacher sees it.'**
  String familyNoNotesSentMessage(String name);

  /// Absence note status.
  ///
  /// In en, this message translates to:
  /// **'Seen'**
  String get familyNoteSeen;

  /// Absence note status.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get familyNoteSent;

  /// Who saw the note.
  ///
  /// In en, this message translates to:
  /// **'Seen by {who} · {when}'**
  String familySeenBy(String who, String when);

  /// Who saw the note, when no name was given.
  ///
  /// In en, this message translates to:
  /// **'the class teacher'**
  String get familyTheClassTeacher;

  /// Absence note with a photo.
  ///
  /// In en, this message translates to:
  /// **'With a photo of a note'**
  String get familyWithPhoto;

  /// Date picker title.
  ///
  /// In en, this message translates to:
  /// **'First day away'**
  String get familyFirstDayAway;

  /// Date picker title.
  ///
  /// In en, this message translates to:
  /// **'Last day away'**
  String get familyLastDayAway;

  /// Photo source.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get familyTakePhoto;

  /// Photo source.
  ///
  /// In en, this message translates to:
  /// **'Choose from your photos'**
  String get familyChoosePhoto;

  /// After sending an absence note.
  ///
  /// In en, this message translates to:
  /// **'Sent. {name}\'s class teacher will see it.'**
  String familyNoteSentSnack(String name);

  /// Form title with no child name.
  ///
  /// In en, this message translates to:
  /// **'Your child will be away'**
  String get familyYourChildWillBeAway;

  /// Form title.
  ///
  /// In en, this message translates to:
  /// **'{name} will be away'**
  String familyChildWillBeAway(String name);

  /// Absence note form.
  ///
  /// In en, this message translates to:
  /// **'The class teacher sees this on the register. It doesn\'t mark {name} absent by itself.'**
  String familyNoteExplain(String name);

  /// Date field.
  ///
  /// In en, this message translates to:
  /// **'First day'**
  String get familyFirstDay;

  /// Date field.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get familyLastDay;

  /// Reason field.
  ///
  /// In en, this message translates to:
  /// **'Why will they be away?'**
  String get familyWhyAway;

  /// Reason hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Fever since last night - the doctor has advised two days\' rest.'**
  String get familyWhyAwayHint;

  /// Reason too short.
  ///
  /// In en, this message translates to:
  /// **'Please write a little more - at least {min} characters.'**
  String familyReasonTooShort(int min);

  /// Send button.
  ///
  /// In en, this message translates to:
  /// **'Send to the school'**
  String get familySendToSchool;

  /// Photo button.
  ///
  /// In en, this message translates to:
  /// **'Add a photo of a doctor\'s note (optional)'**
  String get familyAddDoctorNote;

  /// Remove the chosen photo.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get familyRemove;

  /// Sign-in on a phone with no registration.
  ///
  /// In en, this message translates to:
  /// **'This phone is not registered yet. Enter the setup code from your school\'s letter.'**
  String get familyDeviceNotRegistered;

  /// Link and dialog title.
  ///
  /// In en, this message translates to:
  /// **'Forgot your passcode?'**
  String get familyForgotPasscode;

  /// Forgot passcode dialog.
  ///
  /// In en, this message translates to:
  /// **'Ask your child\'s school office for a new Family app letter. It has a new setup code: enter it here with your mobile number, and choose a new passcode. Your phone stays the same.'**
  String get familyForgotPasscodeHelp;

  /// Closes a dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get familyClose;

  /// Forgot passcode dialog.
  ///
  /// In en, this message translates to:
  /// **'I have a new code'**
  String get familyHaveNewCode;

  /// Sign-in heading on a new phone.
  ///
  /// In en, this message translates to:
  /// **'Set up the Family app'**
  String get familySetUpApp;

  /// Sign-in heading.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get familyWelcomeBack;

  /// Set-up help.
  ///
  /// In en, this message translates to:
  /// **'Use the letter from your child\'s school: your mobile number, the 8-digit setup code, and a 6-digit passcode you choose.'**
  String get familySetUpHelp;

  /// Sign-in help.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your mobile number and your 6-digit passcode.'**
  String get familySignInHelp;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get familyMobileNumber;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Setup code from the letter'**
  String get familySetupCodeLabel;

  /// Setup code validation.
  ///
  /// In en, this message translates to:
  /// **'Enter the 8-digit setup code from the school\'s letter.'**
  String get familySetupCodeInvalid;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Choose a passcode'**
  String get familyChoosePasscode;

  /// Confirm passcode field.
  ///
  /// In en, this message translates to:
  /// **'Type it again'**
  String get familyTypeItAgain;

  /// Passcode confirmation validation.
  ///
  /// In en, this message translates to:
  /// **'The two passcodes are not the same.'**
  String get familyPasscodesDiffer;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Passcode'**
  String get familyPasscode;

  /// Passcode validation.
  ///
  /// In en, this message translates to:
  /// **'Enter your 6-digit passcode.'**
  String get familyPasscodeInvalid;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Set up and sign in'**
  String get familySetUpAndSignIn;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get familySignIn;

  /// Link to the set-up form.
  ///
  /// In en, this message translates to:
  /// **'New phone, or a new letter? Use the setup code'**
  String get familyUseSetupCode;

  /// Link to the sign-in form.
  ///
  /// In en, this message translates to:
  /// **'Already set up on this phone? Sign in'**
  String get familyAlreadySetUp;

  /// Under the sign-in form.
  ///
  /// In en, this message translates to:
  /// **'No letter? Ask your child\'s school office for the Family app setup code.'**
  String get familyNoLetter;

  /// Admit cards empty.
  ///
  /// In en, this message translates to:
  /// **'No admit cards yet'**
  String get familyNoAdmitCards;

  /// Admit cards empty.
  ///
  /// In en, this message translates to:
  /// **'When the school publishes an exam your child sits, its admit card appears here.'**
  String get familyNoAdmitCardsMessage;

  /// Note in the phone's calendar entry for an exam paper.
  ///
  /// In en, this message translates to:
  /// **'Reporting time {time}.'**
  String familyReportingTime(String time);

  /// Admit card version line.
  ///
  /// In en, this message translates to:
  /// **'Version {version}, issued {date}'**
  String familyAdmitVersion(String version, String date);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Download admit card'**
  String get familyDownloadAdmitCard;

  /// Button: exam papers into the phone's calendar.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Add 1 paper to calendar} other{Add {count} papers to calendar}}'**
  String familyAddPapersToCalendar(int count);

  /// After asking for a guardian.
  ///
  /// In en, this message translates to:
  /// **'Sent. The school will look at your request.'**
  String get familyGuardianSent;

  /// Add a guardian form.
  ///
  /// In en, this message translates to:
  /// **'Ask the school to add another guardian of {name}. Once the school agrees, it gives them their own set-up letter, and they see what you see.'**
  String familyGuardianExplain(String name);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Their full name'**
  String get familyTheirFullName;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Enter their name.'**
  String get familyEnterTheirName;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Their mobile number'**
  String get familyTheirMobile;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'How they are related to {name}'**
  String familyHowRelated(String name);

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Choose how they are related.'**
  String get familyChooseRelation;

  /// Send button.
  ///
  /// In en, this message translates to:
  /// **'Ask the school'**
  String get familyAskTheSchool;

  /// Privacy card heading.
  ///
  /// In en, this message translates to:
  /// **'Who can see your phone number'**
  String get familyPrivacyNumberTitle;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'The school office.'**
  String get familyPrivacyNumberOffice;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'Your child\'s own class teachers - not teachers of other classes.'**
  String get familyPrivacyNumberTeachers;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'Staff who take fees, so they can call about a payment.'**
  String get familyPrivacyNumberFees;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'If your child takes the school bus: the transport office, and the bus crew on your child\'s route, so they can call you from the road.'**
  String get familyPrivacyNumberBus;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'The school decides whether any other staff may see it.'**
  String get familyPrivacyNumberOthers;

  /// Privacy card heading.
  ///
  /// In en, this message translates to:
  /// **'The bus on the map'**
  String get familyPrivacyBusTitle;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'The location you see is the bus\'s, sent by the crew\'s phone while a trip runs.'**
  String get familyPrivacyBusSource;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'You can follow it only while your child\'s own trip is running - until they are dropped off or marked as not on the bus.'**
  String get familyPrivacyBusWhen;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'This app never asks for your phone\'s location.'**
  String get familyPrivacyBusNoPhoneLocation;

  /// Privacy card heading.
  ///
  /// In en, this message translates to:
  /// **'What comes to this app'**
  String get familyPrivacyMessagesTitle;

  /// Privacy line.
  ///
  /// In en, this message translates to:
  /// **'You choose which kinds of message the school sends to this app.'**
  String get familyPrivacyMessagesLine;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Choose notifications'**
  String get familyChooseNotifications;

  /// Snackbar action: opens the screen a push message is about.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get familyOpen;

  /// Family app: the meetings screen's title and its row on More (M12, 8.4).
  ///
  /// In en, this message translates to:
  /// **'Parent-teacher meetings'**
  String get familyMeetings;

  /// Subtitle of the meetings row on More.
  ///
  /// In en, this message translates to:
  /// **'Book a time with the class teacher'**
  String get familyMeetingsSub;

  /// Empty meetings screen title.
  ///
  /// In en, this message translates to:
  /// **'No meetings ahead'**
  String get familyNoMeetings;

  /// Empty meetings screen message.
  ///
  /// In en, this message translates to:
  /// **'When the school plans a parent-teacher meeting for this class, it will show here.'**
  String get familyNoMeetingsMessage;

  /// A meeting's date and who the parent meets.
  ///
  /// In en, this message translates to:
  /// **'{date} · with {teacher}'**
  String familyMeetingWith(String date, String teacher);

  /// Stands in for the teacher's name when none is set, mid-sentence.
  ///
  /// In en, this message translates to:
  /// **'the class teacher'**
  String get familyTheClassTeacherLower;

  /// The parent's booked meeting time, e.g. 9:20 AM - 9:30 AM.
  ///
  /// In en, this message translates to:
  /// **'Your time: {time}'**
  String familyYourTime(String time);

  /// A meeting with no slots yet.
  ///
  /// In en, this message translates to:
  /// **'The teacher has not opened times yet. You will get a message when they do.'**
  String get familyMeetingTimesNotOpen;

  /// Every slot is booked by others.
  ///
  /// In en, this message translates to:
  /// **'All times are taken. Please ask the school office.'**
  String get familyMeetingAllTaken;

  /// Booking closes at the end of the day before the meeting.
  ///
  /// In en, this message translates to:
  /// **'Booking has closed. To change anything, please call the school.'**
  String get familyMeetingClosed;

  /// Above the free slots when nothing is booked.
  ///
  /// In en, this message translates to:
  /// **'Pick a time'**
  String get familyPickATime;

  /// Above the slots when the parent already has a booking.
  ///
  /// In en, this message translates to:
  /// **'Or move to another time'**
  String get familyPickAnotherTime;

  /// Confirm dialog title for booking a slot.
  ///
  /// In en, this message translates to:
  /// **'Book {time}?'**
  String familyBookTimeQ(String time);

  /// Confirm dialog title for moving a booking.
  ///
  /// In en, this message translates to:
  /// **'Move to {time}?'**
  String familyMoveTimeQ(String time);

  /// Confirm dialog body for a booking.
  ///
  /// In en, this message translates to:
  /// **'{date}, with {teacher}, about {child}.'**
  String familyBookTimeBody(String date, String teacher, String child);

  /// Button: book the slot.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get familyBook;

  /// Button: move the booking to this slot.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get familyMove;

  /// Snackbar after booking.
  ///
  /// In en, this message translates to:
  /// **'Booked for {time}'**
  String familyBookedFor(String time);

  /// Button: cancel the parent's meeting booking.
  ///
  /// In en, this message translates to:
  /// **'Cancel booking'**
  String get familyCancelBooking;

  /// Confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Cancel this booking?'**
  String get familyCancelBookingQ;

  /// Confirm dialog body.
  ///
  /// In en, this message translates to:
  /// **'Your {time} time will be free for another parent.'**
  String familyCancelBookingBody(String time);

  /// Dialog button: keep the booking.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get familyKeepIt;

  /// Snackbar after cancelling.
  ///
  /// In en, this message translates to:
  /// **'Booking cancelled'**
  String get familyBookingCancelled;

  /// Screen-reader label of a slot someone else booked.
  ///
  /// In en, this message translates to:
  /// **'{time}, taken'**
  String familySlotTakenLabel(String time);

  /// Screen-reader label of the parent's own slot.
  ///
  /// In en, this message translates to:
  /// **'{time}, your time'**
  String familySlotYoursLabel(String time);

  /// Staff/web: the gallery screen's heading (M12, 8.6).
  ///
  /// In en, this message translates to:
  /// **'Events & photos'**
  String get galleryHeading;

  /// Intro line on the gallery screen.
  ///
  /// In en, this message translates to:
  /// **'Photos for parents in the Family app: the whole school\'s events, or one class\'s.'**
  String get galleryIntro;

  /// Empty gallery list.
  ///
  /// In en, this message translates to:
  /// **'No events posted yet.'**
  String get galleryNoEvents;

  /// Button and dialog title: post an event.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get galleryNewEvent;

  /// Dialog title: edit an event.
  ///
  /// In en, this message translates to:
  /// **'Change event'**
  String get galleryChangeEvent;

  /// Snackbar after posting an event.
  ///
  /// In en, this message translates to:
  /// **'Event posted. Now add its photos.'**
  String get galleryPosted;

  /// Snackbar after changing an event.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get gallerySaved;

  /// Form field: the event's name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get galleryTitleLabel;

  /// Hint for the event's name.
  ///
  /// In en, this message translates to:
  /// **'e.g. Annual Day'**
  String get galleryTitleHint;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Give the event a name.'**
  String get galleryTitleRequired;

  /// Form field: the event's date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get galleryDateLabel;

  /// Form field: the event's audience.
  ///
  /// In en, this message translates to:
  /// **'Who sees it'**
  String get galleryWhoSees;

  /// Audience: everyone.
  ///
  /// In en, this message translates to:
  /// **'Parents of the whole school'**
  String get galleryWholeSchool;

  /// Audience: one class.
  ///
  /// In en, this message translates to:
  /// **'Parents of {className}'**
  String galleryParentsOf(String className);

  /// Validation for a teacher.
  ///
  /// In en, this message translates to:
  /// **'Choose your class.'**
  String get galleryChooseClass;

  /// Helper when a teacher has no class.
  ///
  /// In en, this message translates to:
  /// **'You can post to a class you are the class teacher of. You have none yet.'**
  String get galleryNoClassOfYours;

  /// Form field: description.
  ///
  /// In en, this message translates to:
  /// **'A few words (optional)'**
  String get galleryDescriptionLabel;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get galleryPost;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get gallerySave;

  /// How many photos an event has.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no photos} =1{1 photo} other{{count} photos}}'**
  String galleryPhotoCount(int count);

  /// Under an event with no photos.
  ///
  /// In en, this message translates to:
  /// **'Parents see it once it has a photo.'**
  String get galleryNoPhotosYetParents;

  /// Empty event.
  ///
  /// In en, this message translates to:
  /// **'No photos yet.'**
  String get galleryNoPhotosYet;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get galleryAddPhoto;

  /// Button while a photo uploads.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get galleryUploading;

  /// Photo source: the camera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get galleryTakePhoto;

  /// Photo source: the phone's photos.
  ///
  /// In en, this message translates to:
  /// **'Choose from photos'**
  String get galleryChoosePhoto;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Photo added'**
  String get galleryPhotoAdded;

  /// How full an event is.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} photos'**
  String galleryPhotosOf(int count, int max);

  /// An event at its photo limit.
  ///
  /// In en, this message translates to:
  /// **'This event has the most photos it can hold ({max}).'**
  String galleryFull(int max);

  /// Button: edit the event.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get galleryChange;

  /// Button: delete the event.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get galleryDelete;

  /// Confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete {title}?'**
  String galleryDeleteEventQ(String title);

  /// Confirm dialog body.
  ///
  /// In en, this message translates to:
  /// **'The event and all its photos are removed for everyone. This cannot be undone.'**
  String get galleryDeleteEventBody;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Event deleted'**
  String get galleryEventDeleted;

  /// Tooltip on the remove button.
  ///
  /// In en, this message translates to:
  /// **'Remove this photo'**
  String get galleryRemovePhoto;

  /// Confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Remove this photo?'**
  String get galleryRemovePhotoQ;

  /// Confirm dialog body.
  ///
  /// In en, this message translates to:
  /// **'Parents will no longer see it.'**
  String get galleryRemovePhotoBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get galleryRemove;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Photo removed'**
  String get galleryPhotoRemoved;

  /// Screen-reader label of a photo in the grid.
  ///
  /// In en, this message translates to:
  /// **'Photo {number} of {total}'**
  String galleryPhotoLabel(int number, int total);

  /// Family app: the gallery screen's title and its row on More.
  ///
  /// In en, this message translates to:
  /// **'Events & photos'**
  String get familyGallery;

  /// Subtitle of the gallery row on More.
  ///
  /// In en, this message translates to:
  /// **'Photos from school events'**
  String get familyGallerySub;

  /// Empty gallery title.
  ///
  /// In en, this message translates to:
  /// **'No photos yet'**
  String get familyNoGallery;

  /// Empty gallery message.
  ///
  /// In en, this message translates to:
  /// **'When the school shares photos of an event, they will show here.'**
  String get familyNoGalleryMessage;

  /// An event for the whole school.
  ///
  /// In en, this message translates to:
  /// **'Whole school'**
  String get familyGalleryWholeSchool;

  /// How many photos an event has.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String familyGalleryPhotos(int count);

  /// Button: next page.
  ///
  /// In en, this message translates to:
  /// **'Show older events'**
  String get familyGalleryOlder;

  /// An event that was removed.
  ///
  /// In en, this message translates to:
  /// **'This event is no longer shared.'**
  String get familyGalleryGone;

  /// Staff/web: the meetings screen's heading (M12, 8.4).
  ///
  /// In en, this message translates to:
  /// **'Parent-teacher meetings'**
  String get ptmMeetings;

  /// Filter: meetings still to come.
  ///
  /// In en, this message translates to:
  /// **'Ahead'**
  String get ptmAhead;

  /// Filter: meetings already held.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get ptmPast;

  /// Button and dialog title: create a meeting day.
  ///
  /// In en, this message translates to:
  /// **'New meeting'**
  String get ptmNewMeeting;

  /// Dialog title: edit a meeting day.
  ///
  /// In en, this message translates to:
  /// **'Change meeting'**
  String get ptmEditMeeting;

  /// Intro line for the school office.
  ///
  /// In en, this message translates to:
  /// **'Create a meeting day and pick the classes. Each class teacher then opens times, and parents book them in the Family app.'**
  String get ptmIntroOffice;

  /// Intro line for a class teacher.
  ///
  /// In en, this message translates to:
  /// **'Open times for your class. Parents book them in the Family app, and you see who is coming.'**
  String get ptmIntroTeacher;

  /// Empty list.
  ///
  /// In en, this message translates to:
  /// **'No meetings ahead.'**
  String get ptmNoMeetingsAhead;

  /// Empty list of past meetings.
  ///
  /// In en, this message translates to:
  /// **'No past meetings.'**
  String get ptmNoPastMeetings;

  /// Badge: the meeting was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get ptmCancelled;

  /// Badge: parents can no longer book (the meeting is today).
  ///
  /// In en, this message translates to:
  /// **'Booking closed'**
  String get ptmBookingClosed;

  /// A class taking part has no class teacher set.
  ///
  /// In en, this message translates to:
  /// **'No class teacher'**
  String get ptmNoClassTeacher;

  /// A class whose teacher has opened no slots, after the teacher's name.
  ///
  /// In en, this message translates to:
  /// **'no times opened yet'**
  String get ptmNoTimesYet;

  /// How many of a class's slots are booked.
  ///
  /// In en, this message translates to:
  /// **'{booked} of {total} booked'**
  String ptmBookedOf(int booked, int total);

  /// Button: edit the meeting.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get ptmEdit;

  /// Button: cancel the whole meeting day.
  ///
  /// In en, this message translates to:
  /// **'Cancel meeting'**
  String get ptmCancelMeeting;

  /// Confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Cancel {title}?'**
  String ptmCancelMeetingQ(String title);

  /// Confirm dialog body.
  ///
  /// In en, this message translates to:
  /// **'Parents who booked will be told in the Family app. This cannot be undone.'**
  String get ptmCancelMeetingBody;

  /// Dialog button: do not cancel.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get ptmKeepMeeting;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Meeting cancelled'**
  String get ptmMeetingCancelled;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Meeting created'**
  String get ptmMeetingCreated;

  /// Snackbar after changing a meeting.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get ptmSaved;

  /// Form field: the meeting's name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get ptmTitleLabel;

  /// Hint for the meeting's name.
  ///
  /// In en, this message translates to:
  /// **'e.g. Term 1 parent-teacher meeting'**
  String get ptmTitleHint;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Give the meeting a name.'**
  String get ptmTitleRequired;

  /// Form field: the meeting's date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get ptmDateLabel;

  /// Empty date field.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get ptmPickDate;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Pick the date.'**
  String get ptmDateRequired;

  /// Form field.
  ///
  /// In en, this message translates to:
  /// **'Note to parents (optional)'**
  String get ptmNoteLabel;

  /// Helper under the note.
  ///
  /// In en, this message translates to:
  /// **'Shown in the Family app, e.g. what to bring.'**
  String get ptmNoteHelp;

  /// Form section.
  ///
  /// In en, this message translates to:
  /// **'Classes taking part'**
  String get ptmClassesTakingPart;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get ptmSelectAll;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get ptmClearAll;

  /// Classes list before a school is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose the school first.'**
  String get ptmChooseSchoolFirst;

  /// No classes to pick.
  ///
  /// In en, this message translates to:
  /// **'No classes have been set up yet.'**
  String get ptmNoClassesYet;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one class.'**
  String get ptmClassesRequired;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get ptmCreate;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get ptmSave;

  /// On the slots screen of a cancelled meeting.
  ///
  /// In en, this message translates to:
  /// **'This meeting was cancelled.'**
  String get ptmMeetingWasCancelled;

  /// Empty slots list.
  ///
  /// In en, this message translates to:
  /// **'No times opened yet.'**
  String get ptmNoTimesOpened;

  /// Card title: open slots for the class.
  ///
  /// In en, this message translates to:
  /// **'Open times'**
  String get ptmOpenTimes;

  /// Help under Open times.
  ///
  /// In en, this message translates to:
  /// **'The range is cut into slots. A time that overlaps one already open is skipped.'**
  String get ptmOpenTimesHelp;

  /// Button: pick the start time.
  ///
  /// In en, this message translates to:
  /// **'From {time}'**
  String ptmFromTime(String time);

  /// Button: pick the end time.
  ///
  /// In en, this message translates to:
  /// **'To {time}'**
  String ptmToTime(String time);

  /// Dropdown: slot length.
  ///
  /// In en, this message translates to:
  /// **'Each slot'**
  String get ptmSlotLength;

  /// A slot length.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes'**
  String ptmMinutes(int minutes);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Open these times'**
  String get ptmOpenTimesButton;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'The end time must be after the start time.'**
  String get ptmEndAfterStart;

  /// Snackbar after opening slots.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 time opened} other{{count} times opened}}'**
  String ptmTimesOpened(int count);

  /// Snackbar when nothing new was opened.
  ///
  /// In en, this message translates to:
  /// **'Those times are already open.'**
  String get ptmNoNewTimes;

  /// A slot nobody has booked.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get ptmFree;

  /// Who booked a slot: the child and the parent.
  ///
  /// In en, this message translates to:
  /// **'{child} · {parent}'**
  String ptmBookedBy(String child, String parent);

  /// Tooltip on the call button.
  ///
  /// In en, this message translates to:
  /// **'Call {mobile}'**
  String ptmCallParent(String mobile);

  /// Tooltip on the delete button.
  ///
  /// In en, this message translates to:
  /// **'Remove this time'**
  String get ptmRemoveTime;

  /// Confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Remove {time}?'**
  String ptmRemoveTimeQ(String time);

  /// Confirm dialog body for a free slot.
  ///
  /// In en, this message translates to:
  /// **'Nobody has booked it.'**
  String get ptmRemoveFreeBody;

  /// Confirm dialog body for a booked slot.
  ///
  /// In en, this message translates to:
  /// **'{parent} booked this time. They will be told it was removed and asked to book another.'**
  String ptmRemoveBookedBody(String parent);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get ptmRemove;

  /// Snackbar.
  ///
  /// In en, this message translates to:
  /// **'Time removed'**
  String get ptmTimeRemoved;

  /// Staff app Today card: an upcoming meeting.
  ///
  /// In en, this message translates to:
  /// **'{title} on {date}'**
  String ptmTodayCard(String title, String date);

  /// Staff app Today card subtitle.
  ///
  /// In en, this message translates to:
  /// **'Open times and see who booked'**
  String get ptmTodayCardSub;

  /// Bottom bar tab: the staff member's home screen.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get staffNavHome;

  /// Bottom bar tab: periods, teaching reports, syllabus and tests.
  ///
  /// In en, this message translates to:
  /// **'Teaching'**
  String get staffNavTeaching;

  /// Bottom bar tab: an HOD's own department.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get staffNavDepartment;

  /// Bottom bar tab: the staff member's own leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get staffNavLeave;

  /// Bottom bar tab: the staff member's payslips.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get staffNavPay;

  /// Bottom bar tab / title: taking students' fees.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get staffNavFees;

  /// Bottom bar tab: the person's own profile.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get staffNavMe;

  /// Tooltip of the log-out button in the top bar.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get staffLogOut;

  /// Tooltip of the inbox bell with nothing unread.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get staffMessages;

  /// Tooltip of the inbox bell with unread messages.
  ///
  /// In en, this message translates to:
  /// **'Messages, {count} unread'**
  String staffMessagesUnread(int count);

  /// Title of the screen of parents asking for a call back.
  ///
  /// In en, this message translates to:
  /// **'Call requests'**
  String get staffCallRequestsTitle;

  /// Shown to bus crew who signed in to the Staff app.
  ///
  /// In en, this message translates to:
  /// **'Use the School365ai Bus app'**
  String get staffNotTeacherCrewTitle;

  /// Shown to an account that looks after many schools.
  ///
  /// In en, this message translates to:
  /// **'Use the School365ai website'**
  String get staffNotTeacherOfficeTitle;

  /// Explains that bus crew use the Driver app.
  ///
  /// In en, this message translates to:
  /// **'Drivers and bus attendants sign in to School365ai Driver, with their mobile number and passcode.'**
  String get staffNotTeacherCrewBody;

  /// Explains that multi-school accounts use the website.
  ///
  /// In en, this message translates to:
  /// **'This app is for the staff of a school. Your account looks after more than one school, which the website is made for.'**
  String get staffNotTeacherOfficeBody;

  /// Button that signs the person out.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get staffSignOut;

  /// Tooltip of a back arrow.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get staffBack;

  /// Field label: the password in use now.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get staffCurrentPassword;

  /// Validation: current password missing.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password'**
  String get staffEnterCurrentPassword;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get staffNewPassword;

  /// Helper text under a new password field.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters, with a letter and a number.'**
  String get staffNewPasswordHint;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get staffConfirmNewPassword;

  /// Validation: the two new passwords differ.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get staffPasswordsDoNotMatch;

  /// Title of the forced change-password screen.
  ///
  /// In en, this message translates to:
  /// **'Choose your password'**
  String get staffChoosePasswordTitle;

  /// Why the person must change their password.
  ///
  /// In en, this message translates to:
  /// **'Your account was set up with a temporary password. Choose your own to continue.'**
  String get staffChoosePasswordSubtitle;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get staffSavePassword;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Password changed.'**
  String get staffPasswordChanged;

  /// Button on the forced change-password screen.
  ///
  /// In en, this message translates to:
  /// **'Sign out instead'**
  String get staffSignOutInstead;

  /// Title of the forgot-password screen.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get staffResetPasswordTitle;

  /// Title once the reset link was sent.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get staffCheckEmailTitle;

  /// Subtitle of the forgot-password screen.
  ///
  /// In en, this message translates to:
  /// **'Enter your school email and we will send you a link to choose a new password.'**
  String get staffResetPasswordSubtitle;

  /// Subtitle once the reset link was sent.
  ///
  /// In en, this message translates to:
  /// **'A link to choose a new password is on its way.'**
  String get staffCheckEmailSubtitle;

  /// Body once the reset link was sent.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {email}, the email is on its way. The link works once and lasts one hour. If it does not arrive, look in your spam folder.'**
  String staffResetSentBody(String email);

  /// What to do after the reset email.
  ///
  /// In en, this message translates to:
  /// **'Choose your new password from the link, then come back here and sign in with it.'**
  String get staffResetSentNext;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get staffBackToSignIn;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get staffEmail;

  /// Validation: email missing.
  ///
  /// In en, this message translates to:
  /// **'Enter your email.'**
  String get staffEnterEmail;

  /// Validation: email malformed.
  ///
  /// In en, this message translates to:
  /// **'That does not look like an email address.'**
  String get staffNotAnEmail;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get staffSendResetLink;

  /// Title of the sign-in screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get staffWelcomeBack;

  /// Subtitle of the sign-in screen.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your school email and password.'**
  String get staffSignInSubtitle;

  /// Shown when the server ended the session.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Sign in again.'**
  String get staffSessionEnded;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get staffPassword;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get staffShowPassword;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get staffHidePassword;

  /// Validation: password missing.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get staffEnterPassword;

  /// Checkbox on the sign-in screen.
  ///
  /// In en, this message translates to:
  /// **'Remember my email'**
  String get staffRememberEmail;

  /// Link to the password reset.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get staffForgotPassword;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get staffSignIn;

  /// Help line under the sign-in form.
  ///
  /// In en, this message translates to:
  /// **'Trouble signing in? Your school office can unlock your account or send you a new link.'**
  String get staffTroubleSigningIn;

  /// Headline of the welcome screen (two lines).
  ///
  /// In en, this message translates to:
  /// **'Your school day,\nin your pocket.'**
  String get staffWelcomeHeadline;

  /// Intro on the welcome screen.
  ///
  /// In en, this message translates to:
  /// **'For everyone who works at your school. Sign in with the email and password you use for School365ai.'**
  String get staffWelcomeIntro;

  /// Welcome feature title.
  ///
  /// In en, this message translates to:
  /// **'Check in at school'**
  String get staffWelcomeCheckInTitle;

  /// Welcome feature body.
  ///
  /// In en, this message translates to:
  /// **'Mark your arrival and departure from your phone, at school.'**
  String get staffWelcomeCheckInBody;

  /// Welcome feature title.
  ///
  /// In en, this message translates to:
  /// **'Today at a glance'**
  String get staffWelcomeTodayTitle;

  /// Welcome feature body.
  ///
  /// In en, this message translates to:
  /// **'For teachers: your periods in order, with the one under way marked.'**
  String get staffWelcomeTodayBody;

  /// Welcome feature title.
  ///
  /// In en, this message translates to:
  /// **'Register and reports'**
  String get staffWelcomeRegisterTitle;

  /// Welcome feature body.
  ///
  /// In en, this message translates to:
  /// **'Take your class register, even without signal, and say what each period covered.'**
  String get staffWelcomeRegisterBody;

  /// Welcome feature title.
  ///
  /// In en, this message translates to:
  /// **'Your school\'s calendar'**
  String get staffWelcomeCalendarTitle;

  /// Welcome feature body.
  ///
  /// In en, this message translates to:
  /// **'Holidays, half days and your approved leave, without asking the office.'**
  String get staffWelcomeCalendarBody;

  /// Help line on the welcome screen.
  ///
  /// In en, this message translates to:
  /// **'New here? Your school office creates your account and emails you a link to choose your password.'**
  String get staffWelcomeNewHere;

  /// Tagline on the splash screen.
  ///
  /// In en, this message translates to:
  /// **'Your school day, in your pocket.'**
  String get staffSplashTagline;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get staffTryAgain;

  /// Splash status when slow.
  ///
  /// In en, this message translates to:
  /// **'Still trying to reach your school. Check that this phone is online.'**
  String get staffSplashSlow;

  /// Splash status while loading.
  ///
  /// In en, this message translates to:
  /// **'Getting your day ready…'**
  String get staffSplashLoading;

  /// Leave type.
  ///
  /// In en, this message translates to:
  /// **'Casual Leave'**
  String get staffLeaveCasual;

  /// Leave type.
  ///
  /// In en, this message translates to:
  /// **'Medical Leave'**
  String get staffLeaveMedical;

  /// Leave type.
  ///
  /// In en, this message translates to:
  /// **'Earned Leave'**
  String get staffLeaveEarned;

  /// Leave type.
  ///
  /// In en, this message translates to:
  /// **'Half Day'**
  String get staffLeaveHalfDay;

  /// Leave status: waiting for a decision.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get staffLeavePending;

  /// Leave status.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get staffLeaveApproved;

  /// Leave status.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get staffLeaveRejected;

  /// Leave status: taken back by the applicant.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get staffLeaveWithdrawn;

  /// Day name.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get staffDayMonday;

  /// Day name.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get staffDayTuesday;

  /// Day name.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get staffDayWednesday;

  /// Day name.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get staffDayThursday;

  /// Day name.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get staffDayFriday;

  /// Day name.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get staffDaySaturday;

  /// Day name.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get staffDaySunday;

  /// Short day name.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get staffDayMon;

  /// Short day name.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get staffDayTue;

  /// Short day name.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get staffDayWed;

  /// Short day name.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get staffDayThu;

  /// Short day name.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get staffDayFri;

  /// Short day name.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get staffDaySat;

  /// Short day name.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get staffDaySun;

  /// Heading over today's periods when there are none.
  ///
  /// In en, this message translates to:
  /// **'Your periods'**
  String get staffYourPeriods;

  /// Heading over today's periods with how many.
  ///
  /// In en, this message translates to:
  /// **'Your periods ({count})'**
  String staffYourPeriodsCount(int count);

  /// A break that is on now; name is the school's name for it.
  ///
  /// In en, this message translates to:
  /// **'{name} - now'**
  String staffBreakNow(String name);

  /// A span of two dates.
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String staffDateRange(String start, String end);

  /// Greeting with no name.
  ///
  /// In en, this message translates to:
  /// **'Good day'**
  String get staffGoodDay;

  /// Greeting with the first name.
  ///
  /// In en, this message translates to:
  /// **'Good day, {name}'**
  String staffGoodDayName(String name);

  /// Badge: the school closes early today.
  ///
  /// In en, this message translates to:
  /// **'Half day'**
  String get staffHalfDay;

  /// The school is closed today.
  ///
  /// In en, this message translates to:
  /// **'No school today'**
  String get staffNoSchoolToday;

  /// A named holiday; the name is the school's.
  ///
  /// In en, this message translates to:
  /// **'Holiday: {name}'**
  String staffHolidayNamed(String name);

  /// Why nothing is owed on a closed day.
  ///
  /// In en, this message translates to:
  /// **'The school is closed, so there is no register to take and no report to write.'**
  String get staffClosedBody;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'You are on leave today'**
  String get staffOnLeaveToday;

  /// Body of the on-leave card.
  ///
  /// In en, this message translates to:
  /// **'{type}, {span}. Nothing is owed while you are away.'**
  String staffOnLeaveBody(String type, String span);

  /// All done line on Today.
  ///
  /// In en, this message translates to:
  /// **'Nothing owed so far today.'**
  String get staffNothingOwed;

  /// How many registers are still to take.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 register} other{{count} registers}}'**
  String staffOwedRegisters(int count);

  /// How many teaching reports are still to file.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 teaching report} other{{count} teaching reports}}'**
  String staffOwedReports(int count);

  /// Joins two items in a list (with spaces).
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get staffAnd;

  /// What is still owed today.
  ///
  /// In en, this message translates to:
  /// **'Still to do: {items}.'**
  String staffStillToDo(String items);

  /// Badge: the register was taken.
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get staffRegisterTaken;

  /// Subtitle of the register card.
  ///
  /// In en, this message translates to:
  /// **'Your class register'**
  String get staffYourClassRegister;

  /// Badge: saved on the phone, waiting for signal.
  ///
  /// In en, this message translates to:
  /// **'Saved, not sent'**
  String get staffSavedNotSent;

  /// Hint under a register waiting on the phone.
  ///
  /// In en, this message translates to:
  /// **'Sends when there is signal'**
  String get staffSendsWithSignal;

  /// Badge: the server refused it.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get staffNotSent;

  /// Badge: the register is still to take.
  ///
  /// In en, this message translates to:
  /// **'Not taken'**
  String get staffRegisterNotTaken;

  /// Hint under the register card.
  ///
  /// In en, this message translates to:
  /// **'Tap to take the register'**
  String get staffTapToTakeRegister;

  /// Link to find a student.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get staffStudents;

  /// Link / title: the teacher's week.
  ///
  /// In en, this message translates to:
  /// **'My week'**
  String get staffMyWeek;

  /// Card on Today with how many parents are waiting for a call.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A parent asked you to call} other{{count} parents asked you to call}}'**
  String staffParentsAskedToCall(int count);

  /// Subtitle of the call requests card.
  ///
  /// In en, this message translates to:
  /// **'Tap to see who, and ring them'**
  String get staffTapToSeeWho;

  /// A period's class and number.
  ///
  /// In en, this message translates to:
  /// **'{classSection} · Period {number}'**
  String staffClassAndPeriod(String classSection, int number);

  /// Badge: the period under way.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get staffNow;

  /// Badge: a report the server refused.
  ///
  /// In en, this message translates to:
  /// **'Not sent - tap to see why'**
  String get staffNotSentTapWhy;

  /// Badge: the HOD returned the report.
  ///
  /// In en, this message translates to:
  /// **'Sent back - tap to change'**
  String get staffSentBackTapChange;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Report filed'**
  String get staffReportFiled;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Report owed - tap to file'**
  String get staffReportOwedTapFile;

  /// Empty state on Today.
  ///
  /// In en, this message translates to:
  /// **'You have no periods on the timetable today.'**
  String get staffNoPeriodsToday;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Leave this week'**
  String get staffLeaveThisWeek;

  /// One leave: its type and dates.
  ///
  /// In en, this message translates to:
  /// **'{type}, {span}'**
  String staffLeaveLine(String type, String span);

  /// Link on the staff home.
  ///
  /// In en, this message translates to:
  /// **'Find a student'**
  String get staffFindAStudent;

  /// Where things are on the staff home.
  ///
  /// In en, this message translates to:
  /// **'Your leave and payslips are in the Leave and Pay tabs below.'**
  String get staffWhereLeaveAndPay;

  /// Where things are on the staff home.
  ///
  /// In en, this message translates to:
  /// **'Your leave is in the Leave tab below.'**
  String get staffWhereLeave;

  /// Where things are on the staff home.
  ///
  /// In en, this message translates to:
  /// **'Your payslips are in the Pay tab below.'**
  String get staffWherePay;

  /// Where things are on the staff home.
  ///
  /// In en, this message translates to:
  /// **'The school\'s messages are under the bell at the top.'**
  String get staffWhereMessages;

  /// Why there is no check-in today.
  ///
  /// In en, this message translates to:
  /// **'The school is closed, so there is nothing to check in to.'**
  String get staffClosedNoCheckIn;

  /// Why there is no check-in today.
  ///
  /// In en, this message translates to:
  /// **'Nothing to check in to while you are away.'**
  String get staffOnLeaveNoCheckIn;

  /// Why there is no check-in.
  ///
  /// In en, this message translates to:
  /// **'Attendance is marked in the office'**
  String get staffMarkedInOffice;

  /// Why there is no check-in.
  ///
  /// In en, this message translates to:
  /// **'Your school records staff attendance itself rather than from the app.'**
  String get staffMarkedInOfficeBody;

  /// Empty state of My week.
  ///
  /// In en, this message translates to:
  /// **'You have no periods on the timetable yet. The office sets it up.'**
  String get staffNoPeriodsYet;

  /// Day chip for today.
  ///
  /// In en, this message translates to:
  /// **'{day} (today)'**
  String staffDayToday(String day);

  /// Heading over a day's periods.
  ///
  /// In en, this message translates to:
  /// **'{day}: {count, plural, =1{1 period} other{{count} periods}}'**
  String staffDayPeriods(String day, int count);

  /// A period with no subject.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get staffPeriod;

  /// Attendance status.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get staffPresent;

  /// Attendance status.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get staffAbsent;

  /// Badge: arrived late.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get staffLate;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Checked in.'**
  String get staffCheckedIn;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Checked out.'**
  String get staffCheckedOut;

  /// Confirmation with the time.
  ///
  /// In en, this message translates to:
  /// **'Checked in at {time}.'**
  String staffCheckedInAt(String time);

  /// Confirmation with the time.
  ///
  /// In en, this message translates to:
  /// **'Checked out at {time}.'**
  String staffCheckedOutAt(String time);

  /// Part of the check-out question.
  ///
  /// In en, this message translates to:
  /// **'You checked in at {time}.'**
  String staffYouCheckedInAt(String time);

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Check out again?'**
  String get staffCheckOutAgainQ;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Check out now?'**
  String get staffCheckOutNowQ;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'Your leaving time will change to now. The last check-out is the one that counts.'**
  String get staffCheckOutAgainBody;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'This records the time you leave school.'**
  String get staffCheckOutBody;

  /// Button that cancels the check-out.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get staffNotYet;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get staffCheckOut;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Check out again'**
  String get staffCheckOutAgain;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get staffCheckIn;

  /// When settings could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Open your phone\'s settings and allow location for School365ai.'**
  String get staffOpenSettingsForLocation;

  /// Button while busy.
  ///
  /// In en, this message translates to:
  /// **'Finding your location…'**
  String get staffFindingLocation;

  /// Privacy line under the check-in button.
  ///
  /// In en, this message translates to:
  /// **'Your location is used once, to confirm you are within {metres} m of school. It is not stored.'**
  String staffLocationUsedOnce(int metres);

  /// Card title; the reason is the server's.
  ///
  /// In en, this message translates to:
  /// **'Check-in unavailable'**
  String get staffCheckInUnavailable;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Marked absent today'**
  String get staffMarkedAbsent;

  /// Card body.
  ///
  /// In en, this message translates to:
  /// **'The office marked you absent. Check in when you arrive and it is corrected.'**
  String get staffMarkedAbsentBody;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Half-day leave today'**
  String get staffHalfDayLeaveToday;

  /// Card body.
  ///
  /// In en, this message translates to:
  /// **'Check in for the half you work, and the day is recorded as a half day.'**
  String get staffHalfDayLeaveBody;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Check in to start your day'**
  String get staffCheckInToStart;

  /// Card body.
  ///
  /// In en, this message translates to:
  /// **'Tap Check in when you reach school.'**
  String get staffCheckInToStartBody;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Checked in at {time}'**
  String staffCheckedInAtTitle(String time);

  /// Card body.
  ///
  /// In en, this message translates to:
  /// **'Check out when you leave school.'**
  String get staffCheckOutWhenLeaving;

  /// Card body at the end of the day.
  ///
  /// In en, this message translates to:
  /// **'Checked in and out. See you tomorrow.'**
  String get staffCheckedInAndOut;

  /// Note about a day with no check-out.
  ///
  /// In en, this message translates to:
  /// **'You did not check out on {date} (checked in {time}). Ask the office to add when you left.'**
  String staffUnfinishedDay(String date, String time);

  /// Note.
  ///
  /// In en, this message translates to:
  /// **'The office has updated your day on the register. Ask them if something looks wrong.'**
  String get staffOfficeUpdatedDay;

  /// Check-in failed for want of signal.
  ///
  /// In en, this message translates to:
  /// **'No connection, so nothing was recorded. Check in again when your phone is online - the time saved is when it reaches the school.'**
  String get staffCheckInNoConnection;

  /// Location problem.
  ///
  /// In en, this message translates to:
  /// **'Your phone\'s location is switched off. Turn it on, then check in again.'**
  String get staffLocationServiceOff;

  /// Location problem.
  ///
  /// In en, this message translates to:
  /// **'This app is not allowed to see your location. Allow it in your phone\'s settings for this app, then check in again.'**
  String get staffLocationDeniedForever;

  /// Location problem.
  ///
  /// In en, this message translates to:
  /// **'Checking in needs your location once, to confirm you are at school. Allow it and try again.'**
  String get staffLocationDenied;

  /// Location problem.
  ///
  /// In en, this message translates to:
  /// **'This device cannot tell where it is, so it cannot check you in.'**
  String get staffLocationUnsupported;

  /// Location problem.
  ///
  /// In en, this message translates to:
  /// **'Your location could not be found. Try again in a moment.'**
  String get staffLocationNotFound;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Turn on location'**
  String get staffTurnOnLocation;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get staffOpenSettings;

  /// Card title on failure.
  ///
  /// In en, this message translates to:
  /// **'Could not load your check-in'**
  String get staffCheckInLoadFailed;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Check-in is not set up for your account'**
  String get staffNoStaffRecord;

  /// Card body.
  ///
  /// In en, this message translates to:
  /// **'Your account has no staff record at this school. Ask the office to add one.'**
  String get staffNoStaffRecordBody;

  /// Message category.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get staffCategoryAttendance;

  /// Message category.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get staffCategoryTransport;

  /// Message category.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get staffCategoryResult;

  /// Message category.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get staffCategoryAnnouncement;

  /// Message category.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get staffCategoryGeneral;

  /// Message category.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get staffCategoryEmergency;

  /// Filter chip: everything.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get staffPeriodAll;

  /// Filter chip.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get staffPeriodToday;

  /// Filter chip.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get staffPeriodWeek;

  /// Filter chip.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get staffPeriodMonth;

  /// After mark all read with nothing unread.
  ///
  /// In en, this message translates to:
  /// **'Nothing was unread.'**
  String get staffNothingWasUnread;

  /// After mark all read.
  ///
  /// In en, this message translates to:
  /// **'Marked {count} as read.'**
  String staffMarkedRead(int count);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get staffMarkAllRead;

  /// Filter chip.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get staffUnread;

  /// Empty inbox, unread filter.
  ///
  /// In en, this message translates to:
  /// **'Nothing unread.'**
  String get staffNothingUnread;

  /// Empty inbox.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get staffNoMessagesYet;

  /// Empty inbox hint.
  ///
  /// In en, this message translates to:
  /// **'Announcements and notices from your school arrive here.'**
  String get staffInboxEmptyHint;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Show older messages'**
  String get staffShowOlderMessages;

  /// A message about a student.
  ///
  /// In en, this message translates to:
  /// **'About {name}'**
  String staffAboutStudent(String name);

  /// A picture that failed to decode.
  ///
  /// In en, this message translates to:
  /// **'This picture could not be shown.'**
  String get staffPictureNotShown;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get staffDownload;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save or share'**
  String get staffSaveOrShare;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get staffClose;

  /// Button / title.
  ///
  /// In en, this message translates to:
  /// **'Apply for leave'**
  String get staffApplyForLeave;

  /// Heading.
  ///
  /// In en, this message translates to:
  /// **'My leave'**
  String get staffMyLeave;

  /// Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your requests and where each one stands.'**
  String get staffMyLeaveSubtitle;

  /// Empty list for the chosen period (all, day, week, month).
  ///
  /// In en, this message translates to:
  /// **'{period, select, all{No leave requests yet.} day{No leave requests today.} week{No leave requests this week.} month{No leave requests this month.} other{No leave requests yet.}}'**
  String staffEmptyLeaveRequests(String period);

  /// Empty list hint.
  ///
  /// In en, this message translates to:
  /// **'Tap Apply for leave to ask for a day off.'**
  String get staffApplyForLeaveHint;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Show older requests'**
  String get staffShowOlderRequests;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Withdraw this request?'**
  String get staffWithdrawRequestQ;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'It will no longer wait for a decision. You can apply for the same days again.'**
  String get staffWithdrawRequestBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get staffWithdraw;

  /// Button that keeps the request.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get staffKeepIt;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Leave request withdrawn.'**
  String get staffLeaveWithdrawnDone;

  /// Dates of a half-day leave.
  ///
  /// In en, this message translates to:
  /// **'{dates} · half a day'**
  String staffDatesHalfADay(String dates);

  /// Who decided, when the name is unknown.
  ///
  /// In en, this message translates to:
  /// **'Reviewer'**
  String get staffReviewer;

  /// Button while busy.
  ///
  /// In en, this message translates to:
  /// **'Withdrawing...'**
  String get staffWithdrawing;

  /// Load failure.
  ///
  /// In en, this message translates to:
  /// **'Could not load this year\'s leave.'**
  String get staffLeaveTakenLoadFailed;

  /// Heading; year is the academic year's label.
  ///
  /// In en, this message translates to:
  /// **'Taken in {year}'**
  String staffTakenIn(String year);

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No leave taken yet this year.'**
  String get staffNoLeaveTakenYet;

  /// Pending requests.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 request is waiting for a decision.} other{{count} requests are waiting for a decision.}}'**
  String staffRequestsWaiting(int count);

  /// One working day.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get staffOneDay;

  /// Working days; number may be 2.5.
  ///
  /// In en, this message translates to:
  /// **'{number} days'**
  String staffDays(String number);

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Leave approved automatically.'**
  String get staffLeaveAutoApproved;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Leave requested. You will see here when it is decided.'**
  String get staffLeaveRequested;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Leave type'**
  String get staffLeaveType;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get staffDate;

  /// Field label: first date.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get staffFrom;

  /// Field label: last date.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get staffTo;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get staffReason;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Say why you need the leave.'**
  String get staffSayWhyLeave;

  /// Hint.
  ///
  /// In en, this message translates to:
  /// **'Half-day leave: you check in for the half you work, and the day counts as a half day.'**
  String get staffHalfDayLeaveHint;

  /// Hint.
  ///
  /// In en, this message translates to:
  /// **'Weekends and holidays inside the dates are not counted as leave.'**
  String get staffWeekendsNotCounted;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get staffSendRequest;

  /// Payment mode.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get staffModeCash;

  /// Payment mode.
  ///
  /// In en, this message translates to:
  /// **'Bank Transfer'**
  String get staffModeBankTransfer;

  /// Payment mode.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get staffModeUpi;

  /// Payment mode.
  ///
  /// In en, this message translates to:
  /// **'Cheque'**
  String get staffModeCheque;

  /// Payment mode.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get staffModeCard;

  /// Payment mode.
  ///
  /// In en, this message translates to:
  /// **'Online Transfer'**
  String get staffModeOnlineTransfer;

  /// Heading.
  ///
  /// In en, this message translates to:
  /// **'My pay'**
  String get staffMyPay;

  /// Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your payslips, once the month is finalized.'**
  String get staffMyPaySubtitle;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No payslips yet.'**
  String get staffNoPayslipsYet;

  /// Empty state hint.
  ///
  /// In en, this message translates to:
  /// **'A payslip appears here once the school finalizes the month.'**
  String get staffNoPayslipsHint;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Show earlier months'**
  String get staffShowEarlierMonths;

  /// Label under the net pay amount.
  ///
  /// In en, this message translates to:
  /// **'Net pay'**
  String get staffNetPay;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get staffPaid;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Not paid yet'**
  String get staffNotPaidYet;

  /// Title while loading.
  ///
  /// In en, this message translates to:
  /// **'Payslip'**
  String get staffPayslip;

  /// Badge with the date.
  ///
  /// In en, this message translates to:
  /// **'Paid on {date}'**
  String staffPaidOn(String date);

  /// How it was paid, after Paid.
  ///
  /// In en, this message translates to:
  /// **'by {mode}'**
  String staffByMode(String mode);

  /// Section title.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get staffDaysTitle;

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Working days'**
  String get staffWorkingDays;

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Paid days'**
  String get staffPaidDays;

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Half days'**
  String get staffHalfDays;

  /// Row: days with no attendance.
  ///
  /// In en, this message translates to:
  /// **'Not marked'**
  String get staffNotMarked;

  /// Section title.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get staffEarnings;

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Total earnings'**
  String get staffTotalEarnings;

  /// Section title.
  ///
  /// In en, this message translates to:
  /// **'Deductions'**
  String get staffDeductions;

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Total deductions'**
  String get staffTotalDeductions;

  /// Shortfall note.
  ///
  /// In en, this message translates to:
  /// **'Unpaid days reduced this month by {amount}.'**
  String staffUnpaidShortfall(String amount);

  /// Button while busy.
  ///
  /// In en, this message translates to:
  /// **'Getting the PDF...'**
  String get staffGettingPdf;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Share the PDF'**
  String get staffSharePdf;

  /// Button while busy.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get staffSending;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Email me the PDF'**
  String get staffEmailMePdf;

  /// Department tab.
  ///
  /// In en, this message translates to:
  /// **'To review'**
  String get staffTabToReview;

  /// Department tab.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffTabStaff;

  /// Department tab.
  ///
  /// In en, this message translates to:
  /// **'Teachers'**
  String get staffTabTeachers;

  /// Intro of the review tab.
  ///
  /// In en, this message translates to:
  /// **'Reports from your department that nobody has reviewed yet. Open one to read and review it.'**
  String get staffReviewIntro;

  /// Empty review queue for the chosen period.
  ///
  /// In en, this message translates to:
  /// **'{period, select, all{Nothing waiting for review.} day{Nothing waiting for review from today.} week{Nothing waiting for review from this week.} month{Nothing waiting for review from this month.} other{Nothing waiting for review.}}'**
  String staffReviewEmpty(String period);

  /// Empty review queue body.
  ///
  /// In en, this message translates to:
  /// **'Reports your department files appear here until you review them.'**
  String get staffReviewEmptyBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get staffShowMore;

  /// A period by its number.
  ///
  /// In en, this message translates to:
  /// **'Period {number}'**
  String staffPeriodNumber(int number);

  /// Fallback teacher name.
  ///
  /// In en, this message translates to:
  /// **'A teacher'**
  String get staffATeacher;

  /// Intro of the staff tab for today.
  ///
  /// In en, this message translates to:
  /// **'Your department today: who is in, and when they arrived. Mark anyone the register is missing.'**
  String get staffDeptTodayIntro;

  /// Intro of the staff tab for a week or month.
  ///
  /// In en, this message translates to:
  /// **'{period, select, week{Your department this week: each person\'s days in, absent and on leave, out of the school days so far.} month{Your department this month: each person\'s days in, absent and on leave, out of the school days so far.} other{Your department: each person\'s days in, absent and on leave, out of the school days so far.}}'**
  String staffDeptPeriodIntro(String period);

  /// Count of school days.
  ///
  /// In en, this message translates to:
  /// **'1 school day so far'**
  String get staffOneSchoolDaySoFar;

  /// Count of school days.
  ///
  /// In en, this message translates to:
  /// **'{count} school days so far'**
  String staffSchoolDaysSoFar(String count);

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Nobody in your department yet.'**
  String get staffNobodyInDept;

  /// Empty state body.
  ///
  /// In en, this message translates to:
  /// **'The school office adds staff to departments on the website.'**
  String get staffOfficeAddsStaff;

  /// Figure label (lower case).
  ///
  /// In en, this message translates to:
  /// **'present'**
  String get staffFigPresent;

  /// Figure label.
  ///
  /// In en, this message translates to:
  /// **'half day'**
  String get staffFigHalfDay;

  /// Figure label.
  ///
  /// In en, this message translates to:
  /// **'absent'**
  String get staffFigAbsent;

  /// Figure label.
  ///
  /// In en, this message translates to:
  /// **'leave'**
  String get staffFigLeave;

  /// Figure label.
  ///
  /// In en, this message translates to:
  /// **'unmarked'**
  String get staffFigUnmarked;

  /// Holiday body.
  ///
  /// In en, this message translates to:
  /// **'The school is closed today.'**
  String get staffSchoolClosedToday;

  /// Department register summary.
  ///
  /// In en, this message translates to:
  /// **'{present} of {total} in'**
  String staffInOf(int present, int total);

  /// Department register summary with unmarked.
  ///
  /// In en, this message translates to:
  /// **'{present} of {total} in · {unmarked} not marked yet'**
  String staffInOfUnmarked(int present, int total, int unmarked);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'All present'**
  String get staffAllPresent;

  /// Button while busy.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get staffSaving;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Update register'**
  String get staffUpdateRegister;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Submit register'**
  String get staffSubmitRegister;

  /// Button while some are unmarked.
  ///
  /// In en, this message translates to:
  /// **'Mark everyone ({count} left)'**
  String staffMarkEveryone(int count);

  /// Check-in time.
  ///
  /// In en, this message translates to:
  /// **'In {time}'**
  String staffTimeIn(String time);

  /// Check-out time.
  ///
  /// In en, this message translates to:
  /// **'out {time}'**
  String staffTimeOut(String time);

  /// Checked in from the app.
  ///
  /// In en, this message translates to:
  /// **'from the app'**
  String get staffFromTheApp;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Present · late'**
  String get staffPresentLate;

  /// Intro of the leave tab.
  ///
  /// In en, this message translates to:
  /// **'Leave your department has asked for, waiting for your decision.'**
  String get staffDeptLeaveIntro;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing to decide.'**
  String get staffNothingToDecide;

  /// Empty state body.
  ///
  /// In en, this message translates to:
  /// **'New requests from your department appear here.'**
  String get staffNothingToDecideBody;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Approve this leave?'**
  String get staffApproveLeaveQ;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Reject this leave?'**
  String get staffRejectLeaveQ;

  /// Dialog body: who, which leave, which dates.
  ///
  /// In en, this message translates to:
  /// **'{name}: {type}, {dates}.'**
  String staffLeaveDecideBody(String name, String type, String dates);

  /// Fallback when the name is unknown.
  ///
  /// In en, this message translates to:
  /// **'This request'**
  String get staffThisRequest;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get staffApprove;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get staffReject;

  /// Dialog title; the body is the server's.
  ///
  /// In en, this message translates to:
  /// **'At work that day'**
  String get staffAtWorkThatDay;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Approve anyway'**
  String get staffApproveAnyway;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Leave approved.'**
  String get staffLeaveApprovedDone;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Leave rejected.'**
  String get staffLeaveRejectedDone;

  /// Intro of the teachers tab.
  ///
  /// In en, this message translates to:
  /// **'Each teacher this month: reports filed against periods taught, syllabus covered, attendance.'**
  String get staffMonthIntro;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No teachers in your department yet.'**
  String get staffNoTeachersInDept;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get staffOnTrack;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Needs a look'**
  String get staffNeedsALook;

  /// Figure label.
  ///
  /// In en, this message translates to:
  /// **'reports / periods'**
  String get staffFigReportsPeriods;

  /// Figure label.
  ///
  /// In en, this message translates to:
  /// **'to review'**
  String get staffFigToReview;

  /// Figure label.
  ///
  /// In en, this message translates to:
  /// **'syllabus'**
  String get staffFigSyllabus;

  /// Figure label.
  ///
  /// In en, this message translates to:
  /// **'attendance'**
  String get staffFigAttendance;

  /// Title of the register screen; label is the class.
  ///
  /// In en, this message translates to:
  /// **'{label} register'**
  String staffRegisterTitle(String label);

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Submit the register?'**
  String get staffSubmitRegisterQ;

  /// Button that goes back to the register.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get staffCheckAgain;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get staffSubmit;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Register submitted.'**
  String get staffRegisterSubmitted;

  /// Confirmation without signal.
  ///
  /// In en, this message translates to:
  /// **'No signal: the register is saved on this phone and sent when there is.'**
  String get staffRegisterSavedNoSignal;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Register corrected.'**
  String get staffRegisterCorrected;

  /// Correction failed without signal.
  ///
  /// In en, this message translates to:
  /// **'A correction needs a connection, because parents may already have been told. Try again with signal.'**
  String get staffCorrectionNeedsConnection;

  /// Search found nobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody in this class matches \"{query}\".'**
  String staffNobodyMatches(String query);

  /// Closed day.
  ///
  /// In en, this message translates to:
  /// **'The school is closed, so there is no register to take.'**
  String get staffClosedNoRegister;

  /// Empty class.
  ///
  /// In en, this message translates to:
  /// **'No students in this class'**
  String get staffNoStudentsInClass;

  /// Empty class body.
  ///
  /// In en, this message translates to:
  /// **'There is nobody on the class list to mark. Ask the office if that is wrong.'**
  String get staffNoStudentsInClassBody;

  /// How the register works.
  ///
  /// In en, this message translates to:
  /// **'Everyone starts as present. Tap Absent or Leave for anyone who is not - or swipe a row: right for present, left for absent.'**
  String get staffRegisterByException;

  /// Search hint.
  ///
  /// In en, this message translates to:
  /// **'Find by name or roll number'**
  String get staffFindByNameOrRoll;

  /// Register summary part.
  ///
  /// In en, this message translates to:
  /// **'{count} present'**
  String staffCountPresent(int count);

  /// Register summary part.
  ///
  /// In en, this message translates to:
  /// **'{count} absent'**
  String staffCountAbsent(int count);

  /// Register summary part.
  ///
  /// In en, this message translates to:
  /// **'{count} on leave'**
  String staffCountOnLeave(int count);

  /// Ends a sentence built from parts.
  ///
  /// In en, this message translates to:
  /// **'{text}.'**
  String staffSentence(String text);

  /// Register summary note.
  ///
  /// In en, this message translates to:
  /// **'Parents of absent children are told, as your school has set it up.'**
  String get staffParentsAreTold;

  /// A register the server refused; reason is the server's.
  ///
  /// In en, this message translates to:
  /// **'Not sent: {reason} If the register still needs taking, take it again below and submit it. If this looks wrong, ask the school office.'**
  String staffRegisterRefused(String reason);

  /// Banner.
  ///
  /// In en, this message translates to:
  /// **'Sending the register…'**
  String get staffSendingRegister;

  /// Banner.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone, not yet sent. It goes as soon as there is signal - you can close the app.'**
  String get staffRegisterWaiting;

  /// Banner.
  ///
  /// In en, this message translates to:
  /// **'No connection. Take the register as usual: it is saved on this phone and sent when there is signal.'**
  String get staffRegisterOffline;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save correction'**
  String get staffSaveCorrection;

  /// Register state.
  ///
  /// In en, this message translates to:
  /// **'Submitted.'**
  String get staffSubmittedDot;

  /// Button that starts a correction.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get staffCorrect;

  /// Register state.
  ///
  /// In en, this message translates to:
  /// **'Waiting for signal to send.'**
  String get staffWaitingForSignal;

  /// Chip.
  ///
  /// In en, this message translates to:
  /// **'Parent\'s note · seen'**
  String get staffParentsNoteSeen;

  /// Chip.
  ///
  /// In en, this message translates to:
  /// **'Parent\'s note'**
  String get staffParentsNote;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Marked as seen. The parent can see that.'**
  String get staffNoteMarkedSeen;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Note about {name}'**
  String staffNoteAbout(String name);

  /// Dialog hint.
  ///
  /// In en, this message translates to:
  /// **'A note doesn\'t mark the register - mark it as usual.'**
  String get staffNoteDoesNotMark;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Mark as seen'**
  String get staffMarkAsSeen;

  /// Teaching tab.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get staffTabReports;

  /// Teaching tab.
  ///
  /// In en, this message translates to:
  /// **'Syllabus'**
  String get staffTabSyllabus;

  /// Teaching tab.
  ///
  /// In en, this message translates to:
  /// **'Marks'**
  String get staffTabMarks;

  /// Intro of the reports tab.
  ///
  /// In en, this message translates to:
  /// **'What you taught, period by period, and whether it has been reviewed. File a report from its period on Today.'**
  String get staffReportsIntro;

  /// Empty reports list for the chosen period.
  ///
  /// In en, this message translates to:
  /// **'{period, select, all{No reports yet.} day{No reports today.} week{No reports this week.} month{No reports this month.} other{No reports yet.}}'**
  String staffEmptyReports(String period);

  /// Empty reports body.
  ///
  /// In en, this message translates to:
  /// **'Once a period has begun, tap it on Today to say what was taught.'**
  String get staffEmptyReportsBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Show older reports'**
  String get staffShowOlderReports;

  /// A report with no subject.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get staffReport;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get staffReviewed;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Sent back'**
  String get staffSentBack;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Awaiting review'**
  String get staffAwaitingReview;

  /// Intro of the syllabus tab.
  ///
  /// In en, this message translates to:
  /// **'Each class and subject you teach this year. Tap one to tick off topics.'**
  String get staffSyllabusIntro;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No classes on your timetable this year.'**
  String get staffNoClassesThisYear;

  /// Empty state body.
  ///
  /// In en, this message translates to:
  /// **'Your school office puts you on the timetable; your classes appear here once it does.'**
  String get staffNoClassesThisYearBody;

  /// No syllabus outline.
  ///
  /// In en, this message translates to:
  /// **'No topics yet'**
  String get staffNoTopicsYet;

  /// Progress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String staffXOfY(int done, int total);

  /// Test type.
  ///
  /// In en, this message translates to:
  /// **'Class test'**
  String get staffTestClassTest;

  /// Test type.
  ///
  /// In en, this message translates to:
  /// **'Unit test'**
  String get staffTestUnitTest;

  /// Test type.
  ///
  /// In en, this message translates to:
  /// **'Assignment'**
  String get staffTestAssignment;

  /// Test type.
  ///
  /// In en, this message translates to:
  /// **'Quiz'**
  String get staffTestQuiz;

  /// Test type.
  ///
  /// In en, this message translates to:
  /// **'Practical'**
  String get staffTestPractical;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'New test'**
  String get staffNewTest;

  /// Intro of the marks tab.
  ///
  /// In en, this message translates to:
  /// **'Class tests for the classes you teach. Open one to enter marks; publish when everyone is marked.'**
  String get staffMarksIntro;

  /// Empty tests list for the chosen period.
  ///
  /// In en, this message translates to:
  /// **'{period, select, all{No class tests yet.} day{No class tests today.} week{No class tests this week.} month{No class tests this month.} other{No class tests yet.}}'**
  String staffEmptyTests(String period);

  /// Empty tests body.
  ///
  /// In en, this message translates to:
  /// **'Tap New test to set one for a class you teach.'**
  String get staffEmptyTestsBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Show older tests'**
  String get staffShowOlderTests;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get staffDraft;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get staffPublished;

  /// Maximum marks.
  ///
  /// In en, this message translates to:
  /// **'out of {marks}'**
  String staffOutOf(String marks);

  /// A topic tick failed for want of signal.
  ///
  /// In en, this message translates to:
  /// **'No connection. \"{topic}\" was not changed.'**
  String staffTopicNotChanged(String topic);

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No topics in this syllabus yet.'**
  String get staffNoTopicsInSyllabus;

  /// Empty state body.
  ///
  /// In en, this message translates to:
  /// **'Your HOD or school office sets out the topics on the website.'**
  String get staffNoTopicsInSyllabusBody;

  /// Syllabus progress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} topics done · {percent}%'**
  String staffTopicsDone(int done, int total, String percent);

  /// Who ticked a topic off.
  ///
  /// In en, this message translates to:
  /// **'Done · {name}'**
  String staffDoneBy(String name);

  /// A saved draft was restored.
  ///
  /// In en, this message translates to:
  /// **'Your draft is back.'**
  String get staffDraftIsBack;

  /// After Same as last time.
  ///
  /// In en, this message translates to:
  /// **'Copied from {date}. Change what was different today.'**
  String staffCopiedFrom(String date);

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Sent again for review.'**
  String get staffSentAgainForReview;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Report filed.'**
  String get staffReportFiledDone;

  /// Refused by the server; reason is the server's.
  ///
  /// In en, this message translates to:
  /// **'Not sent: {reason}'**
  String staffNotSentReason(String reason);

  /// Names a report waiting on the phone.
  ///
  /// In en, this message translates to:
  /// **'{subject}, {classSection}, period {number}'**
  String staffOutboxReportLabel(
    String subject,
    String classSection,
    int number,
  );

  /// Confirmation without signal.
  ///
  /// In en, this message translates to:
  /// **'No signal: the report is saved on this phone and sent when there is.'**
  String get staffReportKeptForLater;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'This period already has a report for {date}. Pull down on Today to see it.'**
  String staffReportAlreadyFiled(String date);

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'No connection. Nothing was sent - try again when you have signal.'**
  String get staffNothingSentNoSignal;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'This period is no longer yours on the timetable, so it cannot be reported from here.'**
  String get staffPeriodNoLongerYours;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'This report is no longer waiting for changes - it may have been reviewed.'**
  String get staffReportNoLongerReturned;

  /// Refusal: not checked in.
  ///
  /// In en, this message translates to:
  /// **'Check in first. Your teaching reports open once you are marked present today. What you typed is kept on this phone as a draft.'**
  String get staffCheckInFirst;

  /// Button: copy the last report.
  ///
  /// In en, this message translates to:
  /// **'Same as {date}'**
  String staffSameAs(String date);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get staffTemplates;

  /// Title.
  ///
  /// In en, this message translates to:
  /// **'Teaching report'**
  String get staffTeachingReport;

  /// Title.
  ///
  /// In en, this message translates to:
  /// **'Change the report'**
  String get staffChangeTheReport;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Back to Today to check in'**
  String get staffBackToTodayToCheckIn;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'What was taught'**
  String get staffWhatWasTaught;

  /// Field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Fractions: adding unlike denominators'**
  String get staffWhatWasTaughtHint;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Say what was taught in this period.'**
  String get staffSayWhatWasTaught;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Homework (optional)'**
  String get staffHomeworkOptional;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Remarks (optional)'**
  String get staffRemarksOptional;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'File report'**
  String get staffFileReport;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get staffSendAgain;

  /// Syllabus failed to load.
  ///
  /// In en, this message translates to:
  /// **'The syllabus could not be loaded, so no topic can be ticked off with this report. You can tick it later under Teaching.'**
  String get staffSyllabusUnavailable;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Syllabus topic (optional)'**
  String get staffSyllabusTopicOptional;

  /// Field helper.
  ///
  /// In en, this message translates to:
  /// **'Picking one ticks it off for this class'**
  String get staffSyllabusTopicHelper;

  /// Dropdown option.
  ///
  /// In en, this message translates to:
  /// **'Not a syllabus topic'**
  String get staffNotASyllabusTopic;

  /// Sheet title.
  ///
  /// In en, this message translates to:
  /// **'{subject} templates'**
  String staffSubjectTemplates(String subject);

  /// Sheet hint.
  ///
  /// In en, this message translates to:
  /// **'Kept on this phone. Tap one to fill in the report.'**
  String get staffTemplatesHint;

  /// Empty templates.
  ///
  /// In en, this message translates to:
  /// **'None yet. Type a report you write often, then save it here.'**
  String get staffTemplatesEmpty;

  /// A template's homework.
  ///
  /// In en, this message translates to:
  /// **'Homework: {homework}'**
  String staffHomeworkLine(String homework);

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete this template'**
  String get staffDeleteTemplate;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save what is typed as a template'**
  String get staffSaveAsTemplate;

  /// Disabled button.
  ///
  /// In en, this message translates to:
  /// **'Type what was taught to save a template'**
  String get staffTypeToSaveTemplate;

  /// Fallback reviewer name.
  ///
  /// In en, this message translates to:
  /// **'your HOD'**
  String get staffYourHod;

  /// Who reviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed by {name}.'**
  String staffReviewedBy(String name);

  /// Who reviewed and when.
  ///
  /// In en, this message translates to:
  /// **'Reviewed by {name} on {date}.'**
  String staffReviewedByOn(String name, String date);

  /// Author of a report.
  ///
  /// In en, this message translates to:
  /// **'By {name}'**
  String staffByName(String name);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Syllabus topic ticked off'**
  String get staffSyllabusTopicTicked;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Homework'**
  String get staffHomework;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Remarks'**
  String get staffRemarks;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Sent back to the teacher.'**
  String get staffSentBackToTeacher;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'Somebody has already reviewed this report.'**
  String get staffAlreadyReviewed;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'This report is already back with its teacher.'**
  String get staffAlreadyBackWithTeacher;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'This report is not from your department, so it is not yours to send back.'**
  String get staffNotYoursToSendBack;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'No connection. It was not sent back - try again when you have signal.'**
  String get staffNotSentBackNoSignal;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Report reviewed.'**
  String get staffReportReviewedDone;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'This report is not from your department, so it is not yours to review.'**
  String get staffNotYoursToReview;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'No connection. It was not reviewed - try again when you have signal.'**
  String get staffNotReviewedNoSignal;

  /// Fallback teacher name.
  ///
  /// In en, this message translates to:
  /// **'the teacher'**
  String get staffTheTeacher;

  /// A returned report, to its HOD.
  ///
  /// In en, this message translates to:
  /// **'Sent back to {name}. It comes back to your list when they send it again - or mark it reviewed now if it was fine after all.'**
  String staffReturnedWaiting(String name);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Mark reviewed'**
  String get staffMarkReviewed;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Send back with a note'**
  String get staffSendBackWithNote;

  /// Note heading.
  ///
  /// In en, this message translates to:
  /// **'Sent back by {name}'**
  String staffSentBackBy(String name);

  /// Note heading.
  ///
  /// In en, this message translates to:
  /// **'Note from {name}'**
  String staffNoteFrom(String name);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Change and send again'**
  String get staffChangeAndSendAgain;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Say what should change.'**
  String get staffSayWhatShouldChange;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Send back to the teacher?'**
  String get staffSendBackToTeacherQ;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'What should change'**
  String get staffWhatShouldChange;

  /// Field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Please add what the class practised.'**
  String get staffWhatShouldChangeHint;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Send back'**
  String get staffSendBack;

  /// Sheet option.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get staffTakeAPhoto;

  /// Sheet option.
  ///
  /// In en, this message translates to:
  /// **'Choose from your photos'**
  String get staffChooseFromPhotos;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Photo added.'**
  String get staffPhotoAdded;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Remove this photo?'**
  String get staffRemovePhotoQ;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'It is taken off the report for good.'**
  String get staffRemovePhotoBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get staffRemove;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Photo removed.'**
  String get staffPhotoRemoved;

  /// Failure without signal.
  ///
  /// In en, this message translates to:
  /// **'No connection. Try again when you have signal.'**
  String get staffNoConnectionTryLater;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get staffPhotos;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get staffAdd;

  /// Photos hint.
  ///
  /// In en, this message translates to:
  /// **'Up to {max} - the board, or the children\'s work. Seen by your HOD and the office, never by parents.'**
  String staffReportPhotosHint(int max);

  /// Photo failed to decode.
  ///
  /// In en, this message translates to:
  /// **'This photo could not be shown.'**
  String get staffPhotoNotShown;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get staffRemovePhoto;

  /// Title.
  ///
  /// In en, this message translates to:
  /// **'New class test'**
  String get staffNewClassTest;

  /// Empty state body.
  ///
  /// In en, this message translates to:
  /// **'A test is set for a class you teach. Your school office puts you on the timetable.'**
  String get staffNewTestNoClassesBody;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'This school year has no terms yet.'**
  String get staffNoTermsYet;

  /// Empty state body.
  ///
  /// In en, this message translates to:
  /// **'A test belongs to a term. Ask your school office to set up the terms under Academics.'**
  String get staffNoTermsYetBody;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Out of how many marks?'**
  String get staffOutOfHowMany;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Enter a number, like 20 or 25.5.'**
  String get staffEnterANumber;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'The maximum has to be more than 0.'**
  String get staffMaxMoreThanZero;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'That is more than a test can carry.'**
  String get staffMaxTooBig;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Enter a number, or leave it blank.'**
  String get staffEnterNumberOrBlank;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Between 0 and the maximum.'**
  String get staffBetweenZeroAndMax;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'No term of this school year covers {date}. Pick another day.'**
  String staffNoTermCovers(String date);

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Test set. Enter the marks.'**
  String get staffTestSet;

  /// Failure without signal.
  ///
  /// In en, this message translates to:
  /// **'No connection. Nothing was saved - try again when you have signal.'**
  String get staffNothingSavedNoSignal;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Class and subject'**
  String get staffClassAndSubject;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get staffTitle;

  /// Field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Fractions - unit test'**
  String get staffTestTitleHint;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Give the test a title.'**
  String get staffGiveTestTitle;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Kind of test'**
  String get staffKindOfTest;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Day of the test'**
  String get staffDayOfTest;

  /// Field helper.
  ///
  /// In en, this message translates to:
  /// **'No term covers this day'**
  String get staffNoTermCoversDay;

  /// Field label: maximum marks.
  ///
  /// In en, this message translates to:
  /// **'Out of'**
  String get staffOutOfLabel;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Pass mark'**
  String get staffPassMark;

  /// Field helper.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get staffOptional;

  /// Field helper.
  ///
  /// In en, this message translates to:
  /// **'Optional. Blank: {percent}% of the maximum'**
  String staffPassMarkDefault(String percent);

  /// Grade scale note; scale name is the school's.
  ///
  /// In en, this message translates to:
  /// **'Grades by the {scale} scale.'**
  String staffGradesByScale(String scale);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Set test'**
  String get staffSetTest;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Not a number'**
  String get staffNotANumber;

  /// Maximum marks.
  ///
  /// In en, this message translates to:
  /// **'Out of {max}'**
  String staffOutOfMarks(String max);

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Marks saved.'**
  String get staffMarksSaved;

  /// Saved without signal.
  ///
  /// In en, this message translates to:
  /// **'No signal: these marks are saved on this phone and sent when there is. Publish once they are in.'**
  String get staffMarksKeptForLater;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'This test has been published, so its marks cannot change here.'**
  String get staffTestAlreadyPublished;

  /// Refusal.
  ///
  /// In en, this message translates to:
  /// **'Some marks were not accepted. See the highlighted students.'**
  String get staffSomeMarksRefused;

  /// Names marks waiting on the phone.
  ///
  /// In en, this message translates to:
  /// **'Marks: {title}'**
  String staffOutboxMarksLabel(String title);

  /// Publish blocked.
  ///
  /// In en, this message translates to:
  /// **'These marks are still waiting on this phone for signal. Publish once they are sent.'**
  String get staffMarksStillWaiting;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Publish the results?'**
  String get staffPublishResultsQ;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'The marks of {count} students become final, and their guardians are told, as your school has set it up. Only your HOD or the office can reopen it.'**
  String staffPublishFirstBody(int count);

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'The marks become final again. Guardians were told when it was first published, and are not messaged a second time.'**
  String get staffPublishAgainBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get staffPublish;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Results published.'**
  String get staffResultsPublished;

  /// Failure without signal.
  ///
  /// In en, this message translates to:
  /// **'No connection. Nothing was published - try again when you have signal.'**
  String get staffNothingPublishedNoSignal;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Leave without saving?'**
  String get staffLeaveWithoutSavingQ;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'The marks you typed since the last save will be lost.'**
  String get staffLeaveWithoutSavingBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Keep entering'**
  String get staffKeepEntering;

  /// Button that leaves the screen.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get staffLeaveScreen;

  /// Banner.
  ///
  /// In en, this message translates to:
  /// **'Published. The marks are final here; your HOD or the office can reopen the test.'**
  String get staffMarksPublishedBanner;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Nobody in this class to mark.'**
  String get staffNobodyToMark;

  /// Typing errors.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mark is not a number or is out of range. Fix it to save.} other{{count} marks are not numbers or are out of range. Fix them to save.}}'**
  String staffMarksFixFirst(int count);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save marks'**
  String get staffSaveMarks;

  /// Button when nothing changed.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get staffSaved;

  /// Progress.
  ///
  /// In en, this message translates to:
  /// **'{marked} of {total} marked'**
  String staffMarkedCount(int marked, int total);

  /// Pass mark.
  ///
  /// In en, this message translates to:
  /// **'pass {marks}'**
  String staffPassMarks(String marks);

  /// How many are left.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String staffLeft(int count);

  /// Roll number.
  ///
  /// In en, this message translates to:
  /// **'Roll {number}'**
  String staffRoll(String number);

  /// Below the pass mark.
  ///
  /// In en, this message translates to:
  /// **'Below pass'**
  String get staffBelowPass;

  /// Page title.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get staffMyProfile;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'The photo must be a JPEG or PNG image.'**
  String get staffPhotoMustBeImage;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'The photo must be 2 MB or smaller.'**
  String get staffPhotoTooBig;

  /// Failure.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be read. Try another file.'**
  String get staffPhotoUnreadable;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Photo updated.'**
  String get staffPhotoUpdated;

  /// Sheet option.
  ///
  /// In en, this message translates to:
  /// **'Choose from photos'**
  String get staffChooseFromPhotosShort;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Remove photo?'**
  String get staffRemovePhotoShortQ;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'Your initials will be shown instead.'**
  String get staffInitialsInstead;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get staffPhoto;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Upload photo'**
  String get staffUploadPhoto;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get staffChangePhoto;

  /// Validation; field is a field's label.
  ///
  /// In en, this message translates to:
  /// **'{field} is required'**
  String staffFieldRequired(String field);

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'{field} must be 100 characters or fewer'**
  String staffFieldMax100(String field);

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Profile updated.'**
  String get staffProfileUpdated;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'My details'**
  String get staffMyDetails;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get staffFirstName;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get staffLastName;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get staffMobile;

  /// Field helper.
  ///
  /// In en, this message translates to:
  /// **'You sign in with this number. Ask your school office to change it.'**
  String get staffMobileLockedHelper;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Home address'**
  String get staffHomeAddress;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Home address must be 500 characters or fewer'**
  String get staffHomeAddressTooLong;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get staffSave;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Email changed. Other devices have been signed out.'**
  String get staffEmailChanged;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Sign-in email'**
  String get staffSignInEmail;

  /// Empty value.
  ///
  /// In en, this message translates to:
  /// **'No email on record'**
  String get staffNoEmailOnRecord;

  /// Note.
  ///
  /// In en, this message translates to:
  /// **'You sign in with your mobile number and passcode. Your school office keeps your email address.'**
  String get staffEmailKeptBySchool;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get staffChangeEmail;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Work details'**
  String get staffWorkDetails;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Employee ID'**
  String get staffEmployeeId;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Designation'**
  String get staffDesignation;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Joining date'**
  String get staffJoiningDate;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'School'**
  String get staffSchool;

  /// Note.
  ///
  /// In en, this message translates to:
  /// **'These are kept by your school\'s administrators.'**
  String get staffKeptByAdmins;

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get staffSecurity;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get staffChangePassword;

  /// Button / dialog title.
  ///
  /// In en, this message translates to:
  /// **'Signed-in devices'**
  String get staffSignedInDevices;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Change sign-in email'**
  String get staffChangeSignInEmail;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'You sign in as {email}. Other devices will be signed out.'**
  String staffYouSignInAs(String email);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get staffNewEmail;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Enter the new email'**
  String get staffEnterNewEmail;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get staffEnterValidEmail;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get staffChangePasswordTitle;

  /// Dialog intro.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password for your account.'**
  String get staffChooseNewPassword;

  /// Confirmation; device is the server's label.
  ///
  /// In en, this message translates to:
  /// **'Signed out of {device}.'**
  String staffSignedOutOf(String device);

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Sign out of all other devices?'**
  String get staffSignOutOthersQ;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'Every other browser and phone signed in to this account will have to sign in again.'**
  String get staffSignOutOthersBody;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Sign out others'**
  String get staffSignOutOthers;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Signed out of 1 other device.} other{Signed out of {count} other devices.}}'**
  String staffSignedOutOthers(int count);

  /// Note.
  ///
  /// In en, this message translates to:
  /// **'A device is signed out after 7 days without use, and 30 days after signing in.'**
  String get staffSessionLifetime;

  /// Session line; when is the server's label.
  ///
  /// In en, this message translates to:
  /// **'Last used {when}'**
  String staffLastUsed(String when);

  /// Session line; when is the server's label.
  ///
  /// In en, this message translates to:
  /// **'Signed in {when}'**
  String staffSignedInAt(String when);

  /// Chip.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get staffThisDevice;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Sign out of all other devices'**
  String get staffSignOutAllOthers;

  /// Badge on the maintenance page.
  ///
  /// In en, this message translates to:
  /// **'Scheduled maintenance'**
  String get staffMaintenanceBadge;

  /// Headline.
  ///
  /// In en, this message translates to:
  /// **'We\'re making School365ai better.'**
  String get staffMaintenanceHeadline;

  /// Body.
  ///
  /// In en, this message translates to:
  /// **'The platform is briefly offline while we finish some planned work. Nothing has been lost - attendance, records and messages are all exactly where you left them, and will be there when we are back.'**
  String get staffMaintenanceBody;

  /// After a recheck.
  ///
  /// In en, this message translates to:
  /// **'Still offline as of a moment ago. We expect to be back shortly - if this is urgent, contact your school administrator.'**
  String get staffMaintenanceStillDown;

  /// Detail line.
  ///
  /// In en, this message translates to:
  /// **'We expect to be back shortly. If this is urgent, contact your school administrator.'**
  String get staffMaintenanceBackShortly;

  /// Search hint.
  ///
  /// In en, this message translates to:
  /// **'Name or admission number'**
  String get staffNameOrAdmission;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No students to show.'**
  String get staffNoStudentsToShow;

  /// Search found nobody.
  ///
  /// In en, this message translates to:
  /// **'No student you can see matches \"{query}\".'**
  String staffNoStudentMatches(String query);

  /// Admission number.
  ///
  /// In en, this message translates to:
  /// **'Adm. {number}'**
  String staffAdmissionShort(String number);

  /// Guardian name.
  ///
  /// In en, this message translates to:
  /// **'Guardian: {name}'**
  String staffGuardian(String name);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get staffCall;

  /// Sheet title.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s photo'**
  String staffStudentsPhoto(String name);

  /// Failure.
  ///
  /// In en, this message translates to:
  /// **'Could not open the phone\'s dialler.'**
  String get staffDiallerFailed;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'The photo must be 5 MB or smaller.'**
  String get staffStudentPhotoTooBig;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Photo saved.'**
  String get staffPhotoSaved;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s initials will be shown instead.'**
  String staffStudentInitialsInstead(String name);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get staffAddPhoto;

  /// Filter segment.
  ///
  /// In en, this message translates to:
  /// **'To call'**
  String get staffToCall;

  /// Filter segment.
  ///
  /// In en, this message translates to:
  /// **'Called'**
  String get staffCalled;

  /// Page heading.
  ///
  /// In en, this message translates to:
  /// **'Call Requests'**
  String get staffCallRequestsHeading;

  /// Intro.
  ///
  /// In en, this message translates to:
  /// **'Parents ask to be called from the Family app. Ring them on the number shown, then mark it called.'**
  String get staffCallRequestsIntro;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Nobody is waiting for a call.'**
  String get staffNobodyWaitingForCall;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No calls marked yet.'**
  String get staffNoCallsMarked;

  /// Which child a request is about.
  ///
  /// In en, this message translates to:
  /// **'about {name}'**
  String staffAboutStudentLower(String name);

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'To the office'**
  String get staffToTheOffice;

  /// Badge: who the request is for.
  ///
  /// In en, this message translates to:
  /// **'To {name}'**
  String staffToPerson(String name);

  /// Fallback name.
  ///
  /// In en, this message translates to:
  /// **'the class teacher'**
  String get staffTheClassTeacher;

  /// Parent's preferred time (as the parent wrote it).
  ///
  /// In en, this message translates to:
  /// **'Good time: {time}'**
  String staffGoodTime(String time);

  /// Who called back.
  ///
  /// In en, this message translates to:
  /// **'Called by {name}'**
  String staffCalledBy(String name);

  /// Fallback name.
  ///
  /// In en, this message translates to:
  /// **'the school'**
  String get staffTheSchool;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Mark as called'**
  String get staffMarkAsCalled;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Marked as called. The parent can see that.'**
  String get staffMarkedAsCalled;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Called {name}?'**
  String staffCalledPersonQ(String name);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'How did it go? (optional)'**
  String get staffHowDidItGo;

  /// Field helper.
  ///
  /// In en, this message translates to:
  /// **'Only the school sees this note.'**
  String get staffOnlySchoolSeesNote;

  /// Fees tab: take a payment.
  ///
  /// In en, this message translates to:
  /// **'Collect'**
  String get staffFeesCollect;

  /// Fees tab.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get staffFeesOverdue;

  /// Search hint.
  ///
  /// In en, this message translates to:
  /// **'Find a student by name or admission number'**
  String get staffFeesFindStudent;

  /// Hint.
  ///
  /// In en, this message translates to:
  /// **'Find the student paying. Their statement opens, with Record payment.'**
  String get staffFeesCollectHint;

  /// Search found nobody.
  ///
  /// In en, this message translates to:
  /// **'No student this year matches \"{query}\".'**
  String staffFeesNoMatch(String query);

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing collected yet today.'**
  String get staffFeesNothingToday;

  /// Count of today's receipts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 receipt today} other{{count} receipts today}}'**
  String staffReceiptsToday(int count);

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Nobody is overdue.'**
  String get staffFeesNobodyOverdue;

  /// Count of overdue students.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 student with fees overdue} other{{count} students with fees overdue}}'**
  String staffStudentsOverdue(int count);

  /// Overdue amount.
  ///
  /// In en, this message translates to:
  /// **'Overdue {amount}'**
  String staffOverdueAmount(String amount);

  /// Balance owed.
  ///
  /// In en, this message translates to:
  /// **'Owes {amount}'**
  String staffOwesAmount(String amount);

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Call {name}'**
  String staffCallPerson(String name);

  /// Fallback name.
  ///
  /// In en, this message translates to:
  /// **'the guardian'**
  String get staffTheGuardian;

  /// Back button on a student's fees.
  ///
  /// In en, this message translates to:
  /// **'All students'**
  String get staffAllStudents;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Statement PDF'**
  String get staffStatementPdf;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Add Discount'**
  String get staffAddDiscount;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get staffRecordPayment;

  /// Admission number.
  ///
  /// In en, this message translates to:
  /// **'Adm. no. {number}'**
  String staffAdmissionNo(String number);

  /// Admission date.
  ///
  /// In en, this message translates to:
  /// **'Joined {date}'**
  String staffJoined(String date);

  /// Fee total.
  ///
  /// In en, this message translates to:
  /// **'Charged'**
  String get staffFeeCharged;

  /// Fee total.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get staffFeeDiscount;

  /// Fee total / badge.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get staffFeePaid;

  /// Fee total / badge.
  ///
  /// In en, this message translates to:
  /// **'Waived'**
  String get staffFeeWaived;

  /// Fee total.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get staffFeeBalance;

  /// Empty statement.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been charged for {year}. Fees are charged once they are published for this student\'s class or bus route.'**
  String staffNothingCharged(String year);

  /// Section title.
  ///
  /// In en, this message translates to:
  /// **'Discounts'**
  String get staffDiscounts;

  /// Section title.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get staffPayments;

  /// Why a fee was not charged.
  ///
  /// In en, this message translates to:
  /// **'moved to another class'**
  String get staffReasonClassChanged;

  /// Why a fee was not charged.
  ///
  /// In en, this message translates to:
  /// **'moved to another bus route'**
  String get staffReasonRouteChanged;

  /// Why a fee was not charged.
  ///
  /// In en, this message translates to:
  /// **'no longer at the school'**
  String get staffReasonLeft;

  /// Why a fee was not charged.
  ///
  /// In en, this message translates to:
  /// **'the fee was changed'**
  String get staffReasonFeeChanged;

  /// Cancelled installment.
  ///
  /// In en, this message translates to:
  /// **'Was due {date} - not charged: {reason}'**
  String staffWasDueNotCharged(String date, String reason);

  /// Waived installment.
  ///
  /// In en, this message translates to:
  /// **'Was due {date} - waived'**
  String staffWasDueWaived(String date);

  /// Waived installment with reason.
  ///
  /// In en, this message translates to:
  /// **'Was due {date} - waived: {reason}'**
  String staffWasDueWaivedWhy(String date, String reason);

  /// Late fine date.
  ///
  /// In en, this message translates to:
  /// **'Added {date}'**
  String staffAddedOn(String date);

  /// Due date.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String staffDueOn(String date);

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get staffCancelled;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Covered by discount'**
  String get staffCoveredByDiscount;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Part paid'**
  String get staffPartPaid;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get staffFeeDue;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'Late fine'**
  String get staffLateFine;

  /// Amount.
  ///
  /// In en, this message translates to:
  /// **'Discount {amount}'**
  String staffDiscountAmount(String amount);

  /// Amount.
  ///
  /// In en, this message translates to:
  /// **'Paid {amount}'**
  String staffPaidAmount(String amount);

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Paid from the student\'s credit'**
  String get staffPaidFromCredit;

  /// Badge.
  ///
  /// In en, this message translates to:
  /// **'{amount} from credit'**
  String staffFromCredit(String amount);

  /// Amount.
  ///
  /// In en, this message translates to:
  /// **'Balance {amount}'**
  String staffBalanceAmount(String amount);

  /// Tooltip / button.
  ///
  /// In en, this message translates to:
  /// **'Waive'**
  String get staffWaive;

  /// A discount; head is the fee's name.
  ///
  /// In en, this message translates to:
  /// **'{amount} off each {head} installment'**
  String staffOffEachInstallment(String amount, String head);

  /// Fallback fee name.
  ///
  /// In en, this message translates to:
  /// **'fee'**
  String get staffFee;

  /// Who did it.
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String staffByLower(String name);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'End discount'**
  String get staffEndDiscount;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Download receipt'**
  String get staffDownloadReceipt;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel receipt'**
  String get staffCancelReceipt;

  /// Failure.
  ///
  /// In en, this message translates to:
  /// **'The receipt could not be downloaded. Try again.'**
  String get staffReceiptDownloadFailed;

  /// Failure.
  ///
  /// In en, this message translates to:
  /// **'The statement could not be downloaded. Try again.'**
  String get staffStatementDownloadFailed;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'The receipt is on its way to the guardian.'**
  String get staffReceiptEmailed;

  /// Failure.
  ///
  /// In en, this message translates to:
  /// **'The receipt could not be emailed. Try again.'**
  String get staffReceiptEmailFailed;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Receipt {number} cancelled. What it paid is owed again.'**
  String staffReceiptCancelled(String number);

  /// Failure.
  ///
  /// In en, this message translates to:
  /// **'The receipt could not be cancelled. Try again.'**
  String get staffReceiptCancelFailed;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Cancel receipt {number}?'**
  String staffCancelReceiptQ(String number);

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'The receipt stays on record, marked cancelled, and keeps its number. The installments it paid are owed again. This cannot be undone.'**
  String get staffCancelReceiptBody;

  /// Field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Cheque bounced'**
  String get staffCancelReceiptHint;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Say why the receipt is being cancelled.'**
  String get staffSayWhyCancel;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Keep receipt'**
  String get staffKeepReceipt;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Tick at least one installment, with an amount above zero.'**
  String get staffTickInstallment;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount above zero.'**
  String get staffEnterAmountAboveZero;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Record payment - {name}'**
  String staffRecordPaymentFor(String name);

  /// Dialog note.
  ///
  /// In en, this message translates to:
  /// **'Owes nothing for {year}. A payment now is held as credit for the next fees.'**
  String staffOwesNothingFor(String year);

  /// Dialog note.
  ///
  /// In en, this message translates to:
  /// **'Owes {amount} for {year}.'**
  String staffOwesFor(String amount, String year);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Date received'**
  String get staffDateReceived;

  /// Field label: payment mode.
  ///
  /// In en, this message translates to:
  /// **'Paid by'**
  String get staffPaidBy;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Cheque number'**
  String get staffChequeNumber;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Reference (optional)'**
  String get staffReferenceOptional;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Enter the cheque number.'**
  String get staffEnterChequeNumber;

  /// Switch title.
  ///
  /// In en, this message translates to:
  /// **'Choose the installments it pays'**
  String get staffChooseInstallments;

  /// Switch subtitle.
  ///
  /// In en, this message translates to:
  /// **'Off: it goes to what is owed, oldest first.'**
  String get staffChooseInstallmentsOff;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get staffNoteOptional;

  /// Checkbox.
  ///
  /// In en, this message translates to:
  /// **'Email the receipt to the guardian'**
  String get staffEmailReceiptToGuardian;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get staffRecordPaymentButton;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Amount received'**
  String get staffAmountReceived;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Pay everything owed'**
  String get staffPayEverythingOwed;

  /// Note.
  ///
  /// In en, this message translates to:
  /// **'{amount} more than is owed - it will be held as credit for the next fees.'**
  String staffMoreThanOwed(String amount);

  /// An installment.
  ///
  /// In en, this message translates to:
  /// **'Due {date} · owes {amount}'**
  String staffDueAndOwes(String date, String amount);

  /// Field label: amount paid to an installment.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get staffPay;

  /// Total being paid.
  ///
  /// In en, this message translates to:
  /// **'Paying {amount}'**
  String staffPaying(String amount);

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Receipt {number}'**
  String staffReceiptNumber(String number);

  /// Receipt summary.
  ///
  /// In en, this message translates to:
  /// **'{amount} received from {name} on {date} by {mode}.'**
  String staffReceivedFrom(
    String amount,
    String name,
    String date,
    String mode,
  );

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Owed before this payment'**
  String get staffOwedBefore;

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Paid now'**
  String get staffPaidNow;

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Held as credit for the next fees'**
  String get staffHeldAsCredit;

  /// Row.
  ///
  /// In en, this message translates to:
  /// **'Still owed'**
  String get staffStillOwed;

  /// Note.
  ///
  /// In en, this message translates to:
  /// **'The receipt is being emailed to the guardian.'**
  String get staffReceiptBeingEmailed;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get staffDownloadPdf;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get staffDone;

  /// Dialog title; label is the installment's.
  ///
  /// In en, this message translates to:
  /// **'Waive \"{label}\"?'**
  String staffWaiveQ(String label);

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'What is still owed on it is forgiven and it no longer counts as owing. Anything already paid stays paid. This cannot be undone.'**
  String get staffWaiveBody;

  /// Field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Hardship, fine charged in error'**
  String get staffWaiveHint;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" waived.'**
  String staffWaived(String label);

  /// Failure.
  ///
  /// In en, this message translates to:
  /// **'It could not be waived. Try again.'**
  String get staffWaiveFailed;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'End this discount?'**
  String get staffEndDiscountQ;

  /// Dialog body.
  ///
  /// In en, this message translates to:
  /// **'The installments it lowered that are still unpaid go back to their full amount. The discount stays on record as ended.'**
  String get staffEndDiscountBody;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Discount ended.'**
  String get staffDiscountEnded;

  /// Failure.
  ///
  /// In en, this message translates to:
  /// **'The discount could not be ended. Try again.'**
  String get staffDiscountEndFailed;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Discount added - 1 installment lowered.} other{Discount added - {count} installments lowered.}}'**
  String staffDiscountAdded(int count);

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Add discount - {name}'**
  String staffAddDiscountFor(String name);

  /// Dialog intro.
  ///
  /// In en, this message translates to:
  /// **'For {year}. It lowers each unpaid installment now, and any charged later this year. Late fines are never discounted.'**
  String staffDiscountIntro(String year);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Fee type'**
  String get staffFeeType;

  /// Dropdown option.
  ///
  /// In en, this message translates to:
  /// **'All fee types'**
  String get staffAllFeeTypes;

  /// Segment.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get staffFixedAmount;

  /// Segment / field label.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get staffPercentage;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String staffAmountIn(String currency);

  /// Field helper.
  ///
  /// In en, this message translates to:
  /// **'Off each installment.'**
  String get staffOffEach;

  /// Field helper.
  ///
  /// In en, this message translates to:
  /// **'Off each installment, not once for the year.'**
  String get staffOffEachNotOnce;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Enter a value above zero.'**
  String get staffEnterValueAboveZero;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'A percentage cannot be more than 100.'**
  String get staffPercentMax;

  /// Field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Sibling discount, scholarship, staff child'**
  String get staffDiscountReasonHint;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Say why the discount is given.'**
  String get staffSayWhyDiscount;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Add discount'**
  String get staffAddDiscountButton;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Give a reason.'**
  String get staffGiveAReason;

  /// Credit note.
  ///
  /// In en, this message translates to:
  /// **'In credit - it pays the next fees charged, oldest first.'**
  String get staffInCredit;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get staffHistory;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get staffRefund;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Credit history - {name}'**
  String staffCreditHistoryFor(String name);

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No credit has moved on this account yet.'**
  String get staffNoCreditMoved;

  /// Pagination.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {pages}'**
  String staffPageOf(int page, int pages);

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Newer'**
  String get staffNewer;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get staffOlder;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Refund of {amount} recorded.'**
  String staffRefundRecorded(String amount);

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Only {amount} is held in credit.'**
  String staffOnlyHeldInCredit(String amount);

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Refund credit - {name}'**
  String staffRefundCreditFor(String name);

  /// Dialog intro.
  ///
  /// In en, this message translates to:
  /// **'Holds {amount} in credit. Record money you have handed back to the family - it comes off the credit.'**
  String staffHoldsCredit(String amount);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get staffCurrency;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Amount refunded'**
  String get staffAmountRefunded;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Date refunded'**
  String get staffDateRefunded;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Paid back by'**
  String get staffPaidBackBy;

  /// Field hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Left the school'**
  String get staffRefundReasonHint;

  /// Validation.
  ///
  /// In en, this message translates to:
  /// **'Say why the money is refunded.'**
  String get staffSayWhyRefund;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Record refund'**
  String get staffRecordRefund;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Attendance updated.'**
  String get staffAttendanceUpdated;

  /// Confirmation.
  ///
  /// In en, this message translates to:
  /// **'Attendance submitted.'**
  String get staffAttendanceSubmitted;

  /// Dialog title; body is the server's.
  ///
  /// In en, this message translates to:
  /// **'On leave that day'**
  String get staffOnLeaveThatDay;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Mark present anyway'**
  String get staffMarkPresentAnyway;

  /// Icon button tooltip on the marks sheet: dictate marks.
  ///
  /// In en, this message translates to:
  /// **'Speak the marks'**
  String get staffMarksSpeak;

  /// Icon button tooltip on the marks sheet: read a photo of the marks list.
  ///
  /// In en, this message translates to:
  /// **'Read marks from a photo'**
  String get staffMarksFromPhoto;

  /// Shown while the phone listens for marks.
  ///
  /// In en, this message translates to:
  /// **'Listening. Say \"roll 12, 45\", or the marks in roll order.'**
  String get staffMarksListening;

  /// Button: stop listening for marks.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get staffMarksStopListening;

  /// Shown while the photo is read.
  ///
  /// In en, this message translates to:
  /// **'Reading the photo...'**
  String get staffMarksReadingPhoto;

  /// Problem.
  ///
  /// In en, this message translates to:
  /// **'This phone will not listen. Allow the microphone, or type the marks.'**
  String get staffMarksCannotListen;

  /// Problem.
  ///
  /// In en, this message translates to:
  /// **'No marks were heard. Try again, a little slower.'**
  String get staffMarksNothingHeard;

  /// Problem.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be read. Try again, or type the marks.'**
  String get staffMarksCannotReadPhoto;

  /// Problem.
  ///
  /// In en, this message translates to:
  /// **'No marks were found in the photo. Try a clearer photo in good light.'**
  String get staffMarksNothingInPhoto;

  /// Choice: camera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get staffMarksTakePhoto;

  /// Choice: the phone's photos.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get staffMarksChoosePhoto;

  /// Review dialog title.
  ///
  /// In en, this message translates to:
  /// **'Check the marks read'**
  String get staffMarksReviewTitle;

  /// Review dialog hint.
  ///
  /// In en, this message translates to:
  /// **'Nothing goes on the sheet until you confirm. Students left blank stay as they are.'**
  String get staffMarksReviewHint;

  /// Review dialog button: put the marks on the sheet.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get staffMarksReviewConfirm;

  /// Review dialog button: change nothing.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get staffMarksReviewCancel;

  /// Review row with nothing read.
  ///
  /// In en, this message translates to:
  /// **'Not read - stays as it is'**
  String get staffMarksNotRead;

  /// Review row: what was seen is not a mark.
  ///
  /// In en, this message translates to:
  /// **'Could not read \"{text}\"'**
  String staffMarksCouldNotRead(String text);

  /// Review row: the roll was read with no mark after it.
  ///
  /// In en, this message translates to:
  /// **'No mark read'**
  String get staffMarksNoMarkRead;

  /// Review section heading.
  ///
  /// In en, this message translates to:
  /// **'Not put on the sheet'**
  String get staffMarksNotPlaced;

  /// Review issue.
  ///
  /// In en, this message translates to:
  /// **'Roll {roll} is not on this sheet'**
  String staffMarksIssueUnknownRoll(String roll);

  /// Review issue.
  ///
  /// In en, this message translates to:
  /// **'More marks than students'**
  String get staffMarksIssueExtra;

  /// Review issue; trailing value is the earlier one.
  ///
  /// In en, this message translates to:
  /// **'Roll {roll} was read twice; the last one is kept'**
  String staffMarksIssueReadTwice(String roll);

  /// Review issue.
  ///
  /// In en, this message translates to:
  /// **'Could not read this'**
  String get staffMarksIssueUnreadable;

  /// Confirmation after the review.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mark put on the sheet. Check it, then save.} other{{count} marks put on the sheet. Check them, then save.}}'**
  String staffMarksFilled(int count);

  /// Tooltip: close a message.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get staffMarksDismiss;

  /// Title of the Staff app's home-screen widget.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get widgetToday;

  /// When the widget's card was true, e.g. 'as of 9:40 AM'.
  ///
  /// In en, this message translates to:
  /// **'as of {time}'**
  String widgetAsOf(String time);

  /// The widget while the app lock is on: no details.
  ///
  /// In en, this message translates to:
  /// **'Tap to open'**
  String get widgetTapToOpen;

  /// The widget when nobody is signed in.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see your day'**
  String get widgetSignIn;

  /// Staff widget on a closed day without a holiday name.
  ///
  /// In en, this message translates to:
  /// **'The school is closed today'**
  String get widgetSchoolClosed;

  /// Staff widget on a holiday.
  ///
  /// In en, this message translates to:
  /// **'Holiday: {name}'**
  String widgetHoliday(String name);

  /// Staff widget on a day of leave.
  ///
  /// In en, this message translates to:
  /// **'You are on leave today'**
  String get widgetOnLeave;

  /// The period under way.
  ///
  /// In en, this message translates to:
  /// **'Now: P{number} {subject} · {section}'**
  String widgetNowPeriod(int number, String subject, String section);

  /// The next period and when it starts.
  ///
  /// In en, this message translates to:
  /// **'Next: P{number} {subject} · {section} at {time}'**
  String widgetNextPeriod(
    int number,
    String subject,
    String section,
    String time,
  );

  /// A teacher with no periods today.
  ///
  /// In en, this message translates to:
  /// **'No periods today'**
  String get widgetNoPeriods;

  /// All of today's periods are over.
  ///
  /// In en, this message translates to:
  /// **'No more periods today'**
  String get widgetNoMorePeriods;

  /// The class teacher's register is done.
  ///
  /// In en, this message translates to:
  /// **'Register taken'**
  String get widgetRegisterTaken;

  /// One register still to take.
  ///
  /// In en, this message translates to:
  /// **'Register not taken: {section}'**
  String widgetRegisterNotTaken(String section);

  /// Several registers still to take.
  ///
  /// In en, this message translates to:
  /// **'{count} registers not taken'**
  String widgetRegistersNotTaken(int count);

  /// No teaching reports owed.
  ///
  /// In en, this message translates to:
  /// **'Reports up to date'**
  String get widgetReportsUpToDate;

  /// Teaching reports still owed today.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 report owed} other{{count} reports owed}}'**
  String widgetReportsOwed(int count);

  /// When the person checked in.
  ///
  /// In en, this message translates to:
  /// **'Checked in at {time}'**
  String widgetCheckedIn(String time);

  /// The person has not checked in.
  ///
  /// In en, this message translates to:
  /// **'Not checked in yet'**
  String get widgetNotCheckedIn;

  /// Family widget on a closed day.
  ///
  /// In en, this message translates to:
  /// **'No school today'**
  String get widgetNoSchool;

  /// Family widget on a holiday.
  ///
  /// In en, this message translates to:
  /// **'No school today: {name}'**
  String widgetNoSchoolHoliday(String name);

  /// The child's register today.
  ///
  /// In en, this message translates to:
  /// **'Today: {mark}'**
  String widgetAttendance(String mark);

  /// No description provided for @widgetMarkPresent.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get widgetMarkPresent;

  /// No description provided for @widgetMarkAbsent.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get widgetMarkAbsent;

  /// No description provided for @widgetMarkLeave.
  ///
  /// In en, this message translates to:
  /// **'On leave'**
  String get widgetMarkLeave;

  /// No description provided for @widgetMarkNotMarked.
  ///
  /// In en, this message translates to:
  /// **'Not marked yet'**
  String get widgetMarkNotMarked;

  /// Where the child's bus trip stood.
  ///
  /// In en, this message translates to:
  /// **'Bus: {status}'**
  String widgetBus(String status);

  /// Where the child's bus trip stood, and when.
  ///
  /// In en, this message translates to:
  /// **'Bus: {status}, {time}'**
  String widgetBusAt(String status, String time);

  /// Before the bus runs: the pick-up time.
  ///
  /// In en, this message translates to:
  /// **'Bus pick-up {time}'**
  String widgetBusPickup(String time);

  /// No description provided for @widgetTripCancelled.
  ///
  /// In en, this message translates to:
  /// **'Trip cancelled'**
  String get widgetTripCancelled;

  /// No description provided for @widgetReachedSchool.
  ///
  /// In en, this message translates to:
  /// **'Reached school'**
  String get widgetReachedSchool;

  /// No description provided for @widgetTripEnded.
  ///
  /// In en, this message translates to:
  /// **'Trip ended'**
  String get widgetTripEnded;

  /// No description provided for @widgetOnBusToSchool.
  ///
  /// In en, this message translates to:
  /// **'On the bus to school'**
  String get widgetOnBusToSchool;

  /// No description provided for @widgetOnBusHome.
  ///
  /// In en, this message translates to:
  /// **'On the bus home'**
  String get widgetOnBusHome;

  /// No description provided for @widgetDropped.
  ///
  /// In en, this message translates to:
  /// **'Dropped at the stop'**
  String get widgetDropped;

  /// No description provided for @widgetNoBus.
  ///
  /// In en, this message translates to:
  /// **'Did not take the bus'**
  String get widgetNoBus;

  /// No description provided for @widgetBusOnItsWay.
  ///
  /// In en, this message translates to:
  /// **'Bus on its way'**
  String get widgetBusOnItsWay;

  /// An overdue fee.
  ///
  /// In en, this message translates to:
  /// **'Fees: {amount} overdue'**
  String widgetFeesOverdue(String amount);

  /// The next fee and its due date.
  ///
  /// In en, this message translates to:
  /// **'Fees: {amount} due {date}'**
  String widgetFeesDue(String amount, String date);
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
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
