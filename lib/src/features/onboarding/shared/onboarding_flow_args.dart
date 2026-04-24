enum SetPasswordFlow { create, importWallet }

class CreateSecretPassphraseArgs {
  const CreateSecretPassphraseArgs({required this.mnemonic});

  final String mnemonic;
}

class ImportSecretPassphraseArgs {
  const ImportSecretPassphraseArgs({required this.mnemonic});

  final String mnemonic;
}

class ImportBirthdayArgs {
  const ImportBirthdayArgs({
    required this.mnemonic,
    this.initialBirthdayHeight,
  });

  final String mnemonic;
  final int? initialBirthdayHeight;
}

class SetPasswordScreenArgs {
  const SetPasswordScreenArgs._({
    required this.flow,
    required this.mnemonic,
    this.birthdayHeight,
  });

  const SetPasswordScreenArgs.create({required String mnemonic})
    : this._(flow: SetPasswordFlow.create, mnemonic: mnemonic);

  const SetPasswordScreenArgs.importWallet({
    required String mnemonic,
    required int birthdayHeight,
  }) : this._(
         flow: SetPasswordFlow.importWallet,
         mnemonic: mnemonic,
         birthdayHeight: birthdayHeight,
       );

  final SetPasswordFlow flow;
  final String mnemonic;
  final int? birthdayHeight;

  bool get isImport => flow == SetPasswordFlow.importWallet;

  int get importBirthdayHeight => birthdayHeight!;

  String get backRoutePath => switch (flow) {
    SetPasswordFlow.create => '/onboarding/secret-passphrase',
    SetPasswordFlow.importWallet => '/import/birthday',
  };

  Object get backRouteExtra => switch (flow) {
    SetPasswordFlow.create => CreateSecretPassphraseArgs(mnemonic: mnemonic),
    SetPasswordFlow.importWallet => ImportBirthdayArgs(
      mnemonic: mnemonic,
      initialBirthdayHeight: importBirthdayHeight,
    ),
  };
}
