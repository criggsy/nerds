import 'dart:convert';
import 'package:nerds/models/user_pack.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

/// A service class that provides local storage functionality using SharedPreferences.
/// This service handles storing and retrieving various data types with proper error handling.
class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  static LocalStorageService get instance => _instance;

  LocalStorageService._internal();

  SharedPreferences? _prefs;
  final Logger _logger = Logger();

  /// Initialize the local storage service
  /// This method must be called before using any other methods
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _logger.i('LocalStorageService initialized successfully');
    } catch (e) {
      _logger.e('Failed to initialize LocalStorageService: $e');
      rethrow;
    }
  }

  bool get isInitialized => _prefs != null;

  Future<void> setUserPackList(
      String packName, List<UserPack> userPacks) async {
    if (!isInitialized) {
      throw Exception(
          'LocalStorageService not initialized. Call initialize() first.');
    }

    // Get existing packs
    final existingJsonList = _prefs!.getStringList(packName) ?? [];
    final existingPacks = existingJsonList
        .map((json) => UserPack.fromJson(jsonDecode(json)))
        .toList();

    // Add new packs
    existingPacks.addAll(userPacks);

    // Save combined list
    await _prefs!.setStringList(packName,
        existingPacks.map((pack) => jsonEncode(pack.toJson())).toList());
  }

  Future<List<UserPack>> getUserPackList() async {
    if (!isInitialized) {
      throw Exception(
          'LocalStorageService not initialized. Call initialize() first.');
    }

    final jsonString = _prefs!.getStringList('user_packs');
    return jsonString
            ?.map((json) => UserPack.fromJson(jsonDecode(json)))
            .toList() ??
        [];
  }
}
