import 'dart:io'; // Per File
import 'package:flutter/material.dart';

// Importa modelli, helper, altre schermate e widget comuni
import '../models/book.dart';
import '../utils/database_helper.dart';
import 'add_edit_book_page.dart';
import 'fullscreen_image_viewer.dart';
import '../widgets/image_placeholder.dart'; // <-- IMPORT Placeholder

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

  @override
  void initState() {
    super.initState();
    _loadBookData();
  }

  // Carica dati libro e immagini aggiuntive
  void _loadBookData() {
    if (!mounted) return;
    setState(() {
      _bookFuture = DatabaseHelper.instance.getBook(widget.bookId);
      _additionalImagesFuture = DatabaseHelper.instance.getAdditionalImagesForBook(widget.bookId)
          .then((paths) {
            if (mounted) { _additionalImagePaths = paths; }
            return paths;
          }).catchError((error) {
             print("Errore caricamento immagini aggiuntive: $error");
             if (mounted) { _additionalImagePaths = []; }
             return <String>[];
          });
    });
  }

  // --- Funzioni Navigazione e Azione ---
  Future<void> _navigateToEditPage(Book book) async {
     final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => AddEditBookPage(book: book)));
     if (result == true && mounted) { _loadBookData(); }
   }

  void _openFullscreenViewer(BuildContext context, {required List<String> imagePaths, required int initialIndex}) {
    if (imagePaths.isEmpty || initialIndex < 0 || initialIndex >= imagePaths.length) { print("Percorsi non validi per viewer."); return; }
    Navigator.push(context, MaterialPageRoute(builder: (context) => FullscreenImageViewer(imagePaths: imagePaths, initialIndex: initialIndex)));
  }

  Future<void> _deleteBook(BuildContext scaffoldContext, Book book) async {
    bool deleteConfirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Conferma Eliminazione'), content: Text('Eliminare "${book.title}"?'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')), TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Elimina'))])) ?? false;
    if (!deleteConfirmed) return;
    try { final dbHelper = DatabaseHelper.instance; String? coverPathToDelete = book.coverImagePath; List<String> additionalPathsToDelete = List.from(_additionalImagePaths); final deletedRows = await dbHelper.deleteBook(book.id!); if (deletedRows > 0 && mounted) { await _deleteFileQuietly(coverPathToDelete); for (String path in additionalPathsToDelete) { await _deleteFileQuietly(path); } ScaffoldMessenger.of(scaffoldContext).showSnackBar(const SnackBar(content: Text('Libro eliminato'))); Navigator.of(context).pop(true); } else if (mounted) { throw Exception("Eliminazione DB fallita"); } }
    catch(e) { print("Errore eliminazione: $e"); if (mounted) { ScaffoldMessenger.of(scaffoldContext).showSnackBar(SnackBar(content: Text('Errore: $e'))); } }
   }

   Future<void> _deleteFileQuietly(String? path) async {
     if (path == null || path.isEmpty) return; try { final file = File(path); if (await file.exists()) { await file.delete(); print("File eliminato: $path"); } } catch (e) { print("Errore (ignorato) eliminazione file $path: $e"); }
   }


  // --- Costruzione Interfaccia Utente ---
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Book?>(
      future: _bookFuture,
      builder: (context, snapshot) {
        // Gestione stati
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(appBar: AppBar(title: const Text('Errore')), body: Center(child: Text('Errore caricamento libro: ${snapshot.error ?? "Non trovato"}')));
        }
        // Dati caricati
        else {
          final book = snapshot.data!;
          return Scaffold(
            appBar: AppBar(
              title: Text(book.title, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(icon: const Icon(Icons.edit), tooltip: 'Modifica', onPressed: () => _navigateToEditPage(book)),
                Builder(builder: (scaffoldContext) => IconButton(icon: const Icon(Icons.delete), tooltip: 'Elimina', onPressed: () => _deleteBook(scaffoldContext, book))),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // --- Copertina Cliccabile (con Placeholder) ---
                  Center(
                    child: GestureDetector(
                      onTap: (book.coverImagePath != null && book.coverImagePath!.isNotEmpty)
                          ? () => _openFullscreenViewer( context, imagePaths: [book.coverImagePath!], initialIndex: 0)
                          : null,
                      child: Hero(
                        tag: book.coverImagePath ?? 'book_${book.id}_cover_placeholder',
                        child: _buildCoverImageWidget(book.coverImagePath), // Usa l'helper aggiornato
                      ),
                    ),
                  ),
                  const SizedBox(height: 24.0),

                  // --- Dettagli Testuali ---
                  _buildDetailItem(Icons.person_outline, 'Autore', book.author),
                  if (book.publisher?.isNotEmpty ?? false) _buildDetailItem(Icons.business_outlined, 'Editore', book.publisher!),
                  if (book.year != null) _buildDetailItem(Icons.calendar_today_outlined, 'Anno', book.year.toString()),
                  if (book.isbn?.isNotEmpty ?? false) _buildDetailItem(Icons.qr_code_scanner_outlined, 'ISBN', book.isbn!),
                  if (book.notes?.isNotEmpty ?? false) _buildDetailItem(Icons.notes_outlined, 'Note', book.notes!, isMultiline: true),
                  const SizedBox(height: 24.0),

                  // --- Galleria Immagini Aggiuntive ---
                  if (_additionalImagePaths.isNotEmpty || snapshot.connectionState == ConnectionState.waiting)
                      Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text('Immagini Aggiuntive', style: Theme.of(context).textTheme.titleLarge)),
                  if (_additionalImagePaths.isNotEmpty || snapshot.connectionState == ConnectionState.waiting)
                     const Divider(height: 1),
                  const SizedBox(height: 16.0),
                  _buildAdditionalImagesGallery(), // Usa l'helper aggiornato
                  const SizedBox(height: 24.0),
                ],
              ),
            ),
          );
        }
      },
    );
  }


  // --- Widget Helper per la Copertina (CON PLACEHOLDER) ---
  Widget _buildCoverImageWidget(String? imagePath) {
    Widget imageContent;
    if (imagePath == null || imagePath.isEmpty) {
      // Usa il placeholder standard
      imageContent = const ImagePlaceholder(
          height: 250, // Altezza desiderata
          iconSize: 60,
          icon: Icons.image_not_supported_outlined
      );
    } else {
      // Mostra l'immagine
      imageContent = Image.file( File(imagePath), fit: BoxFit.contain,
        errorBuilder: (c, e, s) { // Placeholder per errore
          print("Errore img dettaglio: $imagePath, Errore: $e");
          return const ImagePlaceholder(
            height: 250,
            iconSize: 60,
            icon: Icons.error_outline,
            iconColor: Colors.redAccent,
          );
        },
      );
    }
    // Stile contenitore
    return Container(
        constraints: const BoxConstraints(maxHeight: 350),
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
           elevation: 4.0,
           borderRadius: BorderRadius.circular(4),
           clipBehavior: Clip.antiAlias,
           child: imageContent,
        ),
    );
  }


  // --- Widget Helper per Riga di Dettaglio Testuale (INVARIATO) ---
  Widget _buildDetailItem(IconData icon, String label, String value, {bool isMultiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: isMultiline ? 0 : 4.0),
            child: Icon(icon, color: Colors.grey[700], size: 20),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                const SizedBox(height: 2.0),
                Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // --- Widget Helper Galleria Immagini Aggiuntive (CON PLACEHOLDER) ---
  Widget _buildAdditionalImagesGallery() {
    return FutureBuilder<List<String>>(
      future: _additionalImagesFuture,
      builder: (context, snapshot) {
        // Stati caricamento/errore
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 32.0), child: CircularProgressIndicator(strokeWidth: 2)));
        } else if (snapshot.hasError) {
          return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16.0), child: Text('Errore caricamento immagini: ${snapshot.error}', style: const TextStyle(color: Colors.red))));
        }
        // Dati caricati
        else {
          final imagePaths = _additionalImagePaths;
          if (imagePaths.isEmpty) {
            return Container(); // Niente se vuoto
          }
          // Costruisci GridView
          return GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount( crossAxisCount: 3, crossAxisSpacing: 8.0, mainAxisSpacing: 8.0),
            itemCount: imagePaths.length,
            itemBuilder: (context, index) {
              final path = imagePaths[index];
              return GestureDetector(
                onTap: () => _openFullscreenViewer(context, imagePaths: imagePaths, initialIndex: index),
                child: Hero(
                  tag: path,
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
                      child: Image.file(
                        File(path), fit: BoxFit.cover,
                        // Placeholder per errore miniatura
                        errorBuilder: (c, e, s) => const ImagePlaceholder(icon: Icons.broken_image_outlined, iconSize: 24),
                      ),
                  ),
                ),
              );
            },
          );
        }
      },
    );
  }

} // Fine _BookDetailPageState