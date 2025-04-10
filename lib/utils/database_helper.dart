import 'dart:async'; // Per Future
import 'dart:io';   // Per Directory
import 'package:path/path.dart'; // Per join
import 'package:path_provider/path_provider.dart'; // Per getApplicationDocumentsDirectory
import 'package:sqflite/sqflite.dart'; // Package principale SQLite

// Importa i nostri modelli e utility
import '../models/book.dart';
import 'sort_options.dart'; // <-- Importa l'Enum SortBy che hai creato

// --- Classe DatabaseHelper ---
// Gestisce tutte le interazioni con il database SQLite locale.
class DatabaseHelper {
  // --- Nomi Costanti per DB, Tabelle e Colonne ---
  static const _databaseName = "MyLibrary.db";
  static const _databaseVersion = 1; // Incrementare se si modifica lo schema

  // Tabella Libri
  static const tableBooks = 'books';
  static const columnId = 'id';
  static const columnTitle = 'title';
  static const columnAuthor = 'author';
  static const columnPublisher = 'publisher';
  static const columnYear = 'year';
  static const columnIsbn = 'isbn';
  static const columnCoverImagePath = 'coverImagePath';
  static const columnNotes = 'notes';

  // Tabella Immagini Aggiuntive
  static const tableAdditionalImages = 'additional_images';
  static const columnImageId = 'id'; // ID univoco per l'immagine aggiuntiva
  static const columnBookId = 'book_id'; // Foreign key che collega a books.id
  static const columnImagePath = 'image_path'; // Percorso dell'immagine aggiuntiva


  // --- Singleton Pattern ---
  // Costruttore privato per impedire istanziazione diretta.
  DatabaseHelper._privateConstructor();
  // Istanza statica unica della classe.
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  // Riferimento al database (inizializzato lazy).
  static Database? _database;

  // Getter asincrono per l'istanza del database.
  Future<Database> get database async {
    // Se già inizializzato, ritorna l'istanza esistente.
    if (_database != null) return _database!;
    // Altrimenti, inizializza il database.
    _database = await _initDatabase();
    return _database!;
  }

  // --- Inizializzazione Database ---
  // Apre la connessione al database (lo crea se non esiste).
  _initDatabase() async {
    // Ottiene il percorso della directory documenti dell'app.
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName); // Costruisce il percorso del file DB.

    // Apre il database.
    return await openDatabase(
      path,
      version: _databaseVersion, // Versione dello schema.
      onCreate: _onCreate, // Metodo chiamato alla prima creazione.
      // Configurazione chiamata ogni volta che il DB viene aperto (anche dopo creato).
      // Ideale per abilitare funzionalità come le foreign keys.
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        print("Foreign keys enabled.");
      },
      // onUpgrade: _onUpgrade, // Da implementare se si cambia _databaseVersion
    );
  }

  // --- Creazione Tabelle (SQL) ---
  // Metodo eseguito solo la prima volta che il database viene creato.
  Future _onCreate(Database db, int version) async {
    print("Creating database tables...");
    // Crea tabella 'books'
    await db.execute('''
          CREATE TABLE $tableBooks (
            $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
            $columnTitle TEXT NOT NULL,
            $columnAuthor TEXT NOT NULL,
            $columnPublisher TEXT,
            $columnYear INTEGER,
            $columnIsbn TEXT,
            $columnCoverImagePath TEXT,
            $columnNotes TEXT
          )
          ''');
    // Crea tabella 'additional_images'
    await db.execute('''
          CREATE TABLE $tableAdditionalImages (
            $columnImageId INTEGER PRIMARY KEY AUTOINCREMENT,
            $columnBookId INTEGER NOT NULL,
            $columnImagePath TEXT NOT NULL,
            FOREIGN KEY ($columnBookId) REFERENCES $tableBooks ($columnId)
              ON DELETE CASCADE -- Importante per l'eliminazione a cascata
          )
          ''');
    print("Database tables created.");
  }

  // --- Metodi CRUD per i Libri (Books) ---

  // Inserisce un libro.
  Future<int> insertBook(Book book) async {
    Database db = await instance.database;
    // conflictAlgorithm.replace sovrascrive se l'ID esiste (utile per upsert)
    return await db.insert(tableBooks, book.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Recupera un libro per ID.
  Future<Book?> getBook(int id) async {
    Database db = await instance.database;
    List<Map<String, dynamic>> maps = await db.query(
      tableBooks,
      where: '$columnId = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Book.fromMap(maps.first);
    }
    return null;
  }

  // Aggiorna un libro esistente.
  Future<int> updateBook(Book book) async {
    Database db = await instance.database;
    if (book.id == null) {
      throw ArgumentError("Cannot update a book without an ID");
    }
    return await db.update(
      tableBooks,
      book.toMap(),
      where: '$columnId = ?',
      whereArgs: [book.id],
    );
  }

  // Elimina un libro per ID (CASCADE gestisce le immagini nel DB).
  Future<int> deleteBook(int id) async {
    Database db = await instance.database;
    print("Deleting book with ID: $id from database.");
    int result = await db.delete(
      tableBooks,
      where: '$columnId = ?',
      whereArgs: [id],
    );
    print("Deleted $result rows from $tableBooks for ID: $id");
    return result;
  }


  // ----- METODO getAllBooks AGGIORNATO PER RICERCA E ORDINAMENTO -----
  // Recupera tutti i libri, opzionalmente filtrati e ordinati.
  Future<List<Book>> getAllBooks({
    SortBy sortBy = SortBy.titleAsc, // Ordinamento di default: Titolo A-Z
    String? searchQuery,             // Termine di ricerca opzionale
  }) async {
    Database db = await instance.database;
    print("Fetching books. SortBy: $sortBy, SearchQuery: '$searchQuery'");

    String? whereClause;
    List<dynamic>? whereArgs;

    // Costruisci la clausola WHERE se c'è una query di ricerca.
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      String query = '%${searchQuery.trim().toLowerCase()}%'; // Aggiungi wildcard e minuscolo
      // Cerca la query nel titolo O nell'autore (case-insensitive)
      whereClause = 'LOWER($columnTitle) LIKE ? OR LOWER($columnAuthor) LIKE ?';
      whereArgs = [query, query];
      print("Applying WHERE clause: $whereClause with args: $whereArgs");
    }

    // Costruisci la clausola ORDER BY in base all'opzione `sortBy`.
    String orderByClause;
    switch (sortBy) {
      case SortBy.titleDesc:
        orderByClause = '$columnTitle COLLATE NOCASE DESC'; // COLLATE NOCASE per ordine non case-sensitive
        break;
      case SortBy.authorAsc:
        // Ordine primario per autore, secondario per titolo (per stabilità)
        orderByClause = '$columnAuthor COLLATE NOCASE ASC, $columnTitle COLLATE NOCASE ASC';
        break;
      case SortBy.authorDesc:
        orderByClause = '$columnAuthor COLLATE NOCASE DESC, $columnTitle COLLATE NOCASE ASC';
        break;
      case SortBy.yearAsc:
        // Mette i libri senza anno (NULL) per primi, poi ordina per anno crescente.
        orderByClause = '$columnYear IS NULL ASC, $columnYear ASC, $columnTitle COLLATE NOCASE ASC';
        break;
      case SortBy.yearDesc:
        // Mette i libri senza anno (NULL) per primi (o ultimi a seconda di come IS NULL è interpretato), poi ordina per anno decrescente.
        // Per metterli sempre per ultimi: $columnYear IS NOT NULL, $columnYear DESC ...
        orderByClause = '$columnYear IS NULL ASC, $columnYear DESC, $columnTitle COLLATE NOCASE ASC';
        break;
      case SortBy.titleAsc:
      default: // Caso di default e titleAsc
        orderByClause = '$columnTitle COLLATE NOCASE ASC';
        break;
    }
    print("Applying ORDER BY clause: $orderByClause");

    // Esegui la query al database.
    final List<Map<String, dynamic>> maps = await db.query(
      tableBooks,
      columns: null, // Seleziona tutte le colonne.
      where: whereClause, // Applica il filtro (se presente).
      whereArgs: whereArgs, // Argomenti per il filtro (se presente).
      orderBy: orderByClause, // Applica l'ordinamento.
    );

    print("Query returned ${maps.length} books.");

    // Se la query non restituisce risultati, ritorna una lista vuota.
    if (maps.isEmpty) {
      return [];
    }

    // Converte la lista di mappe (risultati DB) in una lista di oggetti Book.
    return List.generate(maps.length, (i) {
      return Book.fromMap(maps[i]);
    });
  }
  // ----- FINE METODO getAllBooks AGGIORNATO -----


  // --- Metodi per le Immagini Aggiuntive ---

  // Aggiunge un percorso immagine aggiuntiva.
  Future<int> addAdditionalImage(int bookId, String imagePath) async {
    Database db = await instance.database;
    print("Adding additional image for book ID $bookId: $imagePath");
    return await db.insert(tableAdditionalImages, {
      columnBookId: bookId,
      columnImagePath: imagePath,
    });
  }

  // Recupera tutti i percorsi immagine aggiuntivi per un libro.
  Future<List<String>> getAdditionalImagesForBook(int bookId) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableAdditionalImages,
      columns: [columnImagePath], // Seleziona solo la colonna del percorso.
      where: '$columnBookId = ?',
      whereArgs: [bookId],
    );
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) => maps[i][columnImagePath] as String);
  }

  // Elimina un record immagine aggiuntiva dato il suo percorso.
  Future<int> deleteAdditionalImageByPath(String imagePath) async {
    Database db = await instance.database;
    print("Deleting additional image record by path: $imagePath");
    int result = await db.delete(
      tableAdditionalImages,
      where: '$columnImagePath = ?',
      whereArgs: [imagePath],
    );
     print("Deleted $result rows from $tableAdditionalImages for path: $imagePath");
    return result;
  }

  // (Non serve deleteAllAdditionalImagesForBook se ON DELETE CASCADE è attivo).

  // --- Chiusura Database ---
  // Chiude la connessione al database.
  Future close() async {
    final db = await instance.database;
    print("Closing database connection.");
    _database = null; // Resetta la variabile statica.
    db.close();
  }
}