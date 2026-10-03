import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One daily engagement card. The hook title rotates by calendar day.
/// The body always quotes the user's stored palm scan when one exists.
class EngagementAlert {
  final String id;
  final String title;
  final String body;
  final String question;
  final String teaser;
  final IconData icon;
  final bool personalized;

  const EngagementAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.question,
    required this.teaser,
    required this.icon,
    required this.personalized,
  });
}

class EngagementAlertsService {
  EngagementAlertsService._();
  static final EngagementAlertsService instance = EngagementAlertsService._();

  Future<List<EngagementAlert>> todaysAlerts() async {
    final day = _istDate(DateTime.now());
    Map<String, dynamic>? analysis;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        analysis = await Supabase.instance.client
            .from('palm_analysis')
            .select(
              'love_analysis, career_analysis, wealth_analysis, life_analysis, personality_analysis',
            )
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (_) {}
    }

    final love = _snippet(analysis?['love_analysis']);
    final career = _snippet(analysis?['career_analysis']);
    final wealth = _snippet(analysis?['wealth_analysis']);
    final life = _snippet(analysis?['life_analysis']);
    final mind = _snippet(analysis?['personality_analysis']);
    final hasScan = [love, career, wealth, life, mind].any((s) => s.isNotEmpty);
    final dayIndex = day.difference(DateTime.utc(day.year)).inDays;

    String bodyFor(String snippet, String lineName, String fallback) {
      if (snippet.isNotEmpty) {
        return 'From your saved $lineName: $snippet';
      }
      if (hasScan) return fallback;
      return 'Scan your palm so this alert can use your own lines.';
    }

    final hooks = <_Hook>[
      _Hook(
        title: _pick(dayIndex, const [
          'Someone Falling For You...',
          'A Heart-Line Signal Today',
          'Love Is Moving Closer',
        ]),
        line: 'heart line',
        snippet: love,
        fallback:
            'Your heart line is active today. Ask what it means for someone new.',
        question:
            'Based on my heart line from my palm scan, is someone falling for me?',
        teaser:
            'A quiet change in your heart line suggests someone is moving closer than you think...',
        icon: Icons.favorite_rounded,
      ),
      _Hook(
        title: _pick(dayIndex + 1, const [
          'A Massive Change Is Coming?',
          'Your Fate Line Is Shifting',
          'A Turning Point This Week',
        ]),
        line: 'fate line',
        snippet: career,
        fallback:
            'Your fate line points to a career shift. Ask what to do with it.',
        question:
            'Based on my fate line from my palm scan, what change is coming in my career?',
        teaser:
            'A hidden shift in your fate line indicates an unexpected turn...',
        icon: Icons.auto_awesome_rounded,
      ),
      _Hook(
        title: _pick(dayIndex + 2, const [
          'Money Is Coming Your Way?',
          'A Wealth Window Is Open',
          'Your Mercury Line Speaks',
        ]),
        line: 'wealth lines',
        snippet: wealth,
        fallback:
            'Your wealth markings suggest a money opening. Ask how to use it.',
        question:
            'Based on my palm scan wealth lines, is money coming my way soon?',
        teaser:
            'Your wealth lines are holding one money opening you have not been told yet...',
        icon: Icons.currency_rupee_rounded,
      ),
      _Hook(
        title: _pick(dayIndex + 3, const [
          'Your Energy Needs Attention',
          'The Life Line Speaks Today',
          'Protect Your Vitality',
        ]),
        line: 'life line',
        snippet: life,
        fallback:
            'Your life line sets the pace for today. Ask how to spend your energy.',
        question:
            'Based on my life line from my palm scan, how should I take care of my energy today?',
        teaser:
            'Your life line is hinting at a change of pace you have not named yet...',
        icon: Icons.spa_rounded,
      ),
    ];

    return [
      for (var i = 0; i < hooks.length; i++)
        EngagementAlert(
          id: '${day.toIso8601String().substring(0, 10)}-$i',
          title: hooks[i].title,
          body: bodyFor(hooks[i].snippet, hooks[i].line, hooks[i].fallback),
          question: hooks[i].question,
          teaser: hooks[i].teaser,
          icon: hooks[i].icon,
          personalized: hooks[i].snippet.isNotEmpty,
        ),
    ];
  }

  String _snippet(dynamic analysis) {
    if (analysis is! Map) return '';
    final map = Map<String, dynamic>.from(analysis);
    final raw = (map['interpretation_en'] ?? map['summary_en'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return '';
    final sentence = raw.split(RegExp(r'(?<=[.!?])\s+')).first.trim();
    if (sentence.length <= 160) return sentence;
    return '${sentence.substring(0, 157)}...';
  }

  String _pick(int index, List<String> options) =>
      options[index.abs() % options.length];

  DateTime _istDate(DateTime now) {
    final shifted = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateTime.utc(shifted.year, shifted.month, shifted.day);
  }
}

class _Hook {
  final String title;
  final String line;
  final String snippet;
  final String fallback;
    final String question;
    final String teaser;
    final IconData icon;

    const _Hook({
      required this.title,
      required this.line,
      required this.snippet,
      required this.fallback,
      required this.question,
      required this.teaser,
      required this.icon,
    });
}
