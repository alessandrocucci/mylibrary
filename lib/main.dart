import 'dart:async'; // Per Timer (debounce ricerca)
import 'dart:io';   // Per File (immagini lista)
import 'package:flutter/material.dart';

// Importa modelli e utility
import 'models/book.dart';
import 'utils/database_helper.dart';
import 'utils/sort_options.dart'; // Enum per l'ordinamento
// Importa le altre schermate
import 'screens/add_edit_book_page.dart';
import 'screens/book_detail_page.dart';
// Importa il widget Placeholder
import 'widgets/image_placeholder.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LibreriaApp());
}

// Widget radice dell'applicazione
class LibreriaApp extends StatelessWidget {
  const LibreriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyLibrary',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.brown,
          foregroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.brown,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
          border: InputBorder.none,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: Colors.white,
          selectionColor: Colors.white.withOpacity(0.4),
          selectionHandleColor: Colors.white,
        ),
      ),
      home: const BookListPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Schermata Principale: Lista dei Libri ---
class BookListPage extends StatefulWidget {
  const BookListPage({super.key});

  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage> {
  late Future<List<Book>> _booksFuture;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  SortBy _currentSort = SortBy.titleAsc;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadBooks();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- Logica di Caricamento, Navigazione, Eliminazione ---

  void _loadBooks() {
    if (!mounted) return;
    final query = _isSearching ? _searchController.text.trim() : null;
    print("Loading books with Sort: $_currentSort, Query: '$query'");
    setState(() {
      _booksFuture = DatabaseHelper.instance.getAllBooks(
        sortBy: _currentSort,
        searchQuery: query,
      );
    });
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _isSearching) {
        _loadBooks();
      }
    });
  }

  Future<void> _navigateToAddEditPage({Book? book}) async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (context) => AddEditBookPage(book: book)));
    if (result == true && mounted) { _loadBooks(); }
  }

  Future<void> _navigateToDetailPage(int bookId) async {
     print('Navigo al dettaglio per ID: $bookId');
     final result = await Navigator.push(
         context, MaterialPageRoute(builder: (context) => BookDetailPage(bookId: bookId)));
     if (result == true && mounted) { _loadBooks(); }
  }

  // Helper per eliminare file
  Future<void> _deleteFileQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try { final file = File(path); if (await file.exists()) { await file.delete(); print("File eliminato: $path"); } }
    catch (e) { print("Errore (ignorato) eliminazione file $path: $e"); }
  }

  // Elimina libro (con conferma e pulizia file)
  Future<void> _deleteBook(int id) async {
    String? coverPathToDelete; List<String> additionalPathsToDelete = []; bool deleteConfirmed = false;
    deleteConfirmed = await showDialog<bool>(context: context, barrierDismissible: false, builder: (BuildContext ctx) { return AlertDialog( title: const Text('Conferma Eliminazione'), content: Text('Sei sicuro di voler eliminare questo libro? Verranno eliminate anche tutte le immagini associate. L\'azione non può essere annullata.'), actions: <Widget>[ TextButton( child: const Text('Annulla'), onPressed: () => Navigator.of(ctx).pop(false)), TextButton( style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Elimina'), onPressed: () => Navigator.of(ctx).pop(true)) ]); }) ?? false;
    if (!deleteConfirmed) { print("Eliminazione annullata dall'utente per libro ID: $id"); return; }
    print("Inizio processo eliminazione per libro ID: $id");
    try { final dbHelper = DatabaseHelper.instance; final bookToDelete = await dbHelper.getBook(id); if (bookToDelete != null) { coverPathToDelete = bookToDelete.coverImagePath; additionalPathsToDelete = await dbHelper.getAdditionalImagesForBook(id); print("Percorsi da eliminare - Copertina: $coverPathToDelete, Aggiuntive: ${additionalPathsToDelete.length}"); } else { print("Libro con ID $id non trovato."); if (mounted) { ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Errore: Libro non trovato.'), backgroundColor: Colors.orange)); } return; }
      final deletedRows = await dbHelper.deleteBook(id); if (deletedRows > 0) { print("Eliminazione file fisici..."); await _deleteFileQuietly(coverPathToDelete); for (String path in additionalPathsToDelete) { await _deleteFileQuietly(path); } print("Eliminazione file fisici completata."); if (mounted) { ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Libro eliminato con successo'), backgroundColor: Colors.green)); _loadBooks(); } } else { print("Nessuna riga eliminata dal DB per ID: $id"); if (mounted) { ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Eliminazione fallita: libro non trovato?'), backgroundColor: Colors.orange)); } } }
    catch (e, stacktrace) { print("Errore critico eliminazione libro $id: $e"); print(stacktrace); if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red)); } }
    finally { print("Fine processo eliminazione per libro ID: $id"); }
  }


  // --- Costruzione Interfaccia Utente ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: FutureBuilder<List<Book>>(
        future: _booksFuture,
        builder: (context, snapshot) {
          // Gestione stati (waiting, error)
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Errore nel caricamento: ${snapshot.error}'));
          }
          // Dati Caricati
          else if (snapshot.hasData) {
            final books = snapshot.data!;

            // Caso Lista Vuota (con placeholder)
            if (books.isEmpty) {
              return Center( child: Padding( padding: const EdgeInsets.all(24.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[ Icon( _isSearching && _searchController.text.isNotEmpty ? Icons.search_off : Icons.menu_book, size: 80.0, color: Colors.grey[400]), const SizedBox(height: 24.0), Text( _isSearching && _searchController.text.isNotEmpty ? 'Nessun libro trovato per\n"${_searchController.text}".' : 'La tua libreria è vuota.\nTocca + per aggiungere il primo libro!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey[700]), textAlign: TextAlign.center) ] ) ) );
            }
            // Caso Lista Piena (con placeholder immagine)
            else {
              return ListView.builder(
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  Widget leadingWidget;
                  if (book.coverImagePath != null && book.coverImagePath!.isNotEmpty) { final imageFile = File(book.coverImagePath!); leadingWidget = SizedBox( width: 50, height: 70, child: ClipRRect( borderRadius: BorderRadius.circular(4.0), child: Image.file( imageFile, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) { print("Errore img lista: ${book.coverImagePath}, Errore: $error"); return const ImagePlaceholder(width: 50, height: 70, iconSize: 30, icon: Icons.broken_image_outlined); })));
                  } else { leadingWidget = const ImagePlaceholder(width: 50, height: 70, iconSize: 30); }
                  return Card( margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), child: ListTile( leading: leadingWidget, title: Text(book.title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(book.author), onTap: () => _navigateToDetailPage(book.id!), trailing: Row( mainAxisSize: MainAxisSize.min, children: [ IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: 'Modifica', onPressed: () => _navigateToAddEditPage(book: book)), IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), tooltip: 'Elimina', onPressed: () => _deleteBook(book.id!)) ])));
                },
              );
            }
          }
          // Fallback
          else {
            return const Center(child: Text('Nessun dato disponibile.'));
          }
        },
      ),
      // FAB
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAddEditPage(),
        tooltip: 'Aggiungi Libro',
        child: const Icon(Icons.add),
      ),
    );
  }


  // --- Widget Helper AppBar e Azioni ---
  AppBar _buildAppBar() {
    return AppBar(
      title: _isSearching ? TextField(controller: _searchController, autofocus: true, decoration: const InputDecoration(hintText: 'Cerca titolo o autore...'), style: const TextStyle(color: Colors.white, fontSize: 18), onSubmitted: (_) => _loadBooks()) : const Text('MyLibrary'),
      actions: _buildAppBarActions(), // Chiama l'helper aggiornato
    );
  }

  // --- Helper Azioni AppBar (MODIFICATO CON SINGOLA X) ---
  List<Widget> _buildAppBarActions() {
    // Se si sta cercando
    if (_isSearching) {
      return [
        // Pulsante UNICO "Chiudi Ricerca"
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Chiudi ricerca',
          onPressed: () {
            if (!mounted) return;
            // bool wasSearching = _searchController.text.isNotEmpty; // Non più necessario se ricarichiamo sempre
            setState(() {
              _isSearching = false; // Disattiva modalità ricerca
              FocusScope.of(context).unfocus(); // Rimuovi focus tastiera
              _searchController.clear(); // Pulisce il testo
            });
            _debounce?.cancel(); // Cancella debounce
            _loadBooks(); // Ricarica la lista completa
          },
        ),
      ];
    }
    // Se non si sta cercando (modalità normale)
    else {
      return [
        // Pulsante Attiva Ricerca
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Cerca',
          onPressed: () {
            setState(() { _isSearching = true; });
          },
        ),
        // Pulsante Menu Ordinamento
        PopupMenuButton<SortBy>(
          icon: const Icon(Icons.sort),
          tooltip: 'Ordina per',
          onSelected: (SortBy result) { if (_currentSort != result) { setState(() { _currentSort = result; }); _loadBooks(); } },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<SortBy>>[
            _buildSortMenuItem(SortBy.titleAsc, 'Titolo (A-Z)'),
            _buildSortMenuItem(SortBy.titleDesc, 'Titolo (Z-A)'),
            _buildSortMenuItem(SortBy.authorAsc, 'Autore (A-Z)'),
            _buildSortMenuItem(SortBy.authorDesc, 'Autore (Z-A)'),
            _buildSortMenuItem(SortBy.yearAsc, 'Anno (Vecchio > Nuovo)'),
            _buildSortMenuItem(SortBy.yearDesc, 'Anno (Nuovo > Vecchio)'),
          ]
        ),
      ];
    }
  }
  // --- FINE Helper Azioni AppBar ---

  // Helper per voci menu ordinamento (invariato)
  PopupMenuItem<SortBy> _buildSortMenuItem(SortBy value, String text) {
    final bool isSelected = _currentSort == value;
    return PopupMenuItem<SortBy>(value: value, child: Text(text, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Theme.of(context).colorScheme.primary : null)));
  }

} // Fine _BookListPageState