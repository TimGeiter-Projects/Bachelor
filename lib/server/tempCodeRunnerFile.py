from flask import Flask, jsonify, request
from flask_cors import CORS
import torch
from transformers import AutoModel, AutoTokenizer
import numpy as np

app = Flask(__name__)
CORS(app)

# --- Globale Variablen für die Modelle und Tokenizer ---
RECIPE_LM_MODEL_NAME = "mbien/recipenlg"
INGREDIENT_BERT_MODEL_NAME = "alexdseo/RecipeBERT"

# Modelle und Tokenizer
recipe_tokenizer = None
recipe_model = None
ingredient_tokenizer = None
ingredient_model = None
device = None

def load_models_and_tokenizers():
    """
    Lädt beide Modelle und Tokenizer: 
    1. RecipeNLG für die Generierung der Rezepte
    2. RecipeBERT für die Zutatenauswahl
    """
    global recipe_tokenizer, recipe_model, ingredient_tokenizer, ingredient_model, device

    try:
        # Versuche, eine GPU zu finden, sonst nutze die CPU
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        print(f"Nutze Gerät: {device}")

        print(f"Lade RecipeNLG Modell und Tokenizer ({RECIPE_LM_MODEL_NAME})...")
        # Lade RecipeNLG (GPT-2 basiert)
        recipe_tokenizer = AutoTokenizer.from_pretrained(RECIPE_LM_MODEL_NAME)
        recipe_model = AutoModel.from_pretrained(RECIPE_LM_MODEL_NAME).to(device)
        recipe_model.eval()  # Setze das Modell in den Evaluierungsmodus
        
        print(f"Lade RecipeBERT Modell und Tokenizer ({INGREDIENT_BERT_MODEL_NAME})...")
        # Lade RecipeBERT für Zutatenvektoren
        ingredient_tokenizer = AutoTokenizer.from_pretrained(INGREDIENT_BERT_MODEL_NAME)
        ingredient_model = AutoModel.from_pretrained(INGREDIENT_BERT_MODEL_NAME).to(device)
        ingredient_model.eval()  # Setze das Modell in den Evaluierungsmodus

        print("Alle Modelle und Tokenizer erfolgreich geladen.")
        return True
    except Exception as e:
        print(f"Fehler beim Laden der Modelle/Tokenizer: {e}")
        return False

def get_ingredient_embedding(ingredient):
    """
    Berechnet den Embedding-Vektor für eine einzelne Zutat mit RecipeBERT.
    """
    # Stellen sicher, dass das Modell im Evaluierungsmodus ist
    ingredient_model.eval()
    
    # Tokenisierung der Zutat
    inputs = ingredient_tokenizer(ingredient, return_tensors="pt", padding=True, truncation=True, max_length=128).to(device)
    
    # Berechnung des Embeddings
    with torch.no_grad():  # Kein Gradient-Tracking notwendig
        outputs = ingredient_model(**inputs)
    
    # Extrahiere das [CLS] Token als Repräsentation der Zutat
    # (erstes Token des letzten Hidden-State)
    embedding = outputs.last_hidden_state[:, 0, :].cpu().numpy()
    
    return embedding[0]  # Gibt den Vektor für die einzelne Zutat zurück

def compute_similarity(vec1, vec2):
    """
    Berechnet die Kosinus-Ähnlichkeit zwischen zwei Vektoren.
    """
    similarity = np.dot(vec1, vec2) / (np.linalg.norm(vec1) * np.linalg.norm(vec2))
    return similarity

def find_best_matching_ingredients(required_ingredients, all_available_ingredients, num_to_select=5):
    """
    Findet die am besten passenden Zutaten basierend auf RecipeBERT Embeddings.
    
    Args:
        required_ingredients: Liste der bereits ausgewählten Zutaten
        all_available_ingredients: Wörterbuch mit allen verfügbaren Zutaten nach Kategorien
        num_to_select: Anzahl der zusätzlich auszuwählenden Zutaten
        
    Returns:
        Liste mit zusätzlich ausgewählten, am besten passenden Zutaten
    """
    # Wenn keine Pflichtzutaten ausgewählt wurden, können wir nicht gut abgleichen
    if not required_ingredients:
        # Wähle einfach ein paar zufällige Zutaten
        import random
        all_ingredients = []
        for category_ingredients in all_available_ingredients.values():
            all_ingredients.extend(category_ingredients)
        
        if len(all_ingredients) <= num_to_select:
            return all_ingredients
        else:
            return random.sample(all_ingredients, num_to_select)
    
    # Berechne den durchschnittlichen Embedding-Vektor für die ausgewählten Zutaten
    required_embeddings = [get_ingredient_embedding(ing) for ing in required_ingredients]
    average_required_embedding = np.mean(required_embeddings, axis=0)
    
    # Sammle alle verfügbaren Zutaten, die nicht zu den Pflichtzutaten gehören
    available_ingredients = []
    for category, ingredients in all_available_ingredients.items():
        for ingredient in ingredients:
            if ingredient not in required_ingredients:
                available_ingredients.append(ingredient)
    
    # Wenn zu wenige verfügbare Zutaten übrig sind
    if len(available_ingredients) <= num_to_select:
        return available_ingredients
    
    # Berechne die Ähnlichkeiten für alle verfügbaren Zutaten
    ingredient_similarities = []
    for ingredient in available_ingredients:
        embedding = get_ingredient_embedding(ingredient)
        similarity = compute_similarity(embedding, average_required_embedding)
        ingredient_similarities.append((ingredient, similarity))
    
    # Sortiere nach Ähnlichkeit (absteigend)
    ingredient_similarities.sort(key=lambda x: x[1], reverse=True)
    
    # Wähle die Top-N ähnlichsten Zutaten
    best_matching = [item[0] for item in ingredient_similarities[:num_to_select]]
    
    return best_matching

def generate_recipe_with_model(prompt):
    """
    Generiert ein Rezept mit dem RecipeNLG Modell.
    """
    try:
        # Tokenisiere den Prompt
        inputs = recipe_tokenizer(prompt, return_tensors="pt", max_length=512, truncation=True).to(device)

        # Generiere das Rezept
        outputs = recipe_model.generate(
            inputs["input_ids"],
            max_new_tokens=500,
            temperature=0.8,
            top_k=50,
            top_p=0.95,
            do_sample=True,
            num_return_sequences=1,
            pad_token_id=recipe_tokenizer.eos_token_id,
            eos_token_id=recipe_tokenizer.eos_token_id
        )

        # Dekodiere die generierten Token zurück in Text
        generated_text = recipe_tokenizer.decode(outputs[0], skip_special_tokens=True)

        # Extrahiere den Teil nach "Recipe:"
        if "Recipe:" in generated_text:
            recipe_text = generated_text.split("Recipe:", 1)[-1].strip()
        else:
            recipe_text = generated_text.strip()

        return recipe_text, None
    except Exception as e:
        print(f"Fehler bei der Rezeptgenerierung: {e}")
        return None, f"Fehler bei der Generierung: {e}"

@app.route('/generate_recipe', methods=['POST'])
def handle_recipe_request():
    """
    Verarbeitet eingehende POST-Anfragen von der Flutter-App.
    """
    # Prüfe, ob der Anfragekörper JSON ist
    if not request.is_json:
        return jsonify({"error": "Anfrage muss JSON sein"}), 415
    
    # Hole die JSON-Daten aus dem Anfragekörper
    data = request.get_json()
    
    # Extrahiere die ausgewählten Zutaten (required_ingredients)
    required_ingredients = data.get('required_ingredients', [])
    
    # Extrahiere alle verfügbaren Zutaten nach Kategorien
    available_ingredients = {
        'vegetables': data.get('vegetables', []),
        'fruits': data.get('fruits', []),
        'main_ingredients': data.get('main_ingredients', []),
        'spices': data.get('spices', []),
        'others': data.get('others', [])
    }
    
    print(f"Empfangene Pflichtzutaten: {required_ingredients}")
    print(f"Empfangene verfügbare Zutaten: {available_ingredients}")
    
    # Bestimme die besten zusätzlichen Zutaten
    try:
        additional_ingredients = find_best_matching_ingredients(
            required_ingredients,
            available_ingredients,
            num_to_select=min(8 - len(required_ingredients), 5)  # Max 8 Zutaten gesamt, max 5 zusätzliche
        )
        
        # Kombiniere alle zu verwendenden Zutaten
        all_ingredients = required_ingredients + additional_ingredients
        
        # Formatiere die Zutaten
        formatted_ingredients = [
            ingredient[0].upper() + ingredient[1:] if len(ingredient) > 1 else ingredient.upper()
            for ingredient in all_ingredients
        ]
        ingredients_str = ', '.join(formatted_ingredients)
        
        print(f"Generiere Rezept mit Zutaten: {ingredients_str}")
        
        # Generiere das Rezept
        prompt = f"Ingredients: {ingredients_str}\nRecipe:"
        generated_recipe, error = generate_recipe_with_model(prompt)
        
        if error:
            return jsonify({"error": error}), 500
        elif not generated_recipe:
            return jsonify({"error": "Rezeptgenerierung fehlgeschlagen oder kein Text zurückgegeben."}), 500
        
        return jsonify({
            'generated_text': generated_recipe,
            'used_ingredients': ingredients_str
        })
    
    except Exception as e:
        print(f"Fehler bei der Verarbeitung: {e}")
        return jsonify({"error": f"Serverfehler: {e}"}), 500

if __name__ == '__main__':
    # Lade die Modelle und Tokenizer
    if load_models_and_tokenizers():
        # Starte den Flask-Server
        app.run(host='0.0.0.0', port=5000, debug=True)
    else:
        print("Server konnte aufgrund von Fehlern beim Laden der Modelle/Tokenizer nicht gestartet werden.")