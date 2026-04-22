import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ImportBirthdayTab { date, blockHeight }

class ImportDraftState {
  const ImportDraftState({
    this.mnemonic,
    this.selectedTab = ImportBirthdayTab.date,
    this.selectedDate,
    this.estimatedBirthdayHeight,
    this.manualBirthdayHeightText = '',
  });

  final String? mnemonic;
  final ImportBirthdayTab selectedTab;
  final DateTime? selectedDate;
  final int? estimatedBirthdayHeight;
  final String manualBirthdayHeightText;

  bool get hasMnemonic => mnemonic != null && mnemonic!.trim().isNotEmpty;

  ImportDraftState copyWith({
    String? mnemonic,
    ImportBirthdayTab? selectedTab,
    DateTime? selectedDate,
    int? estimatedBirthdayHeight,
    String? manualBirthdayHeightText,
    bool clearSelectedDate = false,
    bool clearEstimatedBirthdayHeight = false,
  }) {
    return ImportDraftState(
      mnemonic: mnemonic ?? this.mnemonic,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedDate: clearSelectedDate
          ? null
          : selectedDate ?? this.selectedDate,
      estimatedBirthdayHeight: clearEstimatedBirthdayHeight
          ? null
          : estimatedBirthdayHeight ?? this.estimatedBirthdayHeight,
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
    state = state.copyWith(selectedTab: tab);
  }

  void setSelectedDate(DateTime? date, {int? estimatedBirthdayHeight}) {
    state = state.copyWith(
      selectedDate: date,
      estimatedBirthdayHeight: estimatedBirthdayHeight,
      clearSelectedDate: date == null,
      clearEstimatedBirthdayHeight: date == null,
    );
  }

  void setManualBirthdayHeightText(String value) {
    state = state.copyWith(manualBirthdayHeightText: value);
  }

  void clear() {
    state = const ImportDraftState();
  }
}

final importDraftProvider =
    NotifierProvider<ImportDraftNotifier, ImportDraftState>(
      ImportDraftNotifier.new,
    );
