import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:intl/intl.dart'; // Import for date formatting

import 'data/zutaten_nur_kategorien_und_namen.dart'; // Make sure this path is correct
import 'Services/scanner.dart'; // Make sure this path is correct

// New class to represent an individual ingredient entry with its date and category
// Diese Definition muss mit den Definitionen in RecipePage, RecipeService und SavedRecipesPage übereinstimmen.
class IngredientEntry {
  final String name;
  final DateTime dateAdded;
  final String category; // NEU: Feld für die Kategorie

  IngredientEntry({required this.name, required this.dateAdded, required this.category});

  // Convert an IngredientEntry to a JSON-serializable map
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dateAdded': dateAdded.toIso8601String(), // Convert DateTime to ISO 8601 string
      'category': category, // NEU: Kategorie in JSON aufnehmen
    };
  }

  // Create an IngredientEntry from a JSON map
  factory IngredientEntry.fromJson(Map<String, dynamic> json) {
    return IngredientEntry(
      name: json['name'] as String,
      dateAdded: DateTime.parse(json['dateAdded'] as String), // Parse ISO 8601 string back to DateTime
      category: json['category'] as String? ?? 'Unknown', // NEU: Kategorie aus JSON lesen, mit Fallback
    );
  }

  // For debugging and comparison
  @override
  String toString() {
    return 'IngredientEntry(name: $name, dateAdded: ${dateAdded.toIso8601String()}, category: $category)';
  }
}


class IngredientsPage extends StatefulWidget {
  const IngredientsPage({super.key});

  @override
  State<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends State<IngredientsPage> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();

  // Changed Map value type to List<IngredientEntry> to store multiple entries with dates
  Map<String, List<IngredientEntry>> _ingredientCountVegetables = {};
  Map<String, List<IngredientEntry>> _ingredientCountMain = {};
  Map<String, List<IngredientEntry>> _ingredientCountSpices = {};
  Map<String, List<IngredientEntry>> _ingredientCountOthers = {};

  // Track expanded state for individual ingredients (for the new arrow functionality)
  final Map<String, bool> _expandedIngredients = {};

  bool _deleteMode = false;

  // bool _editMode = false; // Removed: No longer needed as the button is gone

  // Key for the VisibilityDetector
  final Key _visibilityDetectorKey = const Key(
      'ingredients_page_visibility_detector');

  @override
  void initState() {
    super.initState();
    print("IngredientsPage: initState called");
    WidgetsBinding.instance.addObserver(this);
    // Initial loading of ingredients when the page starts
    _loadIngredients();
  }

  @override
  void dispose() {
    print("IngredientsPage: dispose called");
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      print("IngredientsPage: App came to foreground (resumed).");
      // The VisibilityDetector should reliably handle loading on tab changes,
      // but here you could also load if the app comes from the background.
      // _loadIngredients(); // Re-activate if you also want to update on app resume
    }
  }

  Future<void> _loadIngredients() async {
    print("IngredientsPage: _loadIngredients is being executed...");
    final prefs = await SharedPreferences.getInstance();

    // Helper function to decode a JSON string into Map<String, List<IngredientEntry>>
    Map<String, List<IngredientEntry>> _decodeMap(String? jsonString) {
      if (jsonString != null && jsonString.isNotEmpty) {
        try {
          final Map<String, dynamic> decodedMap = jsonDecode(jsonString);
          return decodedMap.map((key, value) {
            final List<dynamic> entryListJson = value as List<dynamic>;
            final List<IngredientEntry> entries = entryListJson
                .map((entryJson) =>
                IngredientEntry.fromJson(entryJson as Map<String, dynamic>))
                .toList();
            return MapEntry(key, entries);
          });
        } catch (e) {
          print(
              "IngredientsPage: Error decoding map for inventory: $e, json: $jsonString");
        }
      }
      return {};
    }

    if (!mounted) {
      print(
          "IngredientsPage: _loadIngredients - Widget not mounted, returning.");
      return;
    }

    // Load the latest data from SharedPreferences
    final tempVegetables = _decodeMap(prefs.getString('Vegetables'));
    final tempMain = _decodeMap(prefs.getString('Main Ingredients'));
    final tempSpices = _decodeMap(prefs.getString('Spices'));
    final tempOthers = _decodeMap(prefs.getString('Others'));

    // Debug output of loaded data
    print("--- IngredientsPage: LOADING FROM PREFS ---");
    print("Loaded Vegetables (from prefs): $tempVegetables");
    print("Loaded Main Ingredients (from prefs): $tempMain");
    print("Loaded Spices (from prefs): $tempSpices");
    print("Loaded Others (from prefs): $tempOthers");
    print("------------------------------------------");

    // Update the State within setState() to re-render the UI.
    // This is crucial for Flutter to notice the changes and update the UI.
    setState(() {
      _ingredientCountVegetables = tempVegetables;
      _ingredientCountMain = tempMain;
      _ingredientCountSpices = tempSpices;
      _ingredientCountOthers = tempOthers;

      // Initialize expanded state for newly loaded ingredients if necessary
      _expandedIngredients
          .clear(); // Clear old state, re-init as needed in build
      _ingredientCountVegetables.forEach((key, value) {
        // No longer only check for quantity > 1, allow expansion for single items too
        _expandedIngredients[key] = false;
      });
      _ingredientCountMain.forEach((key, value) {
        _expandedIngredients[key] = false;
      });
      _ingredientCountSpices.forEach((key, value) {
        _expandedIngredients[key] = false;
      });
      _ingredientCountOthers.forEach((key, value) {
        _expandedIngredients[key] = false;
      });

      print("IngredientsPage: Inventory loaded and State UPDATED.");
    });
  }

  Future<void> _saveIngredients() async {
    final prefs = await SharedPreferences.getInstance();

    // Helper function to encode Map<String, List<IngredientEntry>> to JSON string
    Future<void> _encodeAndSet(String key,
        Map<String, List<IngredientEntry>> map) async {
      final jsonString = jsonEncode(
          map.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList())));
      print(
          "IngredientsPage: Attempting to save '$key': $jsonString"); // DEBUG: What is being saved
      await prefs.setString(key, jsonString);
    }

    await _encodeAndSet('Vegetables', _ingredientCountVegetables);
    await _encodeAndSet('Main Ingredients', _ingredientCountMain);
    await _encodeAndSet('Spices', _ingredientCountSpices);
    await _encodeAndSet('Others', _ingredientCountOthers);
    print("IngredientsPage: Inventory save completed.");
  }

  void _addIngredient() {
    final String ingredient = _controller.text.trim();
    if (ingredient.isNotEmpty) {
      final String normalizedIngredient = ingredient.toLowerCase();
      final String category = getCategoryForIngredient(normalizedIngredient); // Ermittelt die Kategorie
      final IngredientEntry newEntry = IngredientEntry(
          name: normalizedIngredient,
          dateAdded: DateTime.now(),
          category: category); // NEU: Kategorie hier übergeben!

      setState(() {
        Map<String, List<IngredientEntry>> targetMap;
        switch (category) {
          case "Vegetables":
            targetMap = _ingredientCountVegetables;
            break;
          case "Main Ingredients":
            targetMap = _ingredientCountMain;
            break;
          case "Spices":
            targetMap = _ingredientCountSpices;
            break;
          default:
            targetMap = _ingredientCountOthers;
            break;
        }
        targetMap.update(
          normalizedIngredient,
              (list) {
            list.add(newEntry);
            return list;
          },
          ifAbsent: () => [newEntry],
        );
        // Ensure expanded state is handled for newly added items
        // No longer only check for quantity > 1, allow expansion for single items too
        _expandedIngredients[normalizedIngredient] =
            _expandedIngredients[normalizedIngredient] ?? false;

        _controller.clear();
        FocusScope.of(context).unfocus();
      });
      _saveIngredients();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${ingredient}" added to "$category"!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green[600],
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please enter or select an ingredient.')),
        );
      }
    }
  }

  void _increaseQuantity(String ingredientKey, String categoryMapKey) {
    if (mounted) {
      setState(() {
        Map<String, List<IngredientEntry>> targetMap = _getTargetMap(
            categoryMapKey);
        // Ermittle die Kategorie für den neuen Eintrag
        final String category = getCategoryForIngredient(ingredientKey);
        final IngredientEntry newEntry = IngredientEntry(
            name: ingredientKey,
            dateAdded: DateTime.now(),
            category: category); // NEU: Kategorie hier übergeben!

        targetMap.update(
          ingredientKey,
              (list) {
            list.add(newEntry);
            return list;
          },
          ifAbsent: () => [newEntry],
        );
        // Ensure expanded state is handled for newly added items
        _expandedIngredients[ingredientKey] =
            _expandedIngredients[ingredientKey] ?? false;
      });
    }
    _saveIngredients();
  }

  void _decreaseQuantity(String ingredientKey, String categoryMapKey) {
    if (mounted) {
      setState(() {
        Map<String, List<IngredientEntry>> targetMap = _getTargetMap(
            categoryMapKey);
        if (targetMap[ingredientKey] != null &&
            targetMap[ingredientKey]!.isNotEmpty) {
          // Remove the newest entry to decrease quantity
          targetMap[ingredientKey]!.sort((a, b) =>
              b.dateAdded.compareTo(a.dateAdded)); // Sort descending by date
          targetMap[ingredientKey]!.removeAt(0); // Remove the newest one

          if (targetMap[ingredientKey]!.isEmpty) {
            targetMap.remove(ingredientKey);
            _expandedIngredients.remove(
                ingredientKey); // Remove expanded state if ingredient is gone
            // if (_editMode && _areAllInventoriesEmpty()) { // Removed: No longer needed
            //   _editMode = false;
            // }
          }
        } else {
          targetMap.remove(ingredientKey);
          _expandedIngredients.remove(ingredientKey);
          // if (_editMode && _areAllInventoriesEmpty()) { // Removed: No longer needed
          //   _editMode = false;
          // }
        }
      });
    }
    _saveIngredients();
  }

  Map<String, List<IngredientEntry>> _getTargetMap(String categoryMapKey) {
    switch (categoryMapKey) {
      case "Vegetables":
        return _ingredientCountVegetables;
      case "Main Ingredients":
        return _ingredientCountMain;
      case "Spices":
        return _ingredientCountSpices;
      default:
        return _ingredientCountOthers;
    }
  }

  void _confirmDeleteIngredient(String ingredientKey) {
    final String category = getCategoryForIngredient(ingredientKey);
    String displayIngredient = ingredientKey.length > 1
        ? '${ingredientKey[0].toUpperCase()}${ingredientKey.substring(1)}'
        : ingredientKey.toUpperCase();

    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Delete Ingredient'),
            content: Text(
                'Do you really want to delete all entries for "$displayIngredient" from "$category"?'),
            actions: [
              TextButton(child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop()),
              TextButton(
                child: const Text(
                    'Delete', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      Map<String, List<IngredientEntry>> targetMap;
                      switch (category) {
                        case "Vegetables":
                          targetMap = _ingredientCountVegetables;
                          break;
                        case "Main Ingredients":
                          targetMap = _ingredientCountMain;
                          break;
                        case "Spices":
                          targetMap = _ingredientCountSpices;
                          break;
                        default:
                          targetMap = _ingredientCountOthers;
                          break;
                      }
                      targetMap.remove(ingredientKey);
                      _expandedIngredients.remove(
                          ingredientKey); // Also remove from expanded state
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
      String? productName = await BarcodeScanner.getProductNameFromBarcode(
          barcode);
      if (productName != null && productName.isNotEmpty) {
        String cleanName = productName.replaceAll(
            RegExp(r'^Product:\s*', caseSensitive: false), '');
        cleanName = cleanName
            .split('\n')
            .first
            .trim();
        if (mounted) {
          setState(() {
            _controller.text = cleanName;
          });
          _addIngredient();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Barcode "$barcode" could not be matched to a product.'),
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
    print(
        "IngredientsPage: build called. _deleteMode: $_deleteMode"); // Removed _editMode from print
    return VisibilityDetector(
      key: _visibilityDetectorKey,
      onVisibilityChanged: (visibilityInfo) {
        // Load ingredients when the page is more than 90% visible
        if (mounted && visibilityInfo.visibleFraction > 0.9) {
          print(
              "IngredientsPage: Page became visible (VisibilityDetector). Loading inventory.");
          _loadIngredients();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your Inventory'),
          backgroundColor: Theme
              .of(context)
              .colorScheme
              .inversePrimary,
          actions: [
            if (!_areAllInventoriesEmpty()) ...[
              // Removed the IconButton for _editMode
              // IconButton(
              //   icon: Icon(
              //     _editMode ? Icons.edit_off : Icons.edit,
              //     color: _editMode ? Colors.blue : null,
              //   ),
              //   onPressed: () {
              //     if (mounted) {
              //       setState(() {
              //         _editMode = !_editMode;
              //         if (_editMode) {
              //           _deleteMode = false;
              //         }
              //         _expandedIngredients.updateAll((key, value) => false);
              //       });
              //     }
              //   },
              //   tooltip: _editMode ? 'Exit edit mode' : 'Edit (currently limited)',
              // ),
              // Delete mode button
              IconButton(
                icon: Icon(
                  _deleteMode ? Icons.check_circle_outline : Icons
                      .delete_outline,
                  color: _deleteMode ? Colors.green : null,
                ),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _deleteMode = !_deleteMode;
                      // When delete mode is activated, deactivate edit mode (no editMode anymore)
                      // if (_deleteMode) {
                      //   _editMode = false;
                      // }
                      // Reset expanded state when switching modes
                      _expandedIngredients.updateAll((key, value) => false);
                    });
                  }
                },
                tooltip: _deleteMode
                    ? 'Exit delete mode'
                    : 'Activate delete mode',
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
                            : allIngredients.where((option) =>
                            option.toLowerCase().startsWith(query));
                      },
                      onSelected: (selection) {
                        _controller.text = selection;
                        FocusScope.of(context).unfocus();
                      },
                      fieldViewBuilder: (context, fieldTextEditingController,
                          focusNode, onFieldSubmitted) {
                        // Synchronization of _controller and fieldTextEditingController
                        // This helps when _controller is set externally (e.g. by scanner)
                        if (_controller.text !=
                            fieldTextEditingController.text &&
                            !focusNode.hasFocus) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) fieldTextEditingController.text =
                                _controller.text;
                          });
                        }
                        return TextField(
                          controller: fieldTextEditingController,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Search / enter ingredient',
                            suffixIcon: (fieldTextEditingController.text
                                .isNotEmpty)
                                ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                fieldTextEditingController.clear();
                                _controller
                                    .clear(); // Important: Also clear the main controller
                                focusNode.requestFocus();
                              },
                            ) : null,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (text) {
                            _controller.text =
                                text; // Keep _controller synchronized
                          },
                          onSubmitted: (_) => _addIngredient(),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanBarcode,
                    tooltip: 'Scan barcode',
                  )
                ],
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Add to Inventory'),
                onPressed: _addIngredient,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40)),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _areAllInventoriesEmpty()
                    ? const Center(child: Text(
                    'No ingredients in inventory.\nAdd some or scan a barcode!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey)))
                    : ListView(
                  children: [
                    _buildCategoryTile(
                        'Vegetables', _ingredientCountVegetables, 'Vegetables'),
                    _buildCategoryTile('Main Ingredients', _ingredientCountMain,
                        'Main Ingredients'),
                    _buildCategoryTile(
                        'Spices', _ingredientCountSpices, 'Spices'),
                    _buildCategoryTile(
                        'Others', _ingredientCountOthers, 'Others'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTile(String title,
      Map<String, List<IngredientEntry>> ingredientMap, String categoryKey) {
    List<String> sortedKeys = ingredientMap.keys.toList()
      ..sort((a, b) => a.compareTo(b));
    // Ensure the title is displayed correctly, e.g., "Main Ingredients" -> "Main Ingredients"
    String displayTitle = title.replaceAllMapped(
        RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}').trim();

    return ExpansionTile(
      title: Text(displayTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      initiallyExpanded: ingredientMap.isNotEmpty,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      backgroundColor: Theme
          .of(context)
          .scaffoldBackgroundColor,
      collapsedBackgroundColor: Theme
          .of(context)
          .scaffoldBackgroundColor,
      trailing: _deleteMode && ingredientMap.isNotEmpty
          ? Tooltip(message: "Delete all in '$displayTitle'",
          child: IconButton(icon: Icon(
              Icons.delete_sweep_outlined, color: Colors.red.shade300),
              onPressed: () => _confirmDeleteCategory(
                  categoryKey, ingredientMap, displayTitle)))
          : null,
      children: sortedKeys.isEmpty
          ? [
        const ListTile(
            dense: true, title: Text('No ingredients in this category.'))
      ]
          : sortedKeys.map((key) {
        // Convert key to display format (e.g., "apple" -> "Apple")
        String displayKey = key.length > 1 ? '${key[0].toUpperCase()}${key
            .substring(1)}' : key.toUpperCase();
        final List<IngredientEntry> entries = ingredientMap[key]!;
        final int quantity = entries.length;
        // Sort entries by date added (oldest first) to find the oldest date
        entries.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
        final String oldestDate = DateFormat('MM/dd/yyyy').format(
            entries.first.dateAdded);
        final bool isExpanded = _expandedIngredients[key] ??
            false; // Check if this specific ingredient is expanded

        return Column( // Always return a Column to allow expansion
          children: [
            ListTile(
              // Title displays date only when not expanded
              title: Text(
                  isExpanded ? displayKey : '$displayKey ($oldestDate)'),
              trailing: _buildTrailingWidget(
                  key, categoryKey, quantity, isExpanded),
              // Pass isExpanded state
              leading: _buildLeadingWidget(key, categoryKey),
              onTap: _deleteMode ? () =>
                  _confirmDeleteSingleItemFromCategory(key, categoryKey) : null,
              dense: true,
            ),
            // Sub-list for individual entries when expanded
            if (isExpanded)
              Column(
                children: [
                  ...entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 32.0),
                      // Indent sub-items
                      child: ListTile(
                        title: Text(
                            '${displayKey} (Added: ${DateFormat('MM/dd/yyyy')
                                .format(entry.dateAdded)})'),
                        trailing: _deleteMode ? IconButton(
                          icon: Icon(Icons.remove_circle_outline,
                              color: Colors.red.shade500, size: 20),
                          onPressed: () => _confirmDeleteSpecificEntry(
                              entry, key, categoryKey),
                          tooltip: 'Delete this specific entry',
                        ) : null,
                        dense: true,
                      ),
                    );
                  }).toList(),
                  // New: Plus button at the bottom of the expanded list
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0, top: 8.0),
                    child: ListTile(
                      leading: const Icon(
                          Icons.add_circle_outline, color: Colors.green),
                      title: Text('Add another $displayKey'),
                      onTap: () => _increaseQuantity(key, categoryKey),
                      dense: true,
                    ),
                  ),
                ],
              ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildTrailingWidget(String ingredientKey, String categoryKey,
      int quantity, bool isExpanded) {
    // Always show quantity and arrow button
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${quantity}x',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(
          icon: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons
              .keyboard_arrow_down),
          onPressed: () {
            setState(() {
              _expandedIngredients[ingredientKey] =
              !isExpanded; // Toggle expanded state
            });
          },
          tooltip: isExpanded
              ? 'Collapse details'
              : 'Show all entries and add more', // Adjusted tooltip
        ),
      ],
    );
  }

  Widget? _buildLeadingWidget(String ingredientKey, String categoryKey) {
    if (_deleteMode) {
      return IconButton(
        icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade700),
        visualDensity: VisualDensity.compact,
        onPressed: () =>
            _confirmDeleteSingleItemFromCategory(ingredientKey, categoryKey),
      );
    }
    return null;
  }

  void _confirmDeleteCategory(String categoryMapKey,
      Map<String, List<IngredientEntry>> categoryMap,
      String displayCategoryName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Clear "$displayCategoryName"?'),
          content: const Text(
              'Do you really want to delete all ingredients from this category?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text(
                  'Delete All', style: TextStyle(color: Colors.red)),
              onPressed: () {
                if (mounted) {
                  setState(() {
                    categoryMap.clear();
                    // Clear expanded state for all ingredients in this category
                    _expandedIngredients.removeWhere((key, value) =>
                    categoryMap.containsKey(key) == false);
                    if (_deleteMode && _areAllInventoriesEmpty())
                      _deleteMode = false;
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

  void _confirmDeleteSingleItemFromCategory(String ingredientKey,
      String categoryMapKey) {
    final String categoryDisplay = getCategoryForIngredient(ingredientKey);
    String displayIngredient = ingredientKey.length > 1
        ? '${ingredientKey[0].toUpperCase()}${ingredientKey.substring(1)}'
        : ingredientKey.toUpperCase();

    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text('Delete "$displayIngredient"'),
            content: Text(
                'Do you really want to delete ALL entries for "$displayIngredient" from "$categoryDisplay"?'),
            actions: [
              TextButton(child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop()),
              TextButton(
                child: const Text(
                    'Delete All', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      Map<String,
                          List<IngredientEntry>> targetMap = _getTargetMap(
                          categoryMapKey);
                      targetMap.remove(ingredientKey);
                      _expandedIngredients.remove(
                          ingredientKey); // Also remove from expanded state
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

  void _confirmDeleteSpecificEntry(IngredientEntry entryToDelete,
      String ingredientKey, String categoryMapKey) {
    final String categoryDisplay = getCategoryForIngredient(ingredientKey);
    String displayIngredient = ingredientKey.length > 1
        ? '${ingredientKey[0].toUpperCase()}${ingredientKey.substring(1)}'
        : ingredientKey.toUpperCase();
    String formattedDate = DateFormat('MM/dd/yyyy').format(
        entryToDelete.dateAdded);

    showDialog(
        context: context,
        builder: (context) =>
            AlertDialog(
              title: Text('Delete specific "$displayIngredient" entry'),
              content: Text(
                  'Do you really want to delete the entry for "$displayIngredient" added on "$formattedDate"?'),
              actions: [
                TextButton(child: const Text('Cancel'),
                    onPressed: () => Navigator.of(context).pop()),
                TextButton(
                  child: const Text(
                      'Delete', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    if (mounted) {
                      setState(() {
                        Map<String,
                            List<IngredientEntry>> targetMap = _getTargetMap(
                            categoryMapKey);
                        if (targetMap.containsKey(ingredientKey)) {
                          targetMap[ingredientKey]!.remove(entryToDelete);
                          if (targetMap[ingredientKey]!.isEmpty) {
                            targetMap.remove(ingredientKey);
                            _expandedIngredients.remove(ingredientKey);
                          }
                        }
                      });
                    }
                    _saveIngredients();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ));
  }
}
