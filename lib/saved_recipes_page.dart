import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/recipe.dart'; // Dein Recipe-Modell
import 'services/recipe_service.dart'; // Dein RecipeService
import 'dart:developer'; // Für `log` Debug-Ausgaben

class SavedRecipesPage extends StatefulWidget {
  const SavedRecipesPage({super.key});

  @override
  State<SavedRecipesPage> createState() => _SavedRecipesPageState();
}

class _SavedRecipesPageState extends State<SavedRecipesPage> with WidgetsBindingObserver {
  final RecipeService _recipeService = RecipeService();
  late Future<List<Recipe>> _savedRecipesFuture;
  final Map<String, bool> _expandedStates = {}; // Zustand für aufgeklappte/zugeklappte Rezepte

  // Inventar-Maps, um den Kochstatus zu prüfen
  Map<String, int> _vegetablesMap = {};
  Map<String, int> _mainIngredientsMap = {};
  Map<String, int> _spicesMap = {};
  Map<String, int> _othersMap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // _loadSavedRecipes() und _loadInventory() werden jetzt in didChangeDependencies aufgerufen
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      log('SavedRecipesPage: App resumed, reloading recipes and inventory.');
      _loadInventory(); // Inventar beim Wiederaufnehmen der App neu laden
      _loadSavedRecipes(); // Gespeicherte Rezepte neu laden
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    log('SavedRecipesPage: didChangeDependencies called, reloading recipes and inventory.');
    _loadInventory(); // Lade Inventar zuerst
    _loadSavedRecipes(); // Lade gespeicherte Rezepte danach
  }

  // Lade Inventar aus SharedPreferences
  Future<void> _loadInventory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Stelle sicher, dass die neuesten Daten geladen werden

    Map<String, int> _decodeMap(String? jsonString) {
      if (jsonString != null) {
        try {
          return Map<String, int>.from(jsonDecode(jsonString));
        } catch (e) {
          log('SavedRecipesPage: Error decoding map for inventory: $e, json: $jsonString');
          return {};
        }
      }
      return {};
    }

    if (!mounted) {
      log('SavedRecipesPage: _loadInventory - Widget not mounted, returning.');
      return;
    }

    setState(() {
      _vegetablesMap = _decodeMap(prefs.getString('Vegetables'));
      _mainIngredientsMap = _decodeMap(prefs.getString('Main Ingredients'));
      _spicesMap = _decodeMap(prefs.getString('Spices'));
      _othersMap = _decodeMap(prefs.getString('Others'));
      log('SavedRecipesPage: Inventory loaded: $_vegetablesMap, $_mainIngredientsMap, $_spicesMap, $_othersMap');
    });
  }

  // Lade Rezepte und aktualisiere den Future
  void _loadSavedRecipes() {
    setState(() {
      _savedRecipesFuture = _recipeService.getSavedRecipesLocally();
      // Die _expandedStates werden nicht zurückgesetzt, sodass der Aufklappzustand beibehalten wird.
    });
  }

  // Methode zur Berechnung fehlender Zutaten für ein Rezept (bleibt bestehen und wird in UI genutzt)
  List<String> _getMissingIngredientsForRecipe(Recipe recipe) {
    if (recipe.usedIngredients.isEmpty) {
      return [];
    }

    // Wandle alle tatsächlich verwendeten Rezeptzutaten in Kleinbuchstaben und trimme sie für den Vergleich
    final Set<String> recipeUsedIngredientsNormalized = Set<String>.from(
      recipe.usedIngredients.map((i) => i.toLowerCase().trim()),
    );

    // Kombiniere alle verfügbaren Inventar-Zutaten (normalisiert)
    final Set<String> allAvailableInventoryIngredientsNormalized = {
      ..._vegetablesMap.keys.map((k) => k.toLowerCase().trim()),
      ..._mainIngredientsMap.keys.map((k) => k.toLowerCase().trim()),
      ..._spicesMap.keys.map((k) => k.toLowerCase().trim()),
      ..._othersMap.keys.map((k) => k.toLowerCase().trim()),
    };

    final List<String> missing = [];
    for (String ingredient in recipeUsedIngredientsNormalized) {
      if (!allAvailableInventoryIngredientsNormalized.contains(ingredient)) {
        if (ingredient.isNotEmpty) {
          String? originalIngredient = recipe.usedIngredients.firstWhere(
                (element) => element.toLowerCase().trim() == ingredient,
            orElse: () => ingredient,
          );
          missing.add(originalIngredient);
        }
      }
    }
    log('SavedRecipesPage: Missing ingredients for "${recipe.title}" (based on used ingredients): $missing');
    return missing;
  }

  Future<void> _showDeleteConfirmationDialog(String recipeId, String recipeTitle) async {
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Rezept löschen'),
          content: Text('Möchten Sie das Rezept "$recipeTitle" wirklich löschen?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      await _deleteRecipe(recipeId, recipeTitle);
    }
  }

  Future<void> _deleteRecipe(String recipeId, String recipeTitle) async {
    try {
      await _recipeService.deleteRecipeLocally(recipeId);
      // Nach dem Löschen den Zustand für dieses Rezept entfernen
      setState(() {
        _expandedStates.remove(recipeId);
      });
      _loadSavedRecipes(); // Rezepte nach dem Löschen neu laden
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rezept "$recipeTitle" erfolgreich gelöscht!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Löschen des Rezepts: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helferfunktion zum Bauen der Zutatenliste
  Widget _buildIngredientsList(BuildContext context, List<String> ingredients) {
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
                child: Text(ingredients[index], style: Theme.of(context).textTheme.bodyLarge),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helferfunktion zum Bauen der Anweisungsliste
  Widget _buildDirectionsList(BuildContext context, List<String> directions) {
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
                child: Text(directions[index], style: Theme.of(context).textTheme.bodyLarge),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gespeicherte Rezepte'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rezepte aktualisieren',
            onPressed: _loadSavedRecipes,
          ),
        ],
      ),
      body: FutureBuilder<List<Recipe>>(
        future: _savedRecipesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler beim Laden der Rezepte: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Noch keine Rezepte gespeichert.'));
          }

          final recipes = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: recipes.length,
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              final bool isExpanded = _expandedStates[recipe.id] ?? false;
              final List<String> missingIngredients = _getMissingIngredientsForRecipe(recipe);
              final bool canBeCooked = missingIngredients.isEmpty;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell( // Macht die gesamte Karte klickbar
                  onTap: () {
                    setState(() {
                      _expandedStates[recipe.id] = !isExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                recipe.title,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            // Kochstatus-Icon und zugehöriger Abstand entfernt
                            // Löschbutton ist immer sichtbar
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Rezept löschen',
                              onPressed: () => _showDeleteConfirmationDialog(recipe.id, recipe.title),
                            ),
                          ],
                        ),
                        // Anzeige der fehlenden Zutaten in Kurzform (bleibt bestehen)
                        if (!canBeCooked)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              'Fehlende Zutaten: ${missingIngredients.join(', ')}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Gespeichert am: ${recipe.savedAt.toLocal().toString().split('.')[0]}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        // HIER: Der aufklappbare Bereich für Zutaten und Anweisungen
                        Visibility(
                          visible: isExpanded, // Nur sichtbar, wenn aufgeklappt
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),

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
                              _buildIngredientsList(context, recipe.ingredients),
                              const SizedBox(height: 24),

                              const Text(
                                "ANWEISUNGEN",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const Divider(),
                              const SizedBox(height: 8),
                              _buildDirectionsList(context, recipe.directions),
                              const SizedBox(height: 24),

                              if (recipe.usedIngredients.isNotEmpty) ...[
                                Text(
                                  "Verwendete Zutaten (KI-Generierung): ${recipe.usedIngredients.join(', ')}",
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
