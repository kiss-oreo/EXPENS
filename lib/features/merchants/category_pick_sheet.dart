import 'package:flutter/material.dart';

import '../../core/widgets/app_surfaces.dart';
import '../../data/tables.dart';

/// Picks one category, including subcategories under their parent.
/// Returns the category id, or null if the sheet is dismissed.
Future<int?> showCategoryPickSheet(
  BuildContext context, {
  required List<CategoryRow> categories,
  String title = 'Category',
}) {
  final parents = categories.where((c) => c.parentId == null).toList();
  final childrenOf = <int, List<CategoryRow>>{};
  for (final row in categories) {
    final parentId = row.parentId;
    if (parentId == null) continue;
    childrenOf.putIfAbsent(parentId, () => []).add(row);
  }

  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.62,
          child: ListView(
            children: [
              ListTile(title: Text(title)),
              if (categories.isEmpty)
                const ListTile(title: Text('No categories yet.')),
              for (final parent in parents) ...[
                ListTile(
                  leading: KeyIcon(
                    parent.iconKey,
                    color: Color(parent.colorValue),
                  ),
                  title: Text(parent.name),
                  onTap: () => Navigator.pop(ctx, parent.id),
                ),
                for (final child
                    in childrenOf[parent.id] ?? const <CategoryRow>[])
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 32, right: 16),
                    leading: KeyIcon(
                      child.iconKey,
                      color: Color(child.colorValue),
                    ),
                    title: Text(child.name),
                    subtitle: Text(parent.name),
                    onTap: () => Navigator.pop(ctx, child.id),
                  ),
              ],
              for (final child in categories.where(
                (c) =>
                    c.parentId != null &&
                    !parents.any((p) => p.id == c.parentId),
              ))
                ListTile(
                  leading: KeyIcon(child.iconKey, color: Color(child.colorValue)),
                  title: Text(child.name),
                  onTap: () => Navigator.pop(ctx, child.id),
                ),
            ],
          ),
        ),
      );
    },
  );
}
