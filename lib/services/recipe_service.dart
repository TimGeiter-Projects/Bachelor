import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/recipe.dart';
import '../data/IngriedientEntry.dart'; // Wichtig: Neuer Importpfad für IngredientEntry

class RecipeService {
  final String baseUrl = "https://timinf-dockerrecipe.hf.space/generate_recipe";

  Future<Map<String, dynamic>> generateRecipe({
    required List<String> requiredIngredients,
    // NEU: fullAvailableIngredients enthält die detaillierten IngredientEntry-Objekte
    required Map<String, List<IngredientEntry>> fullAvailableIngredients,
    bool autoExpandIngredients = true, // Wird in der RecipePage verwendet, nicht direkt an die API gesendet
  }) async {
    final headers = {'Content-Type': 'application/json'};

    // Transformation der fullAvailableIngredients in das gewünschte JSON-Format
    List<Map<String, dynamic>> availableIngredientsWithDetails = [];
    // Wir iterieren über alle Listen von IngredientEntry in der Map
    fullAvailableIngredients.forEach((key, entries) {
      for (var entry in entries) {
        availableIngredientsWithDetails.add({
          'name': entry.name,
          'dateAdded': entry.dateAdded.toIso8601String(), // Datum als ISO 8601 String
          'category': entry.category,
        });
      }
    });

    final payload = {
      'required_ingredients': requiredIngredients,
      'available_ingredients': availableIngredientsWithDetails, // HIER ist die neue Struktur!
      'max_ingredients': 7,
      'max_retries': 5,
    };
    final requestBody = jsonEncode(payload);

    print('Sending API request with payload: $requestBody'); // Debug-Ausgabe des Payloads

    try {
      final response = await http.post(Uri.parse(baseUrl), headers: headers, body: requestBody);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('API Error - Status Code: ${response.statusCode}');
        print('API Error - Response Body: ${response.body}');
        throw Exception('Failed to load recipe: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Network/Request Error: $e');
      throw Exception('Error sending request: ${e.toString()}');
    }
  }

  Future<bool> isRecipeSaved(String recipeId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recipesJson = prefs.getString(_savedRecipesKey);

    if (recipesJson != null) {
      final List<dynamic> recipesListJson = jsonDecode(recipesJson);
      return recipesListJson.any((json) => json['id'] == recipeId);
    }
    return false;
  }

  static const String _savedRecipesKey = 'saved_recipes';

  Future<void> saveRecipeLocally(Recipe recipe) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recipesJson = prefs.getString(_savedRecipesKey);
    List<Map<String, dynamic>> recipesListJson;

    if (recipesJson != null) {
      recipesListJson = List<Map<String, dynamic>>.from(jsonDecode(recipesJson));
    } else {
      recipesListJson = [];
    }

    final int existingIndex = recipesListJson.indexWhere((r) => r['id'] == recipe.id);
    if (existingIndex != -1) {
      recipesListJson[existingIndex] = recipe.toJson();
    } else {
      recipesListJson.add(recipe.toJson());
    }

    await prefs.setString(_savedRecipesKey, jsonEncode(recipesListJson));
    print('Recipe saved locally: ${recipe.title}');
  }

  Future<List<Recipe>> getSavedRecipesLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recipesJson = prefs.getString(_savedRecipesKey);

    if (recipesJson != null) {
      final List<dynamic> recipesListJson = jsonDecode(recipesJson);
      recipesListJson.sort((a, b) => DateTime.parse(b['saved_at']).compareTo(DateTime.parse(a['saved_at'])));
      return recipesListJson.map((json) => Recipe.fromJson(Map<String, dynamic>.from(json))).toList();
    }
    return [];
  }

  Future<void> deleteRecipeLocally(String recipeId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recipesJson = prefs.getString(_savedRecipesKey);

    if (recipesJson != null) {
      List<Map<String, dynamic>> recipesListJson = List<Map<String, dynamic>>.from(jsonDecode(recipesJson));
      recipesListJson.removeWhere((r) => r['id'] == recipeId);
      await prefs.setString(_savedRecipesKey, jsonEncode(recipesListJson));
      print('Recipe deleted locally: $recipeId');
    }
  }
}