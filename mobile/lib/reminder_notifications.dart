import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

final reminderNotificationActions = StreamController<NotificationResponse>.broadcast();

class ReminderNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static NotificationResponse? _launchResponse;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(localTimezone));

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(notificationCategories: _darwinCategories),
        macOS: DarwinInitializationSettings(notificationCategories: _darwinCategories),
      ),
      onDidReceiveNotificationResponse: (response) {
        reminderNotificationActions.add(response);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    _launchResponse = launch?.notificationResponse;
    _initialized = true;
  }

  static NotificationResponse? takeLaunchResponse() {
    final response = _launchResponse;
    _launchResponse = null;
    return response;
  }

  static Future<bool?> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true, badge: true);
    }
    return null;
  }

  static Future<void> sync({
    required List<Map<String, dynamic>> prescriptions,
    required List<Map<String, dynamic>> reminders,
  }) async {
    if (!_initialized) return;
    await _plugin.cancelAll();

    for (final prescription in prescriptions) {
      final id = prescription['id']?.toString();
      final name = prescription['name']?.toString() ?? 'Prescribed medicine';
      if (id == null || id.isEmpty) continue;
      final times = (prescription['intake_times'] as List? ?? []).cast<String>();
      final details = [
        if ((prescription['prescribed_dose'] ?? '').toString().isNotEmpty)
          prescription['prescribed_dose'].toString(),
        if ((prescription['quantity'] ?? '').toString().isNotEmpty)
          'Quantity: ${prescription['quantity']}',
        if ((prescription['instructions'] ?? '').toString().isNotEmpty)
          prescription['instructions'].toString(),
      ].join(' · ');
      for (final time in times) {
        await _scheduleDaily(
          key: 'prescription:$id:$time',
          title: 'Prescription reminder: $name',
          body: details.isEmpty ? 'Follow the instructions provided by your doctor.' : details,
          time: time,
          actionLabel: 'Taken',
          payload: jsonEncode({'kind': 'prescription', 'id': id, 'time': time}),
        );
      }
    }

    for (final reminder in reminders) {
      final id = reminder['id'];
      final time = reminder['scheduled_time']?.toString();
      if (id == null || time == null) continue;
      await _scheduleDaily(
        key: 'reminder:$id',
        title: reminder['title']?.toString() ?? 'Health reminder',
        body: reminder['instruction']?.toString() ?? '',
        time: time,
        actionLabel: 'Done',
        payload: jsonEncode({'kind': 'reminder', 'id': id}),
      );
    }
  }

  static Future<void> _scheduleDaily({
    required String key,
    required String title,
    required String body,
    required String time,
    required String actionLabel,
    required String payload,
  }) async {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(time);
    if (match == null) return;
    final now = timezone.TZDateTime.now(timezone.local);
    final today = timezone.TZDateTime(
      timezone.local,
      now.year,
      now.month,
      now.day,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
    final scheduledDate = today.isAfter(now) ? today : today.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      _notificationId(key),
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'beluga_health_reminders',
          'Health reminders',
          channelDescription: 'Daily medication and meal reminders',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          actions: [
            AndroidNotificationAction(
              'mark_complete',
              actionLabel,
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(categoryIdentifier: 'health_reminder'),
        macOS: const DarwinNotificationDetails(categoryIdentifier: 'health_reminder'),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  static int _notificationId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static const _darwinCategories = [
    DarwinNotificationCategory(
      'health_reminder',
      actions: [
        DarwinNotificationAction.plain(
          'mark_complete',
          'Done',
          options: {DarwinNotificationActionOption.foreground},
        ),
      ],
    ),
  ];
}