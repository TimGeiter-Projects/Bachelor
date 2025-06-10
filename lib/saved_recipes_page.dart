import 'package:flutter/material.dart';
import 'data/recipe.dart'; // Dein Recipe-Modell
import 'services/recipe_service.dart'; // Dein RecipeService

class SavedRecipesPage extends StatefulWidget {
  const SavedRecipesPage({super.key});

  @override
  State<SavedRecipesPage> createState() => _SavedRecipesPageState();
}

class _SavedRecipesPageState extends State<SavedRecipesPage> {
  final RecipeService _recipeService = RecipeService();
  late Future<List<Recipe>> _savedRecipesFuture;
  final Map<String, bool> _expandedStates = {}; // Zustand für aufgeklappte/zugeklappte Rezepte

  @override
  void initState() {
    super.initState();
    // _loadSavedRecipes(); // Wird jetzt in didChangeDependencies aufgerufen
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lädt die gespeicherten Rezepte jedes Mal neu, wenn die Abhängigkeiten des Widgets geändert werden,
    // was auch beim Wechseln der Tabs in einem IndexedStack passiert.
    _loadSavedRecipes();
  }

  // Lade Rezepte und aktualisiere den Future
  void _loadSavedRecipes() {
    setState(() {
      _savedRecipesFuture = _recipeService.getSavedRecipesLocally();
      // Die _expandedStates werden nicht zurückgesetzt, sodass der Aufklappzustand beibehalten wird.
    });
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
              // Zustand für dieses spezifische Rezept abrufen (standardmäßig zugeklappt)
              final bool isExpanded = _expandedStates[recipe.id] ?? false;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell( // Macht die gesamte Karte klickbar
                  onTap: () {
                    setState(() {
                      // Zustand umkehren, um auf- oder zuzuklappen
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
                            // Löschbutton ist immer sichtbar
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Rezept löschen',
                              onPressed: () => _showDeleteConfirmationDialog(recipe.id, recipe.title),
                            ),
                          ],
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
