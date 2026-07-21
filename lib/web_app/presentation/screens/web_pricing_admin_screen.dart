import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_pricing_admin_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';

class WebPricingAdminScreen extends StatefulWidget {
  final String pairedUserUid;
  const WebPricingAdminScreen({super.key, required this.pairedUserUid});

  @override
  State<WebPricingAdminScreen> createState() =>
      _WebPricingAdminScreenState();
}

class _WebPricingAdminScreenState extends State<WebPricingAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  bool _loading  = true;
  bool _isAdmin  = false;
  String? _error;

  static const String _staticAdmin = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

  // ── Aggregate stats ───────────────────────────────────────────────────────
  int    _totalSuccessful   = 0;
  int    _totalFailed       = 0;
  int    _totalAttempts     = 0;
  double _revenueNgn        = 0;
  double _revenueUsd        = 0;
  int    _leagueCreations   = 0;
  int    _planSubscriptions = 0;
  int    _verifications     = 0;
  int    _couponRedemptions = 0;

  // Daily revenue map  { 'YYYY-MM-DD': {'NGN': x, 'USD': y} }
  final Map<String, Map<String, double>> _dailyRevenue = {};

  // By product type
  final Map<String, _ProductStat> _byProduct = {};

  // ── NGN pricing controllers ───────────────────────────────────────────────
  final _ngnCreateFee       = TextEditingController();
  final _ngnAccessFee       = TextEditingController();
  final _ngnCouponUnit      = TextEditingController();
  final _ngnCouponThreshold = TextEditingController();
  final _ngnCouponDiscPct   = TextEditingController();
  final _ngnPremiumFee      = TextEditingController();
  final _ngnPremiumDays     = TextEditingController();
  final _ngnPro3mo          = TextEditingController();
  final _ngnPro6mo          = TextEditingController();
  final _ngnProYearly       = TextEditingController();
  final _ngnElite3mo        = TextEditingController();
  final _ngnElite6mo        = TextEditingController();
  final _ngnEliteYearly     = TextEditingController();
  final _ngnMlBasic         = TextEditingController();
  final _ngnMlPro           = TextEditingController();
  final _ngnMlElite         = TextEditingController();
  final _ngnVerifFee        = TextEditingController();
  final _ngnRenewalFee      = TextEditingController();
  final _ngnRenewalDays     = TextEditingController();
  bool _ngnViewers        = false;
  bool _ngnPremiumEnabled = true;
  bool _ngnVerifEnabled   = true;
  bool _ngnRenewalEnabled = true;
  bool _ngnPayments       = true;
  bool _ngnFlutterwave    = true;

  // ── USD pricing controllers ───────────────────────────────────────────────
  final _usdCreateFee       = TextEditingController();
  final _usdAccessFee       = TextEditingController();
  final _usdCouponUnit      = TextEditingController();
  final _usdCouponThreshold = TextEditingController();
  final _usdCouponDiscPct   = TextEditingController();
  final _usdPremiumFee      = TextEditingController();
  final _usdPremiumDays     = TextEditingController();
  final _usdPro3mo          = TextEditingController();
  final _usdPro6mo          = TextEditingController();
  final _usdProYearly       = TextEditingController();
  final _usdElite3mo        = TextEditingController();
  final _usdElite6mo        = TextEditingController();
  final _usdEliteYearly     = TextEditingController();
  final _usdMlBasic         = TextEditingController();
  final _usdMlPro           = TextEditingController();
  final _usdMlElite         = TextEditingController();
  final _usdVerifFee        = TextEditingController();
  final _usdRenewalFee      = TextEditingController();
  final _usdRenewalDays     = TextEditingController();
  bool _usdViewers        = false;
  bool _usdPremiumEnabled = true;
  bool _usdVerifEnabled   = true;
  bool _usdRenewalEnabled = true;
  bool _usdPayments       = true;
  bool _usdFlutterwave    = true;

  bool _savingPricing = false;
  String? _saveMsg;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _allCtrl()) c.dispose();
    super.dispose();
  }

  List<TextEditingController> _allCtrl() => [
    _ngnCreateFee, _ngnAccessFee, _ngnCouponUnit, _ngnCouponThreshold,
    _ngnCouponDiscPct, _ngnPremiumFee, _ngnPremiumDays, _ngnPro3mo,
    _ngnPro6mo, _ngnProYearly, _ngnElite3mo, _ngnElite6mo, _ngnEliteYearly,
    _ngnMlBasic, _ngnMlPro, _ngnMlElite, _ngnVerifFee, _ngnRenewalFee,
    _ngnRenewalDays,
    _usdCreateFee, _usdAccessFee, _usdCouponUnit, _usdCouponThreshold,
    _usdCouponDiscPct, _usdPremiumFee, _usdPremiumDays, _usdPro3mo,
    _usdPro6mo, _usdProYearly, _usdElite3mo, _usdElite6mo, _usdEliteYearly,
    _usdMlBasic, _usdMlPro, _usdMlElite, _usdVerifFee, _usdRenewalFee,
    _usdRenewalDays,
  ];

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _checkAdmin();
      if (_isAdmin) {
        await Future.wait([
          _loadPricing(),
          _loadStats(),
        ]);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkAdmin() async {
    final uid = widget.pairedUserUid.trim();
    if (uid.isEmpty) { _isAdmin = false; return; }
    if (uid == _staticAdmin) { _isAdmin = true; return; }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app').doc('admins').get();
      if (!snap.exists) { _isAdmin = false; return; }
      final list = snap.data()?['pricingAdmins'];
      _isAdmin = list is List &&
          list.any((v) => v.toString().trim() == uid);
    } catch (_) { _isAdmin = false; }
  }

  // ── Load stats ────────────────────────────────────────────────────────────
  Future<void> _loadStats() async {
    try {
      // All payments
      final paySnap = await FirebaseFirestore.instance
          .collection('payments')
          .limit(1000)
          .get();

      int success = 0, failed = 0;
      double ngn = 0, usd = 0;
      int creations = 0, plans = 0, verifs = 0, coupons = 0;
      final Map<String, _ProductStat> byProd = {};
      final Map<String, Map<String, double>> daily = {};

      for (final doc in paySnap.docs) {
        final d        = doc.data();
        final status   = (d['status'] ?? '').toString();
        final currency = (d['currency'] ?? '').toString().toUpperCase();
        final amount   = ((d['amount'] as num?) ?? 0).toDouble();
        final pType    = (d['productType'] ?? 'unknown').toString();
        final paidAtMs = ((d['paidAtMs'] as num?) ?? 0).toInt();

        if (status == 'success') {
          success++;
          if (currency == 'NGN') ngn += amount; else usd += amount;
          if (pType.contains('league_creation')) creations++;
          if (pType.contains('plan_subscription')) plans++;
          if (pType.contains('verification')) verifs++;
          if (pType.contains('coupon')) coupons++;

          // Daily
          if (paidAtMs > 0) {
            final dt  = DateTime.fromMillisecondsSinceEpoch(paidAtMs);
            final key = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
            daily.putIfAbsent(key, () => {'NGN': 0, 'USD': 0});
            daily[key]![currency] = (daily[key]![currency] ?? 0) + amount;
          }

          // By product
          byProd.putIfAbsent(pType, () => _ProductStat(pType));
          byProd[pType]!.count++;
          if (currency == 'NGN') byProd[pType]!.ngn += amount;
          else byProd[pType]!.usd += amount;
        } else {
          failed++;
        }
      }

      // Attempts
      final attSnap = await FirebaseFirestore.instance
          .collection('payment_attempts')
          .limit(500)
          .get();

      if (mounted) {
        setState(() {
          _totalSuccessful   = success;
          _totalFailed       = failed;
          _totalAttempts     = attSnap.docs.length;
          _revenueNgn        = ngn;
          _revenueUsd        = usd;
          _leagueCreations   = creations;
          _planSubscriptions = plans;
          _verifications     = verifs;
          _couponRedemptions = coupons;
          _dailyRevenue
            ..clear()
            ..addAll(daily);
          _byProduct
            ..clear()
            ..addAll(byProd);
        });
      }
    } catch (_) {}
  }

  // ── Load pricing ──────────────────────────────────────────────────────────
  Future<void> _loadPricing() async {
    final data = await AppPricingAdminService().fetch();
    final ngn  = (data['ngn'] as Map?)?.cast<String, dynamic>() ?? {};
    final usd  = (data['usd'] as Map?)?.cast<String, dynamic>() ?? {};
    _fillCtrl(ngn, isUsd: false);
    _fillCtrl(usd, isUsd: true);
  }

  String _fmt(dynamic v) {
    if (v == null) return '0';
    if (v is double) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toStringAsFixed(2);
    }
    if (v is int) return '$v';
    if (v is num) return v.toDouble().toStringAsFixed(2);
    return '$v';
  }

  void _fillCtrl(Map<String, dynamic> m, {required bool isUsd}) {
    String n(String k, double def) =>
        _fmt(m[k] ?? m[k.replaceAll('Fee', 'fee')] ?? def);

    if (isUsd) {
      _usdCreateFee.text       = n('createFee', 5);
      _usdAccessFee.text       = n('accessFee', 1.5);
      _usdCouponUnit.text      = n('couponUnit', 1.5);
      _usdCouponThreshold.text = n('couponThreshold', 20);
      _usdCouponDiscPct.text   = n('couponDiscountPercent', 30);
      _usdPremiumFee.text      = n('premiumFee', 9.99);
      _usdPremiumDays.text     = '${m['premiumDurationDays'] ?? 30}';
      _usdPro3mo.text          = n('proPlan3moFee', 10);
      _usdPro6mo.text          = n('proPlan6moFee', 18);
      _usdProYearly.text       = n('proPlanYearlyFee', 30);
      _usdElite3mo.text        = n('elitePlan3moFee', 20);
      _usdElite6mo.text        = n('elitePlan6moFee', 36);
      _usdEliteYearly.text     = n('elitePlanYearlyFee', 60);
      _usdMlBasic.text         = n('masterLeagueBasicFee', 5);
      _usdMlPro.text           = n('masterLeagueProFee', 10);
      _usdMlElite.text         = n('masterLeagueEliteFee', 20);
      _usdVerifFee.text        = n('organizerVerificationFee', 15);
      _usdRenewalFee.text      = n('organizerVerificationRenewalFee', 12);
      _usdRenewalDays.text     = '${m['organizerVerificationDurationDays'] ?? 90}';
      _usdViewers        = m['viewersEnabled']                    == true;
      _usdPremiumEnabled = m['premiumEnabled']                    != false;
      _usdVerifEnabled   = m['organizerVerificationEnabled']      != false;
      _usdRenewalEnabled = m['organizerVerificationRenewalEnabled'] != false;
      _usdPayments       = m['paymentsEnabled']                   != false;
      _usdFlutterwave    = m['flutterwaveEnabled']                != false;
    } else {
      _ngnCreateFee.text       = n('createFee', 4000);
      _ngnAccessFee.text       = n('accessFee', 1000);
      _ngnCouponUnit.text      = n('couponUnit', 1000);
      _ngnCouponThreshold.text = n('couponThreshold', 0);
      _ngnCouponDiscPct.text   = n('couponDiscountPercent', 30);
      _ngnPremiumFee.text      = n('premiumFee', 5000);
      _ngnPremiumDays.text     = '${m['premiumDurationDays'] ?? 30}';
      _ngnPro3mo.text          = n('proPlan3moFee', 5000);
      _ngnPro6mo.text          = n('proPlan6moFee', 9000);
      _ngnProYearly.text       = n('proPlanYearlyFee', 15000);
      _ngnElite3mo.text        = n('elitePlan3moFee', 10000);
      _ngnElite6mo.text        = n('elitePlan6moFee', 18000);
      _ngnEliteYearly.text     = n('elitePlanYearlyFee', 30000);
      _ngnMlBasic.text         = n('masterLeagueBasicFee', 1500);
      _ngnMlPro.text           = n('masterLeagueProFee', 3000);
      _ngnMlElite.text         = n('masterLeagueEliteFee', 5000);
      _ngnVerifFee.text        = n('organizerVerificationFee', 10000);
      _ngnRenewalFee.text      = n('organizerVerificationRenewalFee', 8000);
      _ngnRenewalDays.text     = '${m['organizerVerificationDurationDays'] ?? 90}';
      _ngnViewers        = m['viewersEnabled']                    == true;
      _ngnPremiumEnabled = m['premiumEnabled']                    != false;
      _ngnVerifEnabled   = m['organizerVerificationEnabled']      != false;
      _ngnRenewalEnabled = m['organizerVerificationRenewalEnabled'] != false;
      _ngnPayments       = m['paymentsEnabled']                   != false;
      _ngnFlutterwave    = m['flutterwaveEnabled']                != false;
    }
  }

  // ── Build price map ───────────────────────────────────────────────────────
  Map<String, dynamic> _buildMap({required bool isUsd}) {
    double d(TextEditingController c) =>
        double.tryParse(c.text.trim()) ?? 0;
    int i(TextEditingController c) =>
        int.tryParse(c.text.trim()) ?? 0;

    if (isUsd) {
      return {
        'createFee': d(_usdCreateFee),
        'accessFee': d(_usdAccessFee),
        'couponUnit': d(_usdCouponUnit),
        'couponThreshold': d(_usdCouponThreshold),
        'couponDiscountPercent': d(_usdCouponDiscPct),
        'premiumFee': d(_usdPremiumFee),
        'premiumDurationDays': i(_usdPremiumDays),
        'proPlan3moFee': d(_usdPro3mo),
        'proPlan6moFee': d(_usdPro6mo),
        'proPlanYearlyFee': d(_usdProYearly),
        'elitePlan3moFee': d(_usdElite3mo),
        'elitePlan6moFee': d(_usdElite6mo),
        'elitePlanYearlyFee': d(_usdEliteYearly),
        'masterLeagueBasicFee': d(_usdMlBasic),
        'masterLeagueProFee': d(_usdMlPro),
        'masterLeagueEliteFee': d(_usdMlElite),
        'organizerVerificationFee': d(_usdVerifFee),
        'organizerVerificationRenewalFee': d(_usdRenewalFee),
        'organizerVerificationDurationDays': i(_usdRenewalDays),
        'viewersEnabled': _usdViewers,
        'premiumEnabled': _usdPremiumEnabled,
        'organizerVerificationEnabled': _usdVerifEnabled,
        'organizerVerificationRenewalEnabled': _usdRenewalEnabled,
        'paymentsEnabled': _usdPayments,
        'flutterwaveEnabled': _usdFlutterwave,
      };
    } else {
      return {
        'createFee': d(_ngnCreateFee),
        'accessFee': d(_ngnAccessFee),
        'couponUnit': d(_ngnCouponUnit),
        'couponThreshold': d(_ngnCouponThreshold),
        'couponDiscountPercent': d(_ngnCouponDiscPct),
        'premiumFee': d(_ngnPremiumFee),
        'premiumDurationDays': i(_ngnPremiumDays),
        'proPlan3moFee': d(_ngnPro3mo),
        'proPlan6moFee': d(_ngnPro6mo),
        'proPlanYearlyFee': d(_ngnProYearly),
        'elitePlan3moFee': d(_ngnElite3mo),
        'elitePlan6moFee': d(_ngnElite6mo),
        'elitePlanYearlyFee': d(_ngnEliteYearly),
        'masterLeagueBasicFee': d(_ngnMlBasic),
        'masterLeagueProFee': d(_ngnMlPro),
        'masterLeagueEliteFee': d(_ngnMlElite),
        'organizerVerificationFee': d(_ngnVerifFee),
        'organizerVerificationRenewalFee': d(_ngnRenewalFee),
        'organizerVerificationDurationDays': i(_ngnRenewalDays),
        'viewersEnabled': _ngnViewers,
        'premiumEnabled': _ngnPremiumEnabled,
        'organizerVerificationEnabled': _ngnVerifEnabled,
        'organizerVerificationRenewalEnabled': _ngnRenewalEnabled,
        'paymentsEnabled': _ngnPayments,
        'flutterwaveEnabled': _ngnFlutterwave,
      };
    }
  }

  Future<void> _savePricing() async {
    setState(() {
      _savingPricing = true;
      _saveMsg   = null;
      _saveError = null;
    });
    try {
      await AppPricingAdminService().save(
        ngn: _buildMap(isUsd: false),
        usd: _buildMap(isUsd: true),
      );
      if (mounted) setState(() => _saveMsg = 'Pricing saved successfully.');
    } catch (e) {
      if (mounted) setState(() => _saveError = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _savingPricing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 64,
                  color: AppTheme.secondaryText(brightness)),
              const SizedBox(height: 20),
              Text('Admin access required',
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  )),
              const SizedBox(height: 10),
              Text(
                'Your account does not have pricing admin privileges.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Top bar ──────────────────────────────────────────────────────
        Glass(
          borderRadius: 0,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          fill: AppTheme.cardColor(brightness),
          border: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.limeAccentDark.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppTheme.limeAccentDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Revenue & Admin Dashboard',
                            style: TextStyle(
                              color: AppTheme.primaryText(brightness),
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            )),
                        Text('Full financial overview and pricing control',
                            style: TextStyle(
                                color: AppTheme.secondaryText(brightness),
                                fontSize: 13)),
                      ],
                    ),
                  ),
                  // Refresh button
                  IconButton(
                    tooltip: 'Refresh stats',
                    onPressed: () async {
                      setState(() => _loading = true);
                      await _loadStats();
                      if (mounted) setState(() => _loading = false);
                    },
                    icon: Icon(Icons.refresh_rounded,
                        color: AppTheme.secondaryText(brightness)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TabBar(
                controller: _tabs,
                labelColor: AppTheme.limeAccentDark,
                unselectedLabelColor: AppTheme.secondaryText(brightness),
                indicatorColor: AppTheme.limeAccentDark,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard_rounded, size: 16),
                      text: 'Overview'),
                  Tab(icon: Icon(Icons.receipt_long_rounded, size: 16),
                      text: 'Payments'),
                  Tab(icon: Icon(Icons.people_rounded, size: 16),
                      text: 'Subscribers'),
                  Tab(icon: Icon(Icons.price_change_rounded, size: 16),
                      text: 'Pricing'),
                  Tab(icon: Icon(Icons.toggle_on_rounded, size: 16),
                      text: 'Settings'),
                ],
              ),
            ],
          ),
        ),

        // ── Status banners ────────────────────────────────────────────────
        if (_saveMsg != null)
          _StatusBanner(message: _saveMsg!, isError: false,
              onDismiss: () => setState(() => _saveMsg = null)),
        if (_saveError != null)
          _StatusBanner(message: _saveError!, isError: true,
              onDismiss: () => setState(() => _saveError = null)),
        if (_error != null)
          _StatusBanner(message: _error!, isError: true,
              onDismiss: () => setState(() => _error = null)),

        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(
                brightness: brightness,
                totalSuccessful: _totalSuccessful,
                totalFailed: _totalFailed,
                totalAttempts: _totalAttempts,
                revenueNgn: _revenueNgn,
                revenueUsd: _revenueUsd,
                leagueCreations: _leagueCreations,
                planSubscriptions: _planSubscriptions,
                verifications: _verifications,
                couponRedemptions: _couponRedemptions,
                dailyRevenue: _dailyRevenue,
                byProduct: _byProduct,
              ),
              _PaymentsTab(brightness: brightness),
              _SubscribersTab(brightness: brightness),
              _PricingTab(
                brightness: brightness,
                isUsd: false,
                saving: _savingPricing,
                onSave: _savePricing,
                // NGN
                createFee: _ngnCreateFee,
                accessFee: _ngnAccessFee,
                couponUnit: _ngnCouponUnit,
                couponThreshold: _ngnCouponThreshold,
                couponDiscPct: _ngnCouponDiscPct,
                premiumFee: _ngnPremiumFee,
                premiumDays: _ngnPremiumDays,
                pro3mo: _ngnPro3mo,
                pro6mo: _ngnPro6mo,
                proYearly: _ngnProYearly,
                elite3mo: _ngnElite3mo,
                elite6mo: _ngnElite6mo,
                eliteYearly: _ngnEliteYearly,
                mlBasic: _ngnMlBasic,
                mlPro: _ngnMlPro,
                mlElite: _ngnMlElite,
                verifFee: _ngnVerifFee,
                renewalFee: _ngnRenewalFee,
                renewalDays: _ngnRenewalDays,
                viewers: _ngnViewers,
                premiumEnabled: _ngnPremiumEnabled,
                verifEnabled: _ngnVerifEnabled,
                renewalEnabled: _ngnRenewalEnabled,
                paymentsEnabled: _ngnPayments,
                flutterwaveEnabled: _ngnFlutterwave,
                onToggleViewers: (v) =>
                    setState(() => _ngnViewers = v),
                onTogglePremium: (v) =>
                    setState(() => _ngnPremiumEnabled = v),
                onToggleVerif: (v) =>
                    setState(() => _ngnVerifEnabled = v),
                onToggleRenewal: (v) =>
                    setState(() => _ngnRenewalEnabled = v),
                onTogglePayments: (v) =>
                    setState(() => _ngnPayments = v),
                onToggleFlutterwave: (v) =>
                    setState(() => _ngnFlutterwave = v),
                usdTab: _PricingTab(
                  brightness: brightness,
                  isUsd: true,
                  saving: _savingPricing,
                  onSave: _savePricing,
                  createFee: _usdCreateFee,
                  accessFee: _usdAccessFee,
                  couponUnit: _usdCouponUnit,
                  couponThreshold: _usdCouponThreshold,
                  couponDiscPct: _usdCouponDiscPct,
                  premiumFee: _usdPremiumFee,
                  premiumDays: _usdPremiumDays,
                  pro3mo: _usdPro3mo,
                  pro6mo: _usdPro6mo,
                  proYearly: _usdProYearly,
                  elite3mo: _usdElite3mo,
                  elite6mo: _usdElite6mo,
                  eliteYearly: _usdEliteYearly,
                  mlBasic: _usdMlBasic,
                  mlPro: _usdMlPro,
                  mlElite: _usdMlElite,
                  verifFee: _usdVerifFee,
                  renewalFee: _usdRenewalFee,
                  renewalDays: _usdRenewalDays,
                  viewers: _usdViewers,
                  premiumEnabled: _usdPremiumEnabled,
                  verifEnabled: _usdVerifEnabled,
                  renewalEnabled: _usdRenewalEnabled,
                  paymentsEnabled: _usdPayments,
                  flutterwaveEnabled: _usdFlutterwave,
                  onToggleViewers: (v) =>
                      setState(() => _usdViewers = v),
                  onTogglePremium: (v) =>
                      setState(() => _usdPremiumEnabled = v),
                  onToggleVerif: (v) =>
                      setState(() => _usdVerifEnabled = v),
                  onToggleRenewal: (v) =>
                      setState(() => _usdRenewalEnabled = v),
                  onTogglePayments: (v) =>
                      setState(() => _usdPayments = v),
                  onToggleFlutterwave: (v) =>
                      setState(() => _usdFlutterwave = v),
                ),
              ),
              _SettingsTab(
                brightness: brightness,
                ngnPayments: _ngnPayments,
                ngnFlutterwave: _ngnFlutterwave,
                usdPayments: _usdPayments,
                usdFlutterwave: _usdFlutterwave,
                ngnVerif: _ngnVerifEnabled,
                usdVerif: _usdVerifEnabled,
                saving: _savingPricing,
                onSave: _savePricing,
                onToggleNgnPayments: (v) =>
                    setState(() => _ngnPayments = v),
                onToggleNgnFlutterwave: (v) =>
                    setState(() => _ngnFlutterwave = v),
                onToggleUsdPayments: (v) =>
                    setState(() => _usdPayments = v),
                onToggleUsdFlutterwave: (v) =>
                    setState(() => _usdFlutterwave = v),
                onToggleNgnVerif: (v) =>
                    setState(() => _ngnVerifEnabled = v),
                onToggleUsdVerif: (v) =>
                    setState(() => _usdVerifEnabled = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _ProductStat {
  final String type;
  int count = 0;
  double ngn = 0;
  double usd = 0;
  _ProductStat(this.type);
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;
  const _StatusBanner({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red : const Color(0xFF22C55E);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: color.withOpacity(0.12),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, color: color, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Overview tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final Brightness brightness;
  final int totalSuccessful;
  final int totalFailed;
  final int totalAttempts;
  final double revenueNgn;
  final double revenueUsd;
  final int leagueCreations;
  final int planSubscriptions;
  final int verifications;
  final int couponRedemptions;
  final Map<String, Map<String, double>> dailyRevenue;
  final Map<String, _ProductStat> byProduct;

  const _OverviewTab({
    required this.brightness,
    required this.totalSuccessful,
    required this.totalFailed,
    required this.totalAttempts,
    required this.revenueNgn,
    required this.revenueUsd,
    required this.leagueCreations,
    required this.planSubscriptions,
    required this.verifications,
    required this.couponRedemptions,
    required this.dailyRevenue,
    required this.byProduct,
  });

  @override
  Widget build(BuildContext context) {
    final successRate = totalAttempts > 0
        ? (totalSuccessful / totalAttempts * 100).toStringAsFixed(1)
        : '0.0';

    // Sort daily revenue descending
    final sortedDays = dailyRevenue.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    // Max for bar chart
    double maxDay = 1;
    for (final k in sortedDays.take(14)) {
      final v = (dailyRevenue[k]?['NGN'] ?? 0) +
          (dailyRevenue[k]?['USD'] ?? 0) * 1500;
      if (v > maxDay) maxDay = v;
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Revenue hero cards ─────────────────────────────────────────
        Row(children: [
          Expanded(child: _HeroCard(
            label: 'Total Revenue (NGN)',
            value: '₦${_fmtMoney(revenueNgn, 'NGN')}',
            sub: '$totalSuccessful successful payments',
            icon: Icons.currency_exchange_rounded,
            accent: const Color(0xFF22C55E),
            brightness: brightness,
          )),
          const SizedBox(width: 12),
          Expanded(child: _HeroCard(
            label: 'Total Revenue (USD)',
            value: '\$${_fmtMoney(revenueUsd, 'USD')}',
            sub: '$totalSuccessful successful payments',
            icon: Icons.attach_money_rounded,
            accent: const Color(0xFF22C55E),
            brightness: brightness,
          )),
        ]),
        const SizedBox(height: 12),

        // ── Metric grid ────────────────────────────────────────────────
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.8,
          children: [
            _MetricCard(
              label: 'Success Rate',
              value: '$successRate%',
              icon: Icons.verified_rounded,
              accent: const Color(0xFF22C55E),
              brightness: brightness,
            ),
            _MetricCard(
              label: 'Failed',
              value: '$totalFailed',
              icon: Icons.cancel_rounded,
              accent: Colors.red,
              brightness: brightness,
            ),
            _MetricCard(
              label: 'League Creations',
              value: '$leagueCreations',
              icon: Icons.emoji_events_rounded,
              accent: const Color(0xFF38BDF8),
              brightness: brightness,
            ),
            _MetricCard(
              label: 'Plan Subscriptions',
              value: '$planSubscriptions',
              icon: Icons.workspace_premium_rounded,
              accent: const Color(0xFFA78BFA),
              brightness: brightness,
            ),
            _MetricCard(
              label: 'Verifications',
              value: '$verifications',
              icon: Icons.verified_user_rounded,
              accent: const Color(0xFFF59E0B),
              brightness: brightness,
            ),
            _MetricCard(
              label: 'Coupon Sales',
              value: '$couponRedemptions',
              icon: Icons.confirmation_number_rounded,
              accent: const Color(0xFFEC4899),
              brightness: brightness,
            ),
            _MetricCard(
              label: 'Total Attempts',
              value: '$totalAttempts',
              icon: Icons.play_circle_rounded,
              accent: AppTheme.limeAccentDark,
              brightness: brightness,
            ),
            _MetricCard(
              label: 'Conversion',
              value: totalAttempts > 0
                  ? '${(totalSuccessful / totalAttempts * 100).toStringAsFixed(0)}%'
                  : '0%',
              icon: Icons.trending_up_rounded,
              accent: AppTheme.limeAccentDark,
              brightness: brightness,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Daily revenue chart ────────────────────────────────────────
        Text('Revenue by day (last 14 days)',
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            )),
        const SizedBox(height: 12),
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: sortedDays.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No revenue data yet.',
                        style: TextStyle(
                            color: AppTheme.secondaryText(brightness))),
                  ),
                )
              : Column(
                  children: sortedDays.take(14).map((day) {
                    final ngn = dailyRevenue[day]?['NGN'] ?? 0;
                    final usd = dailyRevenue[day]?['USD'] ?? 0;
                    final combined = ngn + usd * 1500;
                    final pct = maxDay > 0 ? combined / maxDay : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(day,
                                style: TextStyle(
                                  color:
                                      AppTheme.secondaryText(brightness),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                // NGN bar
                                if (ngn > 0)
                                  FractionallySizedBox(
                                    widthFactor:
                                        (pct * 0.8).clamp(0.02, 0.8),
                                    child: Container(
                                      height: 8,
                                      margin: const EdgeInsets.only(
                                          bottom: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF22C55E),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                // USD bar
                                if (usd > 0)
                                  FractionallySizedBox(
                                    widthFactor:
                                        (usd / (maxDay / 1500) * 0.8)
                                            .clamp(0.02, 0.8),
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF38BDF8),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (ngn > 0)
                                Text('₦${_fmtMoney(ngn, 'NGN')}',
                                    style: const TextStyle(
                                      color: Color(0xFF22C55E),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    )),
                              if (usd > 0)
                                Text('\$${_fmtMoney(usd, 'USD')}',
                                    style: const TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    )),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 24),

        // ── By product type ────────────────────────────────────────────
        Text('Revenue by product type',
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            )),
        const SizedBox(height: 12),
        if (byProduct.isEmpty)
          Text('No data.',
              style: TextStyle(
                  color: AppTheme.secondaryText(brightness)))
        else
          ...byProduct.values.map((stat) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Glass(
                borderRadius: 14,
                padding: const EdgeInsets.all(14),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.limeAccentDark.withOpacity(0.12),
                      ),
                      child: const Icon(Icons.payments_rounded,
                          color: AppTheme.limeAccentDark, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stat.type,
                              style: TextStyle(
                                color: AppTheme.primaryText(brightness),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              )),
                          Text('${stat.count} transactions',
                              style: TextStyle(
                                color: AppTheme.secondaryText(brightness),
                                fontSize: 11,
                              )),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (stat.ngn > 0)
                          Text('₦${_fmtMoney(stat.ngn, 'NGN')}',
                              style: const TextStyle(
                                color: Color(0xFF22C55E),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              )),
                        if (stat.usd > 0)
                          Text('\$${_fmtMoney(stat.usd, 'USD')}',
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              )),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  static String _fmtMoney(double v, String cur) {
    if (cur == 'NGN') return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

// ── Payments tab ──────────────────────────────────────────────────────────────

class _PaymentsTab extends StatefulWidget {
  final Brightness brightness;
  const _PaymentsTab({required this.brightness});

  @override
  State<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<_PaymentsTab> {
  String _filterStatus   = 'all';
  String _filterCurrency = 'all';
  String _filterType     = 'all';
  final _searchCtrl      = TextEditingController();
  String _search         = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness;

    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Search
              SizedBox(
                width: 200,
                child: Glass(
                  borderRadius: 10,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 2),
                  fill: AppTheme.searchBackground(b),
                  borderColor: AppTheme.searchOutline(b),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) =>
                        setState(() => _search = v),
                    decoration: const InputDecoration(
                      hintText: 'Search uid, receipt...',
                      border: InputBorder.none,
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 16),
                    ),
                  ),
                ),
              ),
              // Status
              _FilterChip(
                label: 'All',
                selected: _filterStatus == 'all',
                onTap: () =>
                    setState(() => _filterStatus = 'all'),
                brightness: b,
              ),
              _FilterChip(
                label: 'Success',
                selected: _filterStatus == 'success',
                onTap: () =>
                    setState(() => _filterStatus = 'success'),
                brightness: b,
              ),
              _FilterChip(
                label: 'Failed',
                selected: _filterStatus == 'failed',
                onTap: () =>
                    setState(() => _filterStatus = 'failed'),
                brightness: b,
              ),
              // Currency
              _FilterChip(
                label: 'NGN',
                selected: _filterCurrency == 'NGN',
                onTap: () =>
                    setState(() => _filterCurrency = 'NGN'),
                brightness: b,
              ),
              _FilterChip(
                label: 'USD',
                selected: _filterCurrency == 'USD',
                onTap: () =>
                    setState(() => _filterCurrency = 'USD'),
                brightness: b,
              ),
              if (_filterCurrency != 'all')
                _FilterChip(
                  label: 'Clear',
                  selected: false,
                  onTap: () =>
                      setState(() => _filterCurrency = 'all'),
                  brightness: b,
                ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('payments')
                .orderBy('paidAtMs', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator());
              }

              var docs = snap.data!.docs;

              // Filter
              if (_filterStatus != 'all') {
                docs = docs.where((d) {
                  final status =
                      (d['status'] ?? '').toString();
                  if (_filterStatus == 'success') {
                    return status == 'success';
                  }
                  return status != 'success';
                }).toList();
              }
              if (_filterCurrency != 'all') {
                docs = docs.where((d) {
                  return (d['currency'] ?? '')
                          .toString()
                          .toUpperCase() ==
                      _filterCurrency;
                }).toList();
              }
              if (_search.trim().isNotEmpty) {
                final q = _search.trim().toLowerCase();
                docs = docs.where((d) {
                  final uid =
                      (d['userId'] ?? '').toString().toLowerCase();
                  final receipt = (d['receiptId'] ?? '')
                      .toString()
                      .toLowerCase();
                  final txId = (d['providerTransactionId'] ?? '')
                      .toString()
                      .toLowerCase();
                  final pType = (d['productType'] ?? '')
                      .toString()
                      .toLowerCase();
                  return uid.contains(q) ||
                      receipt.contains(q) ||
                      txId.contains(q) ||
                      pType.contains(q);
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Text('No payments match filters.',
                      style: TextStyle(
                          color:
                              AppTheme.secondaryText(b))),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    16, 4, 16, 24),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d       = docs[i].data();
                  final status  = (d['status'] ?? '').toString();
                  final ok      = status == 'success';
                  final currency =
                      (d['currency'] ?? '').toString().toUpperCase();
                  final amount  =
                      ((d['amount'] as num?) ?? 0).toDouble();
                  final pType   =
                      (d['productType'] ?? '').toString();
                  final uid     =
                      (d['userId'] ?? '').toString();
                  final receipt =
                      (d['receiptId'] ?? '').toString();
                  final txId    = (d['providerTransactionId'] ?? '')
                      .toString();
                  final paidMs  =
                      ((d['paidAtMs'] as num?) ?? 0).toInt();
                  final dt      = paidMs > 0
                      ? DateTime.fromMillisecondsSinceEpoch(
                          paidMs)
                      : null;
                  final dateStr = dt != null
                      ? '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'
                      : '—';
                  final sym     = currency == 'NGN' ? '₦' : '\$';
                  final amtStr  =
                      '$sym${amount.toStringAsFixed(currency == 'NGN' ? 0 : 2)}';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Glass(
                      borderRadius: 14,
                      padding: const EdgeInsets.all(14),
                      fill: AppTheme.cardColor(b),
                      borderColor: AppTheme.cardBorder(b),
                      child: Row(
                        children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (ok
                                  ? const Color(0xFF22C55E)
                                  : Colors.red).withOpacity(0.12),
                            ),
                            child: Icon(
                              ok
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.error_outline_rounded,
                              color: ok
                                  ? const Color(0xFF22C55E)
                                  : Colors.red,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pType.isEmpty
                                      ? 'Payment'
                                      : pType,
                                  style: TextStyle(
                                    color:
                                        AppTheme.primaryText(b),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'UID: ${uid.length > 16 ? '${uid.substring(0, 16)}…' : uid}',
                                  style: TextStyle(
                                    color:
                                        AppTheme.secondaryText(b),
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    color:
                                        AppTheme.secondaryText(b),
                                    fontSize: 11,
                                  ),
                                ),
                                if (receipt.isNotEmpty)
                                  Text(
                                    receipt,
                                    style: TextStyle(
                                      color: AppTheme
                                          .secondaryText(b),
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(amtStr,
                              style: TextStyle(
                                color: ok
                                    ? const Color(0xFF22C55E)
                                    : AppTheme.primaryText(b),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              )),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Subscribers tab ───────────────────────────────────────────────────────────

class _SubscribersTab extends StatefulWidget {
  final Brightness brightness;
  const _SubscribersTab({required this.brightness});

  @override
  State<_SubscribersTab> createState() =>
      _SubscribersTabState();
}

class _SubscribersTabState extends State<_SubscribersTab> {
  String _filterPlan = 'all';

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness;

    return Column(
      children: [
        // Plan filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final plan in ['all', 'basic', 'pro', 'elite'])
                _FilterChip(
                  label: plan == 'all'
                      ? 'All Plans'
                      : plan[0].toUpperCase() + plan.substring(1),
                  selected: _filterPlan == plan,
                  onTap: () =>
                      setState(() => _filterPlan = plan),
                  brightness: b,
                ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _filterPlan == 'all'
                ? FirebaseFirestore.instance
                    .collection('users')
                    .where('activePlanId',
                        whereIn: ['basic', 'pro', 'elite'])
                    .limit(200)
                    .snapshots()
                : FirebaseFirestore.instance
                    .collection('users')
                    .where('activePlanId',
                        isEqualTo: _filterPlan)
                    .limit(200)
                    .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;

              if (docs.isEmpty) {
                return Center(
                  child: Text('No subscribers found.',
                      style: TextStyle(
                          color:
                              AppTheme.secondaryText(b))),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    16, 4, 16, 24),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d        = docs[i].data();
                  final uid      = docs[i].id;
                  final name     =
                      (d['teamName'] ?? '').toString().trim();
                  final email    =
                      (d['email'] ?? '').toString().trim();
                  final plan     =
                      (d['activePlanId'] ?? '').toString();
                  final duration =
                      (d['activePlanDurationId'] ?? '')
                          .toString();
                  final expiryMs =
                      ((d['planExpiresAtMs'] as num?) ?? 0)
                          .toInt();
                  final provider =
                      (d['planProvider'] ?? '').toString();
                  final receipt  =
                      (d['planReceiptId'] ?? '').toString();

                  final expiry = expiryMs > 0
                      ? DateTime.fromMillisecondsSinceEpoch(
                          expiryMs)
                      : null;
                  final expiryStr = expiry != null
                      ? '${expiry.day}/${expiry.month}/${expiry.year}'
                      : '—';
                  final isExpired = expiry != null &&
                      expiry.isBefore(DateTime.now());

                  final planColor = plan == 'elite'
                      ? const Color(0xFFA78BFA)
                      : plan == 'pro'
                          ? const Color(0xFF38BDF8)
                          : AppTheme.limeAccentDark;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Glass(
                      borderRadius: 14,
                      padding: const EdgeInsets.all(14),
                      fill: AppTheme.cardColor(b),
                      borderColor: AppTheme.cardBorder(b),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                planColor.withOpacity(0.15),
                            child: Text(
                              name.isNotEmpty
                                  ? name
                                      .substring(0, 1)
                                      .toUpperCase()
                                  : 'U',
                              style: TextStyle(
                                color: planColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isNotEmpty
                                      ? name
                                      : 'User',
                                  style: TextStyle(
                                    color:
                                        AppTheme.primaryText(b),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                if (email.isNotEmpty)
                                  Text(email,
                                      style: TextStyle(
                                        color: AppTheme
                                            .secondaryText(b),
                                        fontSize: 11,
                                      )),
                                Text(
                                  'UID: ${uid.length > 16 ? '${uid.substring(0, 16)}…' : uid}',
                                  style: TextStyle(
                                    color:
                                        AppTheme.secondaryText(b),
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  'via $provider • ${duration.isEmpty ? 'N/A' : duration}',
                                  style: TextStyle(
                                    color:
                                        AppTheme.secondaryText(b),
                                    fontSize: 11,
                                  ),
                                ),
                                if (receipt.isNotEmpty)
                                  Text(
                                    receipt,
                                    style: TextStyle(
                                      color: AppTheme
                                          .secondaryText(b),
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4),
                                decoration: BoxDecoration(
                                  color: planColor
                                      .withOpacity(0.12),
                                  borderRadius:
                                      BorderRadius.circular(
                                          999),
                                ),
                                child: Text(
                                  plan.toUpperCase(),
                                  style: TextStyle(
                                    color: planColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isExpired
                                    ? 'Expired $expiryStr'
                                    : 'Until $expiryStr',
                                style: TextStyle(
                                  color: isExpired
                                      ? Colors.red
                                      : AppTheme.secondaryText(b),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Pricing tab ───────────────────────────────────────────────────────────────

class _PricingTab extends StatefulWidget {
  final Brightness brightness;
  final bool isUsd;
  final bool saving;
  final VoidCallback onSave;
  final _PricingTab? usdTab;

  final TextEditingController createFee;
  final TextEditingController accessFee;
  final TextEditingController couponUnit;
  final TextEditingController couponThreshold;
  final TextEditingController couponDiscPct;
  final TextEditingController premiumFee;
  final TextEditingController premiumDays;
  final TextEditingController pro3mo;
  final TextEditingController pro6mo;
  final TextEditingController proYearly;
  final TextEditingController elite3mo;
  final TextEditingController elite6mo;
  final TextEditingController eliteYearly;
  final TextEditingController mlBasic;
  final TextEditingController mlPro;
  final TextEditingController mlElite;
  final TextEditingController verifFee;
  final TextEditingController renewalFee;
  final TextEditingController renewalDays;
  final bool viewers;
  final bool premiumEnabled;
  final bool verifEnabled;
  final bool renewalEnabled;
  final bool paymentsEnabled;
  final bool flutterwaveEnabled;
  final ValueChanged<bool> onToggleViewers;
  final ValueChanged<bool> onTogglePremium;
  final ValueChanged<bool> onToggleVerif;
  final ValueChanged<bool> onToggleRenewal;
  final ValueChanged<bool> onTogglePayments;
  final ValueChanged<bool> onToggleFlutterwave;

  const _PricingTab({
    required this.brightness,
    required this.isUsd,
    required this.saving,
    required this.onSave,
    required this.createFee,
    required this.accessFee,
    required this.couponUnit,
    required this.couponThreshold,
    required this.couponDiscPct,
    required this.premiumFee,
    required this.premiumDays,
    required this.pro3mo,
    required this.pro6mo,
    required this.proYearly,
    required this.elite3mo,
    required this.elite6mo,
    required this.eliteYearly,
    required this.mlBasic,
    required this.mlPro,
    required this.mlElite,
    required this.verifFee,
    required this.renewalFee,
    required this.renewalDays,
    required this.viewers,
    required this.premiumEnabled,
    required this.verifEnabled,
    required this.renewalEnabled,
    required this.paymentsEnabled,
    required this.flutterwaveEnabled,
    required this.onToggleViewers,
    required this.onTogglePremium,
    required this.onToggleVerif,
    required this.onToggleRenewal,
    required this.onTogglePayments,
    required this.onToggleFlutterwave,
    this.usdTab,
  });

  @override
  State<_PricingTab> createState() => _PricingTabState();
}

class _PricingTabState extends State<_PricingTab>
    with SingleTickerProviderStateMixin {
  late TabController _currencyTabs;

  @override
  void initState() {
    super.initState();
    _currencyTabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _currencyTabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brightness;

    return Column(
      children: [
        // NGN / USD switcher
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Glass(
            borderRadius: 12,
            padding: const EdgeInsets.all(4),
            fill: AppTheme.searchBackground(b),
            borderColor: AppTheme.searchOutline(b),
            child: TabBar(
              controller: _currencyTabs,
              labelColor: AppTheme.darkText,
              unselectedLabelColor:
                  AppTheme.secondaryText(b),
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: AppTheme.limeAccent,
              ),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: '₦ NGN'),
                Tab(text: '\$ USD'),
              ],
            ),
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _currencyTabs,
            children: [
              // NGN fields
              _buildFields(b, isUsd: false),
              // USD fields - use the usdTab fields if provided
              widget.usdTab != null
                  ? _buildFieldsFromTab(b, widget.usdTab!)
                  : _buildFields(b, isUsd: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFields(Brightness b, {required bool isUsd}) {
    final sym = isUsd ? '\$' : '₦';
    // Use the widget's own fields (which are NGN)
    return _buildFieldsList(
      b: b, sym: sym,
      createFee: widget.createFee,
      accessFee: widget.accessFee,
      couponUnit: widget.couponUnit,
      couponThreshold: widget.couponThreshold,
      couponDiscPct: widget.couponDiscPct,
      premiumFee: widget.premiumFee,
      premiumDays: widget.premiumDays,
      pro3mo: widget.pro3mo,
      pro6mo: widget.pro6mo,
      proYearly: widget.proYearly,
      elite3mo: widget.elite3mo,
      elite6mo: widget.elite6mo,
      eliteYearly: widget.eliteYearly,
      mlBasic: widget.mlBasic,
      mlPro: widget.mlPro,
      mlElite: widget.mlElite,
      verifFee: widget.verifFee,
      renewalFee: widget.renewalFee,
      renewalDays: widget.renewalDays,
      viewers: widget.viewers,
      premiumEnabled: widget.premiumEnabled,
      verifEnabled: widget.verifEnabled,
      renewalEnabled: widget.renewalEnabled,
      onToggleViewers: widget.onToggleViewers,
      onTogglePremium: widget.onTogglePremium,
      onToggleVerif: widget.onToggleVerif,
      onToggleRenewal: widget.onToggleRenewal,
    );
  }

  Widget _buildFieldsFromTab(Brightness b, _PricingTab tab) {
    return _buildFieldsList(
      b: b, sym: '\$',
      createFee: tab.createFee,
      accessFee: tab.accessFee,
      couponUnit: tab.couponUnit,
      couponThreshold: tab.couponThreshold,
      couponDiscPct: tab.couponDiscPct,
      premiumFee: tab.premiumFee,
      premiumDays: tab.premiumDays,
      pro3mo: tab.pro3mo,
      pro6mo: tab.pro6mo,
      proYearly: tab.proYearly,
      elite3mo: tab.elite3mo,
      elite6mo: tab.elite6mo,
      eliteYearly: tab.eliteYearly,
      mlBasic: tab.mlBasic,
      mlPro: tab.mlPro,
      mlElite: tab.mlElite,
      verifFee: tab.verifFee,
      renewalFee: tab.renewalFee,
      renewalDays: tab.renewalDays,
      viewers: tab.viewers,
      premiumEnabled: tab.premiumEnabled,
      verifEnabled: tab.verifEnabled,
      renewalEnabled: tab.renewalEnabled,
      onToggleViewers: tab.onToggleViewers,
      onTogglePremium: tab.onTogglePremium,
      onToggleVerif: tab.onToggleVerif,
      onToggleRenewal: tab.onToggleRenewal,
    );
  }

  Widget _buildFieldsList({
    required Brightness b,
    required String sym,
    required TextEditingController createFee,
    required TextEditingController accessFee,
    required TextEditingController couponUnit,
    required TextEditingController couponThreshold,
    required TextEditingController couponDiscPct,
    required TextEditingController premiumFee,
    required TextEditingController premiumDays,
    required TextEditingController pro3mo,
    required TextEditingController pro6mo,
    required TextEditingController proYearly,
    required TextEditingController elite3mo,
    required TextEditingController elite6mo,
    required TextEditingController eliteYearly,
    required TextEditingController mlBasic,
    required TextEditingController mlPro,
    required TextEditingController mlElite,
    required TextEditingController verifFee,
    required TextEditingController renewalFee,
    required TextEditingController renewalDays,
    required bool viewers,
    required bool premiumEnabled,
    required bool verifEnabled,
    required bool renewalEnabled,
    required ValueChanged<bool> onToggleViewers,
    required ValueChanged<bool> onTogglePremium,
    required ValueChanged<bool> onToggleVerif,
    required ValueChanged<bool> onToggleRenewal,
  }) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PricingSection(label: 'League Fees', brightness: b),
        _PriceField(label: 'Create League Fee',
            sym: sym, ctrl: createFee, b: b),
        _PriceField(label: 'Access / View Fee',
            sym: sym, ctrl: accessFee, b: b),
        _ToggleRow2(label: 'Viewers enabled',
            value: viewers, onChanged: onToggleViewers, b: b),
        const SizedBox(height: 16),

        _PricingSection(label: 'Coupon Pricing', brightness: b),
        _PriceField(label: 'Coupon Unit Price',
            sym: sym, ctrl: couponUnit, b: b),
        _PriceField(label: 'Bulk Discount Threshold',
            sym: sym, ctrl: couponThreshold, b: b),
        _PriceField(label: 'Bulk Discount %',
            sym: '%', ctrl: couponDiscPct, b: b),
        const SizedBox(height: 16),

        _PricingSection(label: 'Premium', brightness: b),
        _ToggleRow2(label: 'Premium enabled',
            value: premiumEnabled,
            onChanged: onTogglePremium, b: b),
        _PriceField(label: 'Premium Fee',
            sym: sym, ctrl: premiumFee, b: b),
        _PriceField(label: 'Premium Duration (days)',
            sym: 'd', ctrl: premiumDays, b: b, isInt: true),
        const SizedBox(height: 16),

        _PricingSection(label: 'Pro Plan', brightness: b),
        _PriceField(label: 'Pro — 3 months',
            sym: sym, ctrl: pro3mo, b: b),
        _PriceField(label: 'Pro — 6 months',
            sym: sym, ctrl: pro6mo, b: b),
        _PriceField(label: 'Pro — Yearly',
            sym: sym, ctrl: proYearly, b: b),
        const SizedBox(height: 16),

        _PricingSection(label: 'Elite Plan', brightness: b),
        _PriceField(label: 'Elite — 3 months',
            sym: sym, ctrl: elite3mo, b: b),
        _PriceField(label: 'Elite — 6 months',
            sym: sym, ctrl: elite6mo, b: b),
        _PriceField(label: 'Elite — Yearly',
            sym: sym, ctrl: eliteYearly, b: b),
        const SizedBox(height: 16),

        _PricingSection(label: 'Master League (Legacy)',
            brightness: b),
        _PriceField(label: 'Basic Workspace',
            sym: sym, ctrl: mlBasic, b: b),
        _PriceField(label: 'Pro Workspace',
            sym: sym, ctrl: mlPro, b: b),
        _PriceField(label: 'Elite Workspace',
            sym: sym, ctrl: mlElite, b: b),
        const SizedBox(height: 16),

        _PricingSection(label: 'Organizer Verification',
            brightness: b),
        _ToggleRow2(label: 'Verification enabled',
            value: verifEnabled,
            onChanged: onToggleVerif, b: b),
        _PriceField(label: 'Verification Fee',
            sym: sym, ctrl: verifFee, b: b),
        _ToggleRow2(label: 'Renewal enabled',
            value: renewalEnabled,
            onChanged: onToggleRenewal, b: b),
        _PriceField(label: 'Renewal Fee',
            sym: sym, ctrl: renewalFee, b: b),
        _PriceField(label: 'Verification Duration (days)',
            sym: 'd', ctrl: renewalDays, b: b, isInt: true),
        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: widget.saving ? null : widget.onSave,
            icon: widget.saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkText),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              widget.saving ? 'Saving...' : 'Save All Pricing',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Settings tab ──────────────────────────────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  final Brightness brightness;
  final bool ngnPayments;
  final bool ngnFlutterwave;
  final bool usdPayments;
  final bool usdFlutterwave;
  final bool ngnVerif;
  final bool usdVerif;
  final bool saving;
  final VoidCallback onSave;
  final ValueChanged<bool> onToggleNgnPayments;
  final ValueChanged<bool> onToggleNgnFlutterwave;
  final ValueChanged<bool> onToggleUsdPayments;
  final ValueChanged<bool> onToggleUsdFlutterwave;
  final ValueChanged<bool> onToggleNgnVerif;
  final ValueChanged<bool> onToggleUsdVerif;

  const _SettingsTab({
    required this.brightness,
    required this.ngnPayments,
    required this.ngnFlutterwave,
    required this.usdPayments,
    required this.usdFlutterwave,
    required this.ngnVerif,
    required this.usdVerif,
    required this.saving,
    required this.onSave,
    required this.onToggleNgnPayments,
    required this.onToggleNgnFlutterwave,
    required this.onToggleUsdPayments,
    required this.onToggleUsdFlutterwave,
    required this.onToggleNgnVerif,
    required this.onToggleUsdVerif,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Emergency controls
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(18),
          fill: Colors.red.withOpacity(0.06),
          borderColor: Colors.red.withOpacity(0.20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text('Emergency Controls',
                    style: TextStyle(
                      color: AppTheme.primaryText(b),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    )),
              ]),
              const SizedBox(height: 4),
              Text(
                'Disable payments globally. Use only in emergencies.',
                style: TextStyle(
                    color: AppTheme.secondaryText(b),
                    fontSize: 12),
              ),
              const SizedBox(height: 14),
              _BigToggle(
                label: 'NGN Payments',
                subtitle: 'All NGN transactions',
                value: ngnPayments,
                onChanged: onToggleNgnPayments,
                activeColor: const Color(0xFF22C55E),
                b: b,
              ),
              const SizedBox(height: 8),
              _BigToggle(
                label: 'USD Payments',
                subtitle: 'All USD transactions',
                value: usdPayments,
                onChanged: onToggleUsdPayments,
                activeColor: const Color(0xFF22C55E),
                b: b,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Flutterwave
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(18),
          fill: AppTheme.cardColor(b),
          borderColor: AppTheme.cardBorder(b),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Flutterwave Gateway',
                  style: TextStyle(
                    color: AppTheme.primaryText(b),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  )),
              const SizedBox(height: 4),
              Text(
                'Enable or disable the Flutterwave payment gateway per currency.',
                style: TextStyle(
                    color: AppTheme.secondaryText(b),
                    fontSize: 12),
              ),
              const SizedBox(height: 14),
              _BigToggle(
                label: 'Flutterwave (NGN)',
                subtitle: 'Card, USSD, bank transfer',
                value: ngnFlutterwave,
                onChanged: onToggleNgnFlutterwave,
                activeColor: AppTheme.limeAccentDark,
                b: b,
              ),
              const SizedBox(height: 8),
              _BigToggle(
                label: 'Flutterwave (USD)',
                subtitle: 'Card payments',
                value: usdFlutterwave,
                onChanged: onToggleUsdFlutterwave,
                activeColor: AppTheme.limeAccentDark,
                b: b,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Verification
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(18),
          fill: AppTheme.cardColor(b),
          borderColor: AppTheme.cardBorder(b),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Organizer Verification',
                  style: TextStyle(
                    color: AppTheme.primaryText(b),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  )),
              const SizedBox(height: 4),
              Text(
                'Control whether organizers can submit verification payments.',
                style: TextStyle(
                    color: AppTheme.secondaryText(b),
                    fontSize: 12),
              ),
              const SizedBox(height: 14),
              _BigToggle(
                label: 'Verification (NGN)',
                subtitle: 'NGN organizer verification',
                value: ngnVerif,
                onChanged: onToggleNgnVerif,
                activeColor: const Color(0xFFF59E0B),
                b: b,
              ),
              const SizedBox(height: 8),
              _BigToggle(
                label: 'Verification (USD)',
                subtitle: 'USD organizer verification',
                value: usdVerif,
                onChanged: onToggleUsdVerif,
                activeColor: const Color(0xFFF59E0B),
                b: b,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Save
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkText),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              saving ? 'Saving...' : 'Save Settings',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color accent;
  final Brightness brightness;
  const _HeroCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.accent,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      fill: accent.withOpacity(0.08),
      borderColor: accent.withOpacity(0.20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                      color: AppTheme.primaryText(brightness),
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    )),
                Text(sub,
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontSize: 11,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final Brightness brightness;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 16,
      padding: const EdgeInsets.all(14),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 18),
          const Spacer(),
          Text(value,
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              )),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Brightness brightness;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.limeAccent
              : AppTheme.searchBackground(brightness),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppTheme.limeAccentDark
                : AppTheme.cardBorder(brightness),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected
                  ? AppTheme.darkText
                  : AppTheme.secondaryText(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

class _PricingSection extends StatelessWidget {
  final String label;
  final Brightness brightness;
  const _PricingSection(
      {required this.label, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          child: Divider(
              color: AppTheme.cardBorder(brightness)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label,
              style: const TextStyle(
                color: AppTheme.limeAccentDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              )),
        ),
        Expanded(
          child: Divider(
              color: AppTheme.cardBorder(brightness)),
        ),
      ]),
    );
  }
}

class _PriceField extends StatelessWidget {
  final String label;
  final String sym;
  final TextEditingController ctrl;
  final Brightness b;
  final bool isInt;
  const _PriceField({
    required this.label,
    required this.sym,
    required this.ctrl,
    required this.b,
    this.isInt = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: isInt
            ? TextInputType.number
            : const TextInputType.numberWithOptions(
                decimal: true),
        inputFormatters: isInt
            ? [FilteringTextInputFormatter.digitsOnly]
            : [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9.]'))
              ],
        style: TextStyle(
          color: AppTheme.primaryText(b),
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: label,
          prefixText: '$sym ',
          filled: true,
          fillColor: AppTheme.searchBackground(b),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: AppTheme.cardBorder(b)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: AppTheme.cardBorder(b)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
                color: AppTheme.limeAccentDark, width: 2),
          ),
        ),
      ),
    );
  }
}

class _ToggleRow2 extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Brightness b;
  const _ToggleRow2({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.b,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        borderRadius: 12,
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 4),
        fill: AppTheme.cardColor(b),
        borderColor: AppTheme.cardBorder(b),
        child: SwitchListTile.adaptive(
          activeColor: AppTheme.limeAccentDark,
          value: value,
          onChanged: onChanged,
          contentPadding: EdgeInsets.zero,
          title: Text(label,
              style: TextStyle(
                color: AppTheme.primaryText(b),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              )),
        ),
      ),
    );
  }
}

class _BigToggle extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;
  final Brightness b;
  const _BigToggle({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.activeColor,
    required this.b,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 8),
      fill: value
          ? activeColor.withOpacity(0.08)
          : AppTheme.searchBackground(b),
      borderColor: value
          ? activeColor.withOpacity(0.30)
          : AppTheme.cardBorder(b),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      color: AppTheme.primaryText(b),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    )),
                Text(subtitle,
                    style: TextStyle(
                      color: AppTheme.secondaryText(b),
                      fontSize: 12,
                    )),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
          ),
        ],
      ),
    );
  }
}
