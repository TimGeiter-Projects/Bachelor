import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/recipe.dart'; // Stelle sicher, dass dieser Pfad korrekt ist: 'data/recipe.dart' oder 'models/recipe.dart'

class RecipeService {
  // --- Hugging Face Space API-Logik (unverändert) ---
  final String baseUrl = "https://timinf-dockerrecipe.hf.space/generate_recipe";

  Future<Map<String, dynamic>> generateRecipe({
    required List<String> requiredIngredients,
    required List<String> availableIngredients,
    bool autoExpandIngredients = true,
  }) async {
    final headers = {'Content-Type': 'application/json'};
    final payload = {
      'required_ingredients': requiredIngredients,
      'available_ingredients': availableIngredients,
      'max_ingredients': 7, // Standardwert, falls nicht von UI gesteuert
      'max_retries': 5,     // Standardwert, falls nicht von UI gesteuert
    };
    final requestBody = jsonEncode(payload);

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

  // NEUE/FEHLENDE METHODE: Prüft, ob ein Rezept bereits gespeichert ist
  Future<bool> isRecipeSaved(String recipeId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recipesJson = prefs.getString(_savedRecipesKey);

    if (recipesJson != null) {
      final List<dynamic> recipesListJson = jsonDecode(recipesJson);
      return recipesListJson.any((json) => json['id'] == recipeId);
    }
    return false;
  }

  // --- METHODEN FÜR LOKALE SPEICHERUNG SIND HIER DEFINIERT ---

  static const String _savedRecipesKey = 'saved_recipes'; // Schlüssel für SharedPreferences

  // Methode zum Speichern eines Rezepts in SharedPreferences
  Future<void> saveRecipeLocally(Recipe recipe) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recipesJson = prefs.getString(_savedRecipesKey);
    List<Map<String, dynamic>> recipesListJson;

    if (recipesJson != null) {
      // Wenn bereits Rezepte gespeichert sind, decodiere sie
      recipesListJson = List<Map<String, dynamic>>.from(jsonDecode(recipesJson));
    } else {
      // Andernfalls, starte mit einer leeren Liste
      recipesListJson = [];
    }

    // Prüfen, ob Rezept bereits existiert (um es zu aktualisieren statt neu hinzuzufügen)
    final int existingIndex = recipesListJson.indexWhere((r) => r['id'] == recipe.id);
    if (existingIndex != -1) {
      // Wenn es existiert, aktualisiere den Eintrag
      recipesListJson[existingIndex] = recipe.toJson();
    } else {
      // Wenn nicht, füge es hinzu
      recipesListJson.add(recipe.toJson());
    }

    // Speichere die aktualisierte Liste als JSON-String
    await prefs.setString(_savedRecipesKey, jsonEncode(recipesListJson));
    print('Recipe saved locally: ${recipe.title}');
  }

  // Methode zum Laden aller gespeicherten Rezepte aus SharedPreferences
  Future<List<Recipe>> getSavedRecipesLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recipesJson = prefs.getString(_savedRecipesKey);

    if (recipesJson != null) {
      // Decodiere den JSON-String in eine Liste von Maps
      final List<dynamic> recipesListJson = jsonDecode(recipesJson);
      // Sortiere die Rezepte nach dem Speicherdatum absteigend (neueste zuerst)
      recipesListJson.sort((a, b) => DateTime.parse(b['saved_at']).compareTo(DateTime.parse(a['saved_at'])));
      // Konvertiere die Maps in Recipe-Objekte
      return recipesListJson.map((json) => Recipe.fromJson(Map<String, dynamic>.from(json))).toList();
    }
    // Gebe eine leere Liste zurück, wenn keine Rezepte gefunden wurden
    return [];
  }

  // Methode zum Löschen eines Rezepts aus SharedPreferences
  Future<void> deleteRecipeLocally(String recipeId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recipesJson = prefs.getString(_savedRecipesKey);

    if (recipesJson != null) {
      List<Map<String, dynamic>> recipesListJson = List<Map<String, dynamic>>.from(jsonDecode(recipesJson));
      // Entferne das Rezept mit der passenden ID
      recipesListJson.removeWhere((r) => r['id'] == recipeId);
      // Speichere die aktualisierte Liste zurück
      await prefs.setString(_savedRecipesKey, jsonEncode(recipesListJson));
      print('Recipe deleted locally: $recipeId');
    }
  }
}
