import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'dart:developer' as developer;
import 'package:timezone/timezone.dart' as tz;
import 'package:nousmind/utils/timezone_fallback.dart';

void main() {
  test('Test getFallbackTimezoneIdentifier returns valid timezone in TZ database', () {
    tz_data.initializeTimeZones();
    
    // Get the identifier for the current offset
    final id = getFallbackTimezoneIdentifier();
    expect(id, isNotEmpty);
    
    // Try to locate it in the timezone database
    final location = tz.getLocation(id);
    expect(location, isNotNull);
    
    developer.log('Current device offset fallback timezone: $id');
  });

  test('Test getSafeLocalTimezone returns a valid timezone', () async {
    tz_data.initializeTimeZones();
    
    final id = await getSafeLocalTimezone();
    expect(id, isNotEmpty);
    
    final location = tz.getLocation(id);
    expect(location, isNotNull);
    
    developer.log('getSafeLocalTimezone returned: $id');
  });
}
