import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:visibility_detector/visibility_detector.dart'; // HIER IMPORTIEREN

import 'ingriedients/ingriedientsData.dart'; // Passe diesen Pfad ggf. an
import 'scanner.dart'; // Scanner-Implementierung muss vorhanden sein

class IngredientsPage extends StatefulWidget {
  const IngredientsPage({super.key});

  @override
  State<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends State<IngredientsPage> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();

  Map<String, int> _ingredientCountVegetables = {};
  Map<String, int> _ingredientCountMain = {};
  Map<String, int> _ingredientCountSpices = {};
  Map<String, int> _ingredientCountOthers = {};
  bool _deleteMode = false;
  bool _editMode = false; // Neuer Modus für Mengenbearbeitung

  // Key für den VisibilityDetector
  final Key _visibilityDetectorKey = const Key('ingredients_page_visibility_detector');

  @override
  void initState() {
    super.initState();
    print("IngredientsPage: initState aufgerufen");
    WidgetsBinding.instance.addObserver(this);
    // _loadIngredients() wird jetzt primär durch VisibilityDetector getriggert,
    // aber ein initiales Laden kann hier nicht schaden.
    _loadIngredients();
  }

  @override
  void dispose() {
    print("IngredientsPage: dispose aufgerufen");
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      print("IngredientsPage: App in den Vordergrund gekommen (resumed).");

    }
  }


  Future<void> _loadIngredients() async {
    print("IngredientsPage: _loadIngredients wird ausgeführt...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Sicherstellen, dass wir die neuesten Daten lesen

    Map<String, int> _decodeMap(String? jsonString) {
      if (jsonString != null) {
        try {
          return Map<String, int>.from(jsonDecode(jsonString));
        } catch (e) {
          print("IngredientsPage: Fehler beim Dekodieren von '$jsonString': $e");
        }
      }
      return {};
    }

    if (!mounted) return;

    final tempVegetables = _decodeMap(prefs.getString('Vegetables'));
    final tempMain = _decodeMap(prefs.getString('Main Ingredients'));
    final tempSpices = _decodeMap(prefs.getString('Spices'));
    final tempOthers = _decodeMap(prefs.getString('Others'));

    bool changed = false;
    if (!DeepEquals.mapEquals(_ingredientCountVegetables, tempVegetables)) {
      _ingredientCountVegetables = tempVegetables;
      changed = true;
    }
    if (!DeepEquals.mapEquals(_ingredientCountMain, tempMain)) {
      _ingredientCountMain = tempMain;
      changed = true;
    }
    if (!DeepEquals.mapEquals(_ingredientCountSpices, tempSpices)) {
      _ingredientCountSpices = tempSpices;
      changed = true;
    }
    if (!DeepEquals.mapEquals(_ingredientCountOthers, tempOthers)) {
      _ingredientCountOthers = tempOthers;
      changed = true;
    }

    if (changed && mounted) {
      setState(() {
        print("IngredientsPage: Inventar geladen und State AKTUALISIERT.");
      });
    } else if (mounted && !changed) {
      print("IngredientsPage: Inventar geladen, aber KEINE ÄNDERUNGEN festgestellt.");
    }
  }

  Future<void> _saveIngredients() async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> _encodeAndSet(String key, Map<String, int> map) async {
      await prefs.setString(key, jsonEncode(map));
    }

    await _encodeAndSet('Vegetables', _ingredientCountVegetables);
    await _encodeAndSet('Main Ingredients', _ingredientCountMain);
    await _encodeAndSet('Spices', _ingredientCountSpices);
    await _encodeAndSet('Others', _ingredientCountOthers);
    print("IngredientsPage: Inventar gespeichert.");
  }

  void _addIngredient() {
    final String ingredient = _controller.text.trim();
    if (ingredient.isNotEmpty) {
      final String normalizedIngredient = ingredient.toLowerCase();
      final String category = getCategoryForIngredient(normalizedIngredient);

      Map<String, int> targetMap;
      switch (category) {
        case "Vegetables": targetMap = _ingredientCountVegetables; break;
        case "Main Ingredients": targetMap = _ingredientCountMain; break;
        case "Spices": targetMap = _ingredientCountSpices; break;
        default: targetMap = _ingredientCountOthers; break;
      }

      if (mounted) {
        setState(() {
          targetMap.update(normalizedIngredient, (count) => count + 1, ifAbsent: () => 1);
          _controller.clear();
          FocusScope.of(context).unfocus();
        });
      }
      _saveIngredients();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${ingredient}" zu "$category" hinzugefügt!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green[600],
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte eine Zutat eingeben oder auswählen.')),
        );
      }
    }
  }

  // Neue Methoden für Mengenbearbeitung
  void _increaseQuantity(String ingredientKey, String categoryMapKey) {
    if (mounted) {
      setState(() {
        Map<String, int> targetMap = _getTargetMap(categoryMapKey);
        targetMap.update(ingredientKey, (count) => count + 1, ifAbsent: () => 1);
      });
    }
    _saveIngredients();
  }

  void _decreaseQuantity(String ingredientKey, String categoryMapKey) {
    if (mounted) {
      setState(() {
        Map<String, int> targetMap = _getTargetMap(categoryMapKey);
        if (targetMap[ingredientKey] != null && targetMap[ingredientKey]! > 1) {
          targetMap.update(ingredientKey, (count) => count - 1);
        } else {
          // Wenn Menge 1 oder weniger, Element entfernen
          targetMap.remove(ingredientKey);
          // Bearbeitungsmodus beenden, wenn alle Inventare leer sind
          if (_editMode && _areAllInventoriesEmpty()) {
            _editMode = false;
          }
        }
      });
    }
    _saveIngredients();
  }

  Map<String, int> _getTargetMap(String categoryMapKey) {
    switch (categoryMapKey) {
      case "Vegetables": return _ingredientCountVegetables;
      case "Main Ingredients": return _ingredientCountMain;
      case "Spices": return _ingredientCountSpices;
      default: return _ingredientCountOthers;
    }
  }

  void _confirmDeleteIngredient(String ingredientKey) {
    final String category = getCategoryForIngredient(ingredientKey);
    String displayIngredient = ingredientKey.length > 1
        ? '${ingredientKey[0].toUpperCase()}${ingredientKey.substring(1)}'
        : ingredientKey.toUpperCase();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zutat löschen'),
        content: Text('Möchtest du "$displayIngredient" wirklich aus "$category" löschen?'),
        actions: [
          TextButton(child: const Text('Abbrechen'), onPressed: () => Navigator.of(context).pop()),
          TextButton(
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
            onPressed: () {
              if (mounted) {
                setState(() {
                  Map<String, int> targetMap;
                  switch (category) {
                    case "Vegetables": targetMap = _ingredientCountVegetables; break;
                    case "Main Ingredients": targetMap = _ingredientCountMain; break;
                    case "Spices": targetMap = _ingredientCountSpices; break;
                    default: targetMap = _ingredientCountOthers; break;
                  }
                  targetMap.remove(ingredientKey);
                  if (_deleteMode && _areAllInventoriesEmpty()) {
                    _deleteMode = false;
                  }
                });
              }
              _saveIngredients();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  bool _areAllInventoriesEmpty() {
    return _ingredientCountVegetables.isEmpty &&
        _ingredientCountMain.isEmpty &&
        _ingredientCountSpices.isEmpty &&
        _ingredientCountOthers.isEmpty;
  }

  Future<void> _scanBarcode() async {
    String? barcode = await BarcodeScanner.scanBarcode(context);
    if (barcode != null && barcode.isNotEmpty) {
      String? productName = await BarcodeScanner.getProductNameFromBarcode(barcode);
      if (productName != null && productName.isNotEmpty) {
        String cleanName = productName.replaceAll(RegExp(r'^Product:\s*', caseSensitive: false), '');
        cleanName = cleanName.split('\n').first.trim();
        if (mounted) {
          setState(() { _controller.text = cleanName; });
          _addIngredient();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Barcode "$barcode" konnte keinem Produkt zugeordnet werden.'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange[800],
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print("IngredientsPage: build aufgerufen. _deleteMode: $_deleteMode, _editMode: $_editMode");
    return VisibilityDetector( // --- HIER VisibilityDetector ---
      key: _visibilityDetectorKey,
      onVisibilityChanged: (visibilityInfo) {
        if (mounted && visibilityInfo.visibleFraction > 0.9) { // Wenn mehr als 90% sichtbar
          print("IngredientsPage: Seite ist sichtbar geworden (VisibilityDetector). Lade Inventar.");
          _loadIngredients();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dein Inventar'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            if (!_areAllInventoriesEmpty()) ...[
              // Bearbeitungsmodus-Button (für Mengen ändern)
              IconButton(
                icon: Icon(
                  _editMode ? Icons.edit_off : Icons.edit,
                  color: _editMode ? Colors.blue : null,
                ),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _editMode = !_editMode;
                      // Wenn Bearbeitungsmodus aktiviert wird, Löschmodus deaktivieren
                      if (_editMode) {
                        _deleteMode = false;
                      }
                    });
                  }
                },
                tooltip: _editMode ? 'Bearbeitungsmodus beenden' : 'Mengen bearbeiten',
              ),
              // Löschmodus-Button
              IconButton(
                icon: Icon(
                  _deleteMode ? Icons.check_circle_outline : Icons.delete_outline,
                  color: _deleteMode ? Colors.green : null,
                ),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _deleteMode = !_deleteMode;
                      // Wenn Löschmodus aktiviert wird, Bearbeitungsmodus deaktivieren
                      if (_deleteMode) {
                        _editMode = false;
                      }
                    });
                  }
                },
                tooltip: _deleteMode ? 'Löschmodus beenden' : 'Löschmodus aktivieren',
              ),
            ],
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        final query = textEditingValue.text.toLowerCase();
                        return query.isEmpty
                            ? const Iterable<String>.empty()
                            : allIngredients.where((option) => option.toLowerCase().startsWith(query));
                      },
                      onSelected: (selection) {
                        _controller.text = selection;
                        FocusScope.of(context).unfocus();
                      },
                      fieldViewBuilder: (context, fieldTextEditingController, focusNode, onFieldSubmitted) {
                        // Synchronisation von _controller und fieldTextEditingController
                        // Dies hilft, wenn _controller extern gesetzt wird (z.B. durch Scanner)
                        if (_controller.text != fieldTextEditingController.text && !focusNode.hasFocus) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) fieldTextEditingController.text = _controller.text;
                          });
                        }
                        return TextField(
                          controller: fieldTextEditingController,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Zutat suchen / eingeben',
                            suffixIcon: (fieldTextEditingController.text.isNotEmpty)
                                ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                fieldTextEditingController.clear();
                                _controller.clear(); // Wichtig: Auch den Hauptcontroller leeren
                                focusNode.requestFocus();
                              },
                            ) : null,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (text){
                            _controller.text = text; // Halte _controller synchron
                          },
                          onSubmitted: (_) => _addIngredient(),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanBarcode,
                    tooltip: 'Barcode scannen',
                  )
                ],
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Zur Inventarliste hinzufügen'),
                onPressed: _addIngredient,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _areAllInventoriesEmpty()
                    ? const Center(child: Text('Keine Zutaten im Inventar.\nFüge welche hinzu oder scanne einen Barcode!', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)))
                    : ListView(
                  children: [
                    _buildCategoryTile('Gemüse', _ingredientCountVegetables, 'Vegetables'),
                    _buildCategoryTile('Hauptzutaten', _ingredientCountMain, 'Main Ingredients'),
                    _buildCategoryTile('Gewürze', _ingredientCountSpices, 'Spices'),
                    _buildCategoryTile('Sonstiges', _ingredientCountOthers, 'Others'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTile(String title, Map<String, int> ingredientMap, String categoryKey) {
    List<String> sortedKeys = ingredientMap.keys.toList()..sort((a, b) => a.compareTo(b));
    String displayTitle = title.replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}').trim();
    if (title == "Hauptzutaten") displayTitle = "Hauptzutaten"; // Spezifische Übersetzung

    return ExpansionTile(
      title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      initiallyExpanded: ingredientMap.isNotEmpty,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest, // Hellere Farbe
      collapsedBackgroundColor: Theme.of(context).scaffoldBackgroundColor,
      trailing: _deleteMode && ingredientMap.isNotEmpty
          ? Tooltip(message: "Alle in '$displayTitle' löschen", child: IconButton(icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade300), onPressed: () => _confirmDeleteCategory(categoryKey, ingredientMap, displayTitle) ))
          : null,
      children: sortedKeys.isEmpty
          ? [const ListTile(dense: true, title: Text('Keine Zutaten in dieser Kategorie.'))]
          : sortedKeys.map((key) {
        String displayKey = key.length > 1 ? '${key[0].toUpperCase()}${key.substring(1)}' : key.toUpperCase();
        return ListTile(
          title: Text(displayKey),
          trailing: _buildTrailingWidget(key, categoryKey, ingredientMap[key]!),
          leading: _buildLeadingWidget(key, categoryKey),
          onTap: _deleteMode ? () => _confirmDeleteSingleItemFromCategory(key, categoryKey) : null,
          dense: true,
        );
      }).toList(),
    );
  }

  Widget _buildTrailingWidget(String ingredientKey, String categoryKey, int quantity) {
    if (_editMode) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.remove, color: Colors.red.shade600, size: 20),
            onPressed: () => _decreaseQuantity(ingredientKey, categoryKey),
            visualDensity: VisualDensity.compact,
            tooltip: 'Menge verringern',
          ),
          Text('${quantity}x', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: Icon(Icons.add, color: Colors.green.shade600, size: 20),
            onPressed: () => _increaseQuantity(ingredientKey, categoryKey),
            visualDensity: VisualDensity.compact,
            tooltip: 'Menge erhöhen',
          ),
        ],
      );
    } else {
      return Text('${quantity}x', style: const TextStyle(fontWeight: FontWeight.bold));
    }
  }

  Widget? _buildLeadingWidget(String ingredientKey, String categoryKey) {
    if (_deleteMode) {
      return IconButton(
        icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade700),
        visualDensity: VisualDensity.compact,
        onPressed: () => _confirmDeleteSingleItemFromCategory(ingredientKey, categoryKey),
      );
    }
    return null;
  }

  void _confirmDeleteCategory(String categoryMapKey, Map<String, int> categoryMap, String displayCategoryName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('"$displayCategoryName" leeren?'),
          content: const Text('Möchtest du wirklich alle Zutaten aus dieser Kategorie löschen?'),
          actions: <Widget>[
            TextButton(child: const Text('Abbrechen'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text('Alle löschen', style: TextStyle(color: Colors.red)),
              onPressed: () {
                if (mounted) {
                  setState(() {
                    categoryMap.clear();
                    if (_deleteMode && _areAllInventoriesEmpty()) _deleteMode = false;
                  });
                }
                _saveIngredients();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteSingleItemFromCategory(String ingredientKey, String categoryMapKey) {
    final String categoryDisplay = getCategoryForIngredient(ingredientKey);
    String displayIngredient = ingredientKey.length > 1
        ? '${ingredientKey[0].toUpperCase()}${ingredientKey.substring(1)}'
        : ingredientKey.toUpperCase();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"$displayIngredient" löschen'),
        content: Text('Möchtest du "$displayIngredient" wirklich aus "$categoryDisplay" löschen?'),
        actions: [
          TextButton(child: const Text('Abbrechen'), onPressed: () => Navigator.of(context).pop()),
          TextButton(
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
            onPressed: () {
              if (mounted) {
                setState(() {
                  Map<String, int> targetMap = _getTargetMap(categoryMapKey);
                  targetMap.remove(ingredientKey);
                  if (_deleteMode && _areAllInventoriesEmpty()) _deleteMode = false;
                });
              }
              _saveIngredients();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class DeepEquals {
  static bool mapEquals<T, U>(Map<T, U>? a, Map<T, U>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (final T key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }
}