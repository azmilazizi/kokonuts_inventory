import 'package:flutter/material.dart';

class TableFilterBar extends StatelessWidget {
  const TableFilterBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.labelText = 'Filter',
    this.isFiltering = false,
    this.trailing,
    this.horizontalController,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final String labelText;
  final bool isFiltering;
  final Widget? trailing;
  final ScrollController? horizontalController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceVariant.withOpacity(0.6);

    final content = Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: isFiltering
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        if (controller.text.isEmpty) {
                          return;
                        }
                        controller.clear();
                        onChanged('');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              isDense: true,
            ),
          ),
          if (trailing != null) ...[const SizedBox(height: 12), trailing!],
        ],
      ),
    );

    final newHorizontalController = horizontalController;
    if (newHorizontalController == null) {
      return content;
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: newHorizontalController,
        builder: (context, child) {
          final offset = newHorizontalController.hasClients
              ? newHorizontalController.offset
              : 0.0;
          return Align(
            alignment: Alignment.centerLeft,
            child: Transform.translate(
              offset: Offset(offset, 0),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width,
                child: child,
              ),
            ),
          );
        },
        child: content,
      ),
    );
  }
}
