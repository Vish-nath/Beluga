import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Singleton offline database for Beluga Health.
/// All data lives locally – nothing is sent to a server.
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'beluga_health.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY DEFAULT 1,
        name TEXT NOT NULL DEFAULT '',
        age INTEGER,
        gender TEXT DEFAULT '',
        blood_type TEXT DEFAULT '',
        height_cm REAL,
        weight_kg REAL,
        location TEXT DEFAULT '',
        conditions TEXT DEFAULT '',
        appetite TEXT DEFAULT '',
        daily_routine TEXT DEFAULT '',
        family_history TEXT DEFAULT '',
        profile_image TEXT DEFAULT '',
        created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
      )
    ''');

    await db.execute('''
      CREATE TABLE meal_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        meal_name TEXT NOT NULL,
        scheduled_time TEXT NOT NULL,
        notes TEXT DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE medications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        prescribed_dose TEXT DEFAULT '',
        quantity TEXT DEFAULT '',
        instructions TEXT DEFAULT '',
        timing TEXT NOT NULL DEFAULT 'before_meal',
        linked_meal_id INTEGER,
        scheduled_time TEXT NOT NULL DEFAULT '08:00',
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE doctor_appointments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doctor_name TEXT NOT NULL,
        specialty TEXT DEFAULT '',
        appointment_date TEXT NOT NULL,
        appointment_time TEXT NOT NULL DEFAULT '10:00',
        location TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        completed INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE calendar_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_date TEXT NOT NULL,
        event_type TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT DEFAULT '',
        completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
      )
    ''');

    await db.execute('''
      CREATE TABLE health_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        log_date TEXT NOT NULL DEFAULT (date('now','localtime')),
        steps INTEGER,
        active_minutes INTEGER,
        sleep_hours REAL,
        fasting_glucose REAL,
        systolic_bp INTEGER,
        diastolic_bp INTEGER,
        weight_kg REAL,
        notes TEXT DEFAULT '',
        created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
      )
    ''');

    // Insert default empty profile
    await db.insert('user_profile', {'id': 1, 'name': ''});
  }

  // ─── USER PROFILE ───────────────────────────────────────

  Future<Map<String, dynamic>> getProfile() async {
    final db = await database;
    final rows = await db.query('user_profile', where: 'id = 1');
    if (rows.isEmpty) {
      await db.insert('user_profile', {'id': 1, 'name': ''});
      return {'id': 1, 'name': ''};
    }
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> saveProfile(Map<String, dynamic> data) async {
    final db = await database;
    final existing = await db.query('user_profile', where: 'id = 1');
    if (existing.isEmpty) {
      await db.insert('user_profile', {...data, 'id': 1});
    } else {
      await db.update('user_profile', data, where: 'id = 1');
    }
  }

  bool isProfileComplete(Map<String, dynamic> profile) {
    final name = (profile['name'] as String? ?? '').trim();
    return name.isNotEmpty;
  }

  // ─── MEAL SCHEDULES ─────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMealSchedules() async {
    final db = await database;
    return db.query('meal_schedules', orderBy: 'scheduled_time ASC');
  }

  Future<int> addMealSchedule(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('meal_schedules', data);
  }

  Future<void> updateMealSchedule(int id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update('meal_schedules', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMealSchedule(int id) async {
    final db = await database;
    await db.delete('meal_schedules', where: 'id = ?', whereArgs: [id]);
  }

  // ─── MEDICATIONS ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMedications() async {
    final db = await database;
    return db.query('medications', orderBy: 'scheduled_time ASC');
  }

  Future<int> addMedication(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('medications', data);
  }

  Future<void> updateMedication(int id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update('medications', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMedication(int id) async {
    final db = await database;
    await db.delete('medications', where: 'id = ?', whereArgs: [id]);
  }

  // ─── DOCTOR APPOINTMENTS ────────────────────────────────

  Future<List<Map<String, dynamic>>> getAppointments() async {
    final db = await database;
    return db.query('doctor_appointments', orderBy: 'appointment_date ASC, appointment_time ASC');
  }

  Future<int> addAppointment(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('doctor_appointments', data);
  }

  Future<void> updateAppointment(int id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update('doctor_appointments', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAppointment(int id) async {
    final db = await database;
    await db.delete('doctor_appointments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> completeAppointment(int id) async {
    final db = await database;
    await db.update('doctor_appointments', {'completed': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ─── CALENDAR EVENTS ───────────────────────────────────

  Future<List<Map<String, dynamic>>> getCalendarEvents({String? date}) async {
    final db = await database;
    if (date != null) {
      return db.query('calendar_events', where: 'event_date = ?', whereArgs: [date], orderBy: 'created_at DESC');
    }
    return db.query('calendar_events', orderBy: 'event_date DESC, created_at DESC');
  }

  Future<Map<String, List<Map<String, dynamic>>>> getCalendarEventsGrouped() async {
    final events = await getCalendarEvents();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final event in events) {
      final date = event['event_date'] as String;
      grouped.putIfAbsent(date, () => []).add(event);
    }
    return grouped;
  }

  Future<int> addCalendarEvent(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('calendar_events', data);
  }

  Future<void> completeCalendarEvent(int id) async {
    final db = await database;
    await db.update('calendar_events', {'completed': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCalendarEvent(int id) async {
    final db = await database;
    await db.delete('calendar_events', where: 'id = ?', whereArgs: [id]);
  }

  /// Record medication taken today into calendar_events
  Future<void> recordMedicationTaken(String medicationName, String time) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await addCalendarEvent({
      'event_date': today,
      'event_type': 'medication',
      'title': 'Took $medicationName',
      'description': 'Taken at $time',
      'completed': 1,
    });
  }

  /// Record meal taken today
  Future<void> recordMealTaken(String mealName) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await addCalendarEvent({
      'event_date': today,
      'event_type': 'meal',
      'title': 'Had $mealName',
      'description': '',
      'completed': 1,
    });
  }

  /// Record health checkup into calendar
  Future<void> recordHealthCheckup(String doctorName, String date) async {
    await addCalendarEvent({
      'event_date': date,
      'event_type': 'checkup',
      'title': 'Checkup with $doctorName',
      'description': '',
      'completed': 1,
    });
  }

  // ─── HEALTH LOG ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getHealthLogs({int? limit}) async {
    final db = await database;
    return db.query('health_log', orderBy: 'log_date DESC', limit: limit);
  }

  Future<int> addHealthLog(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('health_log', data);
  }

  // ─── IMPORT / EXPORT ────────────────────────────────────

  Future<String> exportAllData() async {
    final db = await database;
    final data = <String, dynamic>{
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'user_profile': await db.query('user_profile'),
      'meal_schedules': await db.query('meal_schedules'),
      'medications': await db.query('medications'),
      'doctor_appointments': await db.query('doctor_appointments'),
      'calendar_events': await db.query('calendar_events'),
      'health_log': await db.query('health_log'),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> importAllData(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final db = await database;

    await db.transaction((txn) async {
      // Clear all tables
      for (final table in ['user_profile', 'meal_schedules', 'medications', 'doctor_appointments', 'calendar_events', 'health_log']) {
        await txn.delete(table);
      }

      // Import each table
      for (final table in ['user_profile', 'meal_schedules', 'medications', 'doctor_appointments', 'calendar_events', 'health_log']) {
        final rows = data[table] as List? ?? [];
        for (final row in rows) {
          await txn.insert(table, Map<String, dynamic>.from(row as Map));
        }
      }
    });
  }

  /// Delete all data (privacy reset)
  Future<void> deleteAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in ['calendar_events', 'health_log', 'doctor_appointments', 'medications', 'meal_schedules']) {
        await txn.delete(table);
      }
      await txn.update('user_profile', {
        'name': '', 'age': null, 'gender': '', 'blood_type': '',
        'height_cm': null, 'weight_kg': null, 'location': '',
        'conditions': '', 'appetite': '', 'daily_routine': '',
        'family_history': '', 'profile_image': '',
      }, where: 'id = 1');
    });
  }
}
