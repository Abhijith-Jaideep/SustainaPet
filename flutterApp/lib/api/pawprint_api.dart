import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/* ===================== Users / Dashboard ===================== */

class UserDto {
  final int userid;
  final String name;
  final int ecopetmood; // 0..100
  final int carbonpoints;

  // Optional weekly counters from backend (if present)
  final double weeklyEmissionsProduced;
  final double weeklyEmissionsSaved;

  UserDto({
    required this.userid,
    required this.name,
    required this.ecopetmood,
    required this.carbonpoints,
    required this.weeklyEmissionsProduced,
    required this.weeklyEmissionsSaved,
  });

  factory UserDto.fromJson(Map<String, dynamic> j) {
    final u = (j['user'] is Map<String, dynamic>)
        ? (j['user'] as Map<String, dynamic>)
        : j;

    double _numToDouble(dynamic v) =>
        (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

    return UserDto(
      userid: (u['userid'] as num).toInt(),
      name: (u['name'] ?? '').toString(),
      ecopetmood: (u['ecopetmood'] as num?)?.toInt() ?? 0,
      carbonpoints: (u['carbonpoints'] as num?)?.toInt() ?? 0,
      weeklyEmissionsProduced: _numToDouble(u['weekly_emissions_produced']),
      weeklyEmissionsSaved: _numToDouble(u['weekly_emissions_saved']),
    );
  }
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
    active: (j['active_quests'] as num).toInt(),
    completed: (j['completed_quests'] as num).toInt(),
    totalEmissionsSaved: (j['total_emissions_saved'] as num).toDouble(),
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
        .whereType<Map<String, dynamic>>()
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

  factory ConversionDto.fromJson(Map<String, dynamic> j) => ConversionDto(
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
  final String type; // "Quest" | "Grocery" | "Points" | ...
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
    userquestid:
    j['userquestid'] == null ? null : (j['userquestid'] as num).toInt(),
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

  factory UserQuestDto.fromJson(Map<String, dynamic> j) => UserQuestDto(
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

/* ===================== Receipt Mapping ===================== */

class ReceiptMapRow {
  final String? item;
  final String? displayQty;
  final double? weightKG;
  final String? matchedName;
  final double? emissions;
  final double? totalEmissions;
  final double? confidence;
  final String? method;
  final String? impact;

  ReceiptMapRow({
    this.item,
    this.displayQty,
    this.weightKG,
    this.matchedName,
    this.emissions,
    this.totalEmissions,
    this.confidence,
    this.method,
    this.impact,
  });

  factory ReceiptMapRow.fromJson(Map<String, dynamic> j) => ReceiptMapRow(
    item: j['Item']?.toString(),
    displayQty: j['DisplayQty']?.toString(),
    weightKG: (j['WeightKG'] is num)
        ? (j['WeightKG'] as num).toDouble()
        : double.tryParse('${j['WeightKG']}'),
    matchedName: j['MatchedName']?.toString(),
    emissions: (j['Emissions'] is num)
        ? (j['Emissions'] as num).toDouble()
        : double.tryParse('${j['Emissions']}'),
    totalEmissions: (j['TotalEmissions'] is num)
        ? (j['TotalEmissions'] as num).toDouble()
        : double.tryParse('${j['TotalEmissions']}'),
    confidence: (j['Confidence'] is num)
        ? (j['Confidence'] as num).toDouble()
        : double.tryParse('${j['Confidence']}'),
    method: j['Method']?.toString(),
    impact: (j['Impact'] ?? j['impact'])?.toString(),
  );
}

/* ===================== Socials DTOs ===================== */

class FriendDto {
  final int userid;
  final String name;
  FriendDto({required this.userid, required this.name});
}

class FriendRequestDto {
  final int requestId;
  final int fromUserId;
  final String fromName;
  FriendRequestDto({
    required this.requestId,
    required this.fromUserId,
    required this.fromName,
  });
}

class FriendsLeaderboardRowDto {
  final int userid;
  final String name;
  final int carbonpoints;
  final int ecopetmood;

  /// Weekly emitted (>= 0) as provided by backend or fetched via dashboard.
  final double weeklyEmissionsProduced;

  /// Weekly saved (<= 0) as provided by backend or fetched via dashboard.
  final double weeklyEmissionsSaved;

  FriendsLeaderboardRowDto({
    required this.userid,
    required this.name,
    required this.carbonpoints,
    required this.ecopetmood,
    required this.weeklyEmissionsProduced,
    required this.weeklyEmissionsSaved,
  });

  FriendsLeaderboardRowDto copyWith({
    double? weeklyEmissionsProduced,
    double? weeklyEmissionsSaved,
  }) {
    return FriendsLeaderboardRowDto(
      userid: userid,
      name: name,
      carbonpoints: carbonpoints,
      ecopetmood: ecopetmood,
      weeklyEmissionsProduced:
      weeklyEmissionsProduced ?? this.weeklyEmissionsProduced,
      weeklyEmissionsSaved: weeklyEmissionsSaved ?? this.weeklyEmissionsSaved,
    );
  }
}

/* ===================== API ===================== */

class PawprintApi {
  final String baseUrl;
  PawprintApi(this.baseUrl);

  static const _headers = {'Content-Type': 'application/json'};
  static const _timeout = Duration(seconds: 10);
  static const _parseTimeout = Duration(seconds: 30);
  static const _mapTimeout = Duration(seconds: 20);

  void _logUrl(String label, Uri uri) {
    // ignore: avoid_print
    print('[$label] ${uri.toString()}');
  }

  Future<String> ping() async {
    final uri = Uri.parse('$baseUrl/api/ping');
    final resp = await http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('Ping failed: ${resp.statusCode} ${resp.body}');
    }
    return resp.body;
  }

  /* =============== Users =============== */

  Future<UserDto> createUser({required String name}) async {
    final uri = Uri.parse('$baseUrl/api/users');
    final resp =
    await http.post(uri, headers: _headers, body: jsonEncode({'name': name}));
    if (resp.statusCode != 201) {
      throw Exception('Create user failed: ${resp.statusCode} ${resp.body}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return UserDto.fromJson(j);
  }

  Future<UserDto> getUser(int userid) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid');
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('User lookup error: ${resp.statusCode} ${resp.body}');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return UserDto.fromJson(map);
  }

  Future<List<UserDto>> listUsers() async {
    final uri = Uri.parse('$baseUrl/api/users');
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('List users error: ${resp.statusCode} ${resp.body}');
    }
    final List data = jsonDecode(resp.body) as List;
    return data.map((e) => UserDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DashboardDto> getDashboard(int userid) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/dashboard');
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('Dashboard error: ${resp.statusCode} ${resp.body}');
    }
    return DashboardDto.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /* =============== Emissions / Conversions / Events =============== */

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

    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('Monthly emissions error: ${resp.statusCode} ${resp.body}');
    }
    return MonthlyEmissionsDto.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<List<ConversionDto>> getConversions() async {
    final uri = Uri.parse('$baseUrl/api/conversions');
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('Conversions error: ${resp.statusCode} ${resp.body}');
    }
    final List list = jsonDecode(resp.body) as List;
    return list
        .map((e) => ConversionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<EventDto>> getUserEvents(int userid, {int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/events')
        .replace(queryParameters: {'limit': '$limit'});
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('Events error: ${resp.statusCode} ${resp.body}');
    }
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => EventDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  /* =============== Quests =============== */

  Future<List<UserQuestDto>> getUserQuests(
      int userid, {
        String status = 'active',
      }) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/userquests')
        .replace(queryParameters: {'status': status});
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('User quests error: ${resp.statusCode} ${resp.body}');
    }
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => UserQuestDto.fromJson(e as Map<String, dynamic>)).toList();
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
      throw HttpException('Assign random error: ${resp.statusCode} ${resp.body}');
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

    if (decoded is List) return parseList(decoded);
    if (decoded is Map<String, dynamic>) {
      final created = decoded['created'];
      if (created is List) return parseList(created);
    }
    return const <UserQuestDto>[];
  }

  Future<Map<String, dynamic>> completeUserQuest(
      int userquestid, {
        DateTime? when,
        int moodDelta = 5,
      }) async {
    final uri = Uri.parse('$baseUrl/api/userquests/$userquestid/complete');
    final body = <String, dynamic>{
      if (when != null) 'completeddate': when.toIso8601String(),
      'mood_delta': moodDelta,
    };
    final resp = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw HttpException('Complete quest error: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<UserQuestDto?> getUserQuest(int userQuestId) async {
    final uri = Uri.parse('$baseUrl/api/userquests/$userQuestId');
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);

    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw HttpException('Get userquest error: ${resp.statusCode} ${resp.body}');
    }

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return UserQuestDto.fromJson(map);
  }

  Future<UserQuestDto?> replaceUserQuest(
      int userQuestId, {
        List<String>? difficulty,
      }) async {
    final uri =
    Uri.parse('$baseUrl/api/userquests/$userQuestId/replace_random');
    final body = (difficulty != null && difficulty.isNotEmpty)
        ? {'difficulty': difficulty}
        : {};

    final resp = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);

    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw HttpException('Replace userquest error: ${resp.statusCode} ${resp.body}');
    }

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return UserQuestDto.fromJson(map);
  }

  /* =============== Mood Reset =============== */

  Future<void> resetUserMood(int userid, int mood) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid');
    final resp = await http
        .patch(uri, headers: _headers, body: jsonEncode({'ecopetmood': mood}))
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw HttpException('Reset mood failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /* =============== Receipt Parsing & Mapping =============== */

  Future<dynamic> parseReceiptFromBytes(Uint8List bytes) async {
    final uri = Uri.parse('$baseUrl/api/receipt-parser'); // not under /api
    _logUrl('POST', uri);
    final body = jsonEncode({'image_base64': base64Encode(bytes)});
    final resp =
    await http.post(uri, headers: _headers, body: body).timeout(_parseTimeout);

    if (resp.statusCode != 200) {
      throw HttpException('Parser failed: ${resp.statusCode} ${resp.body}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic> && decoded.containsKey('receipt_json')) {
      return decoded['receipt_json'];
    }
    return decoded;
  }

  Future<List<ReceiptMapRow>> mapReceiptForUser(
      int userid,
      dynamic parserOutput, {
        double? subtotal,
        double? total,
        double? savings,
      }) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/map-receipt');
    _logUrl('POST', uri);

    final payload = _normalizeReceiptPayload(
      parserOutput,
      subtotal: subtotal,
      total: total,
      savings: savings,
    );

    final resp = await http
        .post(uri, headers: _headers, body: jsonEncode(payload))
        .timeout(_mapTimeout);
    if (resp.statusCode != 200) {
      throw HttpException('Map failed: ${resp.statusCode} ${resp.body}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => ReceiptMapRow.fromJson(m))
          .toList();
    }
    throw HttpException('Unexpected /<userid>/map-receipt response: ${resp.body}');
  }

  Future<List<ReceiptMapRow>> processReceiptForUser(
      int userid,
      Uint8List bytes, {
        double? subtotal,
        double? total,
        double? savings,
      }) async {
    final parsed = await parseReceiptFromBytes(bytes);
    return mapReceiptForUser(
      userid,
      parsed,
      subtotal: subtotal,
      total: total,
      savings: savings,
    );
  }

  Map<String, dynamic> _normalizeReceiptPayload(
      dynamic parsed, {
        double? subtotal,
        double? total,
        double? savings,
      }) {
    Map<String, dynamic> payload;

    if (parsed is List) {
      payload = {'items': parsed};
    } else if (parsed is Map<String, dynamic>) {
      if (parsed.containsKey('items') && parsed['items'] is List) {
        payload = Map<String, dynamic>.from(parsed);
      } else if (parsed.containsKey('receipt_json') &&
          parsed['receipt_json'] is List) {
        payload = {'items': parsed['receipt_json'] as List};
      } else {
        payload = {'items': [parsed]};
      }
    } else {
      throw const FormatException('Unsupported parser output format');
    }

    if (subtotal != null) payload['subtotal'] = subtotal;
    if (total != null) payload['total'] = total;
    if (savings != null) payload['savings'] = savings;

    return payload;
  }

  /* =============== Client-side Monthly Leaderboard (all users) =============== */

  Future<List<LeaderboardRowDto>> getMonthlyLeaderboard({int? year, int? month}) async {
    final users = await listUsers();
    final results = await Future.wait(users.map((u) async {
      try {
        final m =
        await getMonthlyEmissions(userid: u.userid, year: year, month: month);
        return LeaderboardRowDto(
          userid: u.userid,
          name: u.name,
          savedKg: m.savedKg,
          emittedKg: m.emittedKg,
        );
      } catch (_) {
        return LeaderboardRowDto(
          userid: u.userid,
          name: u.name,
          savedKg: 0.0,
          emittedKg: 0.0,
        );
      }
    }).toList());

    results.sort((a, b) {
      final s = b.savedKg.compareTo(a.savedKg);
      if (s != 0) return s;
      final e = a.emittedKg.compareTo(b.emittedKg);
      if (e != 0) return e;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return results;
  }

  /* ===================== FRIENDS API — with emissions for leaderboard ===================== */

  /// GET /api/users/<userid>/search_friend
  Future<FriendDto?> searchFriend(int userid) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/search_friend');
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);

    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw HttpException('search_friend error: ${resp.statusCode} ${resp.body}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return FriendDto(
      userid: (j['userid'] as num).toInt(),
      name: (j['name'] ?? '').toString(),
    );
  }

  /// POST /api/users/<fromUserId>/add_friend  { "friend_userid": <toUserId> }
  Future<void> sendFriendRequest({
    required int fromUserId,
    required int toUserId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/users/$fromUserId/add_friend');
    final resp = await http
        .post(uri, headers: _headers, body: jsonEncode({'friend_userid': toUserId}))
        .timeout(_timeout);

    if (resp.statusCode == 200 || resp.statusCode == 201) return;

    // Backend returns 400 if duplicate, 404 if user missing.
    throw HttpException('add_friend failed: ${resp.statusCode} ${resp.body}');
  }

  /// GET /api/users/<userid>/process_request
  /// Returns: { "pending_requests": [ {request_id, from_user_id, from_user_name}, ... ] }
  Future<List<FriendRequestDto>> listFriendRequests(int userid) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/process_request');
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);

    if (resp.statusCode != 200) {
      throw HttpException('process_request (GET) failed: ${resp.statusCode} ${resp.body}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final List list = (j['pending_requests'] as List? ?? const []);
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return FriendRequestDto(
        requestId: (m['request_id'] as num).toInt(),
        fromUserId: (m['from_user_id'] as num).toInt(),
        fromName: (m['from_user_name'] ?? '').toString(),
      );
    }).toList();
  }

  /// POST /api/users/<userid>/process_request  { "request_id": ..., "action": "accept"|"reject" }
  Future<void> respondFriendRequest({
    required int userid,
    required int requestId,
    required bool accept,
  }) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/process_request');
    final body = {'request_id': requestId, 'action': accept ? 'accept' : 'reject'};
    final resp = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);

    if (resp.statusCode == 200) return;

    throw HttpException('process_request (POST) failed: ${resp.statusCode} ${resp.body}');
  }

  /// GET /api/users/<userid>/leaderboard
  ///
  /// Accepts either:
  ///   { "leaderboard": [...] }  or  [ ... ]
  Future<List<FriendsLeaderboardRowDto>> getFriendsLeaderboard(int userid) async {
    final uri = Uri.parse('$baseUrl/api/users/$userid/leaderboard');
    final resp = await http.get(uri, headers: _headers).timeout(_timeout);

    if (resp.statusCode != 200) {
      throw HttpException('leaderboard error: ${resp.statusCode} ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);

    // Flexible payload handling
    List raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final lb = decoded['leaderboard'];
      if (lb is List) {
        raw = lb;
      } else if (decoded['results'] is List) {
        raw = decoded['results'] as List;
      } else {
        throw const FormatException('Unexpected leaderboard payload shape');
      }
    } else {
      throw const FormatException('Unexpected leaderboard payload type');
    }

    double _toDouble(dynamic v) =>
        (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int _toInt(dynamic v) =>
        (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;

    var rows = raw.whereType<Map>().map((e) {
      final m = e.cast<String, dynamic>();
      return FriendsLeaderboardRowDto(
        userid: _toInt(m['userid']),
        name: (m['name'] ?? '').toString(),
        carbonpoints: _toInt(m['carbonpoints']),
        ecopetmood: _toInt(m['ecopetmood']),
        weeklyEmissionsProduced: _toDouble(m['weekly_emissions_produced']),
        weeklyEmissionsSaved: _toDouble(m['weekly_emissions_saved']),
      );
    }).toList();

    // Fill weekly numbers from dashboard if both are zero
    final needsFill = rows.any((r) =>
    r.weeklyEmissionsProduced == 0.0 && r.weeklyEmissionsSaved == 0.0);

    if (needsFill) {
      rows = await Future.wait(rows.map((r) async {
        if (r.weeklyEmissionsProduced != 0.0 || r.weeklyEmissionsSaved != 0.0) {
          return r;
        }
        try {
          final dash = await getDashboard(r.userid);
          return r.copyWith(
            weeklyEmissionsProduced: dash.user.weeklyEmissionsProduced,
            weeklyEmissionsSaved: dash.user.weeklyEmissionsSaved,
          );
        } catch (_) {
          return r;
        }
      }));
    }

    return rows;
  }

  /// "Friends list" derived from leaderboard (excluding current user).
  Future<List<FriendDto>> listFriends(int userid) async {
    final board = await getFriendsLeaderboard(userid);
    return board
        .where((e) => e.userid != userid)
        .map((e) => FriendDto(userid: e.userid, name: e.name))
        .toList();
  }
}

/* ---- Mood enum + mapper ---- */
enum PetMood { neutral, happy, sad }

PetMood petMoodFromScore(int score) {
  if (score > 60) return PetMood.happy;
  if (score <= 30) return PetMood.sad;
  return PetMood.neutral;
}

/* ---- Legacy monthly leaderboard DTO (kept) ---- */
class LeaderboardRowDto {
  final int userid;
  final String name;
  final double savedKg; // positive magnitude
  final double emittedKg; // positive magnitude

  LeaderboardRowDto({
    required this.userid,
    required this.name,
    required this.savedKg,
    required this.emittedKg,
  });
}
