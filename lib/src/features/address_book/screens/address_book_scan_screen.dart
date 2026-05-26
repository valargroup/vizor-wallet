import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../swap/widgets/swap_address_qr_scan_modal.dart';

class AddressBookScanScreen extends StatelessWidget {
  const AddressBookScanScreen({super.key});

  void _complete(BuildContext context, String value) {
    if (context.canPop()) {
      context.pop(value);
      return;
    }
    context.go('/address-book');
  }

  void _cancel(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/address-book');
  }

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackLink(
                label: 'Address Book',
                onTap: () => _cancel(context),
                minWidth: 96,
              ),
            ),
            Expanded(
              child: Center(
                child: SwapAddressQrScanModal(
                  onAddressScanned: (value) => _complete(context, value),
                  onCancel: () => _cancel(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
