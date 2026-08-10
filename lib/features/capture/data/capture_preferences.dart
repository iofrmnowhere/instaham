import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/models/scan_flow.dart';

abstract final class CapturePreferences {
  static const _keyRefType = 'cap_ref_type';
  static const _keyRefName = 'cap_ref_name';
  static const _keyRefLengthCm = 'cap_ref_length_cm';
  static const _keyHeightCm = 'cap_height_cm';

  static Future<void> saveReference(ReferenceSelection reference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRefType, reference.type);
    await prefs.setString(_keyRefName, reference.name);
    await prefs.setDouble(_keyRefLengthCm, reference.lengthCm);
  }

  static Future<ReferenceSelection?> loadReference() async {
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString(_keyRefType);
    final name = prefs.getString(_keyRefName);
    final lengthCm = prefs.getDouble(_keyRefLengthCm);

    if (type != null && name != null && lengthCm != null && lengthCm > 0) {
      return ReferenceSelection(type: type, name: name, lengthCm: lengthCm);
    }
    return null;
  }

  static Future<void> saveHeight(double heightCm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyHeightCm, heightCm);
  }

  static Future<double?> loadHeight() async {
    final prefs = await SharedPreferences.getInstance();
    final heightCm = prefs.getDouble(_keyHeightCm);
    if (heightCm != null && heightCm > 0) {
      return heightCm;
    }
    return null;
  }
}
