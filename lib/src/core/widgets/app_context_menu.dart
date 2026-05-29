import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

class AppContextMenu extends StatelessWidget {
  const AppContextMenu({required this.children, this.width = 160, super.key});

  final List<Widget> children;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadowColor = colors.background.neutralScrim;

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.inverse,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(color: colors.border.subtleOpacity),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                offset: const Offset(0, 2),
                blurRadius: 2,
              ),
              BoxShadow(
                color: shadowColor,
                offset: const Offset(0, 10),
                blurRadius: 15,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xs,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

class AppContextMenuItem extends StatefulWidget {
  const AppContextMenuItem({
    required this.iconName,
    required this.label,
    required this.onTap,
    this.destructive = false,
    super.key,
  });

  final String iconName;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<AppContextMenuItem> createState() => _AppContextMenuItemState();
}

class _AppContextMenuItemState extends State<AppContextMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final itemColor = widget.destructive
        ? colors.text.destructive
        : colors.text.inverse;
    final iconColor = widget.destructive
        ? colors.icon.destructive
        : colors.icon.inverse;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 26,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? colors.state.hover : null,
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
          ),
          child: Row(
            children: [
              AppIcon(
                widget.iconName,
                size: AppIconSize.medium,
                color: iconColor,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(color: itemColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (!mounted) return;
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }
}

class AppContextMenuDivider extends StatelessWidget {
  const AppContextMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(color: context.colors.border.subtleOpacity),
        ),
      ),
    );
  }
}
