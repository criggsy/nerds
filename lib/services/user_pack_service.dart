import 'package:nerds/models/user_pack.dart';

class UserPackService {
  static final UserPackService _instance = UserPackService._internal();
  static UserPackService get instance => _instance;

  UserPackService._internal();

  Future<void> addUserPack(UserPack userPack) async {}
}
