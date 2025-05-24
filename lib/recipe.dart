import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RecipePage extends StatefulWidget {
  const RecipePage({super.key});

  @override
  State<RecipePage> createState() => _RecipePageState();
}

class _RecipePageState extends State<RecipePage> with WidgetsBindingObserver {
  Map<String, dynamic> _recipeData = {};
  bool _isLoading = false;

  Map<String, int> _vegetablesMap = {};
  Map<String, int> _mainIngredientsMap = {};
  Map<String, int> _spicesMap = {};
  Map<String, int> _othersMap = {};

  Set<String> _requiredIngredients = {};
  bool _showRecipes = false;
  bool _hasIngredients = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInventory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadInventory();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    final prefs = await SharedPreferences.getInstance();

    Map<String, int> _decodeMap(String? jsonString) {
      if (jsonString != null) {
        try {
          return Map<String, int>.from(jsonDecode(jsonString));
        } catch (_) {}
      }
      return {};
    }

    if (!mounted) return;

    setState(() {
      _vegetablesMap = _decodeMap(prefs.getString('Vegetables'));
      _mainIngredientsMap = _decodeMap(prefs.getString('Main Ingredients'));
      _spicesMap = _decodeMap(prefs.getString('Spices'));
      _othersMap = _decodeMap(prefs.getString('Others'));

      _hasIngredients = _vegetablesMap.isNotEmpty ||
          _mainIngredientsMap.isNotEmpty ||
          _spicesMap.isNotEmpty ||
          _othersMap.isNotEmpty;

      _cleanupRequiredIngredients();
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
  }

  void _generateRecipe() {
    if (_hasIngredients) {
      _fetchRecipe();
      setState(() {
        _showRecipes = true;
      });
    }
  }

  Future<void> _fetchRecipe() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _recipeData = {};
    });

    List<String> required = _requiredIngredients.toList();
    Set<String> allAvailable = {
      ..._vegetablesMap.keys,
      ..._mainIngredientsMap.keys,
      ..._spicesMap.keys,
      ..._othersMap.keys
    };

    final url = 'http://192.168.88.221:5000/generate_recipe';
    final payload = {
      'required_ingredients': required,
      'available_ingredients': allAvailable.toList()
    };

    try {
      final response = await http
          .post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 300));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        setState(() {
          _recipeData = json;
        });
      } else {
        setState(() {
          _recipeData = {
            'title': 'Fehler',
            'ingredients': ['Serverfehler: ${response.statusCode}'],
            'directions': ['Bitte versuche es später noch einmal.']
          };
        });
      }
    } catch (e) {
      setState(() {
        _recipeData = {
          'title': 'Verbindungsfehler',
          'ingredients': ['Fehler: ${e.toString()}'],
          'directions': ['Prüfe deine Internetverbindung und versuche es erneut.']
        };
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _toggleView() {
    setState(() {
      _showRecipes = !_showRecipes;
    });
  }

  void _toggleIngredient(String ingredient) {
    setState(() {
      if (_requiredIngredients.contains(ingredient)) {
        _requiredIngredients.remove(ingredient);
      } else {
        _requiredIngredients.add(ingredient);
      }
    });
  }

  // Neue Funktion: Zeigt Dialog zur Anpassung der verwendeten Zutaten
  Future<void> _showIngredientDeductionDialog() async {
    if (_recipeData['used_ingredients'] == null) return;

    List<String> usedIngredients = List<String>.from(_recipeData['used_ingredients']);
    Map<String, int> deductionAmounts = {};
    Map<String, String> ingredientCategories = {};

    // Initialisiere Abzugsmengen basierend auf vorhandenen Zutaten
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
                        'Passen Sie die Mengen an, die aus Ihrem Inventar abgezogen werden sollen:',
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

  // Hilfsfunktion: Findet die Kategorie einer Zutat
  String? _findIngredientCategory(String ingredient) {
    if (_vegetablesMap.containsKey(ingredient)) return 'Vegetables';
    if (_mainIngredientsMap.containsKey(ingredient)) return 'Main Ingredients';
    if (_spicesMap.containsKey(ingredient)) return 'Spices';
    if (_othersMap.containsKey(ingredient)) return 'Others';
    return null;
  }

  // Hilfsfunktion: Holt die verfügbare Menge einer Zutat
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

  // Neue Funktion: Zieht Zutaten vom Inventar ab
  Future<void> _deductIngredientsFromInventory(Map<String, int> deductions) async {
    final prefs = await SharedPreferences.getInstance();

    // Kopien der aktuellen Maps erstellen
    Map<String, int> newVegetables = Map.from(_vegetablesMap);
    Map<String, int> newMainIngredients = Map.from(_mainIngredientsMap);
    Map<String, int> newSpices = Map.from(_spicesMap);
    Map<String, int> newOthers = Map.from(_othersMap);

    // Deduktionen anwenden
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

    // Speichere die aktualisierten Maps
    await prefs.setString('Vegetables', jsonEncode(newVegetables));
    await prefs.setString('Main Ingredients', jsonEncode(newMainIngredients));
    await prefs.setString('Spices', jsonEncode(newSpices));
    await prefs.setString('Others', jsonEncode(newOthers));

    // Lade das Inventar neu
    await _loadInventory();

    // Zeige Bestätigung
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zutaten wurden erfolgreich vom Inventar abgezogen!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        _loadInventory();
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(_showRecipes ? 'Rezept Generator' : 'Zutaten auswählen'),
        actions: [
          if (_showRecipes)
            IconButton(
              icon: const Icon(Icons.food_bank),
              tooltip: 'Zutaten auswählen',
              onPressed: _toggleView,
            ),
          if (_showRecipes)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Neues Rezept generieren',
              onPressed: _generateRecipe,
            ),
        ],
      ),
      body: _showRecipes ? _buildRecipeView() : _buildIngredientSelector(),
    );
  }

  Widget _buildRecipeView() {
    if (!_hasIngredients) {
      return const Center(child: Text("Keine Zutaten im Inventar."));
    }

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Rezept wird generiert..."),
          ],
        ),
      );
    }

    if (_recipeData.isEmpty) {
      return const Center(child: Text("Noch kein Rezept generiert."));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recipe title
          Text(
            _recipeData['title'] ?? 'Rezept',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // Ingredients section
          const Text(
            "ZUTATEN",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          _buildIngredientsList(_recipeData['ingredients'] ?? []),
          const SizedBox(height: 24),

          // Directions section
          const Text(
            "ZUBEREITUNG",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          _buildDirectionsList(_recipeData['directions'] ?? []),

          const SizedBox(height: 24),
          // Used ingredients section
          if (_recipeData['used_ingredients'] != null) ...[
            Text(
              "Verwendete Zutaten: ${(_recipeData['used_ingredients'] as List).join(', ')}",
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Neuer breiter Button zum Abziehen der Zutaten
          if (_recipeData['used_ingredients'] != null && (_recipeData['used_ingredients'] as List).isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showIngredientDeductionDialog,
                icon: const Icon(Icons.remove_shopping_cart),
                label: const Text(
                  'Verwendete Zutaten vom Inventar abziehen',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildIngredientsList(List<dynamic> ingredients) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ingredients.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(ingredients[index].toString()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDirectionsList(List<dynamic> directions) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: directions.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(directions[index].toString()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIngredientSelector() {
    if (!_hasIngredients) {
      return const Center(child: Text("Keine Zutaten im Inventar."));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              "Wähle Zutaten aus, die im Rezept vorkommen müssen (${_requiredIngredients.length})"),
          const SizedBox(height: 8),
          if (_requiredIngredients.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                setState(() => _requiredIngredients.clear());
              },
              icon: const Icon(Icons.clear),
              label: const Text("Alle zurücksetzen"),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIngredientCategory("Hauptzutaten", _mainIngredientsMap),
                  _buildIngredientCategory("Gemüse", _vegetablesMap),
                  _buildIngredientCategory("Gewürze", _spicesMap),
                  _buildIngredientCategory("Sonstiges", _othersMap),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton.icon(
              onPressed: _generateRecipe,
              icon: const Icon(Icons.restaurant),
              label: const Text("Rezept generieren"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildIngredientCategory(String name, Map<String, int> map) {
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

          Align(
            alignment: Alignment.topLeft,
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: map.keys.map((ingredient) {
                final selected = _requiredIngredients.contains(ingredient);
                return FilterChip(
                  label: Text(ingredient),
                  selected: selected,
                  onSelected: (_) => _toggleIngredient(ingredient),
                  selectedColor: Theme.of(context).primaryColor,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : null,
                    fontWeight: selected ? FontWeight.bold : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}