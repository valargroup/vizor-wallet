// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/features/swap/models/swap_fiat_amount.dart';
import '../src/features/swap/models/swap_prototype_models.dart';
import '../src/features/swap/widgets/swap_address_qr_scan_modal.dart';
import '../src/features/swap/widgets/swap_composer_panel.dart';
import '../src/features/swap/widgets/swap_near_intents_attribution.dart';

Widget buildSwapPageFigmaNode1UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode1State,
      actionLabel: 'Add Refund Address',
    ),
  );
}

Widget buildSwapPageFigmaNode2UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode2State,
      actionLabel: 'Add Refund Address',
    ),
  );
}

Widget buildSwapPageFigmaNode3UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode3State,
      actionLabel: 'Add Refund Address',
    ),
  );
}

Widget buildSwapPageFigmaNode5UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode5State,
      actionLabel: 'Add Recipient Address',
      zecAvailableText: '128 ZEC',
      zecAvailableZatoshi: BigInt.from(12800000000),
      maxAmountText: '128',
    ),
  );
}

Widget buildSwapPageFigmaNode6UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode6State,
      actionLabel: 'Add Refund Address',
    ),
  );
}

Widget buildSwapAddressModalFigmaNode7UseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAddressEditModal(
      state: _figmaNode3State,
      onSubmitted: (_, _) {},
      onScan: () {},
      onOpenContacts: () {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapAddressScanModalPermissionUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAddressQrScanModalContent(
      status: SwapAddressQrCameraStatus.requesting,
      onCancel: () {},
    ),
  );
}

Widget buildSwapAddressScanModalDeniedUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAddressQrScanModalContent(
      status: SwapAddressQrCameraStatus.denied,
      onRetry: () {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapAddressScanModalActiveUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAddressQrScanModalContent(
      status: SwapAddressQrCameraStatus.active,
      cameraView: const _SwapAddressQrCameraPreview(),
      onCancel: () {},
    ),
  );
}

Widget buildSwapAddressScanModalLoadingUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAddressQrScanModalContent(
      status: SwapAddressQrCameraStatus.loading,
      cameraView: const _SwapAddressQrCameraPreview(dimmed: true),
      onCancel: () {},
    ),
  );
}

Widget buildSwapSlippageModalUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapSlippageModal(
      slippageBps: 50,
      onSubmitted: (_) {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapSlippageModalCustomUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapSlippageModal(
      slippageBps: 125,
      onSubmitted: (_) {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapSlippageModalInvalidUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapSlippageModal(
      slippageBps: 50,
      initialCustomText: '15',
      onSubmitted: (_) {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapAssetModalUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAssetSelectorModal(
      assets: _figmaAssetModalAssets,
      selected: _figmaUsdc,
      onSelected: (_) {},
    ),
  );
}

Widget buildSwapAssetModalEmptyUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAssetSelectorModal(
      assets: _figmaAssetModalAssets,
      selected: _figmaUsdc,
      initialQuery: 'Value',
      onSelected: (_) {},
    ),
  );
}

Widget buildSwapWidgetFigmaNode1UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode1State,
      actionLabel: 'Add Refund Address',
    ),
  );
}

Widget buildSwapWidgetFigmaNode2UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode2State,
      actionLabel: 'Add Refund Address',
    ),
  );
}

Widget buildSwapWidgetFigmaNode3UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode3State,
      actionLabel: 'Add Refund Address',
    ),
  );
}

Widget buildSwapWidgetFigmaNode5UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode5State,
      actionLabel: 'Add Recipient Address',
      zecAvailableText: '128 ZEC',
      zecAvailableZatoshi: BigInt.from(12800000000),
      maxAmountText: '128',
    ),
  );
}

Widget buildSwapWidgetFigmaNode6UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode6State,
      actionLabel: 'Add Refund Address',
    ),
  );
}

final _figmaUsdc = SwapAsset.live(
  assetId: 'figma-usdc-op',
  symbol: 'USDC',
  blockchain: 'op',
  decimals: 6,
);

final _figmaAssetModalAssets = <SwapAsset>[
  _figmaUsdc,
  SwapAsset.eth,
  SwapAsset.usdc,
  SwapAsset.usdt,
  SwapAsset.dai,
  SwapAsset.wbtc,
  SwapAsset.near,
  SwapAsset.btc,
  SwapAsset.sol,
];

final _figmaUsdcPerZec = <SwapAsset, double>{_figmaUsdc: 6.57894737};
final _figmaZecPerUsdc = <SwapAsset, double>{_figmaUsdc: 512};

final _figmaNode1State = SwapPrototypeState(
  direction: SwapDirection.externalToZec,
  amountText: '0',
  receiveAmountText: '0',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  externalRequests: [],
  requestImportText: '',
  slippageBps: 50,
  indicativeExternalPerZec: _figmaUsdcPerZec,
);

final _figmaNode2State = SwapPrototypeState(
  direction: SwapDirection.externalToZec,
  amountText: '0',
  receiveAmountText: '0',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  externalRequests: [],
  requestImportText: '',
  slippageBps: 50,
  quoteMode: SwapQuoteMode.exactOutput,
  indicativeExternalPerZec: _figmaUsdcPerZec,
);

final _figmaNode3State = SwapPrototypeState(
  direction: SwapDirection.externalToZec,
  amountText: '100',
  receiveAmountText: '0.25',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  externalRequests: [],
  requestImportText: '',
  slippageBps: 50,
  indicativeExternalPerZec: _figmaUsdcPerZec,
);

final _figmaNode5State = SwapPrototypeState(
  direction: SwapDirection.zecToExternal,
  amountText: '0.25',
  receiveAmountText: '100',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  externalRequests: [],
  requestImportText: '',
  slippageBps: 50,
  indicativeExternalPerZec: _figmaZecPerUsdc,
);

final _figmaNode6State = SwapPrototypeState(
  direction: SwapDirection.externalToZec,
  amountText: '100',
  amountFiatText: '100',
  amountInputMode: SwapAmountInputMode.fiat,
  receiveAmountText: '0.25',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  externalRequests: [],
  requestImportText: '',
  slippageBps: 50,
  indicativeExternalPerZec: _figmaUsdcPerZec,
);

class _SwapWidgetFrame extends StatelessWidget {
  const _SwapWidgetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.ground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Swap',
                          style: AppTypography.displaySmall.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SwapPageFrame extends StatelessWidget {
  const _SwapPageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1080.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 720.0;

        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: colors.background.base,
            child: AppDesktopShell(
              sidebar: const _PreviewSwapSidebar(),
              pane: AppDesktopPane(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppBackLink(
                        label: 'Back',
                        minWidth: 60,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final bodyHeight = constraints.maxHeight.isFinite
                                ? constraints.maxHeight
                                : 0.0;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: SingleChildScrollView(
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Swap',
                                              style: AppTypography.displaySmall
                                                  .copyWith(
                                                    color: colors.text.accent,
                                                  ),
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.md,
                                            ),
                                            child,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (bodyHeight >= 520)
                                  const Positioned(
                                    left: 0,
                                    bottom: 0,
                                    child: SwapNearIntentsAttribution(),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SwapPageModalFrame extends StatelessWidget {
  const _SwapPageModalFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1080.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 720.0;

        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: colors.background.base,
            child: AppDesktopShell(
              sidebar: const _PreviewSwapSidebar(),
              pane: AppDesktopPane(
                padding: EdgeInsets.zero,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AppBackLink(
                              label: 'Back',
                              minWidth: 60,
                              onTap: () {},
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s),
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Swap',
                                    style: AppTypography.displaySmall.copyWith(
                                      color: colors.text.accent,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _SwapComposerPreview(
                                    initialState: _figmaNode3State,
                                    actionLabel: 'Add Refund Address',
                                    showActionButton: false,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Positioned(
                      left: AppSpacing.md,
                      bottom: 56,
                      child: SwapNearIntentsAttribution(),
                    ),
                    AppPaneModalOverlay(onDismiss: () {}, child: child),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewSwapSidebar extends StatelessWidget {
  const _PreviewSwapSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  AppSidebarItem(
                    label: 'Username',
                    iconName: AppIcons.user,
                    leadingGap: AppSpacing.xs,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Wallet',
                    iconName: AppIcons.wallet,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Send',
                    iconName: AppIcons.plane,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Receive',
                    iconName: AppIcons.arrowDownCircle,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'Swap',
                    iconName: AppIcons.swapArrows,
                    active: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Activity',
                    iconName: AppIcons.history,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSidebarItem(
                    label: 'Settings',
                    iconName: AppIcons.cog,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'About Vizor',
                    iconName: AppIcons.vizor,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Sign Out',
                    iconName: AppIcons.logOut,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 34,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -AppSpacing.md,
                          top: 1,
                          bottom: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.sync.lightSuccess,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(AppRadii.full),
                              ),
                            ),
                            child: const SizedBox(width: 5),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '34% Syncing...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.sync.textSyncing,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapComposerPreview extends StatefulWidget {
  const _SwapComposerPreview({
    required this.initialState,
    required this.actionLabel,
    this.zecAvailableText = '12.3456 ZEC',
    this.zecAvailableZatoshi,
    this.maxAmountText = '12.3456',
    this.showActionButton = true,
  });

  final SwapPrototypeState initialState;
  final String actionLabel;
  final String zecAvailableText;
  final BigInt? zecAvailableZatoshi;
  final String maxAmountText;
  final bool showActionButton;

  @override
  State<_SwapComposerPreview> createState() => _SwapComposerPreviewState();
}

class _SwapComposerPreviewState extends State<_SwapComposerPreview> {
  late SwapPrototypeState _state;
  var _assetSelectorOpen = false;
  var _slippageModalOpen = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
  }

  void _updateAmount(String value) {
    setState(() {
      final next = _state.copyWith(
        amountText: value,
        quoteMode: SwapQuoteMode.exactInput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(
          receiveAmountText: _estimateCounterpart(next),
          quoteMode: SwapQuoteMode.exactInput,
          clearPreviewQuote: true,
        ),
      );
    });
  }

  void _updateAmountFiat(String value) {
    setState(() {
      final amountText = swapTokenAmountTextFromFiatText(
        _state,
        asset: _state.direction.fromAsset(_state.externalAsset),
        fiatAmountText: value,
      );
      final next = _state.copyWith(
        amountText: amountText ?? '',
        amountFiatText: value,
        amountInputMode: SwapAmountInputMode.fiat,
        quoteMode: SwapQuoteMode.exactInput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(
          receiveAmountText: _estimateCounterpart(next),
          clearPreviewQuote: true,
        ),
        preserveAmountFiatInput: true,
      );
    });
  }

  void _updateReceiveAmount(String value) {
    setState(() {
      final next = _state.copyWith(
        receiveAmountText: value,
        quoteMode: SwapQuoteMode.exactOutput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(
          amountText: _estimateCounterpart(next),
          quoteMode: SwapQuoteMode.exactOutput,
          clearPreviewQuote: true,
        ),
      );
    });
  }

  void _updateReceiveAmountFiat(String value) {
    setState(() {
      final receiveAmountText = swapTokenAmountTextFromFiatText(
        _state,
        asset: _state.direction.toAsset(_state.externalAsset),
        fiatAmountText: value,
      );
      final next = _state.copyWith(
        receiveAmountText: receiveAmountText ?? '',
        receiveFiatText: value,
        receiveAmountInputMode: SwapAmountInputMode.fiat,
        quoteMode: SwapQuoteMode.exactOutput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(
          amountText: _estimateCounterpart(next),
          clearPreviewQuote: true,
        ),
        preserveReceiveFiatInput: true,
      );
    });
  }

  void _toggleFiatInputMode(SwapAmountInputSide side) {
    setState(() {
      _state = switch (side) {
        SwapAmountInputSide.pay => _state.copyWith(
          amountInputMode: _state.amountInputMode == SwapAmountInputMode.token
              ? SwapAmountInputMode.fiat
              : SwapAmountInputMode.token,
          amountFiatText: swapFiatInputTextFromTokenText(
            _state,
            asset: _state.direction.fromAsset(_state.externalAsset),
            tokenAmountText: _state.amountText,
          ),
        ),
        SwapAmountInputSide.receive => _state.copyWith(
          receiveAmountInputMode:
              _state.receiveAmountInputMode == SwapAmountInputMode.token
              ? SwapAmountInputMode.fiat
              : SwapAmountInputMode.token,
          receiveFiatText: swapFiatInputTextFromTokenText(
            _state,
            asset: _state.direction.toAsset(_state.externalAsset),
            tokenAmountText: _state.receiveAmountText,
          ),
        ),
      };
    });
  }

  void _toggleDirection() {
    setState(() {
      _state = _withDerivedFiatTexts(
        _state.copyWith(
          direction: _state.direction.toggled,
          amountText: '',
          receiveAmountText: '',
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          destinationText: '',
          quoteMode: SwapQuoteMode.exactInput,
          clearPreviewQuote: true,
        ),
      );
    });
  }

  void _useMaxZecAmount() {
    setState(() {
      final maxAmountText = widget.maxAmountText;
      final next = _state.copyWith(
        amountText: maxAmountText,
        quoteMode: SwapQuoteMode.exactInput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(
          receiveAmountText: _estimateCounterpart(next),
          quoteMode: SwapQuoteMode.exactInput,
          amountInputMode: SwapAmountInputMode.token,
          clearPreviewQuote: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwapComposerPanel(
          state: _state,
          onAmountChanged: _updateAmount,
          onAmountFiatChanged: _updateAmountFiat,
          onReceiveAmountChanged: _updateReceiveAmount,
          onReceiveAmountFiatChanged: _updateReceiveAmountFiat,
          onToggleFiatInputMode: _toggleFiatInputMode,
          onDirectionChanged: (direction) {
            setState(() => _state = _state.copyWith(direction: direction));
          },
          onToggleDirection: _toggleDirection,
          onOpenExternalAssetPicker: () {
            setState(() => _assetSelectorOpen = !_assetSelectorOpen);
          },
          onOpenDestinationAddress: () {
            setState(() {
              _state = _state.copyWith(
                destinationText: _state.direction.sendsZec
                    ? '0xrecipient'
                    : '0xrefund',
              );
            });
          },
          onOpenSlippageSettings: () {
            setState(() => _slippageModalOpen = !_slippageModalOpen);
          },
          onUseMaxZecAmount: _useMaxZecAmount,
          assetSelectorOpen: _assetSelectorOpen,
          slippageSettingsOpen: _slippageModalOpen,
          zecAvailableText: widget.zecAvailableText,
          zecAvailableZatoshi:
              widget.zecAvailableZatoshi ?? BigInt.from(1234560000),
        ),
        if (widget.showActionButton) ...[
          const SizedBox(height: 38),
          SizedBox(
            width: 256,
            child: AppButton(
              onPressed: () {},
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.large,
              child: SizedBox(
                width: 184,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(widget.actionLabel, maxLines: 1),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SwapAddressQrCameraPreview extends StatelessWidget {
  const _SwapAddressQrCameraPreview({this.dimmed = false});

  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final overlayColor = const Color(
      0xFF141818,
    ).withValues(alpha: dimmed ? 0.42 : 0.18);
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF2E3232)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 8,
            right: 8,
            top: 10,
            child: Text(
              'Scan your external wallet transaction QR code.',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: const Color(0xFFFFFFFF),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 196,
              height: 142,
              padding: const EdgeInsets.all(6),
              color: const Color(0xFFFFFFFF),
              child: PrettyQrView.data(
                data: 'ethereum:0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
                decoration: const PrettyQrDecoration(
                  quietZone: PrettyQrQuietZone.zero,
                  shape: PrettyQrSmoothSymbol(
                    roundFactor: 0,
                    color: Color(0xFF141818),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF2E3232),
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              child: const SizedBox(width: 64, height: 64),
            ),
          ),
          DecoratedBox(decoration: BoxDecoration(color: overlayColor)),
        ],
      ),
    );
  }
}

String _estimateCounterpart(SwapPrototypeState state) {
  final quote = state.draftQuote;
  if (quote == null) return '';
  return state.quoteMode == SwapQuoteMode.exactInput
      ? quote.receiveAsset.formatAmount(quote.receiveAmount)
      : quote.sellAsset.formatAmount(quote.sellAmount);
}

SwapPrototypeState _withDerivedFiatTexts(
  SwapPrototypeState state, {
  bool preserveAmountFiatInput = false,
  bool preserveReceiveFiatInput = false,
}) {
  return state.copyWith(
    amountFiatText: preserveAmountFiatInput
        ? state.amountFiatText
        : swapFiatInputTextFromTokenText(
            state,
            asset: state.direction.fromAsset(state.externalAsset),
            tokenAmountText: state.amountText,
          ),
    receiveFiatText: preserveReceiveFiatInput
        ? state.receiveFiatText
        : swapFiatInputTextFromTokenText(
            state,
            asset: state.direction.toAsset(state.externalAsset),
            tokenAmountText: state.receiveAmountText,
          ),
  );
}
