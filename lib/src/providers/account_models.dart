class AccountInfo {
  final String uuid;
  final String name;
  final int order;
  final bool isHardware;

  const AccountInfo({
    required this.uuid,
    required this.name,
    required this.order,
    this.isHardware = false,
  });

  AccountInfo copyWith({String? name, int? order}) => AccountInfo(
    uuid: uuid,
    name: name ?? this.name,
    order: order ?? this.order,
    isHardware: isHardware,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'order': order,
    'isHardware': isHardware,
  };

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
    uuid: json['uuid'] as String,
    name: json['name'] as String,
    order: json['order'] as int? ?? 0,
    isHardware: json['isHardware'] as bool? ?? false,
  );
}

class AccountState {
  final List<AccountInfo> accounts;
  final String? activeAccountUuid;
  final String? activeAddress;

  const AccountState({
    this.accounts = const [],
    this.activeAccountUuid,
    this.activeAddress,
  });

  bool get hasAccounts => accounts.isNotEmpty;

  AccountInfo? get activeAccount {
    if (activeAccountUuid == null) return null;
    for (final a in accounts) {
      if (a.uuid == activeAccountUuid) return a;
    }
    return null;
  }

  AccountState copyWith({
    List<AccountInfo>? accounts,
    String? activeAccountUuid,
    String? activeAddress,
  }) => AccountState(
    accounts: accounts ?? this.accounts,
    activeAccountUuid: activeAccountUuid ?? this.activeAccountUuid,
    activeAddress: activeAddress ?? this.activeAddress,
  );
}
