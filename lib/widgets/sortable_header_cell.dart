import 'package:flutter/material.dart';

class SortableHeaderCell extends StatelessWidget {
  const SortableHeaderCell({
    super.key,
    required this.label,
    required this.flex,
    required this.theme,
    this.textAlign,
    this.isActive = false,
    this.ascending = true,
    this.onTap,
  });

  final String label;
  final int flex;
  final ThemeData theme;
  final TextAlign? textAlign;
  final bool isActive;
  final bool ascending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final alignment = _alignmentFor(textAlign);
    final mainAxisAlignment = _mainAxisFor(textAlign);
    final clickable = onTap != null;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: alignment,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: mainAxisAlignment,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: textAlign ?? TextAlign.start,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                softWrap: true,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );

    return Expanded(
      flex: flex,
      child: MouseRegion(
        cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            splashColor: clickable ? null : Colors.transparent,
            highlightColor: clickable ? null : Colors.transparent,
            hoverColor: clickable
                ? theme.colorScheme.primary.withOpacity(0.06)
                : Colors.transparent,
            child: content,
          ),
        ),
      ),
    );
  }

  Alignment _alignmentFor(TextAlign? align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.end:
      case TextAlign.right:
        return Alignment.centerRight;
      case TextAlign.left:
      case TextAlign.start:
      default:
        return Alignment.centerLeft;
    }
  }

  MainAxisAlignment _mainAxisFor(TextAlign? align) {
    switch (align) {
      case TextAlign.center:
        return MainAxisAlignment.center;
      case TextAlign.end:
      case TextAlign.right:
        return MainAxisAlignment.end;
      case TextAlign.left:
      case TextAlign.start:
      default:
        return MainAxisAlignment.start;
    }
  }
}
