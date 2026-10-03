import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/analytics_service.dart';
import '../../services/app_strings.dart';
import '../../services/cashfree_payment_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/entitlement_notifier.dart';
import '../../services/locale_provider.dart';
import '../../services/premium_strings.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

// Conditional import for Cashfree SDK (not supported on web)
import 'cashfree_checkout_stub.dart'
    if (dart.library.io) 'cashfree_checkout_mobile.dart';

// Cashfree environment: 'sandbox' for test builds, 'production' for release.
// Override at build time: --dart-define=CASHFREE_ENV=sandbox
const String _kCashfreeEnv = String.fromEnvironment(
  'CASHFREE_ENV',
  defaultValue: 'production',
);

/// Premium Paywall Screen — HastVeda branded with Cashfree integration
class PremiumPaywallScreen extends StatefulWidget {
  final String? returnRoute;
  final String locale;

  const PremiumPaywallScreen({super.key, this.returnRoute, this.locale = 'en'});

  @override
  State<PremiumPaywallScreen> createState() => _PremiumPaywallScreenState();
}

class _PremiumPaywallScreenState extends State<PremiumPaywallScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _isVerifying = false; // true while polling/verifying after SDK callback
  final bool _isCouponLoading = false;
  String _couponCode = '';
  String? _couponError;
  String? _couponSuccess;
  double? _discountAmount;
  double? _finalAmount;
  double? _baseAmount;
  double? _gstAmount;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late PremiumStrings _strings;

  final TextEditingController _couponController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _strings = PremiumStrings(locale: widget.locale);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    analytics.track(HastVedaEvents.premiumScreenViewed);
  }

  @override
  void dispose() {
    _animController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  void _onCouponChanged(String value) {
    setState(() {
      _couponCode = value.trim().toUpperCase();
      _couponError = null;
      _couponSuccess = null;
      if (value.isEmpty) {
        _discountAmount = null;
        _finalAmount = null;
      }
    });
  }

  Future<void> _onUnlockTapped() async {
    if (ConnectivityService.instance.isOffline) {
      final lp = context.read<LocaleProvider>();
      final s = AppStrings.of(lp.languageCode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.internetRequired),
          backgroundColor: AppTheme.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      _showWebNotSupported();
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Step 1: Create order server-side
      final orderResult = await CashfreePaymentService.instance.createOrder(
        couponCode: _couponCode.isNotEmpty ? _couponCode : null,
      );

      if (!orderResult.success || orderResult.orderId == null) {
        if (mounted) {
          _showError(orderResult.error ?? 'Failed to create order');
        }
        return;
      }

      // Guard: payment_session_id must be non-null and non-empty before
      // passing to the Cashfree SDK — a null/empty token causes the SDK
      // to throw "Token is not present" with no useful context.
      final sessionId = orderResult.paymentSessionId;
      if (sessionId == null || sessionId.trim().isEmpty) {
        if (mounted) {
          _showError('Unable to start payment. Please try again.');
        }
        return;
      }

      // Step 2: Open Cashfree checkout — this now properly awaits the SDK
      // callback via a Completer (see cashfree_checkout_mobile.dart).
      // The function only returns after the user completes/cancels payment
      // AND server-side verification has been attempted.
      final checkoutResult = await openCashfreeCheckout(
        orderId: orderResult.orderId!,
        paymentSessionId: sessionId,
        environment: _kCashfreeEnv,
        onVerifyPayment: (orderId) async {
          // Show verifying state while we wait for server confirmation
          if (mounted) setState(() => _isVerifying = true);

          // Step 3: Server-side verification — this is the source of truth.
          // Poll briefly (up to 3 attempts) to handle slight DB propagation delay.
          CashfreeVerifyResult? verifyResult;
          for (int attempt = 0; attempt < 3; attempt++) {
            verifyResult = await CashfreePaymentService.instance.verifyPayment(
              orderId,
            );

            if (verifyResult.success &&
                verifyResult.status == 'payment_successful') {
              break;
            }
            // If status is pending, wait briefly and retry
            if (verifyResult.status == 'payment_pending' && attempt < 2) {
              await Future.delayed(const Duration(seconds: 2));
              continue;
            }
            break;
          }

          if (mounted) setState(() => _isVerifying = false);

          if (verifyResult == null) return false;

          // entitlement_grant_failed: Cashfree was PAID but DB write failed
          if (verifyResult.status == 'entitlement_grant_failed') {
            if (mounted) {
              _showError(
                verifyResult.error ??
                    'Payment received but Premium activation failed. Please tap "Restore Purchases" or contact support.',
              );
            }
            return false;
          }

          return verifyResult.success &&
              verifyResult.status == 'payment_successful';
        },
        onError: (errorMessage) {
          if (mounted) {
            setState(() => _isVerifying = false);
            _showError(errorMessage);
          }
        },
      );

      if (checkoutResult == true) {
        // Step 4: Cashfree verification succeeded. Force a fresh entitlements
        // read from Postgres, mark PREMIUM active, and notifyListeners()
        // before the dialog — screens underneath rebuild without logout.
        if (mounted) {
          await context.read<EntitlementNotifier>().notifyPremiumGranted();
        }
        if (mounted) {
          _showPaymentSuccess();
        }
      } else if (checkoutResult == false) {
        // verifyPayment returned false — could be entitlement_grant_failed
        if (mounted) {
          _showError(
            'Payment received but Premium activation failed. Please tap "Restore Purchases" or contact support.',
          );
        }
      }
      // checkoutResult == null means user cancelled or timed out — no action needed
    } catch (e) {
      if (mounted) {
        _showError('Payment failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isVerifying = false;
        });
      }
    }
  }

  void _showWebNotSupported() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _WebNotSupportedSheet(strings: _strings),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showPaymentSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentSuccessDialog(
        onContinue: () {
          Navigator.of(context).pop(); // close dialog
          Navigator.of(context).pop(); // close paywall
        },
      ),
    );
  }

  Future<void> _onRestorePurchases() async {
    setState(() => _isLoading = true);
    if (mounted) {
      await context.read<EntitlementNotifier>().refresh();
    }
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase status refreshed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0A06),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildBenefitsGrid()),
              SliverToBoxAdapter(child: _buildPricingSection()),
              SliverToBoxAdapter(child: _buildCouponSection()),
              SliverToBoxAdapter(child: _buildCtaSection()),
              SliverToBoxAdapter(child: _buildFooter()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        Container(
          height: 340,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A1200), Color(0xFF1A0A00), Color(0xFF0F0A06)],
              stops: [0.0, 0.6, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -60,
          right: -60,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppTheme.primary.withAlpha(80), Colors.transparent],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFF0A0A0F),
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _strings.premiumBadge.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _strings.paywallHeadline,
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _strings.paywallSubtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Colors.white60,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitsGrid() {
    final benefits = [
      _BenefitItem('❤️', _strings.benefitLove),
      _BenefitItem('💰', _strings.benefitWealth),
      _BenefitItem('💼', _strings.benefitCareer),
      _BenefitItem('🧠', _strings.benefitPersonality),
      _BenefitItem('✋', _strings.benefitPalmLines),
      _BenefitItem('💍', _strings.benefitMarriage),
      _BenefitItem('🔮', _strings.benefitFuture),
      _BenefitItem('📅', _strings.benefitPredictions),
      _BenefitItem('📊', _strings.benefitReports),
      _BenefitItem('🕘', _strings.benefitHistory),
    ];

    return Container(
      color: const Color(0xFF0F0A06),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBentoRow(benefits[0], benefits[1], large: true),
          const SizedBox(height: 10),
          _buildBentoRow(benefits[2], benefits[3], large: false),
          const SizedBox(height: 10),
          _buildBentoRow(benefits[4], benefits[5], large: false),
          const SizedBox(height: 10),
          _buildBentoRow(benefits[6], benefits[7], large: true),
          const SizedBox(height: 10),
          _buildBentoRow(benefits[8], benefits[9], large: false),
        ],
      ),
    );
  }

  Widget _buildBentoRow(
    _BenefitItem left,
    _BenefitItem right, {
    required bool large,
  }) {
    return Row(
      children: [
        Expanded(
          flex: large ? 3 : 2,
          child: _BenefitCard(item: left, tall: large),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: large ? 2 : 3,
          child: _BenefitCard(item: right, tall: !large),
        ),
      ],
    );
  }

  Widget _buildPricingSection() {
    final displayBase = _baseAmount ?? CashfreePaymentService.launchPrice;
    final displayGst =
        _gstAmount ?? (CashfreePaymentService.launchPrice * 0.18);
    final displayTotal =
        _finalAmount ?? (CashfreePaymentService.launchPrice + displayGst);
    final hasDiscount = _discountAmount != null && _discountAmount! > 0;

    return Container(
      color: const Color(0xFF0F0A06),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppTheme.primary.withAlpha(80),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0E06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _strings.paywallLaunchOfferLabel.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${displayBase.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: hasDiscount
                            ? Colors.green.shade400
                            : AppTheme.primary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _strings.paywallRegularPriceLabel,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                          Text(
                            _strings.paywallRegularPrice,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white38,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade900,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade700),
                        ),
                        child: Text(
                          '−₹${_discountAmount!.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade400,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // GST breakdown
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Base price',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.white60,
                            ),
                          ),
                          Text(
                            '₹${displayBase.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'GST (18%)',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.white60,
                            ),
                          ),
                          Text(
                            '₹${displayGst.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total payable',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '₹${displayTotal.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'One-time purchase • Lifetime access',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Colors.white38,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponSection() {
    return Container(
      color: const Color(0xFF0F0A06),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Have a discount code?',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  onChanged: _onCouponChanged,
                  textCapitalization: TextCapitalization.characters,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. HV-A8K4P7X2',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 13,
                      color: Colors.white24,
                      letterSpacing: 0.5,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1A0E06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withAlpha(20)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withAlpha(20)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: _couponCode.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white38,
                              size: 18,
                            ),
                            onPressed: () {
                              _couponController.clear();
                              setState(() {
                                _couponCode = '';
                                _couponError = null;
                                _couponSuccess = null;
                                _discountAmount = null;
                                _finalAmount = null;
                              });
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (_couponError != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade400, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _couponError!,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_couponSuccess != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Colors.green.shade400,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _couponSuccess!,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.green.shade400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCtaSection() {
    return Container(
      color: AppTheme.backgroundDark,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.gold.withAlpha(80),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onUnlockTapped,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Color(0xFF0A0A0F),
                          strokeWidth: 2.5,
                        ),
                      )
                    : _isVerifying
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Color(0xFF0A0A0F),
                              strokeWidth: 2.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Verifying payment...',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0A0A0F),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_open_rounded,
                            color: Color(0xFF0A0A0F),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _strings.paywallCta,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0A0A0F),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : _onRestorePurchases,
            child: Text(
              _strings.paywallRestorePurchases,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      color: const Color(0xFF0F0A06),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TrustBadge(icon: Icons.security_rounded, label: 'Secure'),
              const SizedBox(width: 20),
              _TrustBadge(icon: Icons.verified_rounded, label: 'Cashfree'),
              const SizedBox(width: 20),
              _TrustBadge(
                icon: Icons.auto_awesome_rounded,
                label: 'AI Powered',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.primary.withAlpha(180),
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  'Powered by Cashfree Payments • Secure Payments',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SUPPORTING WIDGETS
// ============================================================

class _BenefitItem {
  final String emoji;
  final String label;
  const _BenefitItem(this.emoji, this.label);
}

class _BenefitCard extends StatelessWidget {
  final _BenefitItem item;
  final bool tall;

  const _BenefitCard({required this.item, required this.tall});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: tall ? 80 : 64,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Row(
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white24, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 10,
            color: Colors.white24,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PaymentSuccessDialog extends StatelessWidget {
  final VoidCallback onContinue;

  const _PaymentSuccessDialog({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A0E06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.goldGradient,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Payment Successful!',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Your Premium plan is now active. You now have unlimited access to all Premium features.',
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.white60,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebNotSupportedSheet extends StatelessWidget {
  final PremiumStrings strings;

  const _WebNotSupportedSheet({required this.strings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF1A0E06),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text('📱', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 16),
          Text(
            'Open in the App',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Cashfree payments are available in the HastVeda Android app. Download the APK to complete your purchase.',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: Colors.white54,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'Got it',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
