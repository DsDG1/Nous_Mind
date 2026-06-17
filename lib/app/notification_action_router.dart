import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/router.dart';
import 'package:nousmind/services/notification_service.dart';
import 'package:nousmind/viewmodels/reminders_view_model.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';

/// Routes a notification action button press to the right
/// [RemindersViewModel] call. Snooze pushes the reminder's fire time
/// forward by the user's current snooze duration and re-schedules;
/// complete soft-deletes the reminder so the user can still recover
/// it from the trash page if the press was a misclick.
///
/// The handler runs in two cases:
///  1. The app is in the foreground when the user taps the action.
///  2. The app was cold-launched by the action (handled inside
///     [NotificationService.init] via `getNotificationAppLaunchDetails`).
///
/// In both cases the Provider tree may or may not be mounted yet at
/// the very first frame; the helper gracefully no-ops if it cannot
/// find the view model.
class NotificationActionRouter {
  const NotificationActionRouter();

  static final List<NotificationResponse> _pendingResponses = <NotificationResponse>[];

  void route(NotificationResponse response) {
    final action = response.actionId;
    final reminderId = response.payload;
    if (action == null || reminderId == null || reminderId.isEmpty) return;
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) {
      developer.log('Navigator context is null, queueing notification action response: actionId=$action, payload=$reminderId');
      _pendingResponses.add(response);
      return;
    }
    _handleResponse(navigatorContext, response);
  }

  /// Processes any queued notification responses using the provided [context].
  static void processPending(BuildContext context) {
    if (_pendingResponses.isEmpty) return;
    developer.log('Processing ${_pendingResponses.length} pending notification action responses');
    final copy = List<NotificationResponse>.from(_pendingResponses);
    _pendingResponses.clear();
    for (final response in copy) {
      _handleResponse(context, response);
    }
  }

  static void _handleResponse(BuildContext navigatorContext, NotificationResponse response) {
    final action = response.actionId;
    final reminderId = response.payload;
    if (action == null || reminderId == null || reminderId.isEmpty) return;
    try {
      final reminders = Provider.of<RemindersViewModel>(
        navigatorContext,
        listen: false,
      );
      final settings = Provider.of<SettingsViewModel>(
        navigatorContext,
        listen: false,
      );
      final messenger = ScaffoldMessenger.of(navigatorContext);
      switch (action) {
        case NotificationService.kSnoozeActionId:
          unawaited(
            reminders.snoozeReminder(
              reminderId,
              settings.settings.snoozeDuration.duration,
            ),
          );
          break;
        case NotificationService.kCompleteActionId:
          unawaited(reminders.softDelete(reminderId));
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('已移入回收站')));
          break;
      }
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to handle notification action',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
