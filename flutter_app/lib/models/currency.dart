import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// A currency the app can display amounts in. Switching currency only
/// changes the symbol/grouping shown — it never converts stored amounts,
/// since each business always trades in a single, fixed currency.
class Currency {
  final String code;   // ISO 4217, e.g. 'INR'
  final String symbol;
  final String label;
  final String locale;       // grouping locale for NumberFormat
  final bool   useLakhCrore; // India-style L/K compact notation vs K/M elsewhere

  const Currency(this.code, this.symbol, this.label, this.locale, {this.useLakhCrore = false});

  // The currency currently in effect, kept in sync by AppProvider whenever
  // it loads or changes. Lets free functions (e.g. `rupee()`) that have no
  // BuildContext/AppProvider access still render in the right currency.
  static Currency active = kCurrencies.first;

  String format(double v) {
    final f = NumberFormat(useLakhCrore ? '#,##,##0.##' : '#,##0.##', locale);
    return '$symbol${f.format(v)}';
  }

  /// Abbreviated form for cards/dashboards, e.g. ₹1.5L / $1.5M.
  String compact(double v) {
    final av = v.abs();
    if (useLakhCrore) {
      if (av >= 100000) return '$symbol${(v / 100000).toStringAsFixed(1)}L';
      if (av >= 1000)   return '$symbol${(v / 1000).toStringAsFixed(1)}K';
    } else {
      if (av >= 1000000) return '$symbol${(v / 1000000).toStringAsFixed(1)}M';
      if (av >= 1000)     return '$symbol${(v / 1000).toStringAsFixed(1)}K';
    }
    return '$symbol${v.toStringAsFixed(0)}';
  }
}

/// Curated list — common world currencies plus the ones most relevant to
/// Tamil Nadu retailers and the Tamil diaspora (Gulf, Singapore, Malaysia).
const List<Currency> kCurrencies = [
  Currency('INR', '₹', 'Indian Rupee',        'en_IN', useLakhCrore: true),
  Currency('USD', '\$', 'US Dollar',          'en_US'),
  Currency('GBP', '£',  'British Pound',      'en_US'),
  Currency('EUR', '€',  'Euro',               'en_US'),
  Currency('AED', 'AED', 'UAE Dirham',        'en_US'),
  Currency('SAR', 'SAR', 'Saudi Riyal',       'en_US'),
  Currency('QAR', 'QAR', 'Qatari Riyal',      'en_US'),
  Currency('KWD', 'KWD', 'Kuwaiti Dinar',     'en_US'),
  Currency('OMR', 'OMR', 'Omani Rial',        'en_US'),
  Currency('BHD', 'BHD', 'Bahraini Dinar',    'en_US'),
  Currency('SGD', 'S\$', 'Singapore Dollar',  'en_US'),
  Currency('MYR', 'RM', 'Malaysian Ringgit',  'en_US'),
  Currency('AUD', 'A\$', 'Australian Dollar', 'en_US'),
  Currency('CAD', 'C\$', 'Canadian Dollar',   'en_US'),
  Currency('JPY', '¥',  'Japanese Yen',       'en_US'),
  Currency('CNY', '¥',  'Chinese Yuan',       'en_US'),
  Currency('LKR', 'Rs', 'Sri Lankan Rupee',   'en_US'),
  Currency('NPR', 'Rs', 'Nepalese Rupee',     'en_US'),
  Currency('BDT', '৳',  'Bangladeshi Taka',   'en_US'),
  Currency('ZAR', 'R',  'South African Rand', 'en_US'),
];

/// Device country code → currency code, for the "System" default.
const Map<String, String> kCountryCurrency = {
  'IN': 'INR',
  'US': 'USD', 'GB': 'GBP',
  'DE': 'EUR', 'FR': 'EUR', 'IT': 'EUR', 'ES': 'EUR', 'NL': 'EUR',
  'IE': 'EUR', 'PT': 'EUR', 'BE': 'EUR', 'AT': 'EUR', 'FI': 'EUR', 'GR': 'EUR',
  'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR', 'KW': 'KWD', 'OM': 'OMR', 'BH': 'BHD',
  'SG': 'SGD', 'MY': 'MYR', 'AU': 'AUD', 'CA': 'CAD', 'JP': 'JPY', 'CN': 'CNY',
  'LK': 'LKR', 'NP': 'NPR', 'BD': 'BDT', 'ZA': 'ZAR',
};

/// Device IANA timezone → country code. The device's timezone is normally
/// set by the OS itself (network/GPS), not a personal preference — unlike
/// locale, which many people leave on "English (UK/US)" regardless of where
/// they actually live. This is the primary signal for the "System" default;
/// locale country is only a fallback when the timezone is unmapped.
const Map<String, String> kTimezoneCountry = {
  'Asia/Kolkata': 'IN', 'Asia/Calcutta': 'IN',
  'America/New_York': 'US', 'America/Chicago': 'US', 'America/Denver': 'US',
  'America/Los_Angeles': 'US', 'America/Anchorage': 'US', 'America/Phoenix': 'US',
  'Pacific/Honolulu': 'US',
  'Europe/London': 'GB',
  'Europe/Berlin': 'DE', 'Europe/Paris': 'FR', 'Europe/Rome': 'IT',
  'Europe/Madrid': 'ES', 'Europe/Amsterdam': 'NL', 'Europe/Dublin': 'IE',
  'Europe/Lisbon': 'PT', 'Europe/Brussels': 'BE', 'Europe/Vienna': 'AT',
  'Europe/Helsinki': 'FI', 'Europe/Athens': 'GR',
  'Asia/Dubai': 'AE', 'Asia/Riyadh': 'SA', 'Asia/Qatar': 'QA',
  'Asia/Kuwait': 'KW', 'Asia/Muscat': 'OM', 'Asia/Bahrain': 'BH',
  'Asia/Singapore': 'SG', 'Asia/Kuala_Lumpur': 'MY',
  'Australia/Sydney': 'AU', 'Australia/Melbourne': 'AU', 'Australia/Brisbane': 'AU',
  'Australia/Perth': 'AU', 'Australia/Adelaide': 'AU', 'Australia/Darwin': 'AU',
  'Australia/Hobart': 'AU',
  'America/Toronto': 'CA', 'America/Vancouver': 'CA', 'America/Edmonton': 'CA',
  'America/Winnipeg': 'CA', 'America/Halifax': 'CA', 'America/St_Johns': 'CA',
  'Asia/Tokyo': 'JP', 'Asia/Shanghai': 'CN',
  'Asia/Colombo': 'LK', 'Asia/Kathmandu': 'NP', 'Asia/Dhaka': 'BD',
  'Africa/Johannesburg': 'ZA',
};

Currency currencyByCode(String code) =>
    kCurrencies.firstWhere((c) => c.code == code, orElse: () => kCurrencies.first);

/// Synchronous, locale-only detection — used as a fallback by
/// [detectSystemCurrency] and as the instant value before that resolves.
Currency detectSystemCurrencyFromLocale() {
  final countryCode = ui.PlatformDispatcher.instance.locale.countryCode ?? 'IN';
  final code = kCountryCurrency[countryCode] ?? 'INR';
  return currencyByCode(code);
}

/// Auto-detects a currency from the device's actual region. Prefers the
/// device timezone (set by the OS, reliably tied to physical location) over
/// the locale's country code (a personal language preference that can be
/// "English (UK)" while living in India, falsely suggesting GBP).
/// Falls back to locale, then INR — ArthaNote's home market.
Future<Currency> detectSystemCurrency() async {
  try {
    final tz = await FlutterTimezone.getLocalTimezone();
    final country = kTimezoneCountry[tz];
    if (country != null) return currencyByCode(kCountryCurrency[country] ?? 'INR');
  } catch (_) {
    // Plugin unavailable (e.g. in tests) — fall through to locale.
  }
  return detectSystemCurrencyFromLocale();
}
