import 'dart:async'; // Per Timer (debounce ricerca)
import 'dart:convert'; // Per jsonEncode (Esportazione)
import 'dart:io';   // Per File (immagini lista)
// import 'dart:typed_data'; // Non più necessario qui

import 'package:archive/archive_io.dart'; // Per creare ZIP (Esportazione)
import 'package:file_picker/file_picker.dart'; // Per selezionare file (Importazione)
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'; // Per directory app/temporanea (Esportazione/Importazione)
import 'package:path/path.dart' as p; // Per manipolare percorsi (Esportazione/Importazione)
import 'package:share_plus/share_plus.dart'; // Per condividere file (Esportazione)

// Importa modelli e utility locali
import 'models/book.dart';
import 'utils/database_helper.dart'; // Helper DB aggiornato
import 'utils/sort_options.dart'; // Enum per l'ordinamento
// Importa le altre schermate
import 'screens/add_edit_book_page.dart';
import 'screens/book_detail_page.dart';
// Importa il widget Placeholder
import 'widgets/image_placeholder.dart';
// Importa il servizio di Backup
import 'services/backup_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LibreriaApp());
}

// Widget radice dell'applicazione (invariato)
class LibreriaApp extends StatelessWidget {
  const LibreriaApp({super.key});
  @override
  Widget build(BuildContext context) { /* ... codice LibreriaApp ... */
    return MaterialApp( title: 'MyLibrary', theme: ThemeData( colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown), useMaterial3: true, appBarTheme: const AppBarTheme(backgroundColor: Colors.brown, foregroundColor: Colors.white), floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Colors.brown, foregroundColor: Colors.white), inputDecorationTheme: InputDecorationTheme(hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)), border: InputBorder.none), textSelectionTheme: TextSelectionThemeData(cursorColor: Colors.white, selectionColor: Colors.white.withOpacity(0.4), selectionHandleColor: Colors.white), dialogTheme: DialogTheme(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)))), home: const BookListPage(), debugShowCheckedModeBanner: false);
  }
}

// --- Schermata Principale: Lista dei Libri ---
class BookListPage extends StatefulWidget {
  const BookListPage({super.key});
  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage> {
  // --- Stato ---
  late Future<List<Book>> _booksFuture;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  SortBy _currentSort = SortBy.titleAsc;
  Timer? _debounce;
  bool _isProcessing = false; // Flag per operazioni lunghe

  // --- Istanza Servizio Backup ---
  final BackupService _backupService = BackupService();

  // --- Lifecycle ---
  @override
  void initState() { /* ... codice initState ... */
    super.initState(); _loadBooks(); _searchController.addListener(_onSearchChanged);
  }
  @override
  void dispose() { /* ... codice dispose ... */
    _searchController.removeListener(_onSearchChanged); _searchController.dispose(); _debounce?.cancel(); super.dispose();
  }

  // --- Logica Core (Caricamento, Ricerca, Navigazione) ---
  void _loadBooks() { /* ... codice _loadBooks ... */
    if (!mounted) return; final query = _isSearching ? _searchController.text.trim() : null; print("Loading books with Sort: $_currentSort, Query: '$query'"); setState(() { _booksFuture = DatabaseHelper.instance.getAllBooks(sortBy: _currentSort, searchQuery: query); });
  }
  void _onSearchChanged() { /* ... codice _onSearchChanged ... */
    if (_debounce?.isActive ?? false) _debounce!.cancel(); _debounce = Timer(const Duration(milliseconds: 500), () { if (mounted && _isSearching) { _loadBooks(); } });
  }
  Future<void> _navigateToAddEditPage({Book? book}) async { /* ... codice _navigateToAddEditPage ... */
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => AddEditBookPage(book: book))); if (result == true && mounted) { _loadBooks(); }
  }
  Future<void> _navigateToDetailPage(int bookId) async { /* ... codice _navigateToDetailPage ... */
     print('Navigo al dettaglio per ID: $bookId'); final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => BookDetailPage(bookId: bookId))); if (result == true && mounted) { _loadBooks(); }
  }

  // --- ELIMINAZIONE (MODIFICATA: usa DatabaseHelper.deleteBookAndFiles) ---
  Future<void> _deleteBook(int id) async {
    bool deleteConfirmed = false;
    // 1. Conferma Utente
    deleteConfirmed = await showDialog<bool>(context: context, barrierDismissible: false, builder: (BuildContext ctx) { return AlertDialog( title: const Text('Conferma Eliminazione'), content: Text('Sei sicuro di voler eliminare questo libro e tutte le sue immagini? L\'azione non può essere annullata.'), actions: <Widget>[ TextButton( child: const Text('Annulla'), onPressed: () => Navigator.of(ctx).pop(false)), TextButton( style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Elimina'), onPressed: () => Navigator.of(ctx).pop(true)) ]); }) ?? false;
    if (!deleteConfirmed) { print("Eliminazione annullata ID: $id"); return; }

    _setProcessing(true); // Blocca UI
    print("UI: Avvio eliminazione libro ID: $id tramite DB Helper...");

    try {
      // 2. Chiama il NUOVO metodo del DatabaseHelper
      final int deletedRows = await DatabaseHelper.instance.deleteBookAndFiles(id);
      // La cancellazione dei file avviene dentro il metodo helper

      // 3. Gestisci Successo (deletedRows > 0 è implicito se non ci sono eccezioni)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Libro eliminato con successo'), backgroundColor: Colors.green)
        );
        _loadBooks(); // Aggiorna la lista
      }
    } catch (e, stacktrace) { // 4. Gestisci Errore (propagato da DB Helper)
      print("Errore durante l'eliminazione (UI): $id: $e");
      print(stacktrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'eliminazione: $e'), backgroundColor: Colors.red)
        );
      }
    } finally { // 5. Sblocca UI
      print("UI: Fine processo eliminazione ID: $id");
      _setProcessing(false);
    }
  }
  // --- FINE ELIMINAZIONE ---

  // --- Esportazione (MODIFICATA: usa BackupService) ---
  Future<void> _handleExport() async {
     _setProcessing(true); _showProcessingDialog("Preparazione backup...");
     try {
       // Chiama il servizio
       await _backupService.exportLibrary();
       _hideProcessingDialog(); // Nascondi dialogo PRIMA della condivisione
       await Future.delayed(const Duration(milliseconds: 100)); // Delay
       // Non mostrare SnackBar qui, lascia fare al pannello di condivisione
     } catch (e) {
       print("Errore UI export: $e");
       _hideProcessingDialog();
       if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore esportazione: $e'), backgroundColor: Colors.red)); }
     } finally {
       _setProcessing(false);
     }
  }

  // --- Importazione (MODIFICATA: usa BackupService) ---
  Future<void> _handleImport() async {
     // 1. Conferma utente (gestita qui nella UI)
     bool confirmImport = await showDialog<bool>( context: context, barrierDismissible: false, builder: (ctx) => AlertDialog( title: const Text('Conferma Importazione'), content: const Text( 'ATTENZIONE: L\'importazione SOSTITUIRÀ completamente la libreria corrente.\nTutti i libri e le immagini attuali verranno eliminati.\n\nSei sicuro di voler procedere?', style: TextStyle(color: Colors.redAccent)), actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')), TextButton( style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Procedi')) ] )) ?? false;
     if (!confirmImport) { print("Import: Annullato."); return; }

     // 2. Chiama il servizio
     _setProcessing(true); _showProcessingDialog("Importazione...");
     try {
       bool importComplete = await _backupService.importLibrary();
       _hideProcessingDialog();
       if (importComplete && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Libreria importata!'), backgroundColor: Colors.green));
          _loadBooks(); // Ricarica lista
       }
       // Se ritorna false, l'errore è già stato gestito/loggato dal servizio
     } catch (e) { // Gestisce errori lanciati da importLibrary
       print("Errore UI import: $e");
       _hideProcessingDialog();
       if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore importazione: $e'), backgroundColor: Colors.red)); }
     } finally {
       _setProcessing(false);
     }
  }


  // --- Helper UI Processo (invariati) ---
  void _setProcessing(bool processing) { if (mounted) { setState(() { _isProcessing = processing; }); } }
  void _showProcessingDialog(String message) { if (!mounted) return; showDialog( context: context, barrierDismissible: false, builder: (context) => Dialog( child: Padding( padding: const EdgeInsets.all(20.0), child: Row( mainAxisSize: MainAxisSize.min, children: [ const CircularProgressIndicator(), const SizedBox(width: 20), Text(message) ])))); }
  void _hideProcessingDialog() { if (mounted && Navigator.canPop(context)) { Navigator.of(context, rootNavigator: true).pop(); } }


  // --- Costruzione UI (Build, AppBar, Actions, Lista - invariati rispetto all'ultimo completo) ---
  @override
  Widget build(BuildContext context) { // Build metodo principale
    return Scaffold(
      appBar: _buildAppBar(),
      body: Stack( // Stack per possibile overlay di processo
        children: [
          FutureBuilder<List<Book>>(
            future: _booksFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !_isProcessing) { return const Center(child: CircularProgressIndicator()); }
              else if (snapshot.hasError) { return Center(child: Text('Errore: ${snapshot.error}')); }
              else if (snapshot.hasData) { final books = snapshot.data!; if (books.isEmpty) { return Center( child: Padding( padding: const EdgeInsets.all(24.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[ Icon( _isSearching && _searchController.text.isNotEmpty ? Icons.search_off : Icons.menu_book, size: 80.0, color: Colors.grey[400]), const SizedBox(height: 24.0), Text( _isSearching && _searchController.text.isNotEmpty ? 'Nessun libro trovato per\n"${_searchController.text}".' : 'La tua libreria è vuota.\nTocca + per aggiungere!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey[700]), textAlign: TextAlign.center) ]))); }
                else { return ListView.builder( itemCount: books.length, itemBuilder: (context, index) { final book = books[index]; Widget leadingWidget; if (book.coverImagePath?.isNotEmpty ?? false) { final imageFile = File(book.coverImagePath!); leadingWidget = SizedBox( width: 50, height: 70, child: ClipRRect( borderRadius: BorderRadius.circular(4.0), child: Image.file( imageFile, fit: BoxFit.cover, errorBuilder: (c, e, s) => const ImagePlaceholder(width: 50, height: 70, iconSize: 30, icon: Icons.broken_image_outlined)))); } else { leadingWidget = const ImagePlaceholder(width: 50, height: 70, iconSize: 30); } return Card( margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), child: ListTile( leading: leadingWidget, title: Text(book.title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(book.author), onTap: () => _navigateToDetailPage(book.id!), trailing: Row( mainAxisSize: MainAxisSize.min, children: [ IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: 'Modifica', onPressed: _isProcessing ? null : () => _navigateToAddEditPage(book: book)), IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), tooltip: 'Elimina', onPressed: _isProcessing ? null : () => _deleteBook(book.id!)) ]))); }); } // Fine ListView.builder
              } else { return const Center(child: Text('Nessun dato disponibile.')); } // Fallback
            },
          ),
          // Indicatore di processo globale alternativo/aggiuntivo
          // if (_isProcessing) Container(color: Colors.black.withOpacity(0.1), child: const Center(child: CircularProgressIndicator())),
        ],
      ),
      floatingActionButton: FloatingActionButton( onPressed: _isProcessing ? null : () => _navigateToAddEditPage(), tooltip: 'Aggiungi Libro', child: const Icon(Icons.add)), // Disabilita FAB durante processo
    );
  }

  AppBar _buildAppBar() { // Costruisce AppBar
    return AppBar( title: _isSearching ? TextField(controller: _searchController, autofocus: true, decoration: const InputDecoration(hintText: 'Cerca...'), style: const TextStyle(color: Colors.white, fontSize: 18), onSubmitted: (_) => _loadBooks()) : const Text('MyLibrary'), actions: _buildAppBarActions());
  }

  List<Widget> _buildAppBarActions() { // Costruisce azioni AppBar
    final bool enableActions = !_isProcessing;
    if (_isSearching) { // Azioni Ricerca
      return [ IconButton(icon: const Icon(Icons.close), tooltip: 'Chiudi ricerca', onPressed: enableActions ? () { if (!mounted) return; setState(() { _isSearching = false; FocusScope.of(context).unfocus(); _searchController.clear(); }); _debounce?.cancel(); _loadBooks(); } : null ) ];
    } else { // Azioni Normali
      return [
        IconButton(icon: const Icon(Icons.search), tooltip: 'Cerca', onPressed: enableActions ? () { setState(() { _isSearching = true; }); } : null),
        PopupMenuButton<SortBy>(icon: const Icon(Icons.sort), tooltip: 'Ordina per', enabled: enableActions, onSelected: (SortBy result) { if (_currentSort != result) { setState(() { _currentSort = result; }); _loadBooks(); } }, itemBuilder: (ctx) => [ _buildSortMenuItem(SortBy.titleAsc, 'Titolo (A-Z)'), _buildSortMenuItem(SortBy.titleDesc, 'Titolo (Z-A)'), _buildSortMenuItem(SortBy.authorAsc, 'Autore (A-Z)'), _buildSortMenuItem(SortBy.authorDesc, 'Autore (Z-A)'), _buildSortMenuItem(SortBy.yearAsc, 'Anno (Vecchio > Nuovo)'), _buildSortMenuItem(SortBy.yearDesc, 'Anno (Nuovo > Vecchio)') ]),
        IconButton( icon: const Icon(Icons.backup_outlined), tooltip: 'Esporta Libreria', onPressed: enableActions ? _handleExport : null ), // Usa handleExport
        IconButton( icon: const Icon(Icons.restore_page_outlined), tooltip: 'Importa Libreria', onPressed: enableActions ? _handleImport : null ), // Usa handleImport
      ];
    }
  }

  PopupMenuItem<SortBy> _buildSortMenuItem(SortBy value, String text) { // Helper menu ordinamento
    final bool isSelected = _currentSort == value;
    return PopupMenuItem<SortBy>(value: value, child: Text(text, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Theme.of(context).colorScheme.primary : null)));
  }

} // Fine _BookListPageState