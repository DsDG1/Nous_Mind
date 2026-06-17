import 'dart:developer' as developer;
import 'package:flutter_timezone/flutter_timezone.dart';

/// Returns a fallback timezone identifier matching the device's physical timezone offset.
/// Uses standard IANA 'Etc/GMT' zones (with inverted signs per standard) for whole hours,
/// and exact mapped standard names for major fractional offset timezones.
String getFallbackTimezoneIdentifier() {
  final offset = DateTime.now().timeZoneOffset;
  final hours = offset.inHours;
  final minutes = offset.inMinutes % 60;
  
  if (minutes == 0) {
    if (hours == 0) {
      return 'UTC';
    }
    // IANA Etc/GMT zones have inverted signs:
    // UTC+8 is Etc/GMT-8, UTC-5 is Etc/GMT+5.
    final sign = hours > 0 ? '-' : '+';
    final absHours = hours.abs();
    return 'Etc/GMT$sign$absHours';
  }
  
  // Handle fractional offsets
  final offsetMinutesTotal = offset.inMinutes;
  switch (offsetMinutesTotal) {
    case 330: // +5:30
      return 'Asia/Kolkata';
    case 345: // +5:45
      return 'Asia/Kathmandu';
    case 210: // +3:30
      return 'Asia/Tehran';
    case 270: // +4:30
      return 'Asia/Kabul';
    case 390: // +6:30
      return 'Asia/Yangon';
    case 570: // +9:30
      return 'Australia/Darwin';
    case 525: // +8:45
      return 'Australia/Eucla';
    case -210: // -3:30
      return 'America/St_Johns';
    case -570: // -9:30
      return 'Pacific/Marquesas';
    default:
      // If we cannot match, fallback to the nearest whole hour Etc/GMT
      final sign = hours > 0 ? '-' : '+';
      final absHours = hours.abs();
      return 'Etc/GMT$sign$absHours';
  }
}

/// Safely retrieves the device's local timezone identifier.
/// Falls back to [getFallbackTimezoneIdentifier] if the plugin throws an exception or returns empty.
Future<String> getSafeLocalTimezone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    final id = info.identifier;
    if (id.isNotEmpty) {
      return id;
    }
    return getFallbackTimezoneIdentifier();
  } on Exception catch (error, stackTrace) {
    developer.log(
      'Failed to resolve local timezone identifier from plugin. Attempting fallback offset timezone...',
      error: error,
      stackTrace: stackTrace,
    );
    return getFallbackTimezoneIdentifier();
  } catch (error, stackTrace) {
    // Catch-all for any other errors (e.g. NoSuchMethodError if identifier is missing)
    developer.log(
      'Unexpected error resolving timezone. Attempting fallback offset timezone...',
      error: error,
      stackTrace: stackTrace,
    );
    return getFallbackTimezoneIdentifier();
  }
}
