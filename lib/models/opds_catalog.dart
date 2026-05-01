import 'dart:convert';

class OpdsCatalog {
  const OpdsCatalog({
    required this.id,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
  });

  final String id;
  final String name;
  final String url;
  final String username;
  final String password;

  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }

    final uri = Uri.tryParse(url.trim());
    return uri?.host.isNotEmpty == true ? uri!.host : url.trim();
  }

  Map<String, String> get authHeaders {
    final user = username.trim();
    final pass = password.trim();
    if (user.isEmpty && pass.isEmpty) {
      return const {};
    }

    final token = base64Encode(utf8.encode('$user:$pass'));
    return {'Authorization': 'Basic $token'};
  }

  OpdsCatalog copyWith({
    String? id,
    String? name,
    String? url,
    String? username,
    String? password,
  }) {
    return OpdsCatalog(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'username': username,
      'password': password,
    };
  }

  factory OpdsCatalog.fromJson(Map<String, dynamic> json) {
    return OpdsCatalog(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }
}
