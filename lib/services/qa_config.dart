import './entitlement_service.dart';

// ============================================================
// HastVeda — QA / Testing Configuration
//
// Central place for QA-cycle toggles that must be flipped BACK to their
// production values before shipping a release build.
//
// HOW TO SWITCH BACK TO PRODUCTION BEHAVIOUR
// ------------------------------------------
//   1. Set `bypassFreeScanQuota` to `false` in this file.
//   2. Run the rollback SQL documented at the bottom of the migration:
//        supabase/migrations/20260817000000_qa_bypass_free_scan_quota.sql
//      i.e.
//        UPDATE public.app_settings
//           SET value = jsonb_set(value, '{scans_per_month}', '2'::jsonb)
//         WHERE key = 'free_tier_limits';
//
// Both steps are required — the client short-circuit alone does NOT lift the
// server-side quota enforced by the palm-analysis Edge Function.
// ============================================================

/// QA / testing toggles.
///
/// Everything on this class is a compile-time constant so the Dart tree
/// shaker can eliminate the bypass code paths in release builds once the
/// flags are turned off.
class QaConfig {
  QaConfig._();

  /// When `true`, the client-side free-tier check for
  /// `scans_per_month` in [EntitlementService.checkFreeTierLimit] is
  /// short-circuited and always reports "allowed".
  ///
  /// This mirrors the server-side bypass installed by the migration
  /// `20260817000000_qa_bypass_free_scan_quota.sql`, which raises
  /// `app_settings.free_tier_limits.scans_per_month` to a very large
  /// value so the palm-analysis Edge Function stops returning
  /// `FREE_LIMIT_REACHED` (HTTP 403).
  ///
  /// Flip to `false` (and run the rollback SQL) to restore the
  /// production 2-scans-per-month limit.
  static const bool bypassFreeScanQuota = false;
}
