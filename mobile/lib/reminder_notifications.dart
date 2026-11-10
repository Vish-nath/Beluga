import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
      InitializationSettings(
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

  /// Schedule all notifications from local data.
  static Future<void> syncFromLocal({
    required List<Map<String, dynamic>> meals,
    required List<Map<String, dynamic>> medications,
    required List<Map<String, dynamic>> appointments,
  }) async {
    if (!_initialized) return;
    await _plugin.cancelAll();

    // Schedule meal reminders
    for (final meal in meals) {
      final id = meal['id'];
      final name = meal['meal_name']?.toString() ?? 'Meal';
      final time = meal['scheduled_time']?.toString() ?? '';
      if (id == null || time.isEmpty) continue;

      await _scheduleDaily(
        key: 'meal:$id',
        title: '🍽️ Meal time: $name',
        body: 'Time to have your $name.',
        time: time,
        actionLabel: 'Done',
        payload: jsonEncode({'kind': 'meal', 'id': id, 'name': name}),
      );
    }

    // Schedule medication reminders (before / after meal / custom time)
    for (final med in medications) {
      final id = med['id'];
      final name = med['name']?.toString() ?? 'Medicine';
      final time = med['scheduled_time']?.toString() ?? '';
      final timing = med['timing']?.toString() ?? 'before_meal';
      final dose = med['prescribed_dose']?.toString() ?? '';
      final instructions = med['instructions']?.toString() ?? '';
      if (id == null || time.isEmpty) continue;

      String timingLabel;
      switch (timing) {
        case 'before_meal':
          timingLabel = 'before your meal';
          break;
        case 'after_meal':
          timingLabel = 'after your meal';
          break;
        default:
          timingLabel = 'as scheduled';
      }

      final body = [
        if (dose.isNotEmpty) dose,
        timingLabel,
        if (instructions.isNotEmpty) instructions,
      ].join(' · ');

      await _scheduleDaily(
        key: 'medication:$id',
        title: '💊 Take medication: $name',
        body: body.isEmpty ? 'Follow the instructions provided by your doctor.' : body,
        time: time,
        actionLabel: 'Taken',
        payload: jsonEncode({'kind': 'medication', 'id': id, 'name': name, 'time': time}),
      );
    }

    // Schedule doctor appointment reminders (one-time, morning of the day)
    for (final appt in appointments) {
      final id = appt['id'];
      final doctor = appt['doctor_name']?.toString() ?? 'Doctor';
      final date = appt['appointment_date']?.toString() ?? '';
      final time = appt['appointment_time']?.toString() ?? '09:00';
      if (id == null || date.isEmpty) continue;

      final appointmentDate = DateTime.tryParse(date);
      if (appointmentDate == null) continue;
      final now = DateTime.now();
      if (appointmentDate.isBefore(DateTime(now.year, now.month, now.day))) continue;

      // Remind 1 hour before appointment
      final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(time);
      if (match == null) continue;
      var hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      // 1 hour before
      final reminderHour = hour > 0 ? hour - 1 : 0;

      final scheduledDate = timezone.TZDateTime(
        timezone.local,
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
        reminderHour,
        minute,
      );

      if (scheduledDate.isBefore(timezone.TZDateTime.now(timezone.local))) continue;

      await _plugin.zonedSchedule(
        _notificationId('appointment:$id'),
        '🩺 Doctor appointment in 1 hour',
        'Visit $doctor at $time',
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'beluga_appointments',
            'Appointments',
            channelDescription: 'Doctor appointment reminders',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
          ),
          iOS: const DarwinNotificationDetails(categoryIdentifier: 'health_reminder'),
          macOS: const DarwinNotificationDetails(categoryIdentifier: 'health_reminder'),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({'kind': 'appointment', 'id': id}),
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

  static final _darwinCategories = [
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
