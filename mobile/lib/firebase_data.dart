import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class HealthApi {
  HealthApi(this.token);

  static const _databaseId = 'beluga-health';
  static const _profileDocumentId = 'current';
  static const _profileFields = {
    'age',
    'gender',
    'blood_type',
    'height_cm',
    'weight_kg',
    'bmi',
    'location',
    'conditions',
    'medications',
    'appetite',
    'daily_routine',
    'family_history',
    'profile_image',
  };

  final String? token;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _database = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null || (token != null && user.uid != token)) {
      throw StateError('Sign in to access your Beluga data.');
    }
    return user;
  }

  DocumentReference<Map<String, dynamic>> get _userDocument =>
      _database.collection('users').doc(_currentUser.uid);

  CollectionReference<Map<String, dynamic>> get _profileCollection =>
      _userDocument.collection('profile');

  DocumentReference<Map<String, dynamic>> get _profileDocument =>
      _profileCollection.doc(_profileDocumentId);

  CollectionReference<Map<String, dynamic>> get _medicines =>
      _userDocument.collection('medicines');

  CollectionReference<Map<String, dynamic>> get _measurements =>
      _userDocument.collection('measurements');

  CollectionReference<Map<String, dynamic>> get _reminders =>
      _userDocument.collection('reminders');

  CollectionReference<Map<String, dynamic>> get _prescriptionCompletions =>
      _userDocument.collection('prescription_completions');

  CollectionReference<Map<String, dynamic>> get _patients =>
      _userDocument.collection('patients');

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _finishAuthentication(credential.user!);
  }

  Future<Map<String, dynamic>> signInWithGoogle(String idToken) async {
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await _auth.signInWithCredential(credential);
    return _finishAuthentication(result.user!);
  }

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
  ) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    await user.updateDisplayName(name.trim());
    await _ensureUserDocuments(user, name: name.trim());
    return _sessionResult(user);
  }

  Future<Map<String, dynamic>> _finishAuthentication(User user) async {
    await _ensureUserDocuments(user);
    return _sessionResult(user);
  }

  Future<void> _ensureUserDocuments(User user, {String? name}) async {
    final account = await _userDocument.get();
    final profile = await _profileDocument.get();
    final batch = _database.batch();

    if (!account.exists) {
      batch.set(_userDocument, {
        'name': name ?? user.displayName ?? user.email?.split('@').first ?? '',
        'email': user.email ?? '',
        'is_admin': false,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    if (!profile.exists) {
      batch.set(_profileDocument, {
        'age': null,
        'gender': '',
        'blood_type': '',
        'height_cm': null,
        'weight_kg': null,
        'bmi': null,
        'location': '',
        'conditions': <String>[],
        'medications': <String>[],
        'appetite': '',
        'daily_routine': '',
        'family_history': '',
        'profile_image': '',
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    if (account.exists && name != null) {
      batch.update(_userDocument, {'name': name});
    }
    if (!account.exists || !profile.exists || name != null) {
      await batch.commit();
    }
  }

  Future<Map<String, dynamic>> _sessionResult(User user) async {
    final result = await request('/me');
    return {
      'access_token': user.uid,
      'user': result['user'],
      'profile': result['profile'],
    };
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    _currentUser;
    final uri = Uri.parse(path);
    final parts = uri.pathSegments;
    if (parts.isEmpty) throw ArgumentError.value(path, 'path');

    if (parts.first == 'me' && method == 'GET') return _getMe();
    if (parts.first == 'profile' && method == 'PUT') {
      return _updateProfile(body ?? const {});
    }
    if (parts.first == 'measurements' && method == 'POST') {
      return _addMeasurement(body ?? const {});
    }
    if (parts.first == 'dashboard' && method == 'GET') return _dashboard();
    if (parts.first == 'reminders') {
      if (parts.length == 1 && method == 'GET') return _listReminders();
      if (parts.length == 1 && method == 'POST') {
        return _addReminder(body ?? const {});
      }
      if (parts.length == 2 && method == 'DELETE') {
        await _deleteReminder(parts[1]);
        return null;
      }
      if (parts.length == 3 && parts[2] == 'complete' && method == 'POST') {
        await _completeReminder(parts[1]);
        return null;
      }
    }
    if (parts.first == 'prescription-completions' && method == 'POST') {
      return _completePrescription(body ?? const {});
    }
    if (parts.first == 'patients') {
      if (parts.length == 1 && method == 'GET') {
        return _listPatients(uri.queryParameters['q']);
      }
      if (parts.length == 1 && method == 'POST') {
        return _createPatient(body ?? const {});
      }
      if (parts.length == 2 && method == 'GET') {
        return _getPatient(parts[1]);
      }
      if (parts.length == 2 && method == 'PUT') {
        return _updatePatient(parts[1], body ?? const {});
      }
      if (parts.length == 2 && method == 'DELETE') {
        await _deletePatient(parts[1]);
        return null;
      }
      if (parts.length == 3 && parts[2] == 'visits' && method == 'POST') {
        return _addVisit(parts[1], body ?? const {});
      }
      if (parts.length == 4 && parts[2] == 'visits') {
        if (method == 'PUT') {
          return _updateVisit(parts[1], parts[3], body ?? const {});
        }
        if (method == 'DELETE') {
          await _deleteVisit(parts[1], parts[3]);
          return null;
        }
      }
    }

    throw UnsupportedError('Unsupported Beluga data operation: $method $path');
  }

  Future<Map<String, dynamic>> _getMe() async {
    final account = await _userDocument.get();
    if (!account.exists) {
      await _ensureUserDocuments(_currentUser);
      return _getMe();
    }
    return {
      'user': _decodeDocument(account),
      'profile': await _getProfile(),
    };
  }

  Future<Map<String, dynamic>> _getProfile() async {
    final snapshot = await _profileDocument.get();
    final profile =
        snapshot.exists ? _decodeData(snapshot.data()!) : <String, dynamic>{};
    final medicines = await _medicines.get();
    profile['prescriptions'] = medicines.docs
        .map((document) => _decodeDocument(document))
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return profile;
  }

  Future<Map<String, dynamic>> _updateProfile(
    Map<String, dynamic> body,
  ) async {
    final user = _currentUser;
    final name = (body['name'] as String? ?? '').trim();
    if (name.isEmpty) throw ArgumentError('Name cannot be empty.');

    final profile = Map<String, dynamic>.fromEntries(
      body.entries.where((entry) => _profileFields.contains(entry.key)),
    );
    final height = body['height_cm'] as num?;
    final weight = body['weight_kg'] as num?;
    profile['bmi'] = height != null && weight != null
        ? double.parse(
            (weight / ((height / 100) * (height / 100))).toStringAsFixed(1))
        : null;
    profile['updated_at'] = FieldValue.serverTimestamp();
    final prescriptions = (body['prescriptions'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final existing = await _medicines.get();
    final requestedIds =
        prescriptions.map((item) => item['id'] as String).toSet();
    final batch = _database.batch()
      ..update(_userDocument, {'name': name})
      ..set(_profileDocument, profile, SetOptions(merge: true));
    for (final document in existing.docs) {
      if (!requestedIds.contains(document.id)) batch.delete(document.reference);
    }
    for (final prescription in prescriptions) {
      final id = prescription['id'] as String;
      batch.set(_medicines.doc(id), {
        'id': id,
        'name': prescription['name'],
        'prescribed_dose': prescription['prescribed_dose'] ?? '',
        'quantity': prescription['quantity'] ?? '',
        'intake_times': prescription['intake_times'] ?? <String>[],
        'instructions': prescription['instructions'] ?? '',
      });
    }
    await batch.commit();
    await user.updateDisplayName(name);
    return _getProfile();
  }

  Future<Map<String, dynamic>> _addMeasurement(
    Map<String, dynamic> body,
  ) async {
    final values = Map<String, dynamic>.from(body)
      ..removeWhere((_, value) => value == null);
    if (values.isEmpty) throw ArgumentError('Add at least one measurement.');
    final reference = _measurements.doc();
    await reference.set({
      'id': reference.id,
      ...values,
      'recorded_at': FieldValue.serverTimestamp(),
    });
    return _decodeDocument(await reference.get());
  }

  Future<List<Map<String, dynamic>>> _listMeasurements({
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query =
        _measurements.orderBy('recorded_at', descending: true);
    if (limit != null) query = query.limit(limit);
    final snapshot = await query.get();
    return snapshot.docs.map(_decodeDocument).toList();
  }

  Future<List<Map<String, dynamic>>> _listReminders() async {
    final snapshot = await _reminders.where('active', isEqualTo: true).get();
    final rows = snapshot.docs.map(_decodeDocument).toList();
    rows.sort((a, b) => (a['scheduled_time'] as String)
        .compareTo(b['scheduled_time'] as String));
    final today = _today();
    for (final row in rows) {
      row['completed_today'] = row['completed_on'] == today;
    }
    return rows;
  }

  Future<Map<String, dynamic>> _addReminder(
    Map<String, dynamic> body,
  ) async {
    final reference = _reminders.doc();
    await reference.set({
      'id': reference.id,
      'title': (body['title'] as String).trim(),
      'scheduled_time': body['scheduled_time'],
      'instruction': (body['instruction'] as String? ?? '').trim(),
      'active': true,
      'created_at': FieldValue.serverTimestamp(),
      'completed_on': '',
    });
    return _decodeDocument(await reference.get());
  }

  Future<void> _completeReminder(String id) async {
    final reference = _reminders.doc(id);
    final reminder = await reference.get();
    if (!reminder.exists || reminder.data()?['active'] != true) {
      throw StateError('Reminder not found.');
    }
    await reference.update({'completed_on': _today()});
  }

  Future<void> _deleteReminder(String id) async {
    final reference = _reminders.doc(id);
    if (!(await reference.get()).exists) {
      throw StateError('Reminder not found.');
    }
    await reference.delete();
  }

  Future<Map<String, dynamic>> _completePrescription(
    Map<String, dynamic> body,
  ) async {
    final prescriptionId = body['prescription_id'] as String;
    final scheduledTime = body['scheduled_time'] as String;
    final completedOn = body['completed_on'] as String;
    final completionDate = DateTime.tryParse(completedOn);
    if (completionDate == null ||
        completionDate.toIso8601String().substring(0, 10) != completedOn ||
        DateTime.now().difference(completionDate).inDays.abs() > 1) {
      throw ArgumentError(
          'Completion date must be today in your local timezone.');
    }
    final prescription = await _medicines.doc(prescriptionId).get();
    final intakeTimes =
        List<String>.from(prescription.data()?['intake_times'] ?? const []);
    if (!prescription.exists || !intakeTimes.contains(scheduledTime)) {
      throw StateError('Prescription schedule not found.');
    }
    final id = _encodedId('$prescriptionId|$scheduledTime|$completedOn');
    final reference = _prescriptionCompletions.doc(id);
    await _database.runTransaction((transaction) async {
      if (!(await transaction.get(reference)).exists) {
        transaction.set(reference, {
          'prescription_id': prescriptionId,
          'scheduled_time': scheduledTime,
          'completed_on': completedOn,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    });
    return {'completed': true, 'completed_on': completedOn};
  }

  Future<Map<String, dynamic>> _dashboard() async {
    final result = await _getMe();
    final measurements = await _listMeasurements(limit: 7);
    final reminders = await _listReminders();
    final patientSnapshot = await _patients.get();
    final latest = measurements.isEmpty ? null : measurements.first;
    final flags = <String>[];
    final glucose = latest?['fasting_glucose'];
    if (glucose is num && glucose >= 126) {
      flags.add(
        'This fasting glucose reading is above a commonly used reference threshold. A clinician must interpret and confirm results.',
      );
    }
    final systolic = latest?['systolic_bp'];
    final diastolic = latest?['diastolic_bp'];
    if (systolic is num &&
        diastolic is num &&
        (systolic >= 130 || diastolic >= 80)) {
      flags.add(
        'This blood pressure reading is elevated under common adult guidance. Repeat it correctly and discuss it with a clinician.',
      );
    }
    return {
      'name': result['user']['name'],
      'profile': result['profile'],
      'latest_measurement': latest,
      'measurements': measurements,
      'reminders': reminders,
      'patients_count': patientSnapshot.size,
      'dataset': null,
      'reading_notes': flags,
    };
  }

  Future<List<Map<String, dynamic>>> _listPatients(String? search) async {
    final snapshot =
        await _patients.orderBy('updated_at', descending: true).get();
    final query = search?.trim().toLowerCase() ?? '';
    final result = <Map<String, dynamic>>[];
    for (final document in snapshot.docs) {
      final patient = _decodeDocument(document);
      final visits = await document.reference
          .collection('visits')
          .orderBy('visit_date', descending: true)
          .get();
      patient['visit_count'] = visits.size;
      patient['last_visit_date'] =
          visits.docs.isEmpty ? null : visits.docs.first.data()['visit_date'];
      if (query.isEmpty || _patientMatches(patient, query)) result.add(patient);
    }
    return result;
  }

  bool _patientMatches(Map<String, dynamic> patient, String query) {
    final searchable = [
      patient['name'],
      patient['patient_id'],
      patient['phone'],
      ...(patient['chronic_conditions'] as List? ?? const []),
    ];
    return searchable.any(
      (value) => value.toString().toLowerCase().contains(query),
    );
  }

  Future<Map<String, dynamic>> _createPatient(
    Map<String, dynamic> body,
  ) async {
    final snapshot = await _patients.get();
    var patientId = (body['patient_id'] as String? ?? '').trim();
    if (patientId.isEmpty) patientId = 'PAT-${1001 + snapshot.size}';
    final reference = _patients.doc(_encodedId(patientId));
    if ((await reference.get()).exists) {
      throw StateError(
        "A patient with ID '$patientId' already exists. Please provide a unique patient ID.",
      );
    }
    final now = FieldValue.serverTimestamp();
    await reference.set({
      ...body,
      'patient_id': patientId,
      'name': (body['name'] as String).trim(),
      'email': (body['email'] as String? ?? '').trim().toLowerCase(),
      'created_at': now,
      'updated_at': now,
    });
    return {
      ..._decodeDocument(await reference.get()),
      'visit_count': 0,
      'last_visit_date': null,
      'visits': <Map<String, dynamic>>[],
    };
  }

  Future<DocumentReference<Map<String, dynamic>>> _findPatient(
    String patientId,
  ) async {
    final direct = _patients.doc(_encodedId(patientId));
    if ((await direct.get()).exists) return direct;
    final matches = await _patients
        .where('patient_id', isEqualTo: patientId)
        .limit(1)
        .get();
    if (matches.docs.isEmpty) throw StateError('Patient not found.');
    return matches.docs.first.reference;
  }

  Future<Map<String, dynamic>> _getPatient(String patientId) async {
    final reference = await _findPatient(patientId);
    final patient = _decodeDocument(await reference.get());
    final visits = await reference
        .collection('visits')
        .orderBy('visit_date', descending: true)
        .get();
    patient['visits'] = visits.docs.map(_decodeDocument).toList();
    patient['visit_count'] = visits.size;
    patient['last_visit_date'] =
        visits.docs.isEmpty ? null : visits.docs.first.data()['visit_date'];
    return patient;
  }

  Future<Map<String, dynamic>> _updatePatient(
    String patientId,
    Map<String, dynamic> body,
  ) async {
    final reference = await _findPatient(patientId);
    final current = (await reference.get()).data()!;
    final targetId =
        (body['patient_id'] as String? ?? current['patient_id'] as String)
            .trim();
    if (targetId != current['patient_id']) {
      final target = _patients.doc(_encodedId(targetId));
      if ((await target.get()).exists) {
        throw StateError("A patient with ID '$targetId' already exists.");
      }
    }
    await reference.update({
      ...body,
      'patient_id': targetId,
      'name': (body['name'] as String).trim(),
      'email': (body['email'] as String? ?? '').trim().toLowerCase(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return _getPatient(targetId);
  }

  Future<void> _deletePatient(String patientId) async {
    final reference = await _findPatient(patientId);
    final visits = await reference.collection('visits').get();
    for (var index = 0; index < visits.docs.length; index += 400) {
      final batch = _database.batch();
      for (final visit in visits.docs.skip(index).take(400)) {
        batch.delete(visit.reference);
      }
      await batch.commit();
    }
    await reference.delete();
  }

  Future<Map<String, dynamic>> _addVisit(
    String patientId,
    Map<String, dynamic> body,
  ) async {
    final patient = await _findPatient(patientId);
    final visit = patient.collection('visits').doc();
    final visitDate = (body['visit_date'] as String? ?? '').trim();
    await visit.set({
      ...body,
      'id': visit.id,
      'visit_date': visitDate.isEmpty ? _today() : visitDate,
      'next_followup': body['next_followup'] as String? ?? '',
      'created_at': FieldValue.serverTimestamp(),
    });
    await patient.update({'updated_at': FieldValue.serverTimestamp()});
    return _decodeDocument(await visit.get());
  }

  Future<Map<String, dynamic>> _updateVisit(
    String patientId,
    String visitId,
    Map<String, dynamic> body,
  ) async {
    final patient = await _findPatient(patientId);
    final visit = patient.collection('visits').doc(visitId);
    if (!(await visit.get()).exists) {
      throw StateError('Visit record not found.');
    }
    final visitDate = (body['visit_date'] as String? ?? '').trim();
    await visit.update({
      ...body,
      'visit_date': visitDate.isEmpty ? _today() : visitDate,
      'next_followup': body['next_followup'] as String? ?? '',
    });
    await patient.update({'updated_at': FieldValue.serverTimestamp()});
    return _decodeDocument(await visit.get());
  }

  Future<void> _deleteVisit(String patientId, String visitId) async {
    final patient = await _findPatient(patientId);
    final visit = patient.collection('visits').doc(visitId);
    if (!(await visit.get()).exists) {
      throw StateError('Visit record not found.');
    }
    await visit.delete();
    await patient.update({'updated_at': FieldValue.serverTimestamp()});
  }

  Map<String, dynamic> _decodeDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return {'id': document.id, ..._decodeData(document.data() ?? const {})};
  }

  Map<String, dynamic> _decodeData(Map<String, dynamic> data) =>
      data.map((key, value) => MapEntry(key, _decodeValue(value)));

  dynamic _decodeValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is Map<String, dynamic>) return _decodeData(value);
    if (value is List) return value.map(_decodeValue).toList();
    return value;
  }

  String _encodedId(String value) =>
      'id_${base64Url.encode(utf8.encode(value)).replaceAll('=', '')}';

  String _today() => DateTime.now().toIso8601String().substring(0, 10);
}
