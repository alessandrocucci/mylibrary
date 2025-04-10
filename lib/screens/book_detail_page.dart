import 'dart:io'; // Per File
import 'package:flutter/material.dart';

// Importa modelli, helper, altre schermate e widget comuni
import '../models/book.dart';
import '../utils/database_helper.dart'; // Helper DB aggiornato
import 'add_edit_book_page.dart';
import 'fullscreen_image_viewer.dart';
import '../widgets/image_placeholder.dart';

class BookDetailPage extends StatefulWidget {
  final int bookId; // ID del libro da visualizzare

  const BookDetailPage({super.key, required this.bookId});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  late Future<Book?> _bookFuture;
  late Future<List<String>> _additionalImagesFuture;
  List<String> _additionalImagePaths = []; // Memorizza percorsi aggiuntivi
  bool _isDeleting = false; // Flag per bloccare azioni durante eliminazione

  @override
  void initState() {
    super.initState();
    _loadBookData();
  }

  // Carica dati libro e immagini aggiuntive (invariato)
  void _loadBookData() {
    if (!mounted) return;
    setState(() {
      _bookFuture = DatabaseHelper.instance.getBook(widget.bookId);
      _additionalImagesFuture = DatabaseHelper.instance.getAdditionalImagesForBook(widget.bookId)
          .then((paths) { if (mounted) { _additionalImagePaths = paths; } return paths; })
          .catchError((error) { print("Errore caricamento immagini aggiuntive: $error"); if (mounted) { _additionalImagePaths = []; } return <String>[]; });
    });
  }

  // --- Funzioni Navigazione e Azione ---

  // Naviga alla pagina di modifica (invariato)
  Future<void> _navigateToEditPage(Book book) async {
     final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => AddEditBookPage(book: book)));
     if (result == true && mounted) { _loadBookData(); } // Ricarica se modificato
  }

  // Naviga al visualizzatore full-screen (invariato)
  void _openFullscreenViewer(BuildContext context, {required List<String> imagePaths, required int initialIndex}) {
    if (imagePaths.isEmpty || initialIndex < 0 || initialIndex >= imagePaths.length) { return; }
    Navigator.push(context, MaterialPageRoute(builder: (context) => FullscreenImageViewer(imagePaths: imagePaths, initialIndex: initialIndex)));
  }

  // --- ELIMINAZIONE (MODIFICATA: usa DatabaseHelper.deleteBookAndFiles) ---
  Future<void> _deleteBook(BuildContext scaffoldContext, Book book) async {
    bool deleteConfirmed = await showDialog<bool>( context: context, builder: (ctx) => AlertDialog( title: const Text('Conferma Eliminazione'), content: Text('Eliminare "${book.title}" e tutte le sue immagini?'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')), TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Elimina'))])) ?? false;

    if (!deleteConfirmed || !mounted) return;

    setState(() { _isDeleting = true; }); // Blocca UI
    print("Detail UI: Avvio eliminazione libro ID: ${book.id} tramite DB Helper...");

    try {
      // Chiama il NUOVO metodo del DatabaseHelper
      final deletedRows = await DatabaseHelper.instance.deleteBookAndFiles(book.id!);
      // La cancellazione dei file avviene dentro il metodo helper

      // Gestisci Successo
      if (deletedRows > 0 && mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar( // Usa il context passato dallo Scaffold
          const SnackBar(content: Text('Libro eliminato'), backgroundColor: Colors.green)
        );
        // Torna alla lista precedente e segnala che la lista va aggiornata
        Navigator.of(context).pop(true); // Passa true
      }
      // L'eccezione viene gestita sotto

    } catch(e, stacktrace) { // Gestisci Errore
      print("Errore eliminazione da dettaglio (ricevuto da DB Helper): ${book.id}: $e");
      print(stacktrace);
       if (mounted) {
          ScaffoldMessenger.of(scaffoldContext).showSnackBar(
            SnackBar(content: Text('Errore eliminazione: $e'), backgroundColor: Colors.red)
          );
       }
    } finally {
        if (mounted) {
             setState(() { _isDeleting = false; }); // Sblocca UI
        }
        print("Detail UI: Fine processo eliminazione ID: ${book.id}");
    }
  }

  // RIMOSSA LA FUNZIONE _deleteFileQuietly da qui


  // --- Costruzione Interfaccia Utente ---
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Book?>(
      future: _bookFuture,
      builder: (context, snapshot) {
        // Gestione stati FutureBuilder (invariato)
        if (snapshot.connectionState == ConnectionState.waiting) { return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())); }
        else if (snapshot.hasError || snapshot.data == null) { return Scaffold(appBar: AppBar(title: const Text('Errore')), body: Center(child: Text('Errore caricamento libro: ${snapshot.error ?? "Non trovato"}'))); }
        // Dati libro caricati
        else {
          final book = snapshot.data!;
          return Scaffold(
            appBar: AppBar(
              title: Text(book.title, overflow: TextOverflow.ellipsis),
              actions: [ // Azioni Modifica/Elimina (disabilitate se _isDeleting)
                IconButton(icon: const Icon(Icons.edit), tooltip: 'Modifica', onPressed: _isDeleting ? null : () => _navigateToEditPage(book)),
                Builder(builder: (scaffoldContext) => IconButton(icon: const Icon(Icons.delete), tooltip: 'Elimina', onPressed: _isDeleting ? null : () => _deleteBook(scaffoldContext, book))),
              ],
            ),
            body: SingleChildScrollView( // Corpo scrollabile (invariato)
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 40.0),
              child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  // Copertina Cliccabile (invariato, usa helper)
                  Center( child: GestureDetector( onTap: (book.coverImagePath?.isNotEmpty ?? false) ? () => _openFullscreenViewer( context, imagePaths: [book.coverImagePath!], initialIndex: 0) : null, child: Hero( tag: book.coverImagePath ?? 'book_${book.id}_cover_placeholder', child: _buildCoverImageWidget(book.coverImagePath) ) ) ),
                  const SizedBox(height: 24.0),
                  // Dettagli Testuali (invariato, usa helper)
                  _buildDetailItem(Icons.person_outline, 'Autore', book.author),
                  if (book.publisher?.isNotEmpty ?? false) _buildDetailItem(Icons.business_outlined, 'Editore', book.publisher!),
                  if (book.year != null) _buildDetailItem(Icons.calendar_today_outlined, 'Anno', book.year.toString()),
                  if (book.isbn?.isNotEmpty ?? false) _buildDetailItem(Icons.qr_code_scanner_outlined, 'ISBN', book.isbn!),
                  if (book.notes?.isNotEmpty ?? false) _buildDetailItem(Icons.notes_outlined, 'Note', book.notes!, isMultiline: true),
                  const SizedBox(height: 24.0),
                  // Galleria Immagini Aggiuntive (invariato, usa helper)
                  if (_additionalImagePaths.isNotEmpty || snapshot.connectionState == ConnectionState.waiting) Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text('Immagini Aggiuntive', style: Theme.of(context).textTheme.titleLarge)),
                  if (_additionalImagePaths.isNotEmpty || snapshot.connectionState == ConnectionState.waiting) const Divider(height: 1),
                  const SizedBox(height: 16.0),
                  _buildAdditionalImagesGallery(),
                  const SizedBox(height: 24.0),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  // --- Widget Helper (invariati, usano placeholder) ---
  Widget _buildCoverImageWidget(String? imagePath) { /* ... codice helper copertina con placeholder ... */
    Widget imageContent; if (imagePath == null || imagePath.isEmpty) { imageContent = const ImagePlaceholder( height: 250, iconSize: 60, icon: Icons.image_not_supported_outlined); } else { imageContent = Image.file( File(imagePath), fit: BoxFit.contain, errorBuilder: (c, e, s) { print("Errore img dettaglio: $imagePath, Errore: $e"); return const ImagePlaceholder( height: 250, iconSize: 60, icon: Icons.error_outline, iconColor: Colors.redAccent); }); } return Container( constraints: const BoxConstraints(maxHeight: 350), padding: const EdgeInsets.only(bottom: 8), child: Material( elevation: 4.0, borderRadius: BorderRadius.circular(4), clipBehavior: Clip.antiAlias, child: imageContent));
  }
  Widget _buildDetailItem(IconData icon, String label, String value, {bool isMultiline = false}) { /* ... codice helper dettaglio testo ... */
    return Padding( padding: const EdgeInsets.symmetric(vertical: 8.0), child: Row( crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: <Widget>[ Padding( padding: EdgeInsets.only(top: isMultiline ? 0 : 4.0), child: Icon(icon, color: Colors.grey[700], size: 20)), const SizedBox(width: 16.0), Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[ Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 13)), const SizedBox(height: 2.0), Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4))]))]));
  }
  Widget _buildAdditionalImagesGallery() { /* ... codice helper galleria con placeholder ... */
    return FutureBuilder<List<String>>( future: _additionalImagesFuture, builder: (context, snapshot) { if (snapshot.connectionState == ConnectionState.waiting) { return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 32.0), child: CircularProgressIndicator(strokeWidth: 2))); } else if (snapshot.hasError) { return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16.0), child: Text('Errore caricamento immagini: ${snapshot.error}', style: const TextStyle(color: Colors.red)))); } else { final imagePaths = _additionalImagePaths; if (imagePaths.isEmpty) { return Container(); } return GridView.builder( shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount( crossAxisCount: 3, crossAxisSpacing: 8.0, mainAxisSpacing: 8.0), itemCount: imagePaths.length, itemBuilder: (context, index) { final path = imagePaths[index]; return GestureDetector( onTap: () => _openFullscreenViewer(context, imagePaths: imagePaths, initialIndex: index), child: Hero( tag: path, child: ClipRRect( borderRadius: BorderRadius.circular(4.0), child: Image.file( File(path), fit: BoxFit.cover, errorBuilder: (c, e, s) => const ImagePlaceholder(icon: Icons.broken_image_outlined, iconSize: 24))))); }); } }, );
  }

} // Fine _BookDetailPageState