import 'package:flutter/material.dart';
import '../models/avatar_catalog.dart';

/// Zeigt die Avatar-Auswahl als Grid in einem Dialog und gibt die gewählte
/// [AvatarOption.id] über [onSelected] zurück.
class AvatarPicker extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const AvatarPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
  });

  static Future<String?> show(BuildContext context, {String? selectedId}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AvatarPicker(
        selectedId: selectedId,
        onSelected: (id) => Navigator.of(ctx).pop(id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Avatar wählen'),
      content: SizedBox(
        width: 320,
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: avatarCatalog.map((option) {
            final isSelected = option.id == selectedId;
            return GestureDetector(
              onTap: () => onSelected(option.id),
              child: CircleAvatar(
                radius: 32,
                backgroundColor: isSelected ? Colors.orangeAccent : Colors.transparent,
                child: Padding(
                  padding: EdgeInsets.all(isSelected ? 3.0 : 0),
                  child: CircleAvatar(
                    radius: isSelected ? 29 : 32,
                    backgroundImage: AssetImage(option.assetPath),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}
