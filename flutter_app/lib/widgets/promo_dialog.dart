import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme.dart';

/// Opens the "Redeem promo code" bottom sheet. Returns true if a code was
/// successfully redeemed (so the caller can pop a paywall / refresh).
Future<bool> showPromoCodeSheet(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PromoSheet(),
  );
  return ok ?? false;
}

class _PromoSheet extends StatefulWidget {
  const _PromoSheet();
  @override
  State<_PromoSheet> createState() => _PromoSheetState();
}

class _PromoSheetState extends State<_PromoSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await context.read<AppProvider>().redeemPromoCode(code);
    if (!mounted) return;
    if (res.ok) {
      // Capture the messenger before popping — the sheet context is defunct
      // once we pop, so we can't read it afterwards.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(res.message),
        backgroundColor: kPrimary,
        duration: const Duration(seconds: 4),
      ));
    } else {
      setState(() {
        _busy = false;
        _error = res.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: kGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.card_giftcard_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Redeem promo code',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: kText)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Have a code from ArthaNote? Enter it to unlock Pro.',
                style: TextStyle(fontSize: 13, color: kMuted)),
            const SizedBox(height: 18),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              enabled: !_busy,
              onSubmitted: (_) => _redeem(),
              inputFormatters: [
                UpperCaseFormatter(),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\-]')),
              ],
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: kText),
              decoration: InputDecoration(
                hintText: 'e.g. FOUNDER100',
                hintStyle: const TextStyle(
                    letterSpacing: 1, fontWeight: FontWeight.w600, color: Color(0xFFB0B7C3)),
                filled: true,
                fillColor: Colors.white,
                errorText: _error,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: kPrimary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _redeem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Redeem',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Forces the promo-code field to uppercase as the user types.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
