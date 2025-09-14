// lib/api/pawprint_api.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/* ===================== Users / Dashboard ===================== */

class UserDto {
  final int userid;
  final String name;
  final int ecopetmood; // 0..100
  final int carbonpoints;

  UserDto({
    required this.userid,
    required this.name,
    required this.ecopetmood,
    required this.carbonpoints,
  });

  factory UserDto.fromJson(Map<String, dynamic> j) => UserDto(
    userid: j['user']?['userid'] ?? j['userid'] as int,
    name: j['user']?['name'] ?? j['name'] as String,
    ecopetmood: j['user']?['ecopetmood'] ?? j['ecopetmood'] as int,
    carbonpoints:
    j['user']?['carbonpoints'] ?? j['carbonpoints'] as int,
  );
}

class DashboardDto {
  final UserDto user;
  final int active;
  final int completed;
  final double totalEmissionsSaved;

  DashboardDto({
    required this.user,
    required this.active,
    required this.completed,
    required this.totalEmissionsSaved,
  });

  factory DashboardDto.fromJson(Map<String, dynamic> j) => DashboardDto(
    user: UserDto.fromJson(j),
    active: j['active_quests'] as int,
    completed: j['completed_quests'] as int,
    totalEmissionsSaved:
    (j['total_emissions_saved'] as num).toDouble(),
  );
}

/* ===================== Monthly Emissions ===================== */

class MonthlyEmissionsDto {
  final int year;
  final int month;
  final double emittedKg;
  final double savedKg;
  final double netKg;
  final List<WeeklyBucket> weekly;

  MonthlyEmissionsDto({
    required this.year,
    required this.month,
    required this.emittedKg,
    required this.savedKg,
    required this.netKg,
    required this.weekly,
  });

  factory MonthlyEmissionsDto.fromJson(Map<String, dynamic> j) {
    final period = j['period'] as Map<String, dynamic>;
    final totals = j['totals'] as Map<String, dynamic>;
    final weekly = (j['weekly'] as List)
        .map((w) => WeeklyBucket(
      week: (w['week'] as num).toInt(),
      kg: (w['kg'] as num).toDouble(),
    ))
        .toList();
    return MonthlyEmissionsDto(
      year: (period['year'] as num).toInt(),
      month: (period['month'] as num).toInt(),
      emittedKg: (totals['emitted_kg'] as num).toDouble(),
      savedKg: (totals['saved_kg'] as num).toDouble(),
      netKg: (totals['net_kg'] as num).toDouble(),
      weekly: weekly,
    );
  }
}

class WeeklyBucket {
  final int week;
  final double kg;
  WeeklyBucket({required this.week, required this.kg});
}

/* ===================== Conversions ===================== */

class ConversionDto {
  final int metricid;
  final String name;
  final String? description;
  final double emissionsPerX;

  ConversionDto({
    required this.metricid,
    required this.name,
    required this.description,
    required this.emissionsPerX,
  });

  factory ConversionDto.fromJson(Map<String, dynamic> j) =>
      ConversionDto(
        metricid: (j['metricid'] as num).toInt(),
        name: j['name'] as String,
        description: j['description'] as String?,
        emissionsPerX: (j['emissionsperx'] as num).toDouble(),
      );
}

/* ===================== Events ===================== */

class EventDto {
  final int eventid;
  final int userid;
  final int? userquestid;
  final String description;
  final String type; // "Quest" | ...
  final double emissions; // negative == saved
  final DateTime datetime;

  EventDto({
    required this.eventid,
    required this.userid,
    required this.userquestid,
    required this.description,
    required this.type,
    required this.emissions,
    required this.datetime,
  });

  factory EventDto.fromJson(Map<String, dynamic> j) => EventDto(
    eventid: (j['eventid'] as num).toInt(),
    userid: (j['userid'] as num).toInt(),
    userquestid: j['userquestid'] == null
        ? null
        : (j['userquestid'] as num).toInt(),
    description: j['description'] as String,
    type: j['type'] as String,
    emissions: (j['emissions'] as num).toDouble(),
    datetime: DateTime.parse(j['datetime'] as String),
  );
}

/* ===================== Quests ===================== */

class QuestDto {
  final int questid;
  final String description;
  final String difficulty; // "Easy" | "Medium" | "Hard"
  final int reward; // points
  final double emissions; // negative saving

  QuestDto({
    required this.questid,
    required this.description,
    required this.difficulty,
    required this.reward,
    required this.emissions,
  });

  factory QuestDto.fromJson(Map<String, dynamic> j) => QuestDto(
    questid: (j['questid'] as num).toInt(),
    description: j['description'] as String,
    difficulty: j['difficulty'] as String,
    reward: (j['reward'] as num).toInt(),
    emissions: (j['emissions'] as num).toDouble(),
  );
}

class UserQuestDto {
  final int userquestid;
  final int userid;
  final int questid;
  final bool isactive;
  final bool iscompleted;
  final DateTime? completeddate;
  final QuestDto quest;

  UserQuestDto({
    required this.userquestid,
    required this.userid,
    required this.questid,
    required this.isactive,
    required this.iscompleted,
    required this.completeddate,
    required this.quest,
  });

  factory UserQuestDto.fromJson(Map<String, dynamic> j) =>
      UserQuestDto(
        userquestid: (j['userquestid'] as num).toInt(),
        userid: (j['userid'] as num).toInt(),
        questid: (j['questid'] as num).toInt(),
        isactive: j['isactive'] as bool,
        iscompleted: j['iscompleted'] as bool,
        completeddate: j['completeddate'] == null
            ? null
            : DateTime.parse(j['completeddate'] as String),
        quest: QuestDto.fromJson(j['quest'] as Map<String, dynamic>),
      );
}

/* ===================== API ===================== */

class PawprintApi {
  final String baseUrl;
  PawprintApi(this.baseUrl);

  static const _headers = {'Content-Type': 'application/json'};
  static const _timeout = Duration(seconds: 10);

  Future<String> ping() async {
    final uri = Uri.parse('$baseUrl/api/ping');
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('Ping failed: ${resp.statusCode} ${resp.body}');
    }
    return resp.body;
  }

  /// Create a user on the backend and return the created user.
  Future<UserDto> createUser({required String name}) async {
    final uri = Uri.parse('$baseUrl/api/users');
    final resp = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    if (resp.statusCode != 201) {
      throw Exception('Create user failed: ${resp.statusCode} ${resp.body}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return UserDto.fromJson(j);
  }

  /// Fetch a single user by ID (used by Dev Login).
  Future<UserDto> getUser(int userid) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid');
    final resp =
    await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException(
          'User lookup error: ${resp.statusCode} ${resp.body}');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return UserDto.fromJson(map);
  }

  Future<DashboardDto> getDashboard(int userid) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/dashboard');
    final resp =
    await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException(
          'Dashboard error: ${resp.statusCode} ${resp.body}');
    }
    return DashboardDto.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<MonthlyEmissionsDto> getMonthlyEmissions({
    required int userid,
    int? year,
    int? month,
  }) async {
    final qs = <String, String>{};
    if (year != null) qs['year'] = '$year';
    if (month != null) qs['month'] = '$month';

    final uri = Uri.parse('$baseUrl/api/users/$userid/emissions/monthly')
        .replace(queryParameters: qs.isEmpty ? null : qs);

    final resp =
    await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException(
          'Monthly emissions error: ${resp.statusCode} ${resp.body}');
    }
    return MonthlyEmissionsDto.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<List<ConversionDto>> getConversions() async {
    final uri = Uri.parse('$baseUrl/api/conversions');
    final resp =
    await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException(
          'Conversions error: ${resp.statusCode} ${resp.body}');
    }
    final List list = jsonDecode(resp.body) as List;
    return list
        .map((e) => ConversionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /* =============== Events =============== */

  Future<List<EventDto>> getUserEvents(int userid, {int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/events')
        .replace(queryParameters: {'limit': '$limit'});
    final resp =
    await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('Events error: ${resp.statusCode} ${resp.body}');
    }
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => EventDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /* =============== Quests =============== */

  Future<List<UserQuestDto>> getUserQuests(
      int userid, {
        String status = 'active',
      }) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/userquests')
        .replace(queryParameters: {'status': status});
    final resp =
    await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('User quests error: ${resp.statusCode} ${resp.body}');
    }
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => UserQuestDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UserQuestDto>> assignRandomQuests({
    required int userid,
    int count = 3,
    List<String>? difficulty,
  }) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/quests/assign_random');
    final body = <String, dynamic>{'count': count};
    if (difficulty != null && difficulty.isNotEmpty) {
      body['difficulty'] = difficulty;
    }

    final resp = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);

    if (resp.statusCode == 204 || resp.body.trim().isEmpty) {
      return const <UserQuestDto>[];
    }
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw HttpException(
          'Assign random error: ${resp.statusCode} ${resp.body}');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      return const <UserQuestDto>[];
    }

    List<UserQuestDto> parseList(List list) {
      final out = <UserQuestDto>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final q = item['quest'];
          if (q is Map<String, dynamic>) {
            out.add(UserQuestDto.fromJson(item));
          }
        }
      }
      return out;
    }

    if (decoded is List) {
      return parseList(decoded);
    }
    if (decoded is Map<String, dynamic>) {
      final created = decoded['created'];
      if (created is List) {
        return parseList(created);
      }
    }
    return const <UserQuestDto>[];
  }

  Future<Map<String, dynamic>> completeUserQuest(
      int userquestid, {
        DateTime? when,
        int moodDelta = 5,
      }) async {
    final uri =
    Uri.parse('$baseUrl/api/userquests/$userquestid/complete');
    final body = <String, dynamic>{
      if (when != null) 'completeddate': when.toIso8601String(),
      'mood_delta': moodDelta,
    };
    final resp = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException(
          'Complete quest error: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /* =============== Mood Reset =============== */

  Future<void> resetUserMood(int userid, int mood) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid');
    final resp = await http.patch(
      uri,
      headers: _headers,
      body: jsonEncode({'ecopetmood': mood}),
    ).timeout(_timeout);

    if (resp.statusCode != 200) {
      throw HttpException(
          'Reset mood failed: ${resp.statusCode} ${resp.body}');
    }
  }
}

/* ---- Mood enum + mapper ---- */
enum PetMood { neutral, happy, sad }

PetMood petMoodFromScore(int score) {
  if (score > 60) return PetMood.happy;
  if (score <= 30) return PetMood.sad;
  return PetMood.neutral;
}
