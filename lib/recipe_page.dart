import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/recipe_service.dart';
import 'widgets/ingredient_selector.dart';
import 'widgets/recipe_display.dart';
import 'data/recipe.dart';
import 'dart:developer';
import 'package:intl/intl.dart';
import 'data/IngriedientEntry.dart'; // Wichtig: Neuer Importpfad für IngredientEntry

class RecipePage extends StatefulWidget {
  const RecipePage({super.key});

  @override
  State<RecipePage> createState() => _RecipePageState();
}

class _RecipePageState extends State<RecipePage> with WidgetsBindingObserver {
  // Services
  final RecipeService _recipeService = RecipeService();

  // Recipe Data & Loading State
  Map<String, dynamic> _recipeData = {};
  bool _isLoading = false;
  bool _isCurrentRecipeSaved = false;

  // Inventory Maps (for Shared Preferences) - NOW LISTS OF IngredientEntry
  Map<String, List<IngredientEntry>> _vegetablesMap = {};
  Map<String, List<IngredientEntry>> _mainIngredientsMap = {};
  Map<String, List<IngredientEntry>> _spicesMap = {};
  Map<String, List<IngredientEntry>> _othersMap = {};

  // Ingredient Selection State
  Set<String> _requiredIngredients = {};
  bool _showRecipes = false;
  bool _hasIngredients = false;
  bool _autoExpandIngredients = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    log('RecipePage: initState completed.');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    log('RecipePage: dispose called.');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      log('RecipePage: App resumed, reloading inventory.');
      _loadInventory();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    log('RecipePage: didChangeDependencies called, reloading inventory.');
    _loadInventory();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoExpandIngredients = prefs.getBool('auto_expand_ingredients') ?? true;
    });
    log('RecipePage: Settings loaded. AutoExpand: $_autoExpandIngredients');
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_expand_ingredients', _autoExpandIngredients);
    log('RecipePage: Settings saved. AutoExpand: $_autoExpandIngredients');
  }

  Future<void> _loadInventory() async {
    final prefs = await SharedPreferences.getInstance();
    log('RecipePage: _loadInventory started.');

    await prefs.reload();
    log('RecipePage: SharedPreferences reloaded.');

    Map<String, List<IngredientEntry>> _decodeMap(String? jsonString) {
      if (jsonString != null && jsonString.isNotEmpty) {
        try {
          final Map<String, dynamic> decodedMap = jsonDecode(jsonString);
          return decodedMap.map((key, value) {
            final List<dynamic> entryListJson = value as List<dynamic>;
            final List<IngredientEntry> entries = entryListJson
                .map((entryJson) => IngredientEntry.fromJson(entryJson as Map<String, dynamic>))
                .toList();
            return MapEntry(key, entries);
          });
        } catch (e) {
          log('RecipePage: Error decoding map for inventory: $e, json: $jsonString');
          return {};
        }
      }
      return {};
    }

    if (!mounted) {
      log('RecipePage: _loadInventory - Widget not mounted, returning.');
      return;
    }

    Map<String, List<IngredientEntry>> newVegetablesMap = _decodeMap(prefs.getString('Vegetables'));
    Map<String, List<IngredientEntry>> newMainIngredientsMap = _decodeMap(prefs.getString('Main Ingredients'));
    Map<String, List<IngredientEntry>> newSpicesMap = _decodeMap(prefs.getString('Spices'));
    Map<String, List<IngredientEntry>> newOthersMap = _decodeMap(prefs.getString('Others'));

    log('RecipePage: Data read from prefs AFTER reload (BEFORE setState):');
    log(' Vegetables: $newVegetablesMap');
    log(' Main Ingredients: $newMainIngredientsMap');
    log(' Spices: $newSpicesMap');
    log(' Others: $newOthersMap');

    setState(() {
      _vegetablesMap = newVegetablesMap;
      _mainIngredientsMap = newMainIngredientsMap;
      _spicesMap = newSpicesMap;
      _othersMap = newOthersMap;

      _hasIngredients = _vegetablesMap.values.any((list) => list.isNotEmpty) ||
          _mainIngredientsMap.values.any((list) => list.isNotEmpty) ||
          _spicesMap.values.any((list) => list.isNotEmpty) ||
          _othersMap.values.any((list) => list.isNotEmpty);

      _cleanupRequiredIngredients();
      log('RecipePage: _loadInventory setState completed. _hasIngredients: $_hasIngredients');
    });
  }

  void _cleanupRequiredIngredients() {
    Set<String> allAvailable = {
      ..._vegetablesMap.keys,
      ..._mainIngredientsMap.keys,
      ..._spicesMap.keys,
      ..._othersMap.keys
    };
    _requiredIngredients.removeWhere((ingredient) => !allAvailable.contains(ingredient));
    log('RecipePage: _cleanupRequiredIngredients called. Required ingredients after cleanup: $_requiredIngredients');
  }

  Future<void> _generateRecipe() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _recipeData = {};
      _showRecipes = true;
      _isCurrentRecipeSaved = false;
    });
    log('RecipePage: Generating recipe...');

    List<String> required = _requiredIngredients.toList();
    // Die availableToExpand wird NICHT MEHR direkt an den Service gesendet.
    // Stattdessen senden wir die gesamten Inventar-Maps.
    // Die API muss diese dann intern verarbeiten.
    Map<String, List<IngredientEntry>> fullInventory = {
      ..._vegetablesMap,
      ..._mainIngredientsMap,
      ..._spicesMap,
      ..._othersMap,
    };

    try {
      log('Sending request to RecipeService. Required: $required, Full Inventory for expansion: $fullInventory');

      final recipe = await _recipeService.generateRecipe(
        requiredIngredients: required,
        fullAvailableIngredients: fullInventory, // Senden Sie alle Ihre Inventar-Maps
        autoExpandIngredients: _autoExpandIngredients, // Kann weiterhin für die API-Logik verwendet werden
      );

      if (!mounted) return;

      final String recipeId = recipe['id'] ?? DateTime.now().microsecondsSinceEpoch.toString();
      final bool saved = await _recipeService.isRecipeSaved(recipeId);
      log('RecipePage: Is newly generated recipe saved? $saved (ID: $recipeId)');

      setState(() {
        _recipeData = recipe;
        _recipeData['id'] = recipeId;
        _isCurrentRecipeSaved = saved;
        log('RecipePage: Recipe generated and data set. Title: ${_recipeData['title']}, IsSaved: $_isCurrentRecipeSaved');
      });
    } catch (e) {
      log('RecipePage: Error generating recipe via RecipeService: $e', error: e);
      setState(() {
        _recipeData = {
          'title': 'Generierungsfehler',
          'ingredients': ['Es gab ein Problem beim Generieren des Rezepts.'],
          'directions': [
            'Bitte überprüfen Sie Ihre Internetverbindung und den Hugging Face Space.',
            'Details: ${e.toString()}'
          ],
          'used_ingredients': [],
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
        };
        _isCurrentRecipeSaved = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          log('RecipePage: Loading finished.');
        });
      }
    }
  }

  Future<void> _toggleSaveRecipe() async {
    if (_recipeData.isEmpty || _recipeData['title'] == null || _recipeData['ingredients'].isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kein gültiges Rezept zum Speichern/Löschen vorhanden.'),
          backgroundColor: Colors.red,
        ),
      );
      log('RecipePage: Attempted to save/delete invalid recipe.');
      return;
    }

    final String recipeId = _recipeData['id'] ?? '';
    if (recipeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rezept hat keine gültige ID zum Speichern/Löschen.'),
          backgroundColor: Colors.red,
        ),
      );
      log('RecipePage: Recipe has no valid ID for saving/deleting.');
      return;
    }

    if (_isCurrentRecipeSaved) {
      try {
        await _recipeService.deleteRecipeLocally(recipeId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rezept "${_recipeData['title']}" erfolgreich lokal gelöscht!'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isCurrentRecipeSaved = false;
          });
          log('RecipePage: Recipe "${_recipeData['title']}" deleted successfully.');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler beim lokalen Löschen des Rezepts: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
          log('RecipePage: Error deleting recipe: $e', error: e);
        }
      }
    } else {
      final newRecipe = Recipe(
        id: recipeId,
        title: _recipeData['title'],
        ingredients: List<String>.from(_recipeData['ingredients']),
        directions: List<String>.from(_recipeData['directions']),
        usedIngredients: List<String>.from(_recipeData['used_ingredients']),
        savedAt: DateTime.now(),
      );

      try {
        await _recipeService.saveRecipeLocally(newRecipe);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rezept "${newRecipe.title}" erfolgreich lokal gespeichert!'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _isCurrentRecipeSaved = true;
          });
          log('RecipePage: Recipe "${newRecipe.title}" saved successfully.');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler beim lokalen Speichern des Rezepts: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
          log('RecipePage: Error saving recipe: $e', error: e);
        }
      }
    }
  }

  void _toggleView() {
    setState(() {
      _showRecipes = !_showRecipes;
      if (!_showRecipes) {
        _recipeData = {};
        _isCurrentRecipeSaved = false;
      }
      log('RecipePage: Toggled view. Show recipes: $_showRecipes');
    });
  }

  void _toggleIngredient(String ingredient) {
    setState(() {
      if (_requiredIngredients.contains(ingredient)) {
        _requiredIngredients.remove(ingredient);
      } else {
        _requiredIngredients.add(ingredient);
      }
      log('RecipePage: Toggled ingredient: $ingredient. Required: $_requiredIngredients');
    });
  }

  void _toggleAutoExpand() {
    setState(() {
      _autoExpandIngredients = !_autoExpandIngredients;
    });
    _saveSettings();
    log('RecipePage: Toggled auto expand to: $_autoExpandIngredients');
  }

  Future<void> _showIngredientDeductionDialog() async {
    if (_recipeData['used_ingredients'] == null) return;

    List<String> usedIngredients = List<String>.from(_recipeData['used_ingredients']);
    Map<String, int> deductionAmounts = {};
    Map<String, String> ingredientCategories = {};

    for (String ingredient in usedIngredients) {
      String? category = _findIngredientCategory(ingredient);
      if (category != null) {
        ingredientCategories[ingredient] = category;
        int available = _getIngredientAmount(ingredient, category);
        deductionAmounts[ingredient] = available > 0 ? 1 : 0;
      }
    }

    Map<String, int>? result = await showDialog<Map<String, int>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Zutaten aus Inventar abziehen'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Passen Sie die Mengen an, die von Ihrem Inventar abgezogen werden sollen:',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ...usedIngredients.map((ingredient) {
                        String? category = ingredientCategories[ingredient];
                        int available = category != null ? _getIngredientAmount(ingredient, category) : 0;
                        int currentDeduction = deductionAmounts[ingredient] ?? 0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ingredient,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  available > 0
                                      ? 'Verfügbar: $available'
                                      : 'Nicht im Inventar',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: available > 0 ? Colors.green : Colors.red,
                                  ),
                                ),
                                if (available > 0) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text('Abziehen: '),
                                      IconButton(
                                        onPressed: currentDeduction > 0
                                            ? () {
                                          setDialogState(() {
                                            deductionAmounts[ingredient] = currentDeduction - 1;
                                          });
                                        }
                                            : null,
                                        icon: const Icon(Icons.remove),
                                        iconSize: 20,
                                      ),
                                      Text(
                                        '$currentDeduction',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      IconButton(
                                        onPressed: currentDeduction < available
                                            ? () {
                                          setDialogState(() {
                                            deductionAmounts[ingredient] = currentDeduction + 1;
                                          });
                                        }
                                            : null,
                                        icon: const Icon(Icons.add),
                                        iconSize: 20,
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(deductionAmounts),
                  child: const Text('Abziehen'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await _deductIngredientsFromInventory(result);
    }
  }

  String? _findIngredientCategory(String ingredient) {
    if (_vegetablesMap.containsKey(ingredient)) return 'Vegetables';
    if (_mainIngredientsMap.containsKey(ingredient)) return 'Main Ingredients';
    if (_spicesMap.containsKey(ingredient)) return 'Spices';
    if (_othersMap.containsKey(ingredient)) return 'Others';
    return null;
  }

  int _getIngredientAmount(String ingredient, String category) {
    switch (category) {
      case 'Vegetables':
        return _vegetablesMap[ingredient]?.length ?? 0;
      case 'Main Ingredients':
        return _mainIngredientsMap[ingredient]?.length ?? 0;
      case 'Spices':
        return _spicesMap[ingredient]?.length ?? 0;
      case 'Others':
        return _othersMap[ingredient]?.length ?? 0;
      default:
        return 0;
    }
  }

  Future<void> _deductIngredientsFromInventory(Map<String, int> deductions) async {
    final prefs = await SharedPreferences.getInstance();

    Map<String, List<IngredientEntry>> newVegetables = Map.from(_vegetablesMap);
    Map<String, List<IngredientEntry>> newMainIngredients = Map.from(_mainIngredientsMap);
    Map<String, List<IngredientEntry>> newSpices = Map.from(_spicesMap);
    Map<String, List<IngredientEntry>> newOthers = Map.from(_othersMap);

    for (String ingredient in deductions.keys) {
      int amountToDeduct = deductions[ingredient] ?? 0;
      if (amountToDeduct <= 0) continue;

      String? category = _findIngredientCategory(ingredient);
      if (category == null) continue;

      Map<String, List<IngredientEntry>> targetMap;
      switch (category) {
        case 'Vegetables':
          targetMap = newVegetables;
          break;
        case 'Main Ingredients':
          targetMap = newMainIngredients;
          break;
        case 'Spices':
          targetMap = newSpices;
          break;
        case 'Others':
          targetMap = newOthers;
          break;
        default:
          continue;
      }

      List<IngredientEntry>? currentEntries = targetMap[ingredient];
      if (currentEntries != null && currentEntries.isNotEmpty) {
        currentEntries.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));

        for (int i = 0; i < amountToDeduct && currentEntries.isNotEmpty; i++) {
          currentEntries.removeAt(0);
        }

        if (currentEntries.isEmpty) {
          targetMap.remove(ingredient);
        } else {
          targetMap[ingredient] = currentEntries;
        }
      }
    }

    await prefs.setString('Vegetables', jsonEncode(newVegetables.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))));
    await prefs.setString('Main Ingredients', jsonEncode(newMainIngredients.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))));
    await prefs.setString('Spices', jsonEncode(newSpices.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))));
    await prefs.setString('Others', jsonEncode(newOthers.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))));
    log('RecipePage: Inventory deducted and saved in new format.');

    await _loadInventory();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zutaten erfolgreich aus dem Inventar abgezogen!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezept generieren'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_showRecipes)
            IconButton(
              icon: const Icon(Icons.list_alt),
              tooltip: 'Zutaten auswählen',
              onPressed: _toggleView,
            ),
          if (_showRecipes)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Neues Rezept generieren',
              onPressed: _generateRecipe,
            ),
          if (_showRecipes && _recipeData.isNotEmpty && _recipeData['title'] != null && !_isLoading)
            IconButton(
              icon: Icon(
                _isCurrentRecipeSaved ? Icons.favorite : Icons.favorite_border,
                color: _isCurrentRecipeSaved ? Colors.red : null,
              ),
              tooltip: _isCurrentRecipeSaved ? 'Rezept entfernen' : 'Rezept speichern',
              onPressed: _toggleSaveRecipe,
            ),
        ],
      ),
      body: _showRecipes
          ? RecipeDisplay(
        recipeData: _recipeData,
        isLoading: _isLoading,
        onDeductIngredients: _showIngredientDeductionDialog,
        hasIngredients: _hasIngredients,
      )
          : IngredientSelector(
        vegetablesMap: _vegetablesMap.map((key, entries) {
          entries.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
          return MapEntry(key, entries.isNotEmpty ? DateFormat('MM/dd/yyyy').format(entries.first.dateAdded) : null);
        }),
        mainIngredientsMap: _mainIngredientsMap.map((key, entries) {
          entries.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
          return MapEntry(key, entries.isNotEmpty ? DateFormat('MM/dd/yyyy').format(entries.first.dateAdded) : null);
        }),
        spicesMap: _spicesMap.map((key, entries) {
          entries.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
          return MapEntry(key, entries.isNotEmpty ? DateFormat('MM/dd/yyyy').format(entries.first.dateAdded) : null);
        }),
        othersMap: _othersMap.map((key, entries) {
          entries.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
          return MapEntry(key, entries.isNotEmpty ? DateFormat('MM/dd/yyyy').format(entries.first.dateAdded) : null);
        }),
        requiredIngredients: _requiredIngredients,
        autoExpandIngredients: _autoExpandIngredients,
        onToggleIngredient: _toggleIngredient,
        onGenerateRecipe: _generateRecipe,
        onToggleAutoExpand: _toggleAutoExpand,
        onResetRequiredIngredients: () {
          setState(() => _requiredIngredients.clear());
        },
      ),
    );
  }
}