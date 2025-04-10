// ignore_for_file: public_member_api_docs, sort_constructors_first
// Disabilito temporaneamente alcuni avvisi lint per la leggibilità iniziale

// Definizione della struttura dati per un singolo libro della collezione.
class Book {
  // L'ID univoco del libro nel database.
  // È nullable (int?) perché un libro appena creato (prima di salvarlo)
  // non ha ancora un ID assegnato dal database.
  final int? id;

  // Il titolo del libro. È obbligatorio.
  final String title;

  // L'autore/autrice del libro. È obbligatorio.
  final String author;

  // L'editore del libro. Opzionale.
  final String? publisher;

  // L'anno di pubblicazione o dell'edizione specifica. Opzionale.
  final int? year;

  // Il codice ISBN del libro. Opzionale, specialmente per edizioni vintage.
  final String? isbn;

  // Il percorso locale sul dispositivo dove è salvata l'immagine di copertina.
  // È nullable perché un libro potrebbe non avere una copertina associata.
  final String? coverImagePath;

  // Eventuali note o commenti personali sul libro. Opzionale.
  final String? notes;

  // Costruttore della classe Book.
  // Usa le parentesi graffe {} per i parametri nominali.
  // `required` indica i campi obbligatori.
  const Book({
    this.id,
    required this.title,
    required this.author,
    this.publisher,
    this.year,
    this.isbn,
    this.coverImagePath,
    this.notes,
  });

  // Metodo per creare una COPIA dell'oggetto Book con alcune proprietà modificate.
  // Utile ad esempio quando si aggiorna un libro, per non modificare l'originale
  // direttamente (buona pratica di immutabilità).
  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? publisher,
    int? year,
    String? isbn,
    String? coverImagePath,
    String? notes,
  }) {
    return Book(
      // Usa il valore esistente se un nuovo valore non è fornito
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      publisher: publisher ?? this.publisher,
      year: year ?? this.year,
      isbn: isbn ?? this.isbn,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      notes: notes ?? this.notes,
    );
  }


  // Metodo per convertire un oggetto Book in una Map<String, dynamic>.
  // Questo è necessario per poter inserire/aggiornare i dati nel database SQLite,
  // che lavora con mappe di chiavi (nomi colonne) e valori.
  Map<String, dynamic> toMap() {
    // Nota: l'ID non viene incluso qui quando si crea una nuova riga,
    // perché è AUTOINCREMENT. Ma potremmo volerlo includere per gli update.
    // Per semplicità ora lo includiamo sempre, sqflite gestirà l'insert
    // correttamente ignorando l'id se è null, e usandolo per l'update se presente.
    return <String, dynamic>{
      'id': id,
      'title': title,
      'author': author,
      'publisher': publisher,
      'year': year,
      'isbn': isbn,
      'coverImagePath': coverImagePath,
      'notes': notes,
    };
  }

  // Metodo factory per creare un oggetto Book a partire da una Map<String, dynamic>.
  // Questo serve quando leggiamo i dati dal database SQLite.
  // 'factory' significa che il costruttore non crea necessariamente una nuova istanza,
  // ma può restituirne una esistente o eseguire logica prima di crearla.
  // Qui lo usiamo per fare il parsing pulito dalla mappa del database.
  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      // Legge i valori dalla mappa usando le chiavi (nomi delle colonne).
      // È importante che queste chiavi corrispondano esattamente ai nomi
      // delle colonne che definiremo nella tabella SQLite.
      id: map['id'] != null ? map['id'] as int : null,
      title: map['title'] as String,
      author: map['author'] as String,
      publisher: map['publisher'] != null ? map['publisher'] as String : null,
      year: map['year'] != null ? map['year'] as int : null,
      isbn: map['isbn'] != null ? map['isbn'] as String : null,
      coverImagePath: map['coverImagePath'] != null ? map['coverImagePath'] as String : null,
      notes: map['notes'] != null ? map['notes'] as String : null,
    );
  }

  // --- Metodi Utili per Debug e Confronto (Opzionali ma Raccomandati) ---

  // Override del metodo toString() per avere una rappresentazione leggibile
  // dell'oggetto Book quando lo stampiamo (es. per debug).
  @override
  String toString() {
    return 'Book(id: $id, title: $title, author: $author, publisher: $publisher, year: $year, isbn: $isbn, coverImagePath: $coverImagePath, notes: $notes)';
  }

  // Override dell'operatore di uguaglianza (==).
  // Permette di confrontare due oggetti Book basandosi sui loro contenuti
  // e non solo sulla loro identità in memoria (es. `book1 == book2`).
  @override
  bool operator ==(covariant Book other) {
    if (identical(this, other)) return true; // Se sono lo stesso oggetto in memoria

    return
      other.id == id &&
      other.title == title &&
      other.author == author &&
      other.publisher == publisher &&
      other.year == year &&
      other.isbn == isbn &&
      other.coverImagePath == coverImagePath &&
      other.notes == notes;
  }

  // Override di hashCode.
  // Se si sovrascrive l'operatore ==, è buona norma sovrascrivere anche hashCode
  // per garantire che oggetti uguali abbiano lo stesso codice hash (fondamentale
  // per l'uso in Set o come chiavi in Map).
  @override
  int get hashCode {
    return id.hashCode ^
      title.hashCode ^
      author.hashCode ^
      publisher.hashCode ^
      year.hashCode ^
      isbn.hashCode ^
      coverImagePath.hashCode ^
      notes.hashCode;
  }
}