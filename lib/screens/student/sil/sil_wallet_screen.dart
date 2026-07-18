import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_models.dart';
import 'sil_widgets.dart';

class SilWalletScreen extends StatefulWidget {
  final SilProfile profile;
  final bool offline;

  const SilWalletScreen({
    super.key,
    required this.profile,
    this.offline = false,
  });

  @override
  State<SilWalletScreen> createState() => _SilWalletScreenState();
}

class _SilWalletScreenState extends State<SilWalletScreen> {
  late int _coins;
  List<Map<String, dynamic>> _txs = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _coins = widget.profile.coins;
    _load();
  }

  Future<void> _load() async {
    if (widget.offline) return;
    try {
      final w = await ApiService().silWallet();
      if (!mounted) return;
      setState(() {
        _coins = (w['coins'] as num?)?.toInt() ?? _coins;
        _txs = (w['transactions'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
      });
    } catch (_) {}
  }

  Future<void> _buy(String package) async {
    setState(() => _busy = true);
    try {
      if (widget.offline) {
        final add = package == 'pro' ? 1200 : (package == 'plus' ? 500 : 200);
        setState(() => _coins += add);
      } else {
        final r = await ApiService().silWalletBuy(package);
        setState(() => _coins = (r['coins'] as num?)?.toInt() ?? _coins);
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.bgColor,
        elevation: 0,
        title: Text('League Wallet',
            style: TextStyle(
                color: context.textColor, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textColor),
          onPressed: () {
            Navigator.pop(
              context,
              widget.profile.copyWith(coins: _coins),
            );
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [SilColors.purpleDeep, SilColors.purple],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                const Text('Coin Balance',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.monetization_on_rounded,
                        color: SilColors.gold, size: 36),
                    const SizedBox(width: 8),
                    Text('$_coins',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
          const SilSectionTitle(title: 'Buy coins'),
          _pack('starter', 'Starter', '200 coins', '₦500'),
          _pack('plus', 'Plus', '500 coins', '₦1,000'),
          _pack('pro', 'Pro', '1,200 coins', '₦2,000'),
          const SilSectionTitle(title: 'History'),
          if (_txs.isEmpty)
            Text('No transactions yet.',
                style: TextStyle(color: context.greyColor)),
          ..._txs.map((t) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t['description']?.toString() ?? t['type']?.toString() ?? '',
                    style: TextStyle(
                        color: context.textColor,
                        fontWeight: FontWeight.w600)),
                trailing: Text(
                  '${(t['amount'] as num?)?.toInt() ?? 0}',
                  style: TextStyle(
                    color: ((t['amount'] as num?)?.toInt() ?? 0) >= 0
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _pack(String id, String name, String coins, String price) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.isDark ? const Color(0xFF1A1228) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : () => _buy(id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(
                              color: context.textColor,
                              fontWeight: FontWeight.w800)),
                      Text(coins,
                          style: TextStyle(color: context.greyColor)),
                    ],
                  ),
                ),
                Text(price,
                    style: const TextStyle(
                        color: SilColors.purple, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
