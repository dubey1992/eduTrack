// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get busNavHome => 'Home';

  @override
  String get busNavProfile => 'Profile';

  @override
  String get busMyTripTitle => 'My Trip';

  @override
  String get busLogOut => 'Log out';

  @override
  String get busNotCrewTitle => 'This app is for the bus crew';

  @override
  String get busNotCrewBody =>
      'Your account signs in to the school on the web instead. Ask your school admin if you should be driving a route.';

  @override
  String get busSignOut => 'Sign out';

  @override
  String get busSplashLoading => 'Getting your trips ready…';

  @override
  String get busSplashSlow => 'Still trying to reach your school.';

  @override
  String get busSplashCheckSignal => 'Check that this phone has signal, then try again.';

  @override
  String get busTryAgain => 'Try again';

  @override
  String get busLandingHeadline => 'Your trip sheet, on this phone.';

  @override
  String get busLandingIntro =>
      'For the driver and the attendant on the bus. Everything you need for the run, and nothing else from the school.';

  @override
  String get busLandingStartTitle => 'Start the run';

  @override
  String get busLandingStartBody =>
      'Today\'s routes are waiting when you open the app. One tap starts the pickup or the drop.';

  @override
  String get busLandingTickTitle => 'Tick each child on and off';

  @override
  String get busLandingTickBody => 'Boarded, dropped or absent. The school sees it, and the parents are told.';

  @override
  String get busLandingOfflineTitle => 'Works without signal';

  @override
  String get busLandingOfflineBody =>
      'Marks are kept on the phone and sent the moment you are back in range. Nothing is lost on the road.';

  @override
  String get busLandingCallTitle => 'Call a child\'s parent';

  @override
  String get busLandingCallBody =>
      'One button opens the dialler. You never see the number, and the call is recorded in the log.';

  @override
  String get busLandingNeedSignIn => 'To sign in you need';

  @override
  String get busLandingNeedSetUp => 'Before you start you need';

  @override
  String get busLandingNeedSignInBody => 'Your mobile number and the 4-digit passcode you chose on this phone.';

  @override
  String get busLandingNeedSetUpBody =>
      'Your mobile number, and an 8-digit code from your school office. The code works for 24 hours. You choose a 4-digit passcode while setting up, and after that the passcode is all you need.';

  @override
  String get busLandingSignIn => 'Sign in';

  @override
  String get busLandingSetUp => 'Set up this phone';

  @override
  String get busLandingLostPhone =>
      'Lost your phone, or forgotten the passcode? Your school office can unlock your account and give you a new code.';

  @override
  String get busRegisterTitle => 'Register this phone';

  @override
  String get busSignInTitle => 'Bus crew sign in';

  @override
  String get busRegisterHelp =>
      'Enter your mobile number, the 8-digit setup code from your school office, and choose a 4-digit passcode.';

  @override
  String get busSignInHelp => 'Enter your mobile number and your 4-digit passcode.';

  @override
  String get busMobileLabel => 'Mobile';

  @override
  String get busSetupCodeLabel => 'Setup code';

  @override
  String get busSetupCodeInvalid => 'Enter the 8-digit setup code from your office';

  @override
  String get busNewPasscodeLabel => 'New passcode';

  @override
  String get busConfirmPasscodeLabel => 'Confirm passcode';

  @override
  String get busPasscodesDiffer => 'The passcodes do not match';

  @override
  String get busPasscodeLabel => 'Passcode';

  @override
  String get busPasscodeInvalid => 'Enter your 4-digit passcode';

  @override
  String get busRegisterButton => 'Register and sign in';

  @override
  String get busSignInButton => 'Sign In';

  @override
  String get busUsePasscode => 'Already set up? Sign in with your passcode';

  @override
  String get busUseSetupCode => 'Have a new setup code? Register this phone again';

  @override
  String get busUseEmail => 'Sign in with email instead';

  @override
  String get busBatteryWarning => 'This phone may stop sending the bus\'s position when the screen is off.';

  @override
  String get busBatteryHowToFix => 'How to fix it';

  @override
  String get busNoRoutes => 'No route is assigned to you yet. Ask your school office to add you to a route.';

  @override
  String get busRoutesFromPhone => 'No signal - showing your routes as last saved on this phone.';

  @override
  String get busTripCheck => 'Trip check';

  @override
  String get busStartedOnPhone =>
      'No signal: the trip has started on this phone. Mark children as usual - the school gets it all when signal returns.';

  @override
  String get busRouteNotSaved =>
      'No signal, and this phone has not saved this route yet. Open My Trip once with signal; after that a trip can start without.';

  @override
  String busDriverName(String name) {
    return 'Driver: $name';
  }

  @override
  String busStopsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count stops', one: '1 stop');
    return '$_temp0';
  }

  @override
  String busStudentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count students', one: '1 student');
    return '$_temp0';
  }

  @override
  String busEndedAt(String riders, String time) {
    return '$riders · ended $time';
  }

  @override
  String busLicenceExpired(String date) {
    return 'Your driving licence expired on $date. Tell your school office.';
  }

  @override
  String get busLicenceToday => 'Your driving licence expires today. Tell your school office.';

  @override
  String get busLicenceTomorrow => 'Your driving licence expires tomorrow. Tell your school office.';

  @override
  String busLicenceInDays(int days, String date) {
    return 'Your driving licence expires in $days days, on $date. Tell your school office.';
  }

  @override
  String get busNotStarted => 'Not started';

  @override
  String get busEnRoute => 'En route';

  @override
  String get busCompleted => 'Completed';

  @override
  String get busCancelled => 'Cancelled';

  @override
  String get busPickup => 'Pickup';

  @override
  String get busDrop => 'Drop';

  @override
  String get busDropWaits => 'Starts after the pickup. The drop takes home the children the pickup brought in.';

  @override
  String get busStartPickup => 'Start pickup';

  @override
  String get busStartDrop => 'Start drop';

  @override
  String get busContinuePickup => 'Continue pickup';

  @override
  String get busContinueDrop => 'Continue drop';

  @override
  String get busViewTrip => 'View trip';

  @override
  String get busRunningLateQuestion => 'Running late?';

  @override
  String get busRunningLateHelp => 'The parents still waiting on this route are told.';

  @override
  String busLateMinutes(int minutes) {
    return 'About $minutes minutes late';
  }

  @override
  String busParentsToldLate(int minutes) {
    return 'Parents told: about $minutes minutes late.';
  }

  @override
  String get busNoDialler => 'Could not open the phone\'s dialler.';

  @override
  String get busNoMapsApp => 'Could not open a maps app on this phone.';

  @override
  String get busEndTripQuestion => 'End this trip?';

  @override
  String get busEndAllMarked => 'Every child has been marked. The trip will be recorded as completed.';

  @override
  String busEndUnmarked(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count children have', one: '1 child has');
    return '$_temp0 not been marked and will be recorded as absent.';
  }

  @override
  String get busEndTrip => 'End trip';

  @override
  String get busKeepGoing => 'Keep going';

  @override
  String get busTripEnded => 'Trip ended.';

  @override
  String get busMyRoutes => 'My routes';

  @override
  String get busStartedOnPhoneNoSignal =>
      'Started on this phone with no signal. The school sees this trip when signal returns.';

  @override
  String get busTripFromPhone => 'No signal - showing the trip as last saved on this phone.';

  @override
  String busSearchNoMatch(String query) {
    return 'No child on this trip matches \"$query\". Check the spelling, or clear the search.';
  }

  @override
  String get busOtherRiders => 'Other riders';

  @override
  String get busSchoolPlace => 'school';

  @override
  String busBulkDoneBoarded(int count, String place) {
    return '$count boarded at $place';
  }

  @override
  String busBulkDoneDropped(int count, String place) {
    return '$count dropped at $place';
  }

  @override
  String busBulkDoneOther(int count, String status, String place) {
    return '$count $status at $place';
  }

  @override
  String get busUndo => 'Undo';

  @override
  String get busUndoneAll => 'Taken back - nobody was marked.';

  @override
  String busUndonePartly(int count) {
    return 'Taken back: $count. The rest had already been sent to the school.';
  }

  @override
  String busBoardAllHere(int count) {
    return 'Board all $count here';
  }

  @override
  String busDropAllHere(int count) {
    return 'Drop all $count here';
  }

  @override
  String busBoardAllAtSchool(int count) {
    return 'Board all $count at school';
  }

  @override
  String busDropAllAtSchool(int count) {
    return 'Drop all $count at school';
  }

  @override
  String busMarkedBoarded(String name) {
    return '$name boarded';
  }

  @override
  String busMarkedDropped(String name) {
    return '$name dropped';
  }

  @override
  String busMarkedAbsent(String name) {
    return '$name absent';
  }

  @override
  String busMarkedPending(String name) {
    return '$name pending';
  }

  @override
  String busUndoneOne(String name) {
    return 'Taken back - $name is not marked.';
  }

  @override
  String get busUndoTooLate => 'Already sent to the school, so it stands. Ask the office to correct it.';

  @override
  String get busVoiceMute => 'Mute the spoken prompts';

  @override
  String get busVoiceSpeak => 'Speak the next stop';

  @override
  String busStillOnBoard(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count children are', one: '1 child is');
    return '$_temp0 still on board. Drop them off before ending the trip.';
  }

  @override
  String get busRunningLate => 'Running late';

  @override
  String busTripCounts(int boarded, int waiting, int dropped, int absent) {
    return '$boarded on board · $waiting waiting · $dropped dropped · $absent absent';
  }

  @override
  String busNavigateTo(String stop) {
    return 'Navigate to $stop';
  }

  @override
  String get busReached => 'Reached';

  @override
  String busBulkTitleBoard(String place) {
    return 'Board at $place';
  }

  @override
  String busBulkTitleDrop(String place) {
    return 'Drop at $place';
  }

  @override
  String get busUntickHelp => 'Untick anyone who is not here.';

  @override
  String busBulkConfirmBoard(int count) {
    return 'Board $count';
  }

  @override
  String busBulkConfirmDrop(int count) {
    return 'Drop $count';
  }

  @override
  String get busShareLocation => 'Share my location';

  @override
  String get busLocAsking => 'Asking for your location...';

  @override
  String get busLocOn => 'The school can see where the bus is while this screen is open.';

  @override
  String get busLocOff => 'Off - the school cannot see where the bus is.';

  @override
  String get busLocDenied => 'Location permission was not given, so your location is not being shared.';

  @override
  String get busLocBlocked =>
      'Location is blocked for this app. Allow it in the phone settings to share your location.';

  @override
  String get busLocServiceOff => 'Location is turned off on this phone. Turn it on to share your location.';

  @override
  String get busLocUnsupported => 'This device cannot share its location.';

  @override
  String get busLocTripEnded => 'The trip is no longer running, so location sharing has stopped.';

  @override
  String get busNotSent => 'Not sent';

  @override
  String get busNotSentHelpEnded =>
      'The school did not record these. Tell your school office, who can correct the trip.';

  @override
  String get busNotSentHelpRunning =>
      'The school did not record these. Try again if something has changed, or tell your school office, who can correct the trip.';

  @override
  String get busDismiss => 'Dismiss';

  @override
  String get busMicFailed => 'The microphone could not be used. Check the app\'s permission, or type the name.';

  @override
  String get busSearchListening => 'Listening… say the child\'s name';

  @override
  String get busSearchHint => 'Find a child by name, class or number';

  @override
  String get busClear => 'Clear';

  @override
  String get busStopListening => 'Stop listening';

  @override
  String get busSayName => 'Say the name';

  @override
  String get busStatusPending => 'Pending';

  @override
  String get busStatusBoarded => 'Boarded';

  @override
  String get busStatusDropped => 'Dropped';

  @override
  String get busStatusAbsent => 'Absent';

  @override
  String busMarkedBy(String status, String name) {
    return '$status by $name';
  }

  @override
  String get busCallParent => 'Call parent';

  @override
  String get busNoNumber => 'No number on record';

  @override
  String get busSosSent => 'SOS sent. Your school has been told where you are.';

  @override
  String get busSosSemantics => 'SOS. Hold for two seconds to ask your school for help.';

  @override
  String get busSosHolding => 'Keep holding...';

  @override
  String get busSosHold => 'Hold for SOS';

  @override
  String busMarksSending(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count marks', one: '1 mark');
    return 'Sending $_temp0...';
  }

  @override
  String busMarksOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count marks', one: '1 mark');
    return 'Offline - $_temp0 waiting to send';
  }

  @override
  String busMarksWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count marks', one: '1 mark');
    return '$_temp0 waiting to send';
  }

  @override
  String get busSendNow => 'Send now';

  @override
  String get busNavTermsRefused =>
      'Guidance inside this app needs Google\'s terms, which you did not accept. You can still use Google Maps.';

  @override
  String get busNavNoRoute => 'No route to this stop could be worked out. Check your signal, or try Google Maps.';

  @override
  String get busNavUnavailable =>
      'Guidance inside this app is not switched on for your school yet. Google Maps will take you there.';

  @override
  String get busOpenGoogleMaps => 'Open Google Maps';

  @override
  String get busBatteryTitle => 'Keep the bus on the map';

  @override
  String get busBatteryDone => 'Done. This phone will keep reporting with the screen off.';

  @override
  String get busBatteryNotChanged => 'Not changed. The steps below do the same thing by hand.';

  @override
  String get busBatteryWhy => 'Why the school sometimes loses the bus';

  @override
  String get busBatteryIntro =>
      'While a trip is running, this phone sends its position to the school so the office and parents can see where the bus is. Most phones stop apps they think you are not using - and a phone in a cradle with its screen off looks exactly like an app nobody is using.\n\nThese two settings tell the phone this one is different. You only have to do it once.';

  @override
  String get busBatteryStep1Title => 'Allow it to run in the background';

  @override
  String get busBatteryStep1Done => 'Already allowed on this phone.';

  @override
  String get busBatteryStep1Body => 'This is the setting Android itself controls, and the button below opens it.';

  @override
  String get busBatteryAllow => 'Allow';

  @override
  String get busBatteryStep2Title => 'Turn off your phone maker\'s battery saver for this app';

  @override
  String get busBatteryStep2Body =>
      'This one is not the same on every phone, and no app can change it for you. Find your make below.';

  @override
  String get busBatteryNotSure =>
      'If you are not sure which make your phone is, show this screen to your school office.';

  @override
  String get busMakeXiaomi => 'Xiaomi, Redmi or POCO';

  @override
  String get busMakeXiaomi1 => 'Settings > Apps > Manage apps > School365ai Driver > Battery saver > No restrictions.';

  @override
  String get busMakeXiaomi2 => 'On the same screen, turn on Autostart.';

  @override
  String get busMakeXiaomi3 =>
      'Open Recent apps, swipe down on this app\'s card and tap the padlock so it is not cleared.';

  @override
  String get busMakeOppo => 'Oppo, Realme or OnePlus';

  @override
  String get busMakeOppo1 => 'Settings > Battery > Power saving > App battery usage (or App battery management).';

  @override
  String get busMakeOppo2 => 'Find School365ai Driver and choose Allow background activity, or Don\'t optimise.';

  @override
  String get busMakeOppo3 => 'Turn on Allow auto launch for this app.';

  @override
  String get busMakeVivo => 'Vivo or iQOO';

  @override
  String get busMakeVivo1 =>
      'Settings > Battery > Background power consumption management > School365ai Driver > Allow high background power consumption.';

  @override
  String get busMakeVivo2 => 'Settings > Apps > Autostart, and turn it on for this app.';

  @override
  String get busMakeSamsung => 'Samsung';

  @override
  String get busMakeSamsung1 => 'Settings > Apps > School365ai Driver > Battery > Unrestricted.';

  @override
  String get busMakeSamsung2 =>
      'Settings > Battery > Background usage limits, and make sure this app is not in Sleeping apps or Deep sleeping apps.';

  @override
  String get busMakeOther => 'Any other phone';

  @override
  String get busMakeOther1 =>
      'Settings > Apps > School365ai Driver > Battery, and choose the least restricted option offered.';

  @override
  String get busMakeOther2 => 'If there is an Autostart or Auto launch setting, turn it on.';

  @override
  String get busTripLogUnreadable => 'The trip log could not be read.';

  @override
  String get busTripCheckNone =>
      'No trip has shared its location on this phone yet. Run a trip with \"Share my location\" on, then come back here.';

  @override
  String get busShareReport => 'Share report';

  @override
  String get busClearLog => 'Clear the log';

  @override
  String get busBatteryExempt => 'Battery saving will not stop this app';

  @override
  String get busBatteryMayStop => 'Battery saving may stop this app';

  @override
  String get busBatteryChecking => 'Checking battery settings...';

  @override
  String get busBatteryOwnSetting => 'Some phones have their own setting as well - see the phone\'s battery steps.';

  @override
  String get busSteps => 'Steps';

  @override
  String get busLastTrip => 'Last trip';

  @override
  String get busPositionsTaken => 'Positions taken';

  @override
  String get busLongestGap => 'Longest gap between positions';

  @override
  String get busSentToSchool => 'Sent to the school';

  @override
  String get busStillWaiting => 'Still waiting on this phone';

  @override
  String get busRefused => 'Refused by the server';

  @override
  String get busDroppedAfterEnd => 'Dropped after the trip ended';

  @override
  String get busBackgrounded => 'Times the app went to the background';

  @override
  String busGapVerdict(String gap, String time) {
    return 'A gap of $gap from $time: the phone most likely paused the app. Follow the battery steps for this phone and run a trip again.';
  }

  @override
  String get busNoGapVerdict => 'No long gaps: the phone kept sharing the whole way.';

  @override
  String busSharingStopped(String reason) {
    return 'Sharing stopped: $reason';
  }

  @override
  String get languageTitle => 'Language';

  @override
  String get languagePhone => 'Phone\'s language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageChanged => 'Language changed.';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get errorNoConnection => 'Could not reach the server. Check your connection and try again.';

  @override
  String get errorTimeout => 'The server is taking longer than usual to answer. Try again in a moment.';

  @override
  String get errorUnknown => 'Something went wrong. Please try again.';

  @override
  String get coreLogOutTitle => 'Log out?';

  @override
  String get coreLogOutMessage => 'You will need to sign in again to get back to your school.';

  @override
  String coreLogOutUnsent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count marks have not been sent yet. Sign out anyway? They will be lost.',
      one: '1 mark has not been sent yet. Sign out anyway? They will be lost.',
    );
    return '$_temp0';
  }

  @override
  String get coreLogOut => 'Log out';

  @override
  String get coreStaySignedIn => 'Stay signed in';

  @override
  String get coreLockedTitle => 'School365ai is locked';

  @override
  String get coreLockedHint => 'Use your fingerprint, face or phone\'s screen lock to open it.';

  @override
  String get coreNotUnlocked => 'Not unlocked. Try again.';

  @override
  String get coreUnlock => 'Unlock';

  @override
  String get coreLockOfferTitle => 'Lock the app with your fingerprint?';

  @override
  String get coreLockOfferBody =>
      'Anyone who picks up this phone would need your fingerprint, face or screen lock to open School365ai. You can change this later.';

  @override
  String get coreNotNow => 'Not now';

  @override
  String get coreTurnOn => 'Turn on';

  @override
  String get coreAppLock => 'App lock';

  @override
  String get coreAppLockHint =>
      'Ask for your fingerprint, face or screen lock when the app opens, and after 5 minutes away';

  @override
  String get coreShowPassword => 'Show password';

  @override
  String get coreHidePassword => 'Hide password';

  @override
  String corePasscodeDigits(int length) {
    return 'The passcode must be exactly $length digits.';
  }

  @override
  String get corePasscodeRepeated => 'Choose a passcode that is not one digit repeated.';

  @override
  String corePasscodeRun(String example) {
    return 'Choose a passcode that is not a straight run like $example.';
  }

  @override
  String get familyMarkPresent => 'Present';

  @override
  String get familyMarkAbsent => 'Absent';

  @override
  String get familyMarkLeave => 'On leave';

  @override
  String get familyMarkNotMarked => 'Not marked yet';

  @override
  String get familyFeeStatusPaid => 'Paid';

  @override
  String get familyFeeStatusPartPaid => 'Part paid';

  @override
  String get familyFeeStatusDue => 'Due';

  @override
  String get familyFeeStatusOverdue => 'Overdue';

  @override
  String get familyFeeStatusWaived => 'Waived';

  @override
  String get familyPayModeCash => 'Cash';

  @override
  String get familyPayModeBankTransfer => 'Bank transfer';

  @override
  String get familyPayModeCheque => 'Cheque';

  @override
  String get familyPayModeCard => 'Card';

  @override
  String get familyPayModeOnlineTransfer => 'Online transfer';

  @override
  String get familyInviteApproved => 'Approved - the school will give them a set-up letter';

  @override
  String get familyInviteDeclined => 'Declined by the school';

  @override
  String get familyInviteWaiting => 'Waiting for the school';

  @override
  String get familyRelationMother => 'Mother';

  @override
  String get familyRelationFather => 'Father';

  @override
  String get familyRelationGuardian => 'Guardian';

  @override
  String get familyRelationOther => 'Other';

  @override
  String get familyTripCancelled => 'Trip cancelled';

  @override
  String get familyTripReachedSchool => 'Reached school';

  @override
  String get familyTripEnded => 'Trip ended';

  @override
  String get familyTripOnBusToSchool => 'On the bus to school';

  @override
  String get familyTripOnBusHome => 'On the bus home';

  @override
  String get familyTripDroppedAtStop => 'Dropped at the stop';

  @override
  String get familyTripNotTaken => 'Did not take the bus';

  @override
  String get familyTripOnItsWay => 'Bus on its way';

  @override
  String familyMarkedBy(String who) {
    return 'Marked by $who';
  }

  @override
  String familyMarkedByAt(String who, String stop) {
    return 'Marked by $who at $stop';
  }

  @override
  String get familyKindAttendance => 'Attendance';

  @override
  String get familyKindBus => 'School bus';

  @override
  String get familyKindFees => 'Fees';

  @override
  String get familyKindResults => 'Results';

  @override
  String get familyKindEmergency => 'Emergency';

  @override
  String get familyKindNotice => 'Notice';

  @override
  String get familyKindMessage => 'Message from school';

  @override
  String get familyTabHome => 'Home';

  @override
  String get familyTabAttendance => 'Attendance';

  @override
  String get familyTabBus => 'Bus';

  @override
  String get familyTabFees => 'Fees';

  @override
  String get familyTabMore => 'More';

  @override
  String familyNewNoticesCount(int count) {
    return '$count new notices';
  }

  @override
  String get familyNotices => 'Notices';

  @override
  String familyChildrenCount(int count) {
    return '$count children';
  }

  @override
  String get familySwitch => 'Switch';

  @override
  String get familyWhoseDay => 'Whose day?';

  @override
  String get familyNoConnection => 'No connection';

  @override
  String get familyCouldNotLoad => 'Could not load this';

  @override
  String get familyTryAgain => 'Try again';

  @override
  String get familyHowWorkedOut => 'How is this worked out?';

  @override
  String familyShowingSavedAt(String when) {
    return 'No connection. Showing what was true at $when.';
  }

  @override
  String get familyNoChildrenTitle => 'No children to show';

  @override
  String get familyNoChildrenMessage =>
      'The school has no child linked to your number at the moment. Please contact the school office.';

  @override
  String get familyGoodMorning => 'Good morning';

  @override
  String get familyGoodAfternoon => 'Good afternoon';

  @override
  String get familyGoodEvening => 'Good evening';

  @override
  String familyUpdatedAt(String time) {
    return 'Updated $time';
  }

  @override
  String get familyNoSchoolToday => 'No school today';

  @override
  String get familySchoolClosedToday => 'The school is closed today.';

  @override
  String familyChildInSchool(String name) {
    return '$name is in school';
  }

  @override
  String familyChildMarkedAbsent(String name) {
    return '$name was marked absent';
  }

  @override
  String familyChildOnLeave(String name) {
    return '$name is on leave today';
  }

  @override
  String get familyRegisterNotMarked => 'Register not marked yet';

  @override
  String get familyAttendanceToday => 'Attendance today';

  @override
  String get familyTeacherMarksMorning => 'The class teacher marks it in the morning.';

  @override
  String familyNote(String text) {
    return 'Note: $text';
  }

  @override
  String get familyTellSchoolWhy => 'Tell the school why';

  @override
  String get familyReportSick => 'Report sick';

  @override
  String get familySchoolBus => 'School bus';

  @override
  String get familyNoTripToday => 'No trip has started today';

  @override
  String familyPickupAt(String time) {
    return 'pick-up $time';
  }

  @override
  String get familyTapToWatchBus => 'Tap to watch the bus on the map';

  @override
  String get familyResults => 'Results';

  @override
  String get familyResultsCardLine => 'Test marks and the progress report';

  @override
  String get familyNextFee => 'Next fee';

  @override
  String familyFeeWasDueOn(String label, String date) {
    return '$label · was due on $date';
  }

  @override
  String familyFeeDueOn(String label, String date) {
    return '$label · due on $date';
  }

  @override
  String get familyFromTheSchool => 'From the school';

  @override
  String familyNewCount(int count) {
    return '$count new';
  }

  @override
  String get familyNoMessagesYet => 'No messages yet.';

  @override
  String get familyTodaysClasses => 'Today\'s classes';

  @override
  String familyPeriodNumber(String number) {
    return 'Period $number';
  }

  @override
  String get familyNow => 'Now';

  @override
  String familyTrendRisingLabel(int count, int first, int last) {
    return 'Marks over $count tests, from $first% to $last%, rising';
  }

  @override
  String familyTrendFallingLabel(int count, int first, int last) {
    return 'Marks over $count tests, from $first% to $last%, falling';
  }

  @override
  String familyTrendLine(int count, int first, int last) {
    return '$first% to $last% over $count tests';
  }

  @override
  String get familyPreviousMonth => 'Previous month';

  @override
  String get familyNextMonth => 'Next month';

  @override
  String familyBelowLine(String rate, String days, String line, String name) {
    return 'Attendance is $rate% over the last $days school days, below the school\'s $line% line. The class teacher can help if something is keeping $name away.';
  }

  @override
  String get familyTellAboutAbsence => 'Tell the school about an absence';

  @override
  String get familyNotesSent => 'Notes sent';

  @override
  String get familyThisSchoolYear => 'This school year';

  @override
  String get familyWhyAttendance =>
      'Days present out of the days the class register was marked. A day on leave counts as not present; a day the school did not mark the register, and a holiday, are left out.';

  @override
  String get familyNoRegisterYet => 'No register marked yet.';

  @override
  String familyPresentOfDays(String present, String days) {
    return 'Present $present of $days days';
  }

  @override
  String familyAbsentPart(int count) {
    return ' · absent $count';
  }

  @override
  String familyLeavePart(int count) {
    return ' · leave $count';
  }

  @override
  String familyDaysNotMarked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count school days not marked by the school',
      one: '1 school day not marked by the school',
    );
    return '$_temp0';
  }

  @override
  String get familyWeekdayInitials => 'M T W T F S S';

  @override
  String get familyLeave => 'Leave';

  @override
  String get familyHoliday => 'Holiday';

  @override
  String get familyDayPresent => 'present';

  @override
  String get familyDayAbsent => 'absent';

  @override
  String get familyDayOnLeave => 'on leave';

  @override
  String get familyDayHoliday => 'holiday';

  @override
  String get familyDayNoSchool => 'no school';

  @override
  String get familyDayNotMarked => 'not marked';

  @override
  String get familyDaysMissed => 'Days missed';

  @override
  String get familyNoneThisMonth => 'None this month.';

  @override
  String get familyNoReasonNoted => 'No reason noted.';

  @override
  String get familyNotOnBus => 'Not on a school bus';

  @override
  String get familyNotOnBusMessage => 'If your child should be, the school office can add them to a route.';

  @override
  String get familyBusOnWayToSchool => 'The bus is on its way to school';

  @override
  String get familyBusOnWayHome => 'The bus is on its way home';

  @override
  String get familyTrackOnMap => 'Track it on the map';

  @override
  String get familyRouteAndStop => 'Route and stop';

  @override
  String get familyPickup => 'Pick-up';

  @override
  String get familyDrop => 'Drop';

  @override
  String get familyYourStop => 'your stop';

  @override
  String get familyNotStartedYet => 'Not started yet';

  @override
  String get familyTripWasCancelled => 'This trip was cancelled. The school will be in touch.';

  @override
  String familyNotOnTripList(String name) {
    return '$name is not on this trip\'s list today.';
  }

  @override
  String get familyBusSetOff => 'The bus set off';

  @override
  String familyReachedStop(String stop) {
    return 'Reached $stop';
  }

  @override
  String get familyBusLeftSchool => 'The bus left school';

  @override
  String familyChildGotOff(String name) {
    return '$name got off';
  }

  @override
  String familyChildBoarded(String name) {
    return '$name boarded';
  }

  @override
  String get familyDidNotBoard => 'Did not board';

  @override
  String get familyTripHome => 'Home';

  @override
  String get familyTripToSchool => 'To school';

  @override
  String get familyCall => 'Call';

  @override
  String get familyBusQuestions => 'Questions about the bus';

  @override
  String get familyBusAttendant => 'Bus attendant';

  @override
  String get familyTransportOffice => 'Transport office';

  @override
  String get familySchoolOffice => 'The school office';

  @override
  String get familyYourChild => 'your child';

  @override
  String familyBusNotOnRoadFor(String name) {
    return 'The bus isn\'t on the road for $name now';
  }

  @override
  String get familyBusFollowDuringTrip => 'You can follow it during their trip - on the way to school or home.';

  @override
  String get familyWhereIsBus => 'Where is the bus?';

  @override
  String get familyTheBus => 'The bus';

  @override
  String get familyBusOnRoad => 'The bus is on the road';

  @override
  String familyBusHasBeenTo(String stop) {
    return 'The bus has been to $stop';
  }

  @override
  String familyBusHasReached(String stop) {
    return 'The bus has reached $stop';
  }

  @override
  String familyOnWayTo(String stop) {
    return 'On its way to $stop';
  }

  @override
  String familyAboutTime(String time) {
    return 'about $time';
  }

  @override
  String familyDistanceAway(String distance) {
    return '$distance away';
  }

  @override
  String familyStopsBeforeYours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops before yours',
      one: '1 stop before yours',
    );
    return '$_temp0';
  }

  @override
  String familyMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count minutes', one: '1 minute');
    return '$_temp0';
  }

  @override
  String get familyWaitingForBusLocation => 'Waiting for the bus to share where it is.';

  @override
  String familyLastSeenAgo(String time) {
    return 'Last seen $time ago - the bus may be out of signal.';
  }

  @override
  String get familyOfflineLastUpdate => 'No connection - showing the last update.';

  @override
  String get familyNoFeesYet => 'No fees set yet';

  @override
  String get familyNoFeesYetMessage => 'When the school sets this year\'s fees, they appear here.';

  @override
  String get familyInstalments => 'Instalments';

  @override
  String get familyReceipts => 'Receipts';

  @override
  String get familyNoReceiptsYet =>
      'No payments this year yet. A receipt appears here as soon as the office records one.';

  @override
  String get familyThisYear => 'This year';

  @override
  String familyFeesFor(String year) {
    return 'Fees for $year';
  }

  @override
  String get familyAllPaid => 'All paid';

  @override
  String get familyLeftToPay => 'Left to pay';

  @override
  String familyOfItOverdue(String amount) {
    return '$amount of it is overdue';
  }

  @override
  String get familyCharged => 'Charged';

  @override
  String get familyDiscount => 'Discount';

  @override
  String get familyCreditHeld => 'Credit held';

  @override
  String get familyWhyFees =>
      'Left to pay is this year\'s fees, less any discount, less what the school has recorded as paid, less any instalment the school has waived. Overdue is the part of it from instalments whose due date has passed.';

  @override
  String get familyUpiOpened => 'Once you have paid, the school records it and the receipt appears here.';

  @override
  String get familyUpiNotOpened =>
      'No UPI app opened on this phone. Copy the UPI ID and pay from your bank\'s app instead.';

  @override
  String familyCopied(String what) {
    return '$what copied';
  }

  @override
  String get familyHowToPay => 'How to pay';

  @override
  String get familyPaySchoolDirectly => 'Pay the school directly. This app shows your fees; it does not take payments.';

  @override
  String familyPayWithUpi(String amount) {
    return 'Pay $amount with any UPI app';
  }

  @override
  String get familyUpiExplain =>
      'Opens GPay, PhonePe, Paytm or your bank\'s app with the amount and your child\'s name filled in. The school records the payment when it reaches them.';

  @override
  String get familyFeeCounter => 'Fee counter';

  @override
  String get familyCopyUpiId => 'Copy the UPI ID';

  @override
  String get familyUpiId => 'UPI ID';

  @override
  String get familyCopyBankDetails => 'Copy the bank details';

  @override
  String get familyBankDetails => 'Bank details';

  @override
  String get familyFeeQuestions => 'Questions about fees';

  @override
  String get familyCallSchoolOffice => 'Call the school office';

  @override
  String familyWasDueDate(String date) {
    return 'Was due $date';
  }

  @override
  String familyDueDate(String date) {
    return 'Due $date';
  }

  @override
  String familyPaidOf(String paid, String total) {
    return '$paid paid of $total';
  }

  @override
  String get familyCancelledByOffice => 'Cancelled by the office';

  @override
  String get familyOpenReceipt => 'Open the receipt';

  @override
  String get familyYearStatement => 'The year\'s statement (PDF)';

  @override
  String familyStatementFor(String year) {
    return 'Statement for $year (PDF)';
  }

  @override
  String get familyNoTermsYet => 'No terms yet';

  @override
  String get familyNoTermsYetMessage => 'Results appear here once the school sets up its terms.';

  @override
  String get familyFromClassTeacher => 'From the class teacher';

  @override
  String get familyNoResultsThisTerm => 'No results yet this term';

  @override
  String get familyNoResultsThisTermMessage => 'A test appears here once the teacher publishes its marks.';

  @override
  String get familyWhyResults =>
      'Each subject\'s figure is the average of its published test marks this term, as percentages - weighted when the school gave every test a weight. A test the child missed is left out. The grade comes from the school\'s own grading scale.';

  @override
  String familyProgressReport(String term) {
    return '$term progress report';
  }

  @override
  String get familyReportOpenSaveShare => 'Open it, save it or share it.';

  @override
  String get familyReportReadyTermEnds => 'Ready when the term ends.';

  @override
  String familyReportReadyOn(String date) {
    return 'Ready when the term ends, on $date.';
  }

  @override
  String get familyGetPdf => 'Get PDF';

  @override
  String familyTestsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count tests', one: '1 test');
    return '$_temp0';
  }

  @override
  String familyClassPercent(String percent) {
    return 'class $percent%';
  }

  @override
  String familyGrade(String grade) {
    return 'Grade $grade';
  }

  @override
  String familyClassAverage(String percent) {
    return 'class average $percent%';
  }

  @override
  String get familyTimetable => 'Timetable';

  @override
  String get familyNoTimetableYet => 'No timetable yet';

  @override
  String get familyNoTimetableYetMessage => 'The class\'s timetable appears here once the school sets it.';

  @override
  String familyDayToday(String day) {
    return '$day · today';
  }

  @override
  String familyWeekdayShort(String day) {
    String _temp0 = intl.Intl.selectLogic(day, {
      'monday': 'Mon',
      'tuesday': 'Tue',
      'wednesday': 'Wed',
      'thursday': 'Thu',
      'friday': 'Fri',
      'saturday': 'Sat',
      'sunday': 'Sun',
      'other': '$day',
    });
    return '$_temp0';
  }

  @override
  String familyWeekday(String day) {
    String _temp0 = intl.Intl.selectLogic(day, {
      'monday': 'Monday',
      'tuesday': 'Tuesday',
      'wednesday': 'Wednesday',
      'thursday': 'Thursday',
      'friday': 'Friday',
      'saturday': 'Saturday',
      'sunday': 'Sunday',
      'other': '$day',
    });
    return '$_temp0';
  }

  @override
  String get familyFreePeriod => 'Free period';

  @override
  String familyHalfDay(String day) {
    return '$day is a half day.';
  }

  @override
  String familyNoClassesOn(String day) {
    return 'No classes on $day.';
  }

  @override
  String get familySyllabus => 'Syllabus';

  @override
  String get familyNoSyllabusYet => 'No syllabus yet';

  @override
  String get familyNoSyllabusYetMessage => 'What the class will cover appears here once the school adds it.';

  @override
  String get familyHomework => 'Homework';

  @override
  String get familyNoHomework => 'No homework in the last two weeks';

  @override
  String get familyNoHomeworkMessage => 'When a teacher sets homework for the class, it appears here that day.';

  @override
  String familyTodayDash(String date) {
    return 'Today - $date';
  }

  @override
  String get familyNoTopicsYet => 'No topics added yet.';

  @override
  String familyTopicsCovered(String covered, String total) {
    return '$covered of $total topics covered';
  }

  @override
  String familyComingUp(String topics) {
    return 'Coming up: $topics';
  }

  @override
  String get familyAbsenceNotes => 'Absence notes';

  @override
  String get familyAbsenceNotesSub => 'Tell the school your child will be away';

  @override
  String get familyAddGuardian => 'Add a guardian';

  @override
  String get familyAddGuardianSub => 'Ask the school to add the other parent, or a relative';

  @override
  String get familyAskToCall => 'Ask the school to call you';

  @override
  String get familyAskToCallSub => 'The class teacher or the office rings you back';

  @override
  String get familyAdmitCards => 'Admit cards';

  @override
  String get familyAdmitCardsSub => 'Exam date sheets to download and print';

  @override
  String get familyTimetableSub => 'The class\'s week';

  @override
  String get familySyllabusSub => 'How far each subject has got';

  @override
  String get familyHomeworkSub => 'What the teachers set, day by day';

  @override
  String get familyNoticesSub => 'Messages from the school';

  @override
  String get familySchoolCalendar => 'School calendar';

  @override
  String get familySchoolCalendarSub => 'Holidays and closed days';

  @override
  String get familyNotifications => 'Notifications';

  @override
  String get familyNotificationsSub => 'Choose what comes to this app';

  @override
  String get familyYourPrivacy => 'Your privacy';

  @override
  String get familyYourPrivacySub => 'Who sees your number, and the bus on the map';

  @override
  String get familySignOut => 'Sign out';

  @override
  String get familySignOutSub => 'This phone stays set up; sign in again with your passcode';

  @override
  String get familySignOutQuestion => 'Sign out?';

  @override
  String get familySignOutMessage => 'You will need your passcode to sign in again.';

  @override
  String get familyCouldNotOpen => 'This phone could not open that. Please try another way.';

  @override
  String get familyContactSchool => 'Contact the school';

  @override
  String get familyNoContactDetails => 'The school has not added its contact details yet.';

  @override
  String get familyEmail => 'Email';

  @override
  String get familyMarkAllRead => 'Mark all read';

  @override
  String get familyNoNoticesYet => 'No notices yet';

  @override
  String get familyNoNoticesYetMessage => 'Messages from the school will appear here.';

  @override
  String familyFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count files', one: '1 file');
    return '$_temp0';
  }

  @override
  String get familyHolidaysCalendarName => 'School holidays';

  @override
  String get familyCalendarShareFailed => 'The calendar file could not be shared.';

  @override
  String get familyThisMonth => 'This month';

  @override
  String get familyNoHolidaysThisMonth => 'No holidays this month.';

  @override
  String familyClosedEvery(String days) {
    return 'The school is closed every $days.';
  }

  @override
  String get familyAndJoin => ' and ';

  @override
  String get familyHolidaysComingUp => 'Coming up';

  @override
  String get familyNoHolidaysPlanned => 'No holidays planned yet.';

  @override
  String get familyAddHolidaysToCalendar => 'Add these holidays to my calendar';

  @override
  String get familySwitchAttendanceSub => 'Absent, or on leave';

  @override
  String get familySwitchBusSub => 'Boarded, dropped, did not take the bus';

  @override
  String get familySwitchFeesSub => 'Reminders and receipts';

  @override
  String get familySwitchResultsSub => 'When a test result is published';

  @override
  String get familySwitchNoticesSub => 'Announcements and messages from the school';

  @override
  String get familySwitchHomeworkSub => 'Each evening, the day\'s homework';

  @override
  String get familyEmergencyAlwaysComes => 'Emergency messages from the school always come through.';

  @override
  String get familySaved => 'Saved.';

  @override
  String get familyCallSentOffice => 'Sent. The school office will call you.';

  @override
  String get familyCallSentTeacher => 'Sent. The class teacher will call you.';

  @override
  String familyWhoShouldCall(String name) {
    return 'Who should call you about $name?';
  }

  @override
  String get familyClassTeacher => 'Class teacher';

  @override
  String get familySchoolOfficeShort => 'School office';

  @override
  String get familyWhatAbout => 'What is it about?';

  @override
  String get familyWhatAboutTooShort => 'Please say a little about what it is.';

  @override
  String get familyGoodTimeToCall => 'A good time to call (optional)';

  @override
  String get familyGoodTimeHint => 'e.g. After 5 pm';

  @override
  String get familyAskForCall => 'Ask for a call';

  @override
  String get familyYourRequests => 'Your requests';

  @override
  String get familyNoneYet => 'None yet.';

  @override
  String familyCalledBy(String who, String when) {
    return 'Called by $who · $when';
  }

  @override
  String get familyTheSchool => 'the school';

  @override
  String get familyCalled => 'Called';

  @override
  String get familyWaiting => 'Waiting';

  @override
  String familyAnswerBy(String date) {
    return 'Please answer by $date';
  }

  @override
  String familyAnswersClosedOn(String date) {
    return 'Answers closed on $date';
  }

  @override
  String get familyYes => 'Yes';

  @override
  String get familyNo => 'No';

  @override
  String familyAnswerReached(String when) {
    return 'Your answer reached the school · $when';
  }

  @override
  String get familyNoteForSchool => 'A note for the school (optional)';

  @override
  String get familyAnswerNeeded => 'Answer needed';

  @override
  String familyAbsenceNotesFor(String name) {
    return 'Absence notes for $name';
  }

  @override
  String get familyTellTheSchool => 'Tell the school';

  @override
  String get familyNoNotesSent => 'No notes sent';

  @override
  String familyNoNotesSentMessage(String name) {
    return 'If $name will be away, tell the school here - the class teacher sees it.';
  }

  @override
  String get familyNoteSeen => 'Seen';

  @override
  String get familyNoteSent => 'Sent';

  @override
  String familySeenBy(String who, String when) {
    return 'Seen by $who · $when';
  }

  @override
  String get familyTheClassTeacher => 'the class teacher';

  @override
  String get familyWithPhoto => 'With a photo of a note';

  @override
  String get familyFirstDayAway => 'First day away';

  @override
  String get familyLastDayAway => 'Last day away';

  @override
  String get familyTakePhoto => 'Take a photo';

  @override
  String get familyChoosePhoto => 'Choose from your photos';

  @override
  String familyNoteSentSnack(String name) {
    return 'Sent. $name\'s class teacher will see it.';
  }

  @override
  String get familyYourChildWillBeAway => 'Your child will be away';

  @override
  String familyChildWillBeAway(String name) {
    return '$name will be away';
  }

  @override
  String familyNoteExplain(String name) {
    return 'The class teacher sees this on the register. It doesn\'t mark $name absent by itself.';
  }

  @override
  String get familyFirstDay => 'First day';

  @override
  String get familyLastDay => 'Last day';

  @override
  String get familyWhyAway => 'Why will they be away?';

  @override
  String get familyWhyAwayHint => 'e.g. Fever since last night - the doctor has advised two days\' rest.';

  @override
  String familyReasonTooShort(int min) {
    return 'Please write a little more - at least $min characters.';
  }

  @override
  String get familySendToSchool => 'Send to the school';

  @override
  String get familyAddDoctorNote => 'Add a photo of a doctor\'s note (optional)';

  @override
  String get familyRemove => 'Remove';

  @override
  String get familyDeviceNotRegistered =>
      'This phone is not registered yet. Enter the setup code from your school\'s letter.';

  @override
  String get familyForgotPasscode => 'Forgot your passcode?';

  @override
  String get familyForgotPasscodeHelp =>
      'Ask your child\'s school office for a new Family app letter. It has a new setup code: enter it here with your mobile number, and choose a new passcode. Your phone stays the same.';

  @override
  String get familyClose => 'Close';

  @override
  String get familyHaveNewCode => 'I have a new code';

  @override
  String get familySetUpApp => 'Set up the Family app';

  @override
  String get familyWelcomeBack => 'Welcome back';

  @override
  String get familySetUpHelp =>
      'Use the letter from your child\'s school: your mobile number, the 8-digit setup code, and a 6-digit passcode you choose.';

  @override
  String get familySignInHelp => 'Sign in with your mobile number and your 6-digit passcode.';

  @override
  String get familyMobileNumber => 'Mobile number';

  @override
  String get familySetupCodeLabel => 'Setup code from the letter';

  @override
  String get familySetupCodeInvalid => 'Enter the 8-digit setup code from the school\'s letter.';

  @override
  String get familyChoosePasscode => 'Choose a passcode';

  @override
  String get familyTypeItAgain => 'Type it again';

  @override
  String get familyPasscodesDiffer => 'The two passcodes are not the same.';

  @override
  String get familyPasscode => 'Passcode';

  @override
  String get familyPasscodeInvalid => 'Enter your 6-digit passcode.';

  @override
  String get familySetUpAndSignIn => 'Set up and sign in';

  @override
  String get familySignIn => 'Sign in';

  @override
  String get familyUseSetupCode => 'New phone, or a new letter? Use the setup code';

  @override
  String get familyAlreadySetUp => 'Already set up on this phone? Sign in';

  @override
  String get familyNoLetter => 'No letter? Ask your child\'s school office for the Family app setup code.';

  @override
  String get familyNoAdmitCards => 'No admit cards yet';

  @override
  String get familyNoAdmitCardsMessage =>
      'When the school publishes an exam your child sits, its admit card appears here.';

  @override
  String familyReportingTime(String time) {
    return 'Reporting time $time.';
  }

  @override
  String familyAdmitVersion(String version, String date) {
    return 'Version $version, issued $date';
  }

  @override
  String get familyDownloadAdmitCard => 'Download admit card';

  @override
  String familyAddPapersToCalendar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count papers to calendar',
      one: 'Add 1 paper to calendar',
    );
    return '$_temp0';
  }

  @override
  String get familyGuardianSent => 'Sent. The school will look at your request.';

  @override
  String familyGuardianExplain(String name) {
    return 'Ask the school to add another guardian of $name. Once the school agrees, it gives them their own set-up letter, and they see what you see.';
  }

  @override
  String get familyTheirFullName => 'Their full name';

  @override
  String get familyEnterTheirName => 'Enter their name.';

  @override
  String get familyTheirMobile => 'Their mobile number';

  @override
  String familyHowRelated(String name) {
    return 'How they are related to $name';
  }

  @override
  String get familyChooseRelation => 'Choose how they are related.';

  @override
  String get familyAskTheSchool => 'Ask the school';

  @override
  String get familyPrivacyNumberTitle => 'Who can see your phone number';

  @override
  String get familyPrivacyNumberOffice => 'The school office.';

  @override
  String get familyPrivacyNumberTeachers => 'Your child\'s own class teachers - not teachers of other classes.';

  @override
  String get familyPrivacyNumberFees => 'Staff who take fees, so they can call about a payment.';

  @override
  String get familyPrivacyNumberBus =>
      'If your child takes the school bus: the transport office, and the bus crew on your child\'s route, so they can call you from the road.';

  @override
  String get familyPrivacyNumberOthers => 'The school decides whether any other staff may see it.';

  @override
  String get familyPrivacyBusTitle => 'The bus on the map';

  @override
  String get familyPrivacyBusSource =>
      'The location you see is the bus\'s, sent by the crew\'s phone while a trip runs.';

  @override
  String get familyPrivacyBusWhen =>
      'You can follow it only while your child\'s own trip is running - until they are dropped off or marked as not on the bus.';

  @override
  String get familyPrivacyBusNoPhoneLocation => 'This app never asks for your phone\'s location.';

  @override
  String get familyPrivacyMessagesTitle => 'What comes to this app';

  @override
  String get familyPrivacyMessagesLine => 'You choose which kinds of message the school sends to this app.';

  @override
  String get familyChooseNotifications => 'Choose notifications';

  @override
  String get familyOpen => 'Open';

  @override
  String get staffNavHome => 'Home';

  @override
  String get staffNavTeaching => 'Teaching';

  @override
  String get staffNavDepartment => 'Department';

  @override
  String get staffNavLeave => 'Leave';

  @override
  String get staffNavPay => 'Pay';

  @override
  String get staffNavFees => 'Fees';

  @override
  String get staffNavMe => 'Me';

  @override
  String get staffLogOut => 'Log out';

  @override
  String get staffMessages => 'Messages';

  @override
  String staffMessagesUnread(int count) {
    return 'Messages, $count unread';
  }

  @override
  String get staffCallRequestsTitle => 'Call requests';

  @override
  String get staffNotTeacherCrewTitle => 'Use the School365ai Bus app';

  @override
  String get staffNotTeacherOfficeTitle => 'Use the School365ai website';

  @override
  String get staffNotTeacherCrewBody =>
      'Drivers and bus attendants sign in to School365ai Driver, with their mobile number and passcode.';

  @override
  String get staffNotTeacherOfficeBody =>
      'This app is for the staff of a school. Your account looks after more than one school, which the website is made for.';

  @override
  String get staffSignOut => 'Sign out';

  @override
  String get staffBack => 'Back';

  @override
  String get staffCurrentPassword => 'Current password';

  @override
  String get staffEnterCurrentPassword => 'Enter your current password';

  @override
  String get staffNewPassword => 'New password';

  @override
  String get staffNewPasswordHint => 'At least 8 characters, with a letter and a number.';

  @override
  String get staffConfirmNewPassword => 'Confirm new password';

  @override
  String get staffPasswordsDoNotMatch => 'Passwords do not match';

  @override
  String get staffChoosePasswordTitle => 'Choose your password';

  @override
  String get staffChoosePasswordSubtitle =>
      'Your account was set up with a temporary password. Choose your own to continue.';

  @override
  String get staffSavePassword => 'Save password';

  @override
  String get staffPasswordChanged => 'Password changed.';

  @override
  String get staffSignOutInstead => 'Sign out instead';

  @override
  String get staffResetPasswordTitle => 'Reset your password';

  @override
  String get staffCheckEmailTitle => 'Check your email';

  @override
  String get staffResetPasswordSubtitle =>
      'Enter your school email and we will send you a link to choose a new password.';

  @override
  String get staffCheckEmailSubtitle => 'A link to choose a new password is on its way.';

  @override
  String staffResetSentBody(String email) {
    return 'If an account exists for $email, the email is on its way. The link works once and lasts one hour. If it does not arrive, look in your spam folder.';
  }

  @override
  String get staffResetSentNext => 'Choose your new password from the link, then come back here and sign in with it.';

  @override
  String get staffBackToSignIn => 'Back to sign in';

  @override
  String get staffEmail => 'Email';

  @override
  String get staffEnterEmail => 'Enter your email.';

  @override
  String get staffNotAnEmail => 'That does not look like an email address.';

  @override
  String get staffSendResetLink => 'Send reset link';

  @override
  String get staffWelcomeBack => 'Welcome back';

  @override
  String get staffSignInSubtitle => 'Sign in with your school email and password.';

  @override
  String get staffSessionEnded => 'Your session has ended. Sign in again.';

  @override
  String get staffPassword => 'Password';

  @override
  String get staffShowPassword => 'Show password';

  @override
  String get staffHidePassword => 'Hide password';

  @override
  String get staffEnterPassword => 'Enter your password.';

  @override
  String get staffRememberEmail => 'Remember my email';

  @override
  String get staffForgotPassword => 'Forgot password?';

  @override
  String get staffSignIn => 'Sign in';

  @override
  String get staffTroubleSigningIn =>
      'Trouble signing in? Your school office can unlock your account or send you a new link.';

  @override
  String get staffWelcomeHeadline => 'Your school day,\nin your pocket.';

  @override
  String get staffWelcomeIntro =>
      'For everyone who works at your school. Sign in with the email and password you use for School365ai.';

  @override
  String get staffWelcomeCheckInTitle => 'Check in at school';

  @override
  String get staffWelcomeCheckInBody => 'Mark your arrival and departure from your phone, at school.';

  @override
  String get staffWelcomeTodayTitle => 'Today at a glance';

  @override
  String get staffWelcomeTodayBody => 'For teachers: your periods in order, with the one under way marked.';

  @override
  String get staffWelcomeRegisterTitle => 'Register and reports';

  @override
  String get staffWelcomeRegisterBody =>
      'Take your class register, even without signal, and say what each period covered.';

  @override
  String get staffWelcomeCalendarTitle => 'Your school\'s calendar';

  @override
  String get staffWelcomeCalendarBody => 'Holidays, half days and your approved leave, without asking the office.';

  @override
  String get staffWelcomeNewHere =>
      'New here? Your school office creates your account and emails you a link to choose your password.';

  @override
  String get staffSplashTagline => 'Your school day, in your pocket.';

  @override
  String get staffTryAgain => 'Try again';

  @override
  String get staffSplashSlow => 'Still trying to reach your school. Check that this phone is online.';

  @override
  String get staffSplashLoading => 'Getting your day ready…';

  @override
  String get staffLeaveCasual => 'Casual Leave';

  @override
  String get staffLeaveMedical => 'Medical Leave';

  @override
  String get staffLeaveEarned => 'Earned Leave';

  @override
  String get staffLeaveHalfDay => 'Half Day';

  @override
  String get staffLeavePending => 'Pending';

  @override
  String get staffLeaveApproved => 'Approved';

  @override
  String get staffLeaveRejected => 'Rejected';

  @override
  String get staffLeaveWithdrawn => 'Withdrawn';

  @override
  String get staffDayMonday => 'Monday';

  @override
  String get staffDayTuesday => 'Tuesday';

  @override
  String get staffDayWednesday => 'Wednesday';

  @override
  String get staffDayThursday => 'Thursday';

  @override
  String get staffDayFriday => 'Friday';

  @override
  String get staffDaySaturday => 'Saturday';

  @override
  String get staffDaySunday => 'Sunday';

  @override
  String get staffDayMon => 'Mon';

  @override
  String get staffDayTue => 'Tue';

  @override
  String get staffDayWed => 'Wed';

  @override
  String get staffDayThu => 'Thu';

  @override
  String get staffDayFri => 'Fri';

  @override
  String get staffDaySat => 'Sat';

  @override
  String get staffDaySun => 'Sun';

  @override
  String get staffYourPeriods => 'Your periods';

  @override
  String staffYourPeriodsCount(int count) {
    return 'Your periods ($count)';
  }

  @override
  String staffBreakNow(String name) {
    return '$name - now';
  }

  @override
  String staffDateRange(String start, String end) {
    return '$start to $end';
  }

  @override
  String get staffGoodDay => 'Good day';

  @override
  String staffGoodDayName(String name) {
    return 'Good day, $name';
  }

  @override
  String get staffHalfDay => 'Half day';

  @override
  String get staffNoSchoolToday => 'No school today';

  @override
  String staffHolidayNamed(String name) {
    return 'Holiday: $name';
  }

  @override
  String get staffClosedBody => 'The school is closed, so there is no register to take and no report to write.';

  @override
  String get staffOnLeaveToday => 'You are on leave today';

  @override
  String staffOnLeaveBody(String type, String span) {
    return '$type, $span. Nothing is owed while you are away.';
  }

  @override
  String get staffNothingOwed => 'Nothing owed so far today.';

  @override
  String staffOwedRegisters(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count registers', one: '1 register');
    return '$_temp0';
  }

  @override
  String staffOwedReports(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count teaching reports',
      one: '1 teaching report',
    );
    return '$_temp0';
  }

  @override
  String get staffAnd => ' and ';

  @override
  String staffStillToDo(String items) {
    return 'Still to do: $items.';
  }

  @override
  String get staffRegisterTaken => 'Taken';

  @override
  String get staffYourClassRegister => 'Your class register';

  @override
  String get staffSavedNotSent => 'Saved, not sent';

  @override
  String get staffSendsWithSignal => 'Sends when there is signal';

  @override
  String get staffNotSent => 'Not sent';

  @override
  String get staffRegisterNotTaken => 'Not taken';

  @override
  String get staffTapToTakeRegister => 'Tap to take the register';

  @override
  String get staffStudents => 'Students';

  @override
  String get staffMyWeek => 'My week';

  @override
  String staffParentsAskedToCall(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count parents asked you to call',
      one: 'A parent asked you to call',
    );
    return '$_temp0';
  }

  @override
  String get staffTapToSeeWho => 'Tap to see who, and ring them';

  @override
  String staffClassAndPeriod(String classSection, int number) {
    return '$classSection · Period $number';
  }

  @override
  String get staffNow => 'Now';

  @override
  String get staffNotSentTapWhy => 'Not sent - tap to see why';

  @override
  String get staffSentBackTapChange => 'Sent back - tap to change';

  @override
  String get staffReportFiled => 'Report filed';

  @override
  String get staffReportOwedTapFile => 'Report owed - tap to file';

  @override
  String get staffNoPeriodsToday => 'You have no periods on the timetable today.';

  @override
  String get staffLeaveThisWeek => 'Leave this week';

  @override
  String staffLeaveLine(String type, String span) {
    return '$type, $span';
  }

  @override
  String get staffFindAStudent => 'Find a student';

  @override
  String get staffWhereLeaveAndPay => 'Your leave and payslips are in the Leave and Pay tabs below.';

  @override
  String get staffWhereLeave => 'Your leave is in the Leave tab below.';

  @override
  String get staffWherePay => 'Your payslips are in the Pay tab below.';

  @override
  String get staffWhereMessages => 'The school\'s messages are under the bell at the top.';

  @override
  String get staffClosedNoCheckIn => 'The school is closed, so there is nothing to check in to.';

  @override
  String get staffOnLeaveNoCheckIn => 'Nothing to check in to while you are away.';

  @override
  String get staffMarkedInOffice => 'Attendance is marked in the office';

  @override
  String get staffMarkedInOfficeBody => 'Your school records staff attendance itself rather than from the app.';

  @override
  String get staffNoPeriodsYet => 'You have no periods on the timetable yet. The office sets it up.';

  @override
  String staffDayToday(String day) {
    return '$day (today)';
  }

  @override
  String staffDayPeriods(String day, int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count periods', one: '1 period');
    return '$day: $_temp0';
  }

  @override
  String get staffPeriod => 'Period';

  @override
  String get staffPresent => 'Present';

  @override
  String get staffAbsent => 'Absent';

  @override
  String get staffLate => 'Late';

  @override
  String get staffCheckedIn => 'Checked in.';

  @override
  String get staffCheckedOut => 'Checked out.';

  @override
  String staffCheckedInAt(String time) {
    return 'Checked in at $time.';
  }

  @override
  String staffCheckedOutAt(String time) {
    return 'Checked out at $time.';
  }

  @override
  String staffYouCheckedInAt(String time) {
    return 'You checked in at $time.';
  }

  @override
  String get staffCheckOutAgainQ => 'Check out again?';

  @override
  String get staffCheckOutNowQ => 'Check out now?';

  @override
  String get staffCheckOutAgainBody =>
      'Your leaving time will change to now. The last check-out is the one that counts.';

  @override
  String get staffCheckOutBody => 'This records the time you leave school.';

  @override
  String get staffNotYet => 'Not yet';

  @override
  String get staffCheckOut => 'Check out';

  @override
  String get staffCheckOutAgain => 'Check out again';

  @override
  String get staffCheckIn => 'Check in';

  @override
  String get staffOpenSettingsForLocation => 'Open your phone\'s settings and allow location for School365ai.';

  @override
  String get staffFindingLocation => 'Finding your location…';

  @override
  String staffLocationUsedOnce(int metres) {
    return 'Your location is used once, to confirm you are within $metres m of school. It is not stored.';
  }

  @override
  String get staffCheckInUnavailable => 'Check-in unavailable';

  @override
  String get staffMarkedAbsent => 'Marked absent today';

  @override
  String get staffMarkedAbsentBody => 'The office marked you absent. Check in when you arrive and it is corrected.';

  @override
  String get staffHalfDayLeaveToday => 'Half-day leave today';

  @override
  String get staffHalfDayLeaveBody => 'Check in for the half you work, and the day is recorded as a half day.';

  @override
  String get staffCheckInToStart => 'Check in to start your day';

  @override
  String get staffCheckInToStartBody => 'Tap Check in when you reach school.';

  @override
  String staffCheckedInAtTitle(String time) {
    return 'Checked in at $time';
  }

  @override
  String get staffCheckOutWhenLeaving => 'Check out when you leave school.';

  @override
  String get staffCheckedInAndOut => 'Checked in and out. See you tomorrow.';

  @override
  String staffUnfinishedDay(String date, String time) {
    return 'You did not check out on $date (checked in $time). Ask the office to add when you left.';
  }

  @override
  String get staffOfficeUpdatedDay =>
      'The office has updated your day on the register. Ask them if something looks wrong.';

  @override
  String get staffCheckInNoConnection =>
      'No connection, so nothing was recorded. Check in again when your phone is online - the time saved is when it reaches the school.';

  @override
  String get staffLocationServiceOff => 'Your phone\'s location is switched off. Turn it on, then check in again.';

  @override
  String get staffLocationDeniedForever =>
      'This app is not allowed to see your location. Allow it in your phone\'s settings for this app, then check in again.';

  @override
  String get staffLocationDenied =>
      'Checking in needs your location once, to confirm you are at school. Allow it and try again.';

  @override
  String get staffLocationUnsupported => 'This device cannot tell where it is, so it cannot check you in.';

  @override
  String get staffLocationNotFound => 'Your location could not be found. Try again in a moment.';

  @override
  String get staffTurnOnLocation => 'Turn on location';

  @override
  String get staffOpenSettings => 'Open settings';

  @override
  String get staffCheckInLoadFailed => 'Could not load your check-in';

  @override
  String get staffNoStaffRecord => 'Check-in is not set up for your account';

  @override
  String get staffNoStaffRecordBody => 'Your account has no staff record at this school. Ask the office to add one.';

  @override
  String get staffCategoryAttendance => 'Attendance';

  @override
  String get staffCategoryTransport => 'Transport';

  @override
  String get staffCategoryResult => 'Result';

  @override
  String get staffCategoryAnnouncement => 'Announcement';

  @override
  String get staffCategoryGeneral => 'General';

  @override
  String get staffCategoryEmergency => 'Emergency';

  @override
  String get staffPeriodAll => 'All';

  @override
  String get staffPeriodToday => 'Today';

  @override
  String get staffPeriodWeek => 'This week';

  @override
  String get staffPeriodMonth => 'This month';

  @override
  String get staffNothingWasUnread => 'Nothing was unread.';

  @override
  String staffMarkedRead(int count) {
    return 'Marked $count as read.';
  }

  @override
  String get staffMarkAllRead => 'Mark all read';

  @override
  String get staffUnread => 'Unread';

  @override
  String get staffNothingUnread => 'Nothing unread.';

  @override
  String get staffNoMessagesYet => 'No messages yet.';

  @override
  String get staffInboxEmptyHint => 'Announcements and notices from your school arrive here.';

  @override
  String get staffShowOlderMessages => 'Show older messages';

  @override
  String staffAboutStudent(String name) {
    return 'About $name';
  }

  @override
  String get staffPictureNotShown => 'This picture could not be shown.';

  @override
  String get staffDownload => 'Download';

  @override
  String get staffSaveOrShare => 'Save or share';

  @override
  String get staffClose => 'Close';

  @override
  String get staffApplyForLeave => 'Apply for leave';

  @override
  String get staffMyLeave => 'My leave';

  @override
  String get staffMyLeaveSubtitle => 'Your requests and where each one stands.';

  @override
  String staffEmptyLeaveRequests(String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'all': 'No leave requests yet.',
      'day': 'No leave requests today.',
      'week': 'No leave requests this week.',
      'month': 'No leave requests this month.',
      'other': 'No leave requests yet.',
    });
    return '$_temp0';
  }

  @override
  String get staffApplyForLeaveHint => 'Tap Apply for leave to ask for a day off.';

  @override
  String get staffShowOlderRequests => 'Show older requests';

  @override
  String get staffWithdrawRequestQ => 'Withdraw this request?';

  @override
  String get staffWithdrawRequestBody =>
      'It will no longer wait for a decision. You can apply for the same days again.';

  @override
  String get staffWithdraw => 'Withdraw';

  @override
  String get staffKeepIt => 'Keep it';

  @override
  String get staffLeaveWithdrawnDone => 'Leave request withdrawn.';

  @override
  String staffDatesHalfADay(String dates) {
    return '$dates · half a day';
  }

  @override
  String get staffReviewer => 'Reviewer';

  @override
  String get staffWithdrawing => 'Withdrawing...';

  @override
  String get staffLeaveTakenLoadFailed => 'Could not load this year\'s leave.';

  @override
  String staffTakenIn(String year) {
    return 'Taken in $year';
  }

  @override
  String get staffNoLeaveTakenYet => 'No leave taken yet this year.';

  @override
  String staffRequestsWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count requests are waiting for a decision.',
      one: '1 request is waiting for a decision.',
    );
    return '$_temp0';
  }

  @override
  String get staffOneDay => '1 day';

  @override
  String staffDays(String number) {
    return '$number days';
  }

  @override
  String get staffLeaveAutoApproved => 'Leave approved automatically.';

  @override
  String get staffLeaveRequested => 'Leave requested. You will see here when it is decided.';

  @override
  String get staffLeaveType => 'Leave type';

  @override
  String get staffDate => 'Date';

  @override
  String get staffFrom => 'From';

  @override
  String get staffTo => 'To';

  @override
  String get staffReason => 'Reason';

  @override
  String get staffSayWhyLeave => 'Say why you need the leave.';

  @override
  String get staffHalfDayLeaveHint =>
      'Half-day leave: you check in for the half you work, and the day counts as a half day.';

  @override
  String get staffWeekendsNotCounted => 'Weekends and holidays inside the dates are not counted as leave.';

  @override
  String get staffSendRequest => 'Send request';

  @override
  String get staffModeCash => 'Cash';

  @override
  String get staffModeBankTransfer => 'Bank Transfer';

  @override
  String get staffModeUpi => 'UPI';

  @override
  String get staffModeCheque => 'Cheque';

  @override
  String get staffModeCard => 'Card';

  @override
  String get staffModeOnlineTransfer => 'Online Transfer';

  @override
  String get staffMyPay => 'My pay';

  @override
  String get staffMyPaySubtitle => 'Your payslips, once the month is finalized.';

  @override
  String get staffNoPayslipsYet => 'No payslips yet.';

  @override
  String get staffNoPayslipsHint => 'A payslip appears here once the school finalizes the month.';

  @override
  String get staffShowEarlierMonths => 'Show earlier months';

  @override
  String get staffNetPay => 'Net pay';

  @override
  String get staffPaid => 'Paid';

  @override
  String get staffNotPaidYet => 'Not paid yet';

  @override
  String get staffPayslip => 'Payslip';

  @override
  String staffPaidOn(String date) {
    return 'Paid on $date';
  }

  @override
  String staffByMode(String mode) {
    return 'by $mode';
  }

  @override
  String get staffDaysTitle => 'Days';

  @override
  String get staffWorkingDays => 'Working days';

  @override
  String get staffPaidDays => 'Paid days';

  @override
  String get staffHalfDays => 'Half days';

  @override
  String get staffNotMarked => 'Not marked';

  @override
  String get staffEarnings => 'Earnings';

  @override
  String get staffTotalEarnings => 'Total earnings';

  @override
  String get staffDeductions => 'Deductions';

  @override
  String get staffTotalDeductions => 'Total deductions';

  @override
  String staffUnpaidShortfall(String amount) {
    return 'Unpaid days reduced this month by $amount.';
  }

  @override
  String get staffGettingPdf => 'Getting the PDF...';

  @override
  String get staffSharePdf => 'Share the PDF';

  @override
  String get staffSending => 'Sending…';

  @override
  String get staffEmailMePdf => 'Email me the PDF';

  @override
  String get staffTabToReview => 'To review';

  @override
  String get staffTabStaff => 'Staff';

  @override
  String get staffTabTeachers => 'Teachers';

  @override
  String get staffReviewIntro =>
      'Reports from your department that nobody has reviewed yet. Open one to read and review it.';

  @override
  String staffReviewEmpty(String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'all': 'Nothing waiting for review.',
      'day': 'Nothing waiting for review from today.',
      'week': 'Nothing waiting for review from this week.',
      'month': 'Nothing waiting for review from this month.',
      'other': 'Nothing waiting for review.',
    });
    return '$_temp0';
  }

  @override
  String get staffReviewEmptyBody => 'Reports your department files appear here until you review them.';

  @override
  String get staffShowMore => 'Show more';

  @override
  String staffPeriodNumber(int number) {
    return 'Period $number';
  }

  @override
  String get staffATeacher => 'A teacher';

  @override
  String get staffDeptTodayIntro =>
      'Your department today: who is in, and when they arrived. Mark anyone the register is missing.';

  @override
  String staffDeptPeriodIntro(String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'week': 'Your department this week: each person\'s days in, absent and on leave, out of the school days so far.',
      'month':
          'Your department this month: each person\'s days in, absent and on leave, out of the school days so far.',
      'other': 'Your department: each person\'s days in, absent and on leave, out of the school days so far.',
    });
    return '$_temp0';
  }

  @override
  String get staffOneSchoolDaySoFar => '1 school day so far';

  @override
  String staffSchoolDaysSoFar(String count) {
    return '$count school days so far';
  }

  @override
  String get staffNobodyInDept => 'Nobody in your department yet.';

  @override
  String get staffOfficeAddsStaff => 'The school office adds staff to departments on the website.';

  @override
  String get staffFigPresent => 'present';

  @override
  String get staffFigHalfDay => 'half day';

  @override
  String get staffFigAbsent => 'absent';

  @override
  String get staffFigLeave => 'leave';

  @override
  String get staffFigUnmarked => 'unmarked';

  @override
  String get staffSchoolClosedToday => 'The school is closed today.';

  @override
  String staffInOf(int present, int total) {
    return '$present of $total in';
  }

  @override
  String staffInOfUnmarked(int present, int total, int unmarked) {
    return '$present of $total in · $unmarked not marked yet';
  }

  @override
  String get staffAllPresent => 'All present';

  @override
  String get staffSaving => 'Saving...';

  @override
  String get staffUpdateRegister => 'Update register';

  @override
  String get staffSubmitRegister => 'Submit register';

  @override
  String staffMarkEveryone(int count) {
    return 'Mark everyone ($count left)';
  }

  @override
  String staffTimeIn(String time) {
    return 'In $time';
  }

  @override
  String staffTimeOut(String time) {
    return 'out $time';
  }

  @override
  String get staffFromTheApp => 'from the app';

  @override
  String get staffPresentLate => 'Present · late';

  @override
  String get staffDeptLeaveIntro => 'Leave your department has asked for, waiting for your decision.';

  @override
  String get staffNothingToDecide => 'Nothing to decide.';

  @override
  String get staffNothingToDecideBody => 'New requests from your department appear here.';

  @override
  String get staffApproveLeaveQ => 'Approve this leave?';

  @override
  String get staffRejectLeaveQ => 'Reject this leave?';

  @override
  String staffLeaveDecideBody(String name, String type, String dates) {
    return '$name: $type, $dates.';
  }

  @override
  String get staffThisRequest => 'This request';

  @override
  String get staffApprove => 'Approve';

  @override
  String get staffReject => 'Reject';

  @override
  String get staffAtWorkThatDay => 'At work that day';

  @override
  String get staffApproveAnyway => 'Approve anyway';

  @override
  String get staffLeaveApprovedDone => 'Leave approved.';

  @override
  String get staffLeaveRejectedDone => 'Leave rejected.';

  @override
  String get staffMonthIntro =>
      'Each teacher this month: reports filed against periods taught, syllabus covered, attendance.';

  @override
  String get staffNoTeachersInDept => 'No teachers in your department yet.';

  @override
  String get staffOnTrack => 'On track';

  @override
  String get staffNeedsALook => 'Needs a look';

  @override
  String get staffFigReportsPeriods => 'reports / periods';

  @override
  String get staffFigToReview => 'to review';

  @override
  String get staffFigSyllabus => 'syllabus';

  @override
  String get staffFigAttendance => 'attendance';

  @override
  String staffRegisterTitle(String label) {
    return '$label register';
  }

  @override
  String get staffSubmitRegisterQ => 'Submit the register?';

  @override
  String get staffCheckAgain => 'Check again';

  @override
  String get staffSubmit => 'Submit';

  @override
  String get staffRegisterSubmitted => 'Register submitted.';

  @override
  String get staffRegisterSavedNoSignal => 'No signal: the register is saved on this phone and sent when there is.';

  @override
  String get staffRegisterCorrected => 'Register corrected.';

  @override
  String get staffCorrectionNeedsConnection =>
      'A correction needs a connection, because parents may already have been told. Try again with signal.';

  @override
  String staffNobodyMatches(String query) {
    return 'Nobody in this class matches \"$query\".';
  }

  @override
  String get staffClosedNoRegister => 'The school is closed, so there is no register to take.';

  @override
  String get staffNoStudentsInClass => 'No students in this class';

  @override
  String get staffNoStudentsInClassBody =>
      'There is nobody on the class list to mark. Ask the office if that is wrong.';

  @override
  String get staffRegisterByException =>
      'Everyone starts as present. Tap Absent or Leave for anyone who is not - or swipe a row: right for present, left for absent.';

  @override
  String get staffFindByNameOrRoll => 'Find by name or roll number';

  @override
  String staffCountPresent(int count) {
    return '$count present';
  }

  @override
  String staffCountAbsent(int count) {
    return '$count absent';
  }

  @override
  String staffCountOnLeave(int count) {
    return '$count on leave';
  }

  @override
  String staffSentence(String text) {
    return '$text.';
  }

  @override
  String get staffParentsAreTold => 'Parents of absent children are told, as your school has set it up.';

  @override
  String staffRegisterRefused(String reason) {
    return 'Not sent: $reason If the register still needs taking, take it again below and submit it. If this looks wrong, ask the school office.';
  }

  @override
  String get staffSendingRegister => 'Sending the register…';

  @override
  String get staffRegisterWaiting =>
      'Saved on this phone, not yet sent. It goes as soon as there is signal - you can close the app.';

  @override
  String get staffRegisterOffline =>
      'No connection. Take the register as usual: it is saved on this phone and sent when there is signal.';

  @override
  String get staffSaveCorrection => 'Save correction';

  @override
  String get staffSubmittedDot => 'Submitted.';

  @override
  String get staffCorrect => 'Correct';

  @override
  String get staffWaitingForSignal => 'Waiting for signal to send.';

  @override
  String get staffParentsNoteSeen => 'Parent\'s note · seen';

  @override
  String get staffParentsNote => 'Parent\'s note';

  @override
  String get staffNoteMarkedSeen => 'Marked as seen. The parent can see that.';

  @override
  String staffNoteAbout(String name) {
    return 'Note about $name';
  }

  @override
  String get staffNoteDoesNotMark => 'A note doesn\'t mark the register - mark it as usual.';

  @override
  String get staffMarkAsSeen => 'Mark as seen';

  @override
  String get staffTabReports => 'Reports';

  @override
  String get staffTabSyllabus => 'Syllabus';

  @override
  String get staffTabMarks => 'Marks';

  @override
  String get staffReportsIntro =>
      'What you taught, period by period, and whether it has been reviewed. File a report from its period on Today.';

  @override
  String staffEmptyReports(String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'all': 'No reports yet.',
      'day': 'No reports today.',
      'week': 'No reports this week.',
      'month': 'No reports this month.',
      'other': 'No reports yet.',
    });
    return '$_temp0';
  }

  @override
  String get staffEmptyReportsBody => 'Once a period has begun, tap it on Today to say what was taught.';

  @override
  String get staffShowOlderReports => 'Show older reports';

  @override
  String get staffReport => 'Report';

  @override
  String get staffReviewed => 'Reviewed';

  @override
  String get staffSentBack => 'Sent back';

  @override
  String get staffAwaitingReview => 'Awaiting review';

  @override
  String get staffSyllabusIntro => 'Each class and subject you teach this year. Tap one to tick off topics.';

  @override
  String get staffNoClassesThisYear => 'No classes on your timetable this year.';

  @override
  String get staffNoClassesThisYearBody =>
      'Your school office puts you on the timetable; your classes appear here once it does.';

  @override
  String get staffNoTopicsYet => 'No topics yet';

  @override
  String staffXOfY(int done, int total) {
    return '$done of $total';
  }

  @override
  String get staffTestClassTest => 'Class test';

  @override
  String get staffTestUnitTest => 'Unit test';

  @override
  String get staffTestAssignment => 'Assignment';

  @override
  String get staffTestQuiz => 'Quiz';

  @override
  String get staffTestPractical => 'Practical';

  @override
  String get staffNewTest => 'New test';

  @override
  String get staffMarksIntro =>
      'Class tests for the classes you teach. Open one to enter marks; publish when everyone is marked.';

  @override
  String staffEmptyTests(String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'all': 'No class tests yet.',
      'day': 'No class tests today.',
      'week': 'No class tests this week.',
      'month': 'No class tests this month.',
      'other': 'No class tests yet.',
    });
    return '$_temp0';
  }

  @override
  String get staffEmptyTestsBody => 'Tap New test to set one for a class you teach.';

  @override
  String get staffShowOlderTests => 'Show older tests';

  @override
  String get staffDraft => 'Draft';

  @override
  String get staffPublished => 'Published';

  @override
  String staffOutOf(String marks) {
    return 'out of $marks';
  }

  @override
  String staffTopicNotChanged(String topic) {
    return 'No connection. \"$topic\" was not changed.';
  }

  @override
  String get staffNoTopicsInSyllabus => 'No topics in this syllabus yet.';

  @override
  String get staffNoTopicsInSyllabusBody => 'Your HOD or school office sets out the topics on the website.';

  @override
  String staffTopicsDone(int done, int total, String percent) {
    return '$done of $total topics done · $percent%';
  }

  @override
  String staffDoneBy(String name) {
    return 'Done · $name';
  }

  @override
  String get staffDraftIsBack => 'Your draft is back.';

  @override
  String staffCopiedFrom(String date) {
    return 'Copied from $date. Change what was different today.';
  }

  @override
  String get staffSentAgainForReview => 'Sent again for review.';

  @override
  String get staffReportFiledDone => 'Report filed.';

  @override
  String staffNotSentReason(String reason) {
    return 'Not sent: $reason';
  }

  @override
  String staffOutboxReportLabel(String subject, String classSection, int number) {
    return '$subject, $classSection, period $number';
  }

  @override
  String get staffReportKeptForLater => 'No signal: the report is saved on this phone and sent when there is.';

  @override
  String staffReportAlreadyFiled(String date) {
    return 'This period already has a report for $date. Pull down on Today to see it.';
  }

  @override
  String get staffNothingSentNoSignal => 'No connection. Nothing was sent - try again when you have signal.';

  @override
  String get staffPeriodNoLongerYours =>
      'This period is no longer yours on the timetable, so it cannot be reported from here.';

  @override
  String get staffReportNoLongerReturned => 'This report is no longer waiting for changes - it may have been reviewed.';

  @override
  String get staffCheckInFirst =>
      'Check in first. Your teaching reports open once you are marked present today. What you typed is kept on this phone as a draft.';

  @override
  String staffSameAs(String date) {
    return 'Same as $date';
  }

  @override
  String get staffTemplates => 'Templates';

  @override
  String get staffTeachingReport => 'Teaching report';

  @override
  String get staffChangeTheReport => 'Change the report';

  @override
  String get staffBackToTodayToCheckIn => 'Back to Today to check in';

  @override
  String get staffWhatWasTaught => 'What was taught';

  @override
  String get staffWhatWasTaughtHint => 'e.g. Fractions: adding unlike denominators';

  @override
  String get staffSayWhatWasTaught => 'Say what was taught in this period.';

  @override
  String get staffHomeworkOptional => 'Homework (optional)';

  @override
  String get staffRemarksOptional => 'Remarks (optional)';

  @override
  String get staffFileReport => 'File report';

  @override
  String get staffSendAgain => 'Send again';

  @override
  String get staffSyllabusUnavailable =>
      'The syllabus could not be loaded, so no topic can be ticked off with this report. You can tick it later under Teaching.';

  @override
  String get staffSyllabusTopicOptional => 'Syllabus topic (optional)';

  @override
  String get staffSyllabusTopicHelper => 'Picking one ticks it off for this class';

  @override
  String get staffNotASyllabusTopic => 'Not a syllabus topic';

  @override
  String staffSubjectTemplates(String subject) {
    return '$subject templates';
  }

  @override
  String get staffTemplatesHint => 'Kept on this phone. Tap one to fill in the report.';

  @override
  String get staffTemplatesEmpty => 'None yet. Type a report you write often, then save it here.';

  @override
  String staffHomeworkLine(String homework) {
    return 'Homework: $homework';
  }

  @override
  String get staffDeleteTemplate => 'Delete this template';

  @override
  String get staffSaveAsTemplate => 'Save what is typed as a template';

  @override
  String get staffTypeToSaveTemplate => 'Type what was taught to save a template';

  @override
  String get staffYourHod => 'your HOD';

  @override
  String staffReviewedBy(String name) {
    return 'Reviewed by $name.';
  }

  @override
  String staffReviewedByOn(String name, String date) {
    return 'Reviewed by $name on $date.';
  }

  @override
  String staffByName(String name) {
    return 'By $name';
  }

  @override
  String get staffSyllabusTopicTicked => 'Syllabus topic ticked off';

  @override
  String get staffHomework => 'Homework';

  @override
  String get staffRemarks => 'Remarks';

  @override
  String get staffSentBackToTeacher => 'Sent back to the teacher.';

  @override
  String get staffAlreadyReviewed => 'Somebody has already reviewed this report.';

  @override
  String get staffAlreadyBackWithTeacher => 'This report is already back with its teacher.';

  @override
  String get staffNotYoursToSendBack => 'This report is not from your department, so it is not yours to send back.';

  @override
  String get staffNotSentBackNoSignal => 'No connection. It was not sent back - try again when you have signal.';

  @override
  String get staffReportReviewedDone => 'Report reviewed.';

  @override
  String get staffNotYoursToReview => 'This report is not from your department, so it is not yours to review.';

  @override
  String get staffNotReviewedNoSignal => 'No connection. It was not reviewed - try again when you have signal.';

  @override
  String get staffTheTeacher => 'the teacher';

  @override
  String staffReturnedWaiting(String name) {
    return 'Sent back to $name. It comes back to your list when they send it again - or mark it reviewed now if it was fine after all.';
  }

  @override
  String get staffMarkReviewed => 'Mark reviewed';

  @override
  String get staffSendBackWithNote => 'Send back with a note';

  @override
  String staffSentBackBy(String name) {
    return 'Sent back by $name';
  }

  @override
  String staffNoteFrom(String name) {
    return 'Note from $name';
  }

  @override
  String get staffChangeAndSendAgain => 'Change and send again';

  @override
  String get staffSayWhatShouldChange => 'Say what should change.';

  @override
  String get staffSendBackToTeacherQ => 'Send back to the teacher?';

  @override
  String get staffWhatShouldChange => 'What should change';

  @override
  String get staffWhatShouldChangeHint => 'e.g. Please add what the class practised.';

  @override
  String get staffSendBack => 'Send back';

  @override
  String get staffTakeAPhoto => 'Take a photo';

  @override
  String get staffChooseFromPhotos => 'Choose from your photos';

  @override
  String get staffPhotoAdded => 'Photo added.';

  @override
  String get staffRemovePhotoQ => 'Remove this photo?';

  @override
  String get staffRemovePhotoBody => 'It is taken off the report for good.';

  @override
  String get staffRemove => 'Remove';

  @override
  String get staffPhotoRemoved => 'Photo removed.';

  @override
  String get staffNoConnectionTryLater => 'No connection. Try again when you have signal.';

  @override
  String get staffPhotos => 'Photos';

  @override
  String get staffAdd => 'Add';

  @override
  String staffReportPhotosHint(int max) {
    return 'Up to $max - the board, or the children\'s work. Seen by your HOD and the office, never by parents.';
  }

  @override
  String get staffPhotoNotShown => 'This photo could not be shown.';

  @override
  String get staffRemovePhoto => 'Remove photo';

  @override
  String get staffNewClassTest => 'New class test';

  @override
  String get staffNewTestNoClassesBody =>
      'A test is set for a class you teach. Your school office puts you on the timetable.';

  @override
  String get staffNoTermsYet => 'This school year has no terms yet.';

  @override
  String get staffNoTermsYetBody =>
      'A test belongs to a term. Ask your school office to set up the terms under Academics.';

  @override
  String get staffOutOfHowMany => 'Out of how many marks?';

  @override
  String get staffEnterANumber => 'Enter a number, like 20 or 25.5.';

  @override
  String get staffMaxMoreThanZero => 'The maximum has to be more than 0.';

  @override
  String get staffMaxTooBig => 'That is more than a test can carry.';

  @override
  String get staffEnterNumberOrBlank => 'Enter a number, or leave it blank.';

  @override
  String get staffBetweenZeroAndMax => 'Between 0 and the maximum.';

  @override
  String staffNoTermCovers(String date) {
    return 'No term of this school year covers $date. Pick another day.';
  }

  @override
  String get staffTestSet => 'Test set. Enter the marks.';

  @override
  String get staffNothingSavedNoSignal => 'No connection. Nothing was saved - try again when you have signal.';

  @override
  String get staffClassAndSubject => 'Class and subject';

  @override
  String get staffTitle => 'Title';

  @override
  String get staffTestTitleHint => 'e.g. Fractions - unit test';

  @override
  String get staffGiveTestTitle => 'Give the test a title.';

  @override
  String get staffKindOfTest => 'Kind of test';

  @override
  String get staffDayOfTest => 'Day of the test';

  @override
  String get staffNoTermCoversDay => 'No term covers this day';

  @override
  String get staffOutOfLabel => 'Out of';

  @override
  String get staffPassMark => 'Pass mark';

  @override
  String get staffOptional => 'Optional';

  @override
  String staffPassMarkDefault(String percent) {
    return 'Optional. Blank: $percent% of the maximum';
  }

  @override
  String staffGradesByScale(String scale) {
    return 'Grades by the $scale scale.';
  }

  @override
  String get staffSetTest => 'Set test';

  @override
  String get staffNotANumber => 'Not a number';

  @override
  String staffOutOfMarks(String max) {
    return 'Out of $max';
  }

  @override
  String get staffMarksSaved => 'Marks saved.';

  @override
  String get staffMarksKeptForLater =>
      'No signal: these marks are saved on this phone and sent when there is. Publish once they are in.';

  @override
  String get staffTestAlreadyPublished => 'This test has been published, so its marks cannot change here.';

  @override
  String get staffSomeMarksRefused => 'Some marks were not accepted. See the highlighted students.';

  @override
  String staffOutboxMarksLabel(String title) {
    return 'Marks: $title';
  }

  @override
  String get staffMarksStillWaiting =>
      'These marks are still waiting on this phone for signal. Publish once they are sent.';

  @override
  String get staffPublishResultsQ => 'Publish the results?';

  @override
  String staffPublishFirstBody(int count) {
    return 'The marks of $count students become final, and their guardians are told, as your school has set it up. Only your HOD or the office can reopen it.';
  }

  @override
  String get staffPublishAgainBody =>
      'The marks become final again. Guardians were told when it was first published, and are not messaged a second time.';

  @override
  String get staffPublish => 'Publish';

  @override
  String get staffResultsPublished => 'Results published.';

  @override
  String get staffNothingPublishedNoSignal => 'No connection. Nothing was published - try again when you have signal.';

  @override
  String get staffLeaveWithoutSavingQ => 'Leave without saving?';

  @override
  String get staffLeaveWithoutSavingBody => 'The marks you typed since the last save will be lost.';

  @override
  String get staffKeepEntering => 'Keep entering';

  @override
  String get staffLeaveScreen => 'Leave';

  @override
  String get staffMarksPublishedBanner =>
      'Published. The marks are final here; your HOD or the office can reopen the test.';

  @override
  String get staffNobodyToMark => 'Nobody in this class to mark.';

  @override
  String staffMarksFixFirst(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count marks are not numbers or are out of range. Fix them to save.',
      one: '1 mark is not a number or is out of range. Fix it to save.',
    );
    return '$_temp0';
  }

  @override
  String get staffSaveMarks => 'Save marks';

  @override
  String get staffSaved => 'Saved';

  @override
  String staffMarkedCount(int marked, int total) {
    return '$marked of $total marked';
  }

  @override
  String staffPassMarks(String marks) {
    return 'pass $marks';
  }

  @override
  String staffLeft(int count) {
    return '$count left';
  }

  @override
  String staffRoll(String number) {
    return 'Roll $number';
  }

  @override
  String get staffBelowPass => 'Below pass';

  @override
  String get staffMyProfile => 'My Profile';

  @override
  String get staffPhotoMustBeImage => 'The photo must be a JPEG or PNG image.';

  @override
  String get staffPhotoTooBig => 'The photo must be 2 MB or smaller.';

  @override
  String get staffPhotoUnreadable => 'The photo could not be read. Try another file.';

  @override
  String get staffPhotoUpdated => 'Photo updated.';

  @override
  String get staffChooseFromPhotosShort => 'Choose from photos';

  @override
  String get staffRemovePhotoShortQ => 'Remove photo?';

  @override
  String get staffInitialsInstead => 'Your initials will be shown instead.';

  @override
  String get staffPhoto => 'Photo';

  @override
  String get staffUploadPhoto => 'Upload photo';

  @override
  String get staffChangePhoto => 'Change photo';

  @override
  String staffFieldRequired(String field) {
    return '$field is required';
  }

  @override
  String staffFieldMax100(String field) {
    return '$field must be 100 characters or fewer';
  }

  @override
  String get staffProfileUpdated => 'Profile updated.';

  @override
  String get staffMyDetails => 'My details';

  @override
  String get staffFirstName => 'First name';

  @override
  String get staffLastName => 'Last name';

  @override
  String get staffMobile => 'Mobile';

  @override
  String get staffMobileLockedHelper => 'You sign in with this number. Ask your school office to change it.';

  @override
  String get staffHomeAddress => 'Home address';

  @override
  String get staffHomeAddressTooLong => 'Home address must be 500 characters or fewer';

  @override
  String get staffSave => 'Save';

  @override
  String get staffEmailChanged => 'Email changed. Other devices have been signed out.';

  @override
  String get staffSignInEmail => 'Sign-in email';

  @override
  String get staffNoEmailOnRecord => 'No email on record';

  @override
  String get staffEmailKeptBySchool =>
      'You sign in with your mobile number and passcode. Your school office keeps your email address.';

  @override
  String get staffChangeEmail => 'Change email';

  @override
  String get staffWorkDetails => 'Work details';

  @override
  String get staffEmployeeId => 'Employee ID';

  @override
  String get staffDesignation => 'Designation';

  @override
  String get staffJoiningDate => 'Joining date';

  @override
  String get staffSchool => 'School';

  @override
  String get staffKeptByAdmins => 'These are kept by your school\'s administrators.';

  @override
  String get staffSecurity => 'Security';

  @override
  String get staffChangePassword => 'Change password';

  @override
  String get staffSignedInDevices => 'Signed-in devices';

  @override
  String get staffChangeSignInEmail => 'Change sign-in email';

  @override
  String staffYouSignInAs(String email) {
    return 'You sign in as $email. Other devices will be signed out.';
  }

  @override
  String get staffNewEmail => 'New email';

  @override
  String get staffEnterNewEmail => 'Enter the new email';

  @override
  String get staffEnterValidEmail => 'Enter a valid email';

  @override
  String get staffChangePasswordTitle => 'Change Password';

  @override
  String get staffChooseNewPassword => 'Choose a new password for your account.';

  @override
  String staffSignedOutOf(String device) {
    return 'Signed out of $device.';
  }

  @override
  String get staffSignOutOthersQ => 'Sign out of all other devices?';

  @override
  String get staffSignOutOthersBody =>
      'Every other browser and phone signed in to this account will have to sign in again.';

  @override
  String get staffSignOutOthers => 'Sign out others';

  @override
  String staffSignedOutOthers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Signed out of $count other devices.',
      one: 'Signed out of 1 other device.',
    );
    return '$_temp0';
  }

  @override
  String get staffSessionLifetime => 'A device is signed out after 7 days without use, and 30 days after signing in.';

  @override
  String staffLastUsed(String when) {
    return 'Last used $when';
  }

  @override
  String staffSignedInAt(String when) {
    return 'Signed in $when';
  }

  @override
  String get staffThisDevice => 'This device';

  @override
  String get staffSignOutAllOthers => 'Sign out of all other devices';

  @override
  String get staffMaintenanceBadge => 'Scheduled maintenance';

  @override
  String get staffMaintenanceHeadline => 'We\'re making School365ai better.';

  @override
  String get staffMaintenanceBody =>
      'The platform is briefly offline while we finish some planned work. Nothing has been lost - attendance, records and messages are all exactly where you left them, and will be there when we are back.';

  @override
  String get staffMaintenanceStillDown =>
      'Still offline as of a moment ago. We expect to be back shortly - if this is urgent, contact your school administrator.';

  @override
  String get staffMaintenanceBackShortly =>
      'We expect to be back shortly. If this is urgent, contact your school administrator.';

  @override
  String get staffNameOrAdmission => 'Name or admission number';

  @override
  String get staffNoStudentsToShow => 'No students to show.';

  @override
  String staffNoStudentMatches(String query) {
    return 'No student you can see matches \"$query\".';
  }

  @override
  String staffAdmissionShort(String number) {
    return 'Adm. $number';
  }

  @override
  String staffGuardian(String name) {
    return 'Guardian: $name';
  }

  @override
  String get staffCall => 'Call';

  @override
  String staffStudentsPhoto(String name) {
    return '$name\'s photo';
  }

  @override
  String get staffDiallerFailed => 'Could not open the phone\'s dialler.';

  @override
  String get staffStudentPhotoTooBig => 'The photo must be 5 MB or smaller.';

  @override
  String get staffPhotoSaved => 'Photo saved.';

  @override
  String staffStudentInitialsInstead(String name) {
    return '$name\'s initials will be shown instead.';
  }

  @override
  String get staffAddPhoto => 'Add photo';

  @override
  String get staffToCall => 'To call';

  @override
  String get staffCalled => 'Called';

  @override
  String get staffCallRequestsHeading => 'Call Requests';

  @override
  String get staffCallRequestsIntro =>
      'Parents ask to be called from the Family app. Ring them on the number shown, then mark it called.';

  @override
  String get staffNobodyWaitingForCall => 'Nobody is waiting for a call.';

  @override
  String get staffNoCallsMarked => 'No calls marked yet.';

  @override
  String staffAboutStudentLower(String name) {
    return 'about $name';
  }

  @override
  String get staffToTheOffice => 'To the office';

  @override
  String staffToPerson(String name) {
    return 'To $name';
  }

  @override
  String get staffTheClassTeacher => 'the class teacher';

  @override
  String staffGoodTime(String time) {
    return 'Good time: $time';
  }

  @override
  String staffCalledBy(String name) {
    return 'Called by $name';
  }

  @override
  String get staffTheSchool => 'the school';

  @override
  String get staffMarkAsCalled => 'Mark as called';

  @override
  String get staffMarkedAsCalled => 'Marked as called. The parent can see that.';

  @override
  String staffCalledPersonQ(String name) {
    return 'Called $name?';
  }

  @override
  String get staffHowDidItGo => 'How did it go? (optional)';

  @override
  String get staffOnlySchoolSeesNote => 'Only the school sees this note.';

  @override
  String get staffFeesCollect => 'Collect';

  @override
  String get staffFeesOverdue => 'Overdue';

  @override
  String get staffFeesFindStudent => 'Find a student by name or admission number';

  @override
  String get staffFeesCollectHint => 'Find the student paying. Their statement opens, with Record payment.';

  @override
  String staffFeesNoMatch(String query) {
    return 'No student this year matches \"$query\".';
  }

  @override
  String get staffFeesNothingToday => 'Nothing collected yet today.';

  @override
  String staffReceiptsToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count receipts today',
      one: '1 receipt today',
    );
    return '$_temp0';
  }

  @override
  String get staffFeesNobodyOverdue => 'Nobody is overdue.';

  @override
  String staffStudentsOverdue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count students with fees overdue',
      one: '1 student with fees overdue',
    );
    return '$_temp0';
  }

  @override
  String staffOverdueAmount(String amount) {
    return 'Overdue $amount';
  }

  @override
  String staffOwesAmount(String amount) {
    return 'Owes $amount';
  }

  @override
  String staffCallPerson(String name) {
    return 'Call $name';
  }

  @override
  String get staffTheGuardian => 'the guardian';

  @override
  String get staffAllStudents => 'All students';

  @override
  String get staffStatementPdf => 'Statement PDF';

  @override
  String get staffAddDiscount => 'Add Discount';

  @override
  String get staffRecordPayment => 'Record Payment';

  @override
  String staffAdmissionNo(String number) {
    return 'Adm. no. $number';
  }

  @override
  String staffJoined(String date) {
    return 'Joined $date';
  }

  @override
  String get staffFeeCharged => 'Charged';

  @override
  String get staffFeeDiscount => 'Discount';

  @override
  String get staffFeePaid => 'Paid';

  @override
  String get staffFeeWaived => 'Waived';

  @override
  String get staffFeeBalance => 'Balance';

  @override
  String staffNothingCharged(String year) {
    return 'Nothing has been charged for $year. Fees are charged once they are published for this student\'s class or bus route.';
  }

  @override
  String get staffDiscounts => 'Discounts';

  @override
  String get staffPayments => 'Payments';

  @override
  String get staffReasonClassChanged => 'moved to another class';

  @override
  String get staffReasonRouteChanged => 'moved to another bus route';

  @override
  String get staffReasonLeft => 'no longer at the school';

  @override
  String get staffReasonFeeChanged => 'the fee was changed';

  @override
  String staffWasDueNotCharged(String date, String reason) {
    return 'Was due $date - not charged: $reason';
  }

  @override
  String staffWasDueWaived(String date) {
    return 'Was due $date - waived';
  }

  @override
  String staffWasDueWaivedWhy(String date, String reason) {
    return 'Was due $date - waived: $reason';
  }

  @override
  String staffAddedOn(String date) {
    return 'Added $date';
  }

  @override
  String staffDueOn(String date) {
    return 'Due $date';
  }

  @override
  String get staffCancelled => 'Cancelled';

  @override
  String get staffCoveredByDiscount => 'Covered by discount';

  @override
  String get staffPartPaid => 'Part paid';

  @override
  String get staffFeeDue => 'Due';

  @override
  String get staffLateFine => 'Late fine';

  @override
  String staffDiscountAmount(String amount) {
    return 'Discount $amount';
  }

  @override
  String staffPaidAmount(String amount) {
    return 'Paid $amount';
  }

  @override
  String get staffPaidFromCredit => 'Paid from the student\'s credit';

  @override
  String staffFromCredit(String amount) {
    return '$amount from credit';
  }

  @override
  String staffBalanceAmount(String amount) {
    return 'Balance $amount';
  }

  @override
  String get staffWaive => 'Waive';

  @override
  String staffOffEachInstallment(String amount, String head) {
    return '$amount off each $head installment';
  }

  @override
  String get staffFee => 'fee';

  @override
  String staffByLower(String name) {
    return 'by $name';
  }

  @override
  String get staffEndDiscount => 'End discount';

  @override
  String get staffDownloadReceipt => 'Download receipt';

  @override
  String get staffCancelReceipt => 'Cancel receipt';

  @override
  String get staffReceiptDownloadFailed => 'The receipt could not be downloaded. Try again.';

  @override
  String get staffStatementDownloadFailed => 'The statement could not be downloaded. Try again.';

  @override
  String get staffReceiptEmailed => 'The receipt is on its way to the guardian.';

  @override
  String get staffReceiptEmailFailed => 'The receipt could not be emailed. Try again.';

  @override
  String staffReceiptCancelled(String number) {
    return 'Receipt $number cancelled. What it paid is owed again.';
  }

  @override
  String get staffReceiptCancelFailed => 'The receipt could not be cancelled. Try again.';

  @override
  String staffCancelReceiptQ(String number) {
    return 'Cancel receipt $number?';
  }

  @override
  String get staffCancelReceiptBody =>
      'The receipt stays on record, marked cancelled, and keeps its number. The installments it paid are owed again. This cannot be undone.';

  @override
  String get staffCancelReceiptHint => 'e.g. Cheque bounced';

  @override
  String get staffSayWhyCancel => 'Say why the receipt is being cancelled.';

  @override
  String get staffKeepReceipt => 'Keep receipt';

  @override
  String get staffTickInstallment => 'Tick at least one installment, with an amount above zero.';

  @override
  String get staffEnterAmountAboveZero => 'Enter an amount above zero.';

  @override
  String staffRecordPaymentFor(String name) {
    return 'Record payment - $name';
  }

  @override
  String staffOwesNothingFor(String year) {
    return 'Owes nothing for $year. A payment now is held as credit for the next fees.';
  }

  @override
  String staffOwesFor(String amount, String year) {
    return 'Owes $amount for $year.';
  }

  @override
  String get staffDateReceived => 'Date received';

  @override
  String get staffPaidBy => 'Paid by';

  @override
  String get staffChequeNumber => 'Cheque number';

  @override
  String get staffReferenceOptional => 'Reference (optional)';

  @override
  String get staffEnterChequeNumber => 'Enter the cheque number.';

  @override
  String get staffChooseInstallments => 'Choose the installments it pays';

  @override
  String get staffChooseInstallmentsOff => 'Off: it goes to what is owed, oldest first.';

  @override
  String get staffNoteOptional => 'Note (optional)';

  @override
  String get staffEmailReceiptToGuardian => 'Email the receipt to the guardian';

  @override
  String get staffRecordPaymentButton => 'Record payment';

  @override
  String get staffAmountReceived => 'Amount received';

  @override
  String get staffPayEverythingOwed => 'Pay everything owed';

  @override
  String staffMoreThanOwed(String amount) {
    return '$amount more than is owed - it will be held as credit for the next fees.';
  }

  @override
  String staffDueAndOwes(String date, String amount) {
    return 'Due $date · owes $amount';
  }

  @override
  String get staffPay => 'Pay';

  @override
  String staffPaying(String amount) {
    return 'Paying $amount';
  }

  @override
  String staffReceiptNumber(String number) {
    return 'Receipt $number';
  }

  @override
  String staffReceivedFrom(String amount, String name, String date, String mode) {
    return '$amount received from $name on $date by $mode.';
  }

  @override
  String get staffOwedBefore => 'Owed before this payment';

  @override
  String get staffPaidNow => 'Paid now';

  @override
  String get staffHeldAsCredit => 'Held as credit for the next fees';

  @override
  String get staffStillOwed => 'Still owed';

  @override
  String get staffReceiptBeingEmailed => 'The receipt is being emailed to the guardian.';

  @override
  String get staffDownloadPdf => 'Download PDF';

  @override
  String get staffDone => 'Done';

  @override
  String staffWaiveQ(String label) {
    return 'Waive \"$label\"?';
  }

  @override
  String get staffWaiveBody =>
      'What is still owed on it is forgiven and it no longer counts as owing. Anything already paid stays paid. This cannot be undone.';

  @override
  String get staffWaiveHint => 'e.g. Hardship, fine charged in error';

  @override
  String staffWaived(String label) {
    return '\"$label\" waived.';
  }

  @override
  String get staffWaiveFailed => 'It could not be waived. Try again.';

  @override
  String get staffEndDiscountQ => 'End this discount?';

  @override
  String get staffEndDiscountBody =>
      'The installments it lowered that are still unpaid go back to their full amount. The discount stays on record as ended.';

  @override
  String get staffDiscountEnded => 'Discount ended.';

  @override
  String get staffDiscountEndFailed => 'The discount could not be ended. Try again.';

  @override
  String staffDiscountAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Discount added - $count installments lowered.',
      one: 'Discount added - 1 installment lowered.',
    );
    return '$_temp0';
  }

  @override
  String staffAddDiscountFor(String name) {
    return 'Add discount - $name';
  }

  @override
  String staffDiscountIntro(String year) {
    return 'For $year. It lowers each unpaid installment now, and any charged later this year. Late fines are never discounted.';
  }

  @override
  String get staffFeeType => 'Fee type';

  @override
  String get staffAllFeeTypes => 'All fee types';

  @override
  String get staffFixedAmount => 'Fixed amount';

  @override
  String get staffPercentage => 'Percentage';

  @override
  String staffAmountIn(String currency) {
    return 'Amount ($currency)';
  }

  @override
  String get staffOffEach => 'Off each installment.';

  @override
  String get staffOffEachNotOnce => 'Off each installment, not once for the year.';

  @override
  String get staffEnterValueAboveZero => 'Enter a value above zero.';

  @override
  String get staffPercentMax => 'A percentage cannot be more than 100.';

  @override
  String get staffDiscountReasonHint => 'e.g. Sibling discount, scholarship, staff child';

  @override
  String get staffSayWhyDiscount => 'Say why the discount is given.';

  @override
  String get staffAddDiscountButton => 'Add discount';

  @override
  String get staffGiveAReason => 'Give a reason.';

  @override
  String get staffInCredit => 'In credit - it pays the next fees charged, oldest first.';

  @override
  String get staffHistory => 'History';

  @override
  String get staffRefund => 'Refund';

  @override
  String staffCreditHistoryFor(String name) {
    return 'Credit history - $name';
  }

  @override
  String get staffNoCreditMoved => 'No credit has moved on this account yet.';

  @override
  String staffPageOf(int page, int pages) {
    return 'Page $page of $pages';
  }

  @override
  String get staffNewer => 'Newer';

  @override
  String get staffOlder => 'Older';

  @override
  String staffRefundRecorded(String amount) {
    return 'Refund of $amount recorded.';
  }

  @override
  String staffOnlyHeldInCredit(String amount) {
    return 'Only $amount is held in credit.';
  }

  @override
  String staffRefundCreditFor(String name) {
    return 'Refund credit - $name';
  }

  @override
  String staffHoldsCredit(String amount) {
    return 'Holds $amount in credit. Record money you have handed back to the family - it comes off the credit.';
  }

  @override
  String get staffCurrency => 'Currency';

  @override
  String get staffAmountRefunded => 'Amount refunded';

  @override
  String get staffDateRefunded => 'Date refunded';

  @override
  String get staffPaidBackBy => 'Paid back by';

  @override
  String get staffRefundReasonHint => 'e.g. Left the school';

  @override
  String get staffSayWhyRefund => 'Say why the money is refunded.';

  @override
  String get staffRecordRefund => 'Record refund';

  @override
  String get staffAttendanceUpdated => 'Attendance updated.';

  @override
  String get staffAttendanceSubmitted => 'Attendance submitted.';

  @override
  String get staffOnLeaveThatDay => 'On leave that day';

  @override
  String get staffMarkPresentAnyway => 'Mark present anyway';

  @override
  String get widgetToday => 'Today';

  @override
  String widgetAsOf(String time) {
    return 'as of $time';
  }

  @override
  String get widgetTapToOpen => 'Tap to open';

  @override
  String get widgetSignIn => 'Sign in to see your day';

  @override
  String get widgetSchoolClosed => 'The school is closed today';

  @override
  String widgetHoliday(String name) {
    return 'Holiday: $name';
  }

  @override
  String get widgetOnLeave => 'You are on leave today';

  @override
  String widgetNowPeriod(int number, String subject, String section) {
    return 'Now: P$number $subject · $section';
  }

  @override
  String widgetNextPeriod(int number, String subject, String section, String time) {
    return 'Next: P$number $subject · $section at $time';
  }

  @override
  String get widgetNoPeriods => 'No periods today';

  @override
  String get widgetNoMorePeriods => 'No more periods today';

  @override
  String get widgetRegisterTaken => 'Register taken';

  @override
  String widgetRegisterNotTaken(String section) {
    return 'Register not taken: $section';
  }

  @override
  String widgetRegistersNotTaken(int count) {
    return '$count registers not taken';
  }

  @override
  String get widgetReportsUpToDate => 'Reports up to date';

  @override
  String widgetReportsOwed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports owed',
      one: '1 report owed',
    );
    return '$_temp0';
  }

  @override
  String widgetCheckedIn(String time) {
    return 'Checked in at $time';
  }

  @override
  String get widgetNotCheckedIn => 'Not checked in yet';

  @override
  String get widgetNoSchool => 'No school today';

  @override
  String widgetNoSchoolHoliday(String name) {
    return 'No school today: $name';
  }

  @override
  String widgetAttendance(String mark) {
    return 'Today: $mark';
  }

  @override
  String get widgetMarkPresent => 'Present';

  @override
  String get widgetMarkAbsent => 'Absent';

  @override
  String get widgetMarkLeave => 'On leave';

  @override
  String get widgetMarkNotMarked => 'Not marked yet';

  @override
  String widgetBus(String status) {
    return 'Bus: $status';
  }

  @override
  String widgetBusAt(String status, String time) {
    return 'Bus: $status, $time';
  }

  @override
  String widgetBusPickup(String time) {
    return 'Bus pick-up $time';
  }

  @override
  String get widgetTripCancelled => 'Trip cancelled';

  @override
  String get widgetReachedSchool => 'Reached school';

  @override
  String get widgetTripEnded => 'Trip ended';

  @override
  String get widgetOnBusToSchool => 'On the bus to school';

  @override
  String get widgetOnBusHome => 'On the bus home';

  @override
  String get widgetDropped => 'Dropped at the stop';

  @override
  String get widgetNoBus => 'Did not take the bus';

  @override
  String get widgetBusOnItsWay => 'Bus on its way';

  @override
  String widgetFeesOverdue(String amount) {
    return 'Fees: $amount overdue';
  }

  @override
  String widgetFeesDue(String amount, String date) {
    return 'Fees: $amount due $date';
  }
}
