import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:visibility_detector/visibility_detector.dart';
import 'ingriedients/zutaten_nur_kategorien_und_namen.dart';
import 'scanner.dart';

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
  bool _editMode = false; // New mode for quantity editing

  // Key for the VisibilityDetector
  final Key _visibilityDetectorKey = const Key('ingredients_page_visibility_detector');

  @override
  void initState() {
    super.initState();
    print("IngredientsPage: initState called");
    WidgetsBinding.instance.addObserver(this);
    // _loadIngredients() is now primarily triggered by VisibilityDetector,
    // but initial loading here doesn't hurt.
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
    }
  }

  Future<void> _loadIngredients() async {
    print("IngredientsPage: _loadIngredients is being executed...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Ensure we read the latest data

    Map<String, int> _decodeMap(String? jsonString) {
      if (jsonString != null) {
        try {
          return Map<String, int>.from(jsonDecode(jsonString));
        } catch (e) {
          print("IngredientsPage: Error decoding '$jsonString': $e");
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
        print("IngredientsPage: Inventory loaded and State UPDATED.");
      });
    } else if (mounted && !changed) {
      print("IngredientsPage: Inventory loaded, but NO CHANGES detected.");
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
    print("IngredientsPage: Inventory saved.");
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
          content: Text('"${ingredient}" added to "$category"!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green[600],
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter or select an ingredient.')),
        );
      }
    }
  }

  // New methods for quantity editing
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
          // If quantity is 1 or less, remove element
          targetMap.remove(ingredientKey);
          // Exit edit mode if all inventories are empty
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
        title: const Text('Delete Ingredient'),
        content: Text('Do you really want to delete "$displayIngredient" from "$category"?'),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
            content: Text('Barcode "$barcode" could not be matched to a product.'),
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
    print("IngredientsPage: build called. _deleteMode: $_deleteMode, _editMode: $_editMode");
    return VisibilityDetector( // --- HERE VisibilityDetector ---
      key: _visibilityDetectorKey,
      onVisibilityChanged: (visibilityInfo) {
        if (mounted && visibilityInfo.visibleFraction > 0.9) { // When more than 90% visible
          print("IngredientsPage: Page became visible (VisibilityDetector). Loading inventory.");
          _loadIngredients();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your Inventory'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            if (!_areAllInventoriesEmpty()) ...[
              // Edit mode button (for changing quantities)
              IconButton(
                icon: Icon(
                  _editMode ? Icons.edit_off : Icons.edit,
                  color: _editMode ? Colors.blue : null,
                ),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _editMode = !_editMode;
                      // When edit mode is activated, deactivate delete mode
                      if (_editMode) {
                        _deleteMode = false;
                      }
                    });
                  }
                },
                tooltip: _editMode ? 'Exit edit mode' : 'Edit quantities',
              ),
              // Delete mode button
              IconButton(
                icon: Icon(
                  _deleteMode ? Icons.check_circle_outline : Icons.delete_outline,
                  color: _deleteMode ? Colors.green : null,
                ),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _deleteMode = !_deleteMode;
                      // When delete mode is activated, deactivate edit mode
                      if (_deleteMode) {
                        _editMode = false;
                      }
                    });
                  }
                },
                tooltip: _deleteMode ? 'Exit delete mode' : 'Activate delete mode',
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
                        // Synchronization of _controller and fieldTextEditingController
                        // This helps when _controller is set externally (e.g. by scanner)
                        if (_controller.text != fieldTextEditingController.text && !focusNode.hasFocus) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) fieldTextEditingController.text = _controller.text;
                          });
                        }
                        return TextField(
                          controller: fieldTextEditingController,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Search / enter ingredient',
                            suffixIcon: (fieldTextEditingController.text.isNotEmpty)
                                ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                fieldTextEditingController.clear();
                                _controller.clear(); // Important: Also clear the main controller
                                focusNode.requestFocus();
                              },
                            ) : null,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (text){
                            _controller.text = text; // Keep _controller synchronized
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
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _areAllInventoriesEmpty()
                    ? const Center(child: Text('No ingredients in inventory.\nAdd some or scan a barcode!', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)))
                    : ListView(
                  children: [
                    _buildCategoryTile('Vegetables', _ingredientCountVegetables, 'Vegetables'),
                    _buildCategoryTile('Main Ingredients', _ingredientCountMain, 'Main Ingredients'),
                    _buildCategoryTile('Spices', _ingredientCountSpices, 'Spices'),
                    _buildCategoryTile('Others', _ingredientCountOthers, 'Others'),
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

    return ExpansionTile(
      title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      initiallyExpanded: ingredientMap.isNotEmpty,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Lighter color
      collapsedBackgroundColor: Theme.of(context).scaffoldBackgroundColor,
      trailing: _deleteMode && ingredientMap.isNotEmpty
          ? Tooltip(message: "Delete all in '$displayTitle'", child: IconButton(icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade300), onPressed: () => _confirmDeleteCategory(categoryKey, ingredientMap, displayTitle) ))
          : null,
      children: sortedKeys.isEmpty
          ? [const ListTile(dense: true, title: Text('No ingredients in this category.'))]
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
            tooltip: 'Decrease quantity',
          ),
          Text('${quantity}x', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: Icon(Icons.add, color: Colors.green.shade600, size: 20),
            onPressed: () => _increaseQuantity(ingredientKey, categoryKey),
            visualDensity: VisualDensity.compact,
            tooltip: 'Increase quantity',
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
          title: Text('Clear "$displayCategoryName"?'),
          content: const Text('Do you really want to delete all ingredients from this category?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text('Delete All', style: TextStyle(color: Colors.red)),
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
        title: Text('Delete "$displayIngredient"'),
        content: Text('Do you really want to delete "$displayIngredient" from "$categoryDisplay"?'),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
          TextButton(
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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