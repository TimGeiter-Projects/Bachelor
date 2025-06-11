import 'package:flutter/material.dart';

class IngredientSelector extends StatefulWidget {
  // Angepasst: Maps empfangen jetzt String? (das älteste Datum) als Wert
  final Map<String, String?> vegetablesMap;
  final Map<String, String?> mainIngredientsMap;
  final Map<String, String?> spicesMap;
  final Map<String, String?> othersMap;
  final Set<String> requiredIngredients;
  final bool autoExpandIngredients;
  final ValueChanged<String> onToggleIngredient;
  final VoidCallback onGenerateRecipe;
  final VoidCallback onToggleAutoExpand;
  final VoidCallback onResetRequiredIngredients;
  final VoidCallback? onRefreshData; // Neue Callback-Funktion

  const IngredientSelector({
    super.key,
    required this.vegetablesMap,
    required this.mainIngredientsMap,
    required this.spicesMap,
    required this.othersMap,
    required this.requiredIngredients,
    required this.autoExpandIngredients,
    required this.onToggleIngredient,
    required this.onGenerateRecipe,
    required this.onToggleAutoExpand,
    required this.onResetRequiredIngredients,
    this.onRefreshData,
  });

  @override
  State<IngredientSelector> createState() => _IngredientSelectorState();
}

class _IngredientSelectorState extends State<IngredientSelector>
    with AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true; // Behält den State beim Tab-Wechsel

  @override
  void initState() {
    super.initState();
    // Die Daten werden nun über didChangeDependencies in der RecipePage aktualisiert.
    // Eine zusätzliche Aktualisierung hier ist in der Regel nicht nötig,
    // es sei denn, es gibt einen spezifischen Grund, warum der Selector sich selbst
    // beim ersten Bauen aktualisieren müsste, unabhängig von der übergeordneten Seite.
    // widget.onRefreshData?.call(); // Entfernt, da die RecipePage dies steuert.
  }

  @override
  void didUpdateWidget(IngredientSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Da die RecipePage onRefreshData über didChangeDependencies triggert,
    // ist diese Logik hier in der Regel nicht mehr notwendig, um doppelte Aufrufe zu vermeiden.
    // if (_shouldRefreshData(oldWidget)) {
    //   widget.onRefreshData?.call();
    // }
  }

  // Diese Methode ist nicht mehr direkt notwendig, da die RecipePage
  // die Aktualisierung des Inventars nach Änderungen selbst steuert.
  // bool _shouldRefreshData(IngredientSelector oldWidget) {
  //   return oldWidget.vegetablesMap.length != widget.vegetablesMap.length ||
  //       oldWidget.mainIngredientsMap.length != widget.mainIngredientsMap.length ||
  //       oldWidget.spicesMap.length != widget.spicesMap.length ||
  //       oldWidget.othersMap.length != widget.othersMap.length;
  // }

  bool get _hasIngredients {
    // Überprüft, ob mindestens eine der Maps Einträge hat (der Wert ist hier ein String? oder null)
    return widget.vegetablesMap.isNotEmpty ||
        widget.mainIngredientsMap.isNotEmpty ||
        widget.spicesMap.isNotEmpty ||
        widget.othersMap.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Wichtig für AutomaticKeepAliveClientMixin

    if (!_hasIngredients) {
      return const Center(child: Text("Keine Zutaten im Inventar gefunden."));
    }

    return RefreshIndicator(
      // onRefresh weiterhin, falls der Nutzer manuell aktualisieren möchte
      onRefresh: () async {
        widget.onRefreshData?.call();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Auto-expand toggle card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      widget.autoExpandIngredients ? Icons.smart_toy : Icons.apps,
                      color: widget.autoExpandIngredients ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Zutaten automatisch ergänzen',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: widget.autoExpandIngredients ? Colors.blue : Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.autoExpandIngredients
                                ? 'KI wählt passende Zutaten automatisch aus (empfohlen)'
                                : 'Nur ausgewählte Zutaten verwenden',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: widget.autoExpandIngredients,
                      onChanged: (value) => widget.onToggleAutoExpand(),
                      activeColor: Colors.blue,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Generate Recipe Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onGenerateRecipe,
                icon: const Icon(Icons.restaurant),
                label: const Text(
                  "KI-Rezept generieren",
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Ingredient selection header
            Row(
              children: [
                Text(
                  "Ausgewählte Zutaten (${widget.requiredIngredients.length})",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (widget.requiredIngredients.isNotEmpty)
                  TextButton.icon(
                    onPressed: widget.onResetRequiredIngredients,
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text("Zurücksetzen"),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Ingredient categories
            // Angepasst: Map-Typ ist jetzt Map<String, String?>
            _buildIngredientCategory(context, "Hauptzutaten", widget.mainIngredientsMap, widget.requiredIngredients, widget.onToggleIngredient),
            _buildIngredientCategory(context, "Gemüse", widget.vegetablesMap, widget.requiredIngredients, widget.onToggleIngredient),
            _buildIngredientCategory(context, "Gewürze", widget.spicesMap, widget.requiredIngredients, widget.onToggleIngredient),
            _buildIngredientCategory(context, "Sonstiges", widget.othersMap, widget.requiredIngredients, widget.onToggleIngredient),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // Angepasst: Map-Typ ist jetzt Map<String, String?>
  Widget _buildIngredientCategory(BuildContext context, String name, Map<String, String?> map, Set<String> selected, ValueChanged<String> onToggle) {
    if (map.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.green,
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: map.keys.map((ingredient) {
              final isSelected = selected.contains(ingredient);
              final oldestDate = map[ingredient]; // Das älteste Datum ist direkt der Wert in der Map

              String labelText = ingredient;
              if (oldestDate != null && oldestDate.isNotEmpty) {
                labelText += ' ($oldestDate)'; // Füge das Datum hinzu
              }

              return FilterChip(
                label: Text(labelText),
                selected: isSelected,
                onSelected: (_) => onToggle(ingredient),
                selectedColor: Theme.of(context).primaryColor,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : null,
                  fontWeight: isSelected ? FontWeight.bold : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
