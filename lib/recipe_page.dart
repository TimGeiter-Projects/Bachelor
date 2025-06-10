import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/recipe_service.dart';
import 'widgets/ingredient_selector.dart';
import 'widgets/recipe_display.dart';
import 'data/recipe.dart'; // Dein Recipe-Modell
import 'dart:developer'; // Für `log` Debug-Ausgaben

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

  // Inventory Maps (for Shared Preferences)
  Map<String, int> _vegetablesMap = {};
  Map<String, int> _mainIngredientsMap = {};
  Map<String, int> _spicesMap = {};
  Map<String, int> _othersMap = {};

  // Ingredient Selection State
  Set<String> _requiredIngredients = {};
  bool _showRecipes = false;
  bool _hasIngredients = false;
  bool _autoExpandIngredients = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // _loadInventory(); // Wird jetzt in didChangeDependencies aufgerufen
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
      _loadInventory(); // Dies ist für den Fall, dass die App aus dem Hintergrund kommt
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lädt das Inventar jedes Mal neu, wenn die Abhängigkeiten des Widgets geändert werden,
    // was auch beim Wechseln der Tabs in einem IndexedStack passiert.
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

    Map<String, int> _decodeMap(String? jsonString) {
      if (jsonString != null) {
        try {
          return Map<String, int>.from(jsonDecode(jsonString));
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

    // Temporäre Maps, um die neu geladenen Daten zu halten
    Map<String, int> newVegetablesMap = _decodeMap(prefs.getString('Vegetables'));
    Map<String, int> newMainIngredientsMap = _decodeMap(prefs.getString('Main Ingredients'));
    Map<String, int> newSpicesMap = _decodeMap(prefs.getString('Spices'));
    Map<String, int> newOthersMap = _decodeMap(prefs.getString('Others'));

    log('RecipePage: Loaded inventory data:');
    log('  Vegetables: $newVegetablesMap');
    log('  Main Ingredients: $newMainIngredientsMap');
    log('  Spices: $newSpicesMap');
    log('  Others: $newOthersMap');

    setState(() {
      _vegetablesMap = newVegetablesMap;
      _mainIngredientsMap = newMainIngredientsMap;
      _spicesMap = newSpicesMap;
      _othersMap = newOthersMap;

      _hasIngredients = _vegetablesMap.isNotEmpty ||
          _mainIngredientsMap.isNotEmpty ||
          _spicesMap.isNotEmpty ||
          _othersMap.isNotEmpty;

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

  // --- Rezeptgenerierung (integriert den RecipeService) ---
  Future<void> _generateRecipe() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _recipeData = {};
      _showRecipes = true;
    });
    log('RecipePage: Generating recipe...');

    List<String> required = _requiredIngredients.toList();
    Set<String> allAvailable = {
      ..._vegetablesMap.keys,
      ..._mainIngredientsMap.keys,
      ..._spicesMap.keys,
      ..._othersMap.keys
    };

    List<String> availableToExpand = _autoExpandIngredients
        ? allAvailable.difference(_requiredIngredients).toList()
        : [];

    try {
      log('Sending request to RecipeService. Required: $required, Available for expansion: $availableToExpand');

      final recipe = await _recipeService.generateRecipe(
        requiredIngredients: required,
        availableIngredients: availableToExpand,
        autoExpandIngredients: _autoExpandIngredients,
      );

      if (!mounted) return;

      setState(() {
        _recipeData = recipe;
        log('RecipePage: Recipe generated and data set. Title: ${_recipeData['title']}');
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
          'used_ingredients': []
        };
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

  // --- Rezept Lokal Speichern ---
  Future<void> _saveCurrentRecipe() async {
    if (_recipeData.isEmpty || _recipeData['title'] == null || _recipeData['ingredients'].isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kein gültiges Rezept zum Speichern vorhanden.'),
          backgroundColor: Colors.red,
        ),
      );
      log('RecipePage: Attempted to save invalid recipe.');
      return;
    }

    final newRecipe = Recipe(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
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

  // --- UI-Steuerung (unverändert, außer hinzugefügte Logs) ---
  void _toggleView() {
    setState(() {
      _showRecipes = !_showRecipes;
      if (!_showRecipes) {
        _recipeData = {};
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
    // ... (unveränderter Code für Abzugsdialog)
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
        return _vegetablesMap[ingredient] ?? 0;
      case 'Main Ingredients':
        return _mainIngredientsMap[ingredient] ?? 0;
      case 'Spices':
        return _spicesMap[ingredient] ?? 0;
      case 'Others':
        return _othersMap[ingredient] ?? 0;
      default:
        return 0;
    }
  }

  Future<void> _deductIngredientsFromInventory(Map<String, int> deductions) async {
    final prefs = await SharedPreferences.getInstance();

    Map<String, int> newVegetables = Map.from(_vegetablesMap);
    Map<String, int> newMainIngredients = Map.from(_mainIngredientsMap);
    Map<String, int> newSpices = Map.from(_spicesMap);
    Map<String, int> newOthers = Map.from(_othersMap);

    for (String ingredient in deductions.keys) {
      int amount = deductions[ingredient] ?? 0;
      if (amount <= 0) continue;

      String? category = _findIngredientCategory(ingredient);
      if (category == null) continue;

      switch (category) {
        case 'Vegetables':
          int current = newVegetables[ingredient] ?? 0;
          int newAmount = current - amount;
          if (newAmount <= 0) {
            newVegetables.remove(ingredient);
          } else {
            newVegetables[ingredient] = newAmount;
          }
          break;
        case 'Main Ingredients':
          int current = newMainIngredients[ingredient] ?? 0;
          int newAmount = current - amount;
          if (newAmount <= 0) {
            newMainIngredients.remove(ingredient);
          } else {
            newMainIngredients[ingredient] = newAmount;
          }
          break;
        case 'Spices':
          int current = newSpices[ingredient] ?? 0;
          int newAmount = current - amount;
          if (newAmount <= 0) {
            newSpices.remove(ingredient);
          } else {
            newSpices[ingredient] = newAmount;
          }
          break;
        case 'Others':
          int current = newOthers[ingredient] ?? 0;
          int newAmount = current - amount;
          if (newAmount <= 0) {
            newOthers.remove(ingredient);
          } else {
            newOthers[ingredient] = newAmount;
          }
          break;
      }
    }

    await prefs.setString('Vegetables', jsonEncode(newVegetables));
    await prefs.setString('Main Ingredients', jsonEncode(newMainIngredients));
    await prefs.setString('Spices', jsonEncode(newSpices));
    await prefs.setString('Others', jsonEncode(newOthers));
    log('RecipePage: Inventory deducted and saved.');

    await _loadInventory(); // Wichtig: Nach dem Abziehen das Inventar neu laden, damit die UI aktualisiert wird.

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
          // Speichern-Button in der AppBar
          if (_showRecipes && _recipeData.isNotEmpty && _recipeData['title'] != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.favorite_border),
              tooltip: 'Rezept speichern',
              onPressed: _saveCurrentRecipe,
            ),
        ],
      ),
      body: _showRecipes
          ? RecipeDisplay(
        recipeData: _recipeData,
        isLoading: _isLoading,
        onDeductIngredients: _showIngredientDeductionDialog,
        onSaveRecipe: _saveCurrentRecipe, // Callback übergeben
        hasIngredients: _hasIngredients,
      )
          : IngredientSelector(
        vegetablesMap: _vegetablesMap,
        mainIngredientsMap: _mainIngredientsMap,
        spicesMap: _spicesMap,
        othersMap: _othersMap,
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
