import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

// Personalized Predictions Service
// Fetches the user's latest palm analysis and generates personalized predictions
// using the actual palm data. No static/hardcoded content.

class PersonalizedPrediction {
  final String category;
  final String categoryHi;
  final String content;
  final String contentHi;
  final String iconName;
  final int confidence;
  final bool isMajorEvent;

  const PersonalizedPrediction({
    required this.category,
    required this.categoryHi,
    required this.content,
    required this.contentHi,
    required this.iconName,
    required this.confidence,
    this.isMajorEvent = false,
  });
}

class PalmPredictionsData {
  final List<PersonalizedPrediction> today;
  final List<PersonalizedPrediction> weekly;
  final List<PersonalizedPrediction> monthly;
  final List<PersonalizedPrediction> yearly;
  final String? palmType;
  final String? userName;
  final bool isPersonalized;
  final String? errorMessage;

  const PalmPredictionsData({
    required this.today,
    required this.weekly,
    required this.monthly,
    required this.yearly,
    this.palmType,
    this.userName,
    this.isPersonalized = false,
    this.errorMessage,
  });

  static PalmPredictionsData empty() => const PalmPredictionsData(
    today: [],
    weekly: [],
    monthly: [],
    yearly: [],
    isPersonalized: false,
  );
}

class PersonalizedPredictionsService {
  static PersonalizedPredictionsService? _instance;
  static PersonalizedPredictionsService get instance =>
      _instance ??= PersonalizedPredictionsService._();
  PersonalizedPredictionsService._();

  PalmPredictionsData? _cache;
  String? _cacheDay;
  Future<PalmPredictionsData>? _inFlight;

  /// Latest palm scan, then cached AI horoscopes for the current periods.
  /// If the horoscope function is unavailable, the same stored lines are used locally.
  Future<PalmPredictionsData> getPredictions() {
    final day = _istDayKey(DateTime.now());
    if (_cache != null && _cacheDay == day) return Future.value(_cache!);
    _inFlight ??= _load(day);
    return _inFlight!;
  }

  Future<PalmPredictionsData> _load(String day) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return PalmPredictionsData.empty();

      final analysis = await SupabaseService.instance.client
          .from('palm_analysis')
          .select(
            'id, summary, life_analysis, love_analysis, career_analysis, health_analysis, wealth_analysis, personality_analysis',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (analysis == null) return PalmPredictionsData.empty();

      Map<String, dynamic>? features;
      try {
        features = await SupabaseService.instance.client
            .from('palm_features')
            .select(
              'life_line, heart_line, head_line, fate_line, mercury_line, mounts',
            )
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (_) {}

      String? userName;
      try {
        final profile = await SupabaseService.instance.client
            .from('user_profiles')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
        userName = profile?['full_name'] as String?;
      } catch (_) {}

      PalmPredictionsData? remote;
      try {
        final response = await SupabaseService.instance.client.functions
            .invoke('horoscope-insights');
        final data = response.data;
        if (data is Map && data['personalized'] == true) {
          remote = _fromServer(Map<String, dynamic>.from(data), userName);
        }
      } catch (e) {
        debugPrint('horoscope-insights unavailable, using saved scan: $e');
      }

      final result = (remote != null && remote.today.isNotEmpty)
          ? remote
          : _fromScan(
              Map<String, dynamic>.from(analysis),
              features,
              userName,
            );
      _cache = result;
      _cacheDay = day;
      return result;
    } catch (e) {
      debugPrint('PersonalizedPredictionsService error: $e');
      return PalmPredictionsData.empty();
    } finally {
      _inFlight = null;
    }
  }

  PalmPredictionsData _fromServer(
    Map<String, dynamic> data,
    String? userName,
  ) {
    final insights = data['insights'];
    if (insights is! Map) return PalmPredictionsData.empty();
    List<PersonalizedPrediction> read(String key) {
      final raw = insights[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (item) => PersonalizedPrediction(
              category: (item['category'] ?? 'Insight').toString(),
              categoryHi: (item['category_hi'] ?? item['category'] ?? 'Insight')
                  .toString(),
              content: (item['content'] ?? '').toString(),
              contentHi: (item['content_hi'] ?? item['content'] ?? '')
                  .toString(),
              iconName: (item['icon'] ?? 'auto_awesome').toString(),
              confidence: (item['confidence'] as num?)?.toInt() ?? 75,
              isMajorEvent: item['is_major'] == true,
            ),
          )
          .where((p) => p.content.trim().isNotEmpty)
          .toList();
    }

    final today = read('daily');
    return PalmPredictionsData(
      today: today,
      weekly: read('weekly'),
      monthly: read('monthly'),
      yearly: read('yearly'),
      userName: userName,
      isPersonalized: today.isNotEmpty,
    );
  }

  PalmPredictionsData _fromScan(
    Map<String, dynamic> analysis,
    Map<String, dynamic>? features,
    String? userName,
  ) {
    final love = _text(analysis['love_analysis']);
    final career = _text(analysis['career_analysis']);
    final wealth = _text(analysis['wealth_analysis']);
    final health = _text(analysis['health_analysis']);
    final life = _text(analysis['life_analysis']);
    final mind = _text(analysis['personality_analysis']);
    final heart = _trait(features?['heart_line'], 'heart line');
    final fate = _trait(features?['fate_line'], 'fate line');
    final mercury = _trait(features?['mercury_line'], 'mercury line');
    final lifeLine = _trait(features?['life_line'], 'life line');
    final head = _trait(features?['head_line'], 'head line');

    PersonalizedPrediction? card({
      required String category,
      required String categoryHi,
      required String trait,
      required String saved,
      required String period,
      required String icon,
      required int confidence,
    }) {
      if (saved.isEmpty && trait == category) return null;
      final basis = saved.isNotEmpty ? saved : 'No extra note was stored.';
      return PersonalizedPrediction(
        category: category,
        categoryHi: categoryHi,
        content:
            '$period your $trait, saved from your palm scan, sets this reading. $basis',
        contentHi:
            '$period आपकी $trait, जो आपके स्कैन में सहेजी है, इस पठन का आधार है। $basis',
        iconName: icon,
        confidence: confidence,
        isMajorEvent: confidence >= 85,
      );
    }

    List<PersonalizedPrediction> pack(String period) => [
      card(
        category: 'Love',
        categoryHi: 'प्रेम',
        trait: heart,
        saved: love,
        period: period,
        icon: 'favorite_outline',
        confidence: 82,
      ),
      card(
        category: 'Career',
        categoryHi: 'करियर',
        trait: fate,
        saved: career,
        period: period,
        icon: 'work_outline',
        confidence: 80,
      ),
      card(
        category: 'Wealth',
        categoryHi: 'धन',
        trait: mercury,
        saved: wealth,
        period: period,
        icon: 'currency_rupee',
        confidence: 78,
      ),
      card(
        category: 'Health',
        categoryHi: 'स्वास्थ्य',
        trait: lifeLine,
        saved: health.isNotEmpty ? health : life,
        period: period,
        icon: 'self_improvement',
        confidence: 76,
      ),
      card(
        category: 'Mind',
        categoryHi: 'मन',
        trait: head,
        saved: mind,
        period: period,
        icon: 'auto_awesome',
        confidence: 77,
      ),
    ].whereType<PersonalizedPrediction>().toList();

    final today = pack('Today');
    return PalmPredictionsData(
      today: today,
      weekly: pack('This week'),
      monthly: pack('This month'),
      yearly: pack('This year'),
      userName: userName,
      isPersonalized: today.isNotEmpty,
    );
  }

  String _text(dynamic analysis) {
    if (analysis is! Map) return '';
    final map = Map<String, dynamic>.from(analysis);
    final raw = (map['interpretation_en'] ?? map['summary_en'] ?? '')
        .toString()
        .trim();
    if (raw.length <= 420) return raw;
    return '${raw.substring(0, 417)}...';
  }

  String _trait(dynamic line, String name) {
    if (line is! Map) return name;
    final map = Map<String, dynamic>.from(line);
    const keys = ['length', 'depth', 'curve', 'quality', 'clarity', 'shape'];
    final bits = <String>[];
    for (final key in keys) {
      final value = map[key];
      if (value == null || value is Map || value is List) continue;
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      bits.add('$key $text');
    }
    if (bits.isEmpty) return name;
    return '$name (${bits.take(3).join(', ')})';
  }

  String _istDayKey(DateTime now) {
    final shifted = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final y = shifted.year.toString().padLeft(4, '0');
    final m = shifted.month.toString().padLeft(2, '0');
    final d = shifted.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
