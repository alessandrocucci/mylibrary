import 'dart:convert'; // Per JSON
import 'dart:io';     // Per File, Directory
import 'dart:typed_data'; // Per Uint8List

import 'package:archive/archive_io.dart';     // Per creare/leggere ZIP
import 'package:file_picker/file_picker.dart'; // Per selezionare file (Import)
// import 'package:flutter/foundation.dart'; // Non serve più se non usiamo compute
import 'package:path/path.dart' as p;         // Per manipolare percorsi
import 'package:path_provider/path_provider.dart'; // Per directory temporanea/documenti
import 'package:share_plus/share_plus.dart';     // Per condividere file (Export)

// Importa dipendenze locali
import '../models/book.dart';
import '../utils/database_helper.dart'; // Usa l'helper aggiornato

/// Servizio per gestire l'esportazione e l'importazione della libreria.
class BackupService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // --- ESPORTAZIONE ---
  Future<bool> exportLibrary() async {
    print("BackupService: Avvio esportazione...");
    try {
      print("BackupService Export: Recupero libri...");
      final List<Book> allBooks = await _dbHelper.getAllBooks();
      print("BackupService Export: Recuperati ${allBooks.length} libri.");
      if (allBooks.isEmpty) { print("BackupService Export: Libreria vuota."); throw Exception("La libreria è vuota."); }

      List<Map<String, dynamic>> booksJsonData = []; Map<String, String> imageFilesToZip = {}; print("BackupService Export: Preparazione dati...");
      for (final book in allBooks) {
        if (book.id == null) continue; String? coverRelativePath; List<String> additionalImagesRelativePaths = [];
        if (book.coverImagePath?.isNotEmpty ?? false) { final originalPath = book.coverImagePath!; final zipFileName = 'book${book.id}_cover${p.extension(originalPath)}'; coverRelativePath = p.join('images', zipFileName); imageFilesToZip[originalPath] = coverRelativePath; }
        // NOTA: Rimuoviamo i controlli mounted da qui
        final additionalPaths = await _dbHelper.getAdditionalImagesForBook(book.id!);
        // if (!mounted) return false; // <-- RIMOSSO
        for (int j = 0; j < additionalPaths.length; j++) { final originalPath = additionalPaths[j]; if (originalPath.isNotEmpty) { final zipFileName = 'book${book.id}_img$j${p.extension(originalPath)}'; final relativePath = p.join('images', zipFileName); additionalImagesRelativePaths.add(relativePath); imageFilesToZip[originalPath] = relativePath; } }
        booksJsonData.add({ 'title': book.title, 'author': book.author, 'publisher': book.publisher, 'year': book.year, 'isbn': book.isbn, 'notes': book.notes, 'coverImageRelativePath': coverRelativePath, 'additionalImagesRelativePaths': additionalImagesRelativePaths });
       }
      print("BackupService Export: Dati pronti. ${imageFilesToZip.length} immagini.");

      print("BackupService Export: Creazione ZIP...");
      final String zipFilePath = await _createZipArchive(booksJsonData, imageFilesToZip);
      print("BackupService Export: ZIP creato: $zipFilePath");
      // if (!mounted) return false; // <-- RIMOSSO

      print("BackupService Export: Avvio condivisione...");
      final xFile = XFile(zipFilePath);
      final result = await Share.shareXFiles([xFile], text: 'MyLibrary Backup', subject: 'MyLibrary Backup ${DateTime.now().toLocal().toString().split('.')[0]}');
      if (result.status == ShareResultStatus.success) { print('BackupService Export: File condiviso.'); } else if (result.status == ShareResultStatus.dismissed) { print('BackupService Export: Condivisione annullata.'); } else { print('BackupService Export: Errore condivisione: ${result.status}'); }
      return true;
    } catch (e, stacktrace) { print("Errore BackupService.exportLibrary: $e\n$stacktrace"); return false; }
  }

    // Helper privato creazione ZIP (CON TRY-CATCH SU ADD FILE)
  Future<String> _createZipArchive(
      List<Map<String, dynamic>> booksJsonData,
      Map<String, String> imageFilesToZip // Es: {'/data/.../img1.jpg': 'images/book1_cover.jpg'}
      ) async {
    final encoder = ZipFileEncoder();
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final zipFilePath = p.join(tempDir.path, 'MyLibrary_Backup_$timestamp.zip');
    print("BackupService ZIP: Creazione file in $zipFilePath");
    encoder.create(zipFilePath); // Crea il file zip vuoto

    // Aggiungi JSON
    print("BackupService ZIP: Aggiunta JSON...");
    final jsonDataString = jsonEncode({'books': booksJsonData});
    encoder.addArchiveFile(ArchiveFile.string('library_data.json', jsonDataString));
    print("BackupService ZIP: JSON aggiunto.");

    int imageCounter = 0;
    print("BackupService ZIP: Inizio aggiunta ${imageFilesToZip.length} immagini referenziate (metodo ArchiveFile)...");
    for (var entry in imageFilesToZip.entries) {
      final originalPath = entry.key;
      final zipPath = entry.value;      // Es: images/book1_cover.jpg
      final file = File(originalPath);

      print("BackupService ZIP: Controllo esistenza: $originalPath");
      if (await file.exists()) {
        print("BackupService ZIP: File esiste. Lettura bytes e tentativo aggiunta: $originalPath -> $zipPath");
        try {
          // --- LEGGI I BYTE E USA addArchiveFile ---
          final Uint8List fileBytes = await file.readAsBytes(); // Leggi i dati del file
          // Crea un ArchiveFile specificando nome nello zip, dimensione e dati
          encoder.addArchiveFile(ArchiveFile(zipPath, fileBytes.length, fileBytes));
          // --- FINE METODO ALTERNATIVO ---

          imageCounter++;
          print("BackupService ZIP: Aggiunto $zipPath OK (con ArchiveFile).");
        } catch (e, stacktrace) {
          print("BackupService ZIP ERROR durante addArchiveFile per $originalPath: $e");
          print(stacktrace);
        }
      } else {
        print("BackupService ZIP WARNING: File originale NON trovato: $originalPath");
      }
    }
    print("BackupService ZIP: $imageCounter / ${imageFilesToZip.length} immagini effettivamente aggiunte.");

    print("BackupService ZIP: Chiusura encoder...");
    encoder.close(); // Finalizza lo ZIP
    print("BackupService ZIP: Encoder chiuso.");
    return zipFilePath;
  }


  // --- IMPORTAZIONE ---
  Future<bool> importLibrary() async {
    print("BackupService Import: Avvio selezione file...");
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    if (result == null || result.files.single.path == null) { print("BackupService Import: Selezione annullata."); return false; }
    final String zipFilePath = result.files.single.path!;
    print("BackupService Import: File selezionato: $zipFilePath");
    if (!zipFilePath.toLowerCase().endsWith('.zip')) { throw Exception("Il file selezionato non è un file .zip"); }
    try {
       await _performImport(zipFilePath);
       return true; // Successo
    } catch (e) {
        print("Errore catturato in importLibrary: $e");
        throw e; // Rilancia l'errore per la UI
    }
  }

  // Helper che esegue l'importazione
  Future<void> _performImport(String zipFilePath) async {
    Directory? tempExtractDir;
    try {
      // a. Estrai ZIP
      print("Import: Lettura e decodifica ZIP..."); /* ... logica estrazione corretta come prima ... */
      final zipFile = File(zipFilePath); final Uint8List bytes = await zipFile.readAsBytes(); final archive = ZipDecoder().decodeBytes(bytes); print("Import: Archivio con ${archive.length} elementi."); tempExtractDir = await Directory.systemTemp.createTemp('mylibrary_import_'); print("Import: Directory temp: ${tempExtractDir.path}"); Map<String, dynamic>? jsonData; Map<String, String> extractedImagePaths = {};
      for (final file in archive) { String normalizedZipFileName = p.normalize(file.name).replaceAll(r'\', '/'); if (normalizedZipFileName.startsWith('./')) { normalizedZipFileName = normalizedZipFileName.substring(2); } final extractedFilePath = p.join(tempExtractDir.path, normalizedZipFileName); /*print("Import: Processing: $normalizedZipFileName");*/ if (file.isFile) { final outFile = File(extractedFilePath); await outFile.parent.create(recursive: true); await outFile.writeAsBytes(file.content as List<int>); if (normalizedZipFileName == 'library_data.json') { final jsonString = utf8.decode(file.content as List<int>); jsonData = jsonDecode(jsonString) as Map<String, dynamic>; print("Import: JSON estratto."); } else if (normalizedZipFileName.startsWith('images/')) { extractedImagePaths[normalizedZipFileName] = extractedFilePath; /*print("Import: Immagine mappata: $normalizedZipFileName");*/ } } else { await Directory(extractedFilePath).create(recursive: true); } }
      if (jsonData == null) { throw Exception("'library_data.json' non trovato."); } print("Import: Estrazione completata. ${extractedImagePaths.length} immagini mappate."); if (jsonData['books'] == null || jsonData['books'] is! List) { throw Exception("Formato JSON non valido."); }
      final List booksToImport = jsonData['books'] as List; print("Import: Trovati ${booksToImport.length} libri.");
      // if (!mounted) return; // <-- RIMOSSO


      // b. Pulisci Libreria Corrente
      print("Import: Pulizia libreria corrente...");
      final List<Book> currentBooks = await _dbHelper.getAllBooks();
      // if (!mounted) return; // <-- RIMOSSO
      print("Import: ${currentBooks.length} libri esistenti da eliminare.");
      for (final book in currentBooks) {
         if (book.id != null) {
            try {
                // Chiama il metodo centralizzato per eliminare libro e file
                await _dbHelper.deleteBookAndFiles(book.id!);
                 // if (!mounted) return; // <-- RIMOSSO
            } catch (deleteError) { print("Import WARNING: Errore pulizia libro ID ${book.id}: $deleteError"); }
         }
      }
      print("Import: Libreria corrente pulita.");
      // if (!mounted) return; // <-- RIMOSSO


      // c. Importa Nuovi Dati
      print("Import: Inizio importazione...");
      final appDocDir = await getApplicationDocumentsDirectory();
      // if (!mounted) return; // <-- RIMOSSO
      int importedBookCount = 0;
      for (final bookData in booksToImport) {
        if (bookData is! Map<String, dynamic>) continue;
        String? finalCoverPath;
        // Copia copertina (usa percorsi normalizzati)
        String? coverRelativePath = bookData['coverImageRelativePath'] as String?;
        if (coverRelativePath != null) { coverRelativePath = p.normalize(coverRelativePath).replaceAll(r'\', '/'); if (extractedImagePaths.containsKey(coverRelativePath)) { final tempImagePath = extractedImagePaths[coverRelativePath]!; final newFileName = 'imported_${DateTime.now().millisecondsSinceEpoch}_${p.basename(coverRelativePath)}'; final newFinalPath = p.join(appDocDir.path, newFileName); try { await File(tempImagePath).copy(newFinalPath); finalCoverPath = newFinalPath; } catch (e) { print("Import WARNING: Errore copia copertina: $e"); } } else { print("Import WARNING: Copertina $coverRelativePath non trovata."); } }
        // Crea e inserisci libro
        final newBook = Book( title: bookData['title'] as String? ?? 'N/A', author: bookData['author'] as String? ?? 'N/A', publisher: bookData['publisher'] as String?, year: bookData['year'] as int?, isbn: bookData['isbn'] as String?, notes: bookData['notes'] as String?, coverImagePath: null);
        final newBookId = await _dbHelper.insertBook(newBook);
        // if (!mounted) return; // <-- RIMOSSO
        // Aggiorna con percorso copertina
        if (finalCoverPath != null) { await _dbHelper.updateBook(newBook.copyWith(id: newBookId, coverImagePath: finalCoverPath)); /*if (!mounted) return;*/ } // <-- RIMOSSO
        // Copia e inserisci immagini aggiuntive
        final additionalRelativePathsRaw = (bookData['additionalImagesRelativePaths'] as List?)?.cast<String>() ?? [];
        for (final relativePathRaw in additionalRelativePathsRaw) { String relativePath = p.normalize(relativePathRaw).replaceAll(r'\', '/'); if (extractedImagePaths.containsKey(relativePath)) { final tempImagePath = extractedImagePaths[relativePath]!; final newFileName = 'imported_${DateTime.now().millisecondsSinceEpoch}_${p.basename(relativePath)}'; final newFinalPath = p.join(appDocDir.path, newFileName); try { await File(tempImagePath).copy(newFinalPath); await _dbHelper.addAdditionalImage(newBookId, newFinalPath); /*if (!mounted) return;*/ } catch (e) { print("Import WARNING: Errore copia immagine agg.: $e"); } } else { print("Import WARNING: Immagine agg. $relativePath non trovata."); } }
        importedBookCount++;
      } // Fine ciclo import
      print("Import: Completato. $importedBookCount libri processati.");
      // Successo se arriva qui

    } catch (e) { // Gestione Errori _performImport
        print("Errore GRAVE durante _performImport: $e");
        throw Exception("Errore durante l'importazione: ${e.toString()}"); // Rilancia per UI
    } finally { // Pulizia Directory Temporanea
      if (tempExtractDir != null && await tempExtractDir.exists()) { /* ... pulizia temp dir ... */
        print("Import: Pulizia dir temp ${tempExtractDir.path}..."); try { await tempExtractDir.delete(recursive: true); print("Import: Dir temp pulita."); } catch (e) { print("Import WARNING: Impossibile pulire dir temp: $e"); }
      }
    }
  }

  // RIMOSSO _deleteFileQuietly da qui

} // Fine classe BackupService