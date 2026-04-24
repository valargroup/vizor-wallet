import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ImportBirthdayTab { date, blockHeight }

class ImportDraftState {
  const ImportDraftState({
    this.mnemonic,
    this.selectedTab = ImportBirthdayTab.date,
    this.selectedDate,
    this.birthdayHeight,
    this.manualBirthdayHeightText = '',
  });

  final String? mnemonic;
  final ImportBirthdayTab selectedTab;
  final DateTime? selectedDate;
  final int? birthdayHeight;
  final String manualBirthdayHeightText;

  bool get hasMnemonic => mnemonic != null && mnemonic!.trim().isNotEmpty;

  ImportDraftState copyWith({
    String? mnemonic,
    ImportBirthdayTab? selectedTab,
    DateTime? selectedDate,
    int? birthdayHeight,
    String? manualBirthdayHeightText,
    bool clearSelectedDate = false,
    bool clearBirthdayHeight = false,
  }) {
    return ImportDraftState(
      mnemonic: mnemonic ?? this.mnemonic,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedDate: clearSelectedDate
          ? null
          : selectedDate ?? this.selectedDate,
      birthdayHeight: clearBirthdayHeight
          ? null
          : birthdayHeight ?? this.birthdayHeight,
      manualBirthdayHeightText:
          manualBirthdayHeightText ?? this.manualBirthdayHeightText,
    );
  }
}

class ImportDraftNotifier extends Notifier<ImportDraftState> {
  @override
  ImportDraftState build() => const ImportDraftState();

  void start({required String mnemonic}) {
    state = ImportDraftState(mnemonic: mnemonic);
  }

  void setTab(ImportBirthdayTab tab) {
    state = state.copyWith(selectedTab: tab, clearBirthdayHeight: true);
  }

  void setSelectedDate(DateTime? date, {int? birthdayHeight}) {
    state = state.copyWith(
      selectedDate: date,
      birthdayHeight: birthdayHeight,
      clearSelectedDate: date == null,
      clearBirthdayHeight: date == null || birthdayHeight == null,
    );
  }

  void setManualBirthdayHeightText(String value) {
    state = state.copyWith(
      manualBirthdayHeightText: value,
      clearBirthdayHeight: true,
    );
  }

  void setBirthdayHeight(int height) {
    state = state.copyWith(birthdayHeight: height);
  }

  void clear() {
    state = const ImportDraftState();
  }
}

final importDraftProvider =
    NotifierProvider<ImportDraftNotifier, ImportDraftState>(
      ImportDraftNotifier.new,
    );
