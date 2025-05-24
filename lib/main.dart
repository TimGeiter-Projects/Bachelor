import 'package:flutter/material.dart';
import 'ingriedients.dart'; // Importiert die Inventarseite
import 'recipe.dart';      // Importiert die Rezeptseite

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recipe App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      // Startet mit dem MainScreen, der die Navigation enthält
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

//----------------------------------------------------------------------
// Haupt-Widget, das die BottomNavigationBar und die Seiten verwaltet
//----------------------------------------------------------------------
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // Index der aktuell ausgewählten Seite

  // Liste der Widgets (Seiten), die in der Navigation angezeigt werden
  static final List<Widget> _widgetOptions = <Widget>[
    const IngredientsPage(), // Index 0: Inventarseite
    const RecipePage(),      // Index 1: Rezeptseite (Platzhalter oder deine Implementierung)
  ];

  // Funktion, die aufgerufen wird, wenn ein Item in der NavBar getippt wird
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Der Body zeigt das aktuell ausgewählte Widget aus _widgetOptions an
      // IndexedStack erhält den Zustand der nicht sichtbaren Seiten
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      // Die Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Inventar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            activeIcon: Icon(Icons.menu_book),
            label: 'Rezepte',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}