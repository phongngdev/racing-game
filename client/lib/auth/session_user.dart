enum AppRole {
  user,
  admin;

  static AppRole parse(Object? value) => switch (value) {
    'User' => AppRole.user,
    'Admin' => AppRole.admin,
    _ => throw const FormatException('The API returned an unknown user role.'),
  };
}

class SessionUser {
  const SessionUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
  });

  final String id;
  final String username;
  final String email;
  final AppRole role;

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final username = json['username'];
    final email = json['email'];
    if (id is! String || username is! String || email is! String) {
      throw const FormatException('The API returned an invalid user profile.');
    }
    return SessionUser(
      id: id,
      username: username,
      email: email,
      role: AppRole.parse(json['role']),
    );
  }
}
