// Definisce le possibili opzioni di ordinamento per la lista dei libri
enum SortBy {
  titleAsc,       // Titolo A-Z (Default)
  titleDesc,      // Titolo Z-A
  authorAsc,      // Autore A-Z
  authorDesc,     // Autore Z-A
  yearAsc,        // Anno Crescente (i nulli potrebbero finire prima o dopo a seconda del DB)
  yearDesc,       // Anno Decrescente (i nulli potrebbero finire prima o dopo)
  // Potremmo aggiungere date di aggiunta/modifica in futuro
}