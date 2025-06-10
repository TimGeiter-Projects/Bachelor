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
  bool _isCurrentRecipeSaved = false; // Status, ob das aktuell angezeigte Rezept gespeichert ist

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

    await prefs.reload(); // Stellt sicher, dass die neuesten Daten vom Speicher geladen werden
    log('RecipePage: SharedPreferences reloaded.');

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

    Map<String, int> newVegetablesMap = _decodeMap(prefs.getString('Vegetables'));
    Map<String, int> newMainIngredientsMap = _decodeMap(prefs.getString('Main Ingredients'));
    Map<String, int> newSpicesMap = _decodeMap(prefs.getString('Spices'));
    Map<String, int> newOthersMap = _decodeMap(prefs.getString('Others'));

    log('RecipePage: Data read from prefs AFTER reload (BEFORE setState):');
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
      _isCurrentRecipeSaved = false; // Setze zurück, da ein neues Rezept generiert wird
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

      // Generiere eine ID, wenn das Rezept vom API-Dienst keine hat.
      // Dies ist wichtig, da das API-Modell möglicherweise keine ID zurückgibt,
      // aber wir eine für die lokale Speicherung benötigen.
      final String recipeId = recipe['id'] ?? DateTime.now().microsecondsSinceEpoch.toString();
      final bool saved = await _recipeService.isRecipeSaved(recipeId);
      log('RecipePage: Is newly generated recipe saved? $saved (ID: $recipeId)');


      setState(() {
        _recipeData = recipe;
        _recipeData['id'] = recipeId; // Stelle sicher, dass das Rezept eine ID hat
        _isCurrentRecipeSaved = saved; // Setze den Status basierend auf der Prüfung
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
          'id': DateTime.now().microsecondsSinceEpoch.toString(), // Gib dem Fehlerrezept auch eine ID
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

  // --- Rezept Lokal Speichern / Löschen (Toggle-Funktion) ---
  Future<void> _toggleSaveRecipe() async {
    // Prüfe, ob überhaupt ein gültiges Rezept angezeigt wird, bevor wir speichern/löschen
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

    // Stellen Sie sicher, dass das Rezept eine ID hat, bevor Sie fortfahren
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
      // Rezept ist bereits gespeichert, also löschen
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
      // Rezept ist nicht gespeichert, also speichern
      final newRecipe = Recipe(
        id: recipeId, // Verwende die bereits existierende ID aus _recipeData
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

  // --- UI-Steuerung (unverändert, außer hinzugefügte Logs) ---
  void _toggleView() {
    setState(() {
      _showRecipes = !_showRecipes;
      if (!_showRecipes) {
        _recipeData = {};
        _isCurrentRecipeSaved = false; // Setze zurück, wenn die Ansicht gewechselt wird
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
          if (_showRecipes) // Nur anzeigen, wenn ein Rezept angezeigt wird
            IconButton(
              icon: const Icon(Icons.list_alt),
              tooltip: 'Zutaten auswählen',
              onPressed: _toggleView,
            ),
          if (_showRecipes) // Nur anzeigen, wenn ein Rezept angezeigt wird
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Neues Rezept generieren',
              onPressed: _generateRecipe,
            ),
          // NEU: Herz-Icon als Toggle-Button
          if (_showRecipes && _recipeData.isNotEmpty && _recipeData['title'] != null && !_isLoading)
            IconButton(
              icon: Icon(
                _isCurrentRecipeSaved ? Icons.favorite : Icons.favorite_border, // Füllen oder umranden
                color: _isCurrentRecipeSaved ? Colors.red : null, // Rot, wenn gespeichert
              ),
              tooltip: _isCurrentRecipeSaved ? 'Rezept entfernen' : 'Rezept speichern',
              onPressed: _toggleSaveRecipe, // Ruft die Toggle-Funktion auf
            ),
        ],
      ),
      body: _showRecipes
          ? RecipeDisplay(
        recipeData: _recipeData,
        isLoading: _isLoading,
        onDeductIngredients: _showIngredientDeductionDialog,
        hasIngredients: _hasIngredients,
        // onSaveRecipe und isCurrentRecipeSaved werden hier nicht mehr übergeben
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
