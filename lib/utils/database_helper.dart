import 'dart:async';
import 'dart:io'; // Necessario per File
import 'package:path/path.dart'; // Necessario per join
import 'package:path_provider/path_provider.dart'; // Necessario per getApplicationDocumentsDirectory
import 'package:sqflite/sqflite.dart'; // Package SQLite

// Importa modelli e utility locali
import '../models/book.dart';
import 'sort_options.dart';

class DatabaseHelper {
  // --- Costanti DB ---
  static const _databaseName = "MyLibrary.db";
  static const _databaseVersion = 1;

  // --- Nomi Tabelle e Colonne ---
  static const tableBooks = 'books';
  static const columnId = 'id';
  static const columnTitle = 'title';
  static const columnAuthor = 'author';
  static const columnPublisher = 'publisher';
  static const columnYear = 'year';
  static const columnIsbn = 'isbn';
  static const columnCoverImagePath = 'coverImagePath';
  static const columnNotes = 'notes';

  static const tableAdditionalImages = 'additional_images';
  static const columnImageId = 'id';
  static const columnBookId = 'book_id';
  static const columnImagePath = 'image_path';

  // --- Singleton ---
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // --- Inizializzazione DB ---
  _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onConfigure: (db) async { await db.execute('PRAGMA foreign_keys = ON'); print("Foreign keys enabled."); }
    );
  }

  // --- Creazione Tabelle ---
  Future _onCreate(Database db, int version) async {
    print("Creating database tables...");
    await db.execute(''' CREATE TABLE $tableBooks ( $columnId INTEGER PRIMARY KEY AUTOINCREMENT, $columnTitle TEXT NOT NULL, $columnAuthor TEXT NOT NULL, $columnPublisher TEXT, $columnYear INTEGER, $columnIsbn TEXT, $columnCoverImagePath TEXT, $columnNotes TEXT )''');
    await db.execute(''' CREATE TABLE $tableAdditionalImages ( $columnImageId INTEGER PRIMARY KEY AUTOINCREMENT, $columnBookId INTEGER NOT NULL, $columnImagePath TEXT NOT NULL, FOREIGN KEY ($columnBookId) REFERENCES $tableBooks ($columnId) ON DELETE CASCADE )''');
    print("Database tables created.");
  }

  // --- CRUD Libri ---
  Future<int> insertBook(Book book) async {
    Database db = await instance.database;
    return await db.insert(tableBooks, book.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Book?> getBook(int id) async {
    Database db = await instance.database;
    List<Map<String, dynamic>> maps = await db.query(tableBooks, where: '$columnId = ?', whereArgs: [id]);
    if (maps.isNotEmpty) { return Book.fromMap(maps.first); }
    return null;
  }

  Future<int> updateBook(Book book) async {
    Database db = await instance.database;
    if (book.id == null) throw ArgumentError("Cannot update book without ID");
    return await db.update(tableBooks, book.toMap(), where: '$columnId = ?', whereArgs: [book.id]);
  }

  // --- Metodi Immagini Aggiuntive ---
  Future<int> addAdditionalImage(int bookId, String imagePath) async {
    Database db = await instance.database;
    return await db.insert(tableAdditionalImages, {columnBookId: bookId, columnImagePath: imagePath});
  }

  Future<List<String>> getAdditionalImagesForBook(int bookId) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(tableAdditionalImages, columns: [columnImagePath], where: '$columnBookId = ?', whereArgs: [bookId]);
    if (maps.isEmpty) return [];
    return List.generate(maps.length, (i) => maps[i][columnImagePath] as String);
  }

  Future<int> deleteAdditionalImageByPath(String imagePath) async {
    Database db = await instance.database;
    return await db.delete(tableAdditionalImages, where: '$columnImagePath = ?', whereArgs: [imagePath]);
  }

  // --- Metodo getAllBooks (con Ricerca e Ordinamento) ---
  Future<List<Book>> getAllBooks({SortBy sortBy = SortBy.titleAsc, String? searchQuery}) async {
    Database db = await instance.database; String? whereClause; List<dynamic>? whereArgs; if (searchQuery != null && searchQuery.trim().isNotEmpty) { String query = '%${searchQuery.trim().toLowerCase()}%'; whereClause = 'LOWER($columnTitle) LIKE ? OR LOWER($columnAuthor) LIKE ?'; whereArgs = [query, query]; } String orderByClause; switch (sortBy) { case SortBy.titleDesc: orderByClause = '$columnTitle COLLATE NOCASE DESC'; break; case SortBy.authorAsc: orderByClause = '$columnAuthor COLLATE NOCASE ASC, $columnTitle COLLATE NOCASE ASC'; break; case SortBy.authorDesc: orderByClause = '$columnAuthor COLLATE NOCASE DESC, $columnTitle COLLATE NOCASE ASC'; break; case SortBy.yearAsc: orderByClause = '$columnYear IS NULL ASC, $columnYear ASC, $columnTitle COLLATE NOCASE ASC'; break; case SortBy.yearDesc: orderByClause = '$columnYear IS NULL ASC, $columnYear DESC, $columnTitle COLLATE NOCASE ASC'; break; case SortBy.titleAsc: default: orderByClause = '$columnTitle COLLATE NOCASE ASC'; break; } final List<Map<String, dynamic>> maps = await db.query(tableBooks, where: whereClause, whereArgs: whereArgs, orderBy: orderByClause); if (maps.isEmpty) return []; return List.generate(maps.length, (i) => Book.fromMap(maps[i]));
  }


  // ****************************************************************
  // *** METODI PER ELIMINAZIONE COMPLETA - ASSICURATI CHE CI SIANO ***
  // ****************************************************************

  /// Helper privato per eliminare un file in modo sicuro, ignorando errori.
  Future<void> _deleteFileQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        print("DB_Helper: File eliminato: $path");
      }
    } catch (e) {
      print("DB_Helper WARNING: Errore (ignorato) eliminazione file $path: $e");
    }
  }

  /// Elimina un libro dal database E i file immagine associati (copertina e aggiuntive).
  /// Restituisce il numero di righe eliminate dal database (dovrebbe essere 1 se successo).
  /// Lancia un'eccezione se il libro non viene trovato prima dell'eliminazione
  /// o se l'eliminazione dal DB fallisce.
  Future<int> deleteBookAndFiles(int id) async {
    print("DB_Helper: Inizio eliminazione completa per libro ID: $id");
    String? coverPathToDelete;
    List<String> additionalPathsToDelete = [];

    // 1. Recupera i percorsi dei file PRIMA di eliminare dal DB
    final bookToDelete = await getBook(id); // Usa il metodo esistente getBook
    if (bookToDelete == null) {
        print("DB_Helper ERROR: Libro con ID $id non trovato per l'eliminazione.");
        throw Exception("Libro con ID $id non trovato."); // Segnala l'errore
    }
    coverPathToDelete = bookToDelete.coverImagePath;
    // Recupera i percorsi aggiuntivi ANCHE QUI, nel caso il libro esista ma non abbia immagini aggiuntive
    additionalPathsToDelete = await getAdditionalImagesForBook(id);
    print("DB_Helper: Percorsi trovati - Copertina: $coverPathToDelete, Aggiuntive: ${additionalPathsToDelete.length}");

    // 2. Elimina il record del libro dal Database (CASCADE gestisce additional_images)
    final db = await instance.database;
    print("DB_Helper: Eliminazione record DB ID: $id...");
    final deletedRows = await db.delete(
      tableBooks,
      where: '$columnId = ?',
      whereArgs: [id],
    );
    print("DB_Helper: Righe DB eliminate: $deletedRows");

    // 3. Se l'eliminazione dal DB è andata a buon fine, elimina i file fisici
    if (deletedRows > 0) {
        print("DB_Helper: Eliminazione file fisici associati...");
        // Usa l'helper privato per cancellare i file
        await _deleteFileQuietly(coverPathToDelete);
        for (String path in additionalPathsToDelete) {
            await _deleteFileQuietly(path);
        }
        print("DB_Helper: Eliminazione file fisici completata.");
        return deletedRows; // Successo
    } else {
        // Errore: eliminazione DB fallita nonostante il libro esistesse
        print("DB_Helper ERROR: Eliminazione dal DB fallita per libro ID: $id (0 righe eliminate).");
        throw Exception("Eliminazione libro ID $id fallita nel database.");
    }
  }
  // ****************************************************************
  // ****************************************************************


  // --- Chiusura Database ---
  Future close() async {
     final db = await instance.database;
     _database = null; // Resetta per riapertura
     await db.close(); // Chiudi connessione DB
     print("Database connection closed.");
  }
} // Fine classe DatabaseHelper