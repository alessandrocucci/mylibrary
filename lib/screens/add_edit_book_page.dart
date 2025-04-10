import 'dart:io'; // Per File
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Per TextInputFormatters
import 'package:image_picker/image_picker.dart'; // Per selezionare immagini
import 'package:path_provider/path_provider.dart'; // Per salvare immagini localmente
import 'package:path/path.dart' as p; // Per manipolare percorsi (rinominato con 'p')

// Importa modello, DB Helper e widget comuni
import '../models/book.dart';
import '../utils/database_helper.dart';
import '../widgets/image_placeholder.dart'; // <-- NUOVO IMPORT del Placeholder

class AddEditBookPage extends StatefulWidget {
  // Libro esistente da modificare (null se si aggiunge)
  final Book? book;

  const AddEditBookPage({super.key, this.book});

  @override
  State<AddEditBookPage> createState() => _AddEditBookPageState();
}

class _AddEditBookPageState extends State<AddEditBookPage> {
  final _formKey = GlobalKey<FormState>(); // Chiave per il Form

  // Controller per i campi di testo
  late TextEditingController _titleController;
  late TextEditingController _authorController;
  late TextEditingController _publisherController;
  late TextEditingController _yearController;
  late TextEditingController _isbnController;
  late TextEditingController _notesController;

  // Gestione Immagini
  XFile? _selectedCoverImageFile;     // Nuovo file copertina selezionato
  String? _existingCoverImagePath;    // Percorso copertina esistente (in modifica)
  List<String> _existingAdditionalImagePaths = []; // Percorsi aggiuntivi esistenti
  final List<XFile> _selectedAdditionalImageFiles = []; // Nuovi file aggiuntivi selezionati

  bool _isLoading = false; // Flag per stato di caricamento/salvataggio

  @override
  void initState() {
    super.initState();

    // Inizializza controller con dati esistenti (se in modifica)
    final book = widget.book;
    _titleController = TextEditingController(text: book?.title ?? '');
    _authorController = TextEditingController(text: book?.author ?? '');
    _publisherController = TextEditingController(text: book?.publisher ?? '');
    _yearController = TextEditingController(text: book?.year?.toString() ?? '');
    _isbnController = TextEditingController(text: book?.isbn ?? '');
    _notesController = TextEditingController(text: book?.notes ?? '');
    _existingCoverImagePath = book?.coverImagePath;

    // Carica percorsi immagini aggiuntive esistenti (se in modifica)
    if (book != null && book.id != null) {
      _loadAdditionalImages(book.id!);
    }
  }

  @override
  void dispose() {
    // Pulisci tutti i controller
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _yearController.dispose();
    _isbnController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // Carica percorsi immagini aggiuntive dal DB
  Future<void> _loadAdditionalImages(int bookId) async {
    if (!mounted) return;
    try {
      final paths = await DatabaseHelper.instance.getAdditionalImagesForBook(bookId);
      if (mounted) {
        setState(() { _existingAdditionalImagePaths = paths; });
      }
    } catch (e) {
      print("Errore caricamento immagini aggiuntive nel form: $e");
      // Gestire errore? Mostrare SnackBar?
    }
  }

  // --- Logica Selezione Immagini ---

  Future<void> _pickCoverImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1000); // Qualità/Dimensione opzionali
      if (pickedFile != null && mounted) {
        setState(() { _selectedCoverImageFile = pickedFile; });
      }
    } catch (e) {
      print("Errore selezione copertina: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore selezione immagine.')));
    }
  }

  Future<void> _pickAdditionalImages() async {
    final ImagePicker picker = ImagePicker();
    try {
      final List<XFile> pickedFiles = await picker.pickMultiImage(imageQuality: 75, maxWidth: 1200); // Qualità/Dimensione opzionali
      if (pickedFiles.isNotEmpty && mounted) {
        setState(() { _selectedAdditionalImageFiles.addAll(pickedFiles); });
      }
    } catch (e) {
      print("Errore selezione immagini multiple: $e");
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore selezione immagini.')));
    }
  }

  // --- Logica Salvataggio ---

  Future<void> _saveBook() async {
    // 1. Valida il form
    if (!_formKey.currentState!.validate()) {
      return; // Interrompi se non valido
    }

    if (mounted) setState(() { _isLoading = true; }); // Mostra overlay caricamento

    String? finalCoverImagePath = _existingCoverImagePath;
    bool coverImageChanged = false;

    try {
      // 2. Gestione Immagine Copertina
      if (_selectedCoverImageFile != null) { // Se è stata scelta una NUOVA copertina
        final newPath = await _saveImageLocally(_selectedCoverImageFile!);
        if (newPath != null) {
          coverImageChanged = true; // Segna che è cambiata
          finalCoverImagePath = newPath; // Aggiorna il percorso da salvare
        } else {
          throw Exception("Errore salvataggio nuova copertina."); // Errore salvataggio file
        }
      }

      // Se la copertina NON è stata cambiata MA quella esistente è stata rimossa dall'utente
      // ( _selectedCoverImageFile è null e _existingCoverImagePath è null)
      // allora finalCoverImagePath è già null e va bene così.

      // 3. Crea o Aggiorna Oggetto Book
      final bookToSave = Book(
        id: widget.book?.id, // ID esistente o null
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        publisher: _publisherController.text.trim().nullIfEmpty, // Estensione helper sotto
        year: int.tryParse(_yearController.text),
        isbn: _isbnController.text.trim().nullIfEmpty,
        coverImagePath: finalCoverImagePath, // Percorso finale della copertina
        notes: _notesController.text.trim().nullIfEmpty,
        // dateAdded non gestito qui, andrebbe messo in insertBook nel DB Helper
      );

      // 4. Salva nel Database
      int savedBookId;
      final dbHelper = DatabaseHelper.instance;
      if (widget.book == null) {
        savedBookId = await dbHelper.insertBook(bookToSave);
        print("Nuovo libro inserito con ID: $savedBookId");
      } else {
        await dbHelper.updateBook(bookToSave);
        savedBookId = bookToSave.id!;
        print("Libro aggiornato con ID: $savedBookId");
        // Se la copertina è cambiata, elimina il vecchio file ORA che il DB è aggiornato
        if (coverImageChanged && _existingCoverImagePath != null) {
             await _deleteFileQuietly(_existingCoverImagePath!);
        }
        // Se la copertina è stata rimossa (final è null ma existing non lo era)
        else if (finalCoverImagePath == null && _existingCoverImagePath != null){
             await _deleteFileQuietly(_existingCoverImagePath!);
        }

      }

      // 5. Salva NUOVE Immagini Aggiuntive
      if (_selectedAdditionalImageFiles.isNotEmpty) {
        print("Salvataggio ${_selectedAdditionalImageFiles.length} nuove immagini aggiuntive...");
        for (var imageFile in _selectedAdditionalImageFiles) {
          final newPath = await _saveImageLocally(imageFile);
          if (newPath != null) {
            await dbHelper.addAdditionalImage(savedBookId, newPath);
          } // Gestire errore salvataggio singolo file aggiuntivo?
        }
      }

      // 6. Successo: mostra messaggio e torna indietro
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Libro "${bookToSave.title}" salvato!'), backgroundColor: Colors.green));
        Navigator.of(context).pop(true); // Ritorna true per aggiornare la lista
      }

    } catch (e, stacktrace) { // Gestione Errori
      print("Errore salvataggio libro: $e");
      print(stacktrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante il salvataggio: $e'), backgroundColor: Colors.red));
      }
    } finally { // Assicura che l'indicatore venga nascosto
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  // --- Helper per File Immagine ---
  Future<String?> _saveImageLocally(XFile imageFile) async { /* ... come prima ... */
     try { final Directory appDocDir = await getApplicationDocumentsDirectory(); final String fileName = p.basename(imageFile.path); final String timestamp = DateTime.now().millisecondsSinceEpoch.toString(); final String uniqueFileName = '${timestamp}_$fileName'; final String localPath = p.join(appDocDir.path, uniqueFileName); final File localFile = File(localPath); await localFile.writeAsBytes(await imageFile.readAsBytes()); print("Immagine salvata in: $localPath"); return localPath; } catch (e) { print("Errore salvataggio file: $e"); return null; }
  }
  Future<void> _deleteFileQuietly(String? path) async { /* ... come prima ... */
    if (path == null || path.isEmpty) return; try { final file = File(path); if (await file.exists()) { await file.delete(); print("File eliminato: $path"); } } catch (e) { print("Errore (ignorato) eliminazione file $path: $e"); }
  }

  // --- Gestione Rimozione Immagini dal Form ---
  void _removeNewAdditionalImage(XFile fileToRemove) { setState(() { _selectedAdditionalImageFiles.remove(fileToRemove); }); }
  Future<void> _removeExistingAdditionalImage(String pathToRemove) async { /* ... come prima, con dialogo conferma ... */
      bool confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Conferma'), content: const Text('Rimuovere questa immagine?'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')), TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Rimuovi'))])) ?? false;
      if (confirm && mounted) { setState(() { _isLoading = true; _existingAdditionalImagePaths.remove(pathToRemove); }); try { await DatabaseHelper.instance.deleteAdditionalImageByPath(pathToRemove); await _deleteFileQuietly(pathToRemove); } catch (e) { print("Errore rimozione img esistente: $e"); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore rimozione immagine.'), backgroundColor: Colors.red)); /* Rimetti in lista? */ } finally { if (mounted) setState(() { _isLoading = false; }); } }
  }
  void _removeCoverImage() {
    setState(() {
        _selectedCoverImageFile = null; // Rimuovi nuova selezione
        // Segna che la copertina esistente (se c'era) va rimossa al salvataggio
        // La rimozione effettiva del file avviene in _saveBook
        _existingCoverImagePath = null;
    });
 }

  // --- Costruzione Interfaccia Utente ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book == null ? 'Aggiungi Libro' : 'Modifica Libro'),
        actions: [
          // Pulsante Salva (disabilitato durante il caricamento)
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Salva',
            onPressed: _isLoading ? null : _saveBook,
          ),
        ],
      ),
      // --- Stack per Overlay Caricamento ---
      body: Stack(
        children: [
          // Contenuto principale del form (scrollabile)
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Campi di testo (Title, Author obbligatori)
                  TextFormField(controller: _titleController, decoration: const InputDecoration(labelText: 'Titolo *', hintText: 'Es. Orgoglio e Pregiudizio', border: OutlineInputBorder()), validator: (v) => (v == null || v.trim().isEmpty) ? 'Il titolo è obbligatorio.' : null, textInputAction: TextInputAction.next),
                  const SizedBox(height: 16.0),
                  TextFormField(controller: _authorController, decoration: const InputDecoration(labelText: 'Autore *', hintText: 'Es. Jane Austen', border: OutlineInputBorder()), validator: (v) => (v == null || v.trim().isEmpty) ? 'L\'autore è obbligatorio.' : null, textInputAction: TextInputAction.next),
                  const SizedBox(height: 16.0),
                  TextFormField(controller: _publisherController, decoration: const InputDecoration(labelText: 'Editore', hintText: 'Es. Garzanti (Ed. 1985)', border: OutlineInputBorder()), textInputAction: TextInputAction.next),
                  const SizedBox(height: 16.0),
                  TextFormField(controller: _yearController, decoration: const InputDecoration(labelText: 'Anno Edizione', hintText: 'Es. 1985', border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], textInputAction: TextInputAction.next),
                  const SizedBox(height: 16.0),
                  TextFormField(controller: _isbnController, decoration: const InputDecoration(labelText: 'ISBN', hintText: 'Es. 978-8804681100', border: OutlineInputBorder()), textInputAction: TextInputAction.next),
                  const SizedBox(height: 24.0),

                  // --- Sezione Copertina (USA PLACEHOLDER) ---
                  Text('Copertina', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8.0),
                  _buildCoverImagePicker(), // Helper che usa placeholder
                  const SizedBox(height: 24.0),

                  // --- Sezione Immagini Aggiuntive (USA PLACEHOLDER) ---
                  Text('Immagini Aggiuntive', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8.0),
                  _buildAdditionalImagePicker(), // Helper che usa placeholder
                  const SizedBox(height: 24.0),

                  // Campo Note
                  TextFormField(controller: _notesController, decoration: const InputDecoration(labelText: 'Note Personali', hintText: 'Es. Trovato al mercatino...', border: OutlineInputBorder(), alignLabelWithHint: true), maxLines: 4, textInputAction: TextInputAction.done),
                  const SizedBox(height: 24.0),

                  // Pulsante Salva alternativo (in fondo al form)
                  // ElevatedButton.icon(
                  //   icon: Icon(Icons.save),
                  //   label: Text('Salva Libro'),
                  //   onPressed: _isLoading ? null : _saveBook,
                  //   style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12)),
                  // ),
                ],
              ),
            ),
          ), // Fine SingleChildScrollView

          // --- Overlay di Caricamento (MODIFICATO) ---
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5), // Sfondo scuro semi-trasparente
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          // --- Fine Overlay ---

        ],
      ), // Fine Stack
    );
  }

  // --- Helper Widget per Selezione Copertina (MODIFICATO CON PLACEHOLDER) ---
  Widget _buildCoverImagePicker() {
    Widget imageWidget;

    if (_selectedCoverImageFile != null) { // Priorità 1: Nuova immagine selezionata
      imageWidget = Image.file(File(_selectedCoverImageFile!.path), fit: BoxFit.contain);
    } else if (_existingCoverImagePath != null && _existingCoverImagePath!.isNotEmpty) { // Priorità 2: Immagine esistente
      imageWidget = Image.file(File(_existingCoverImagePath!), fit: BoxFit.contain,
        // Placeholder per errore caricamento immagine esistente
        errorBuilder: (c, e, s) => const ImagePlaceholder(height: 150, icon: Icons.error_outline, iconSize: 50, iconColor: Colors.redAccent),
      );
    } else { // Priorità 3: Nessuna immagine -> Placeholder
      imageWidget = const ImagePlaceholder(
        height: 150,
        icon: Icons.add_a_photo_outlined, // Icona per aggiungere foto
        iconSize: 50,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, // Allarga pulsanti
      children: [
        // Anteprima
        Container(
          height: 150,
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12.0),
          // Aggiungi un bordo per delimitare l'area anche se c'è il placeholder
           decoration: BoxDecoration(
             border: Border.all(color: Colors.grey.shade400, width: 1),
             borderRadius: BorderRadius.circular(4.0),
           ),
           child: ClipRRect( // Arrotonda contenuto (immagine o placeholder)
                borderRadius: BorderRadius.circular(3.0), // Leggermente meno del bordo
                child: imageWidget
           ),
        ),
        // Pulsanti Galleria/Camera
        Row(
          children: [
            Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.photo_library_outlined), label: const Text('Galleria'), onPressed: () => _pickCoverImage(ImageSource.gallery))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.camera_alt_outlined), label: const Text('Fotocamera'), onPressed: () => _pickCoverImage(ImageSource.camera))),
          ],
        ),
        // Pulsante Rimuovi (solo se c'è un'immagine)
        if (_selectedCoverImageFile != null || (_existingCoverImagePath != null && _existingCoverImagePath!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Rimuovi Copertina', style: TextStyle(color: Colors.red)),
              onPressed: _removeCoverImage, // Chiama la funzione dedicata
            ),
          ),
      ],
    );
  }


  // --- Helper Widget per Galleria Aggiuntive (MODIFICATO CON PLACEHOLDER) ---
  Widget _buildAdditionalImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Griglia Immagini
        if (_existingAdditionalImagePaths.isNotEmpty || _selectedAdditionalImageFiles.isNotEmpty)
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8.0, mainAxisSpacing: 8.0),
            itemCount: _existingAdditionalImagePaths.length + _selectedAdditionalImageFiles.length,
            itemBuilder: (context, index) {
              Widget imageWidget;
              bool isExistingImage = index < _existingAdditionalImagePaths.length;
              String heroTag; // Tag univoco per animazione Hero

              if (isExistingImage) { // Immagine esistente
                final path = _existingAdditionalImagePaths[index];
                heroTag = path; // Usa il percorso come tag
                imageWidget = Image.file(File(path), fit: BoxFit.cover,
                  // Placeholder per errore
                  errorBuilder: (c,e,s) => const ImagePlaceholder(icon: Icons.broken_image_outlined, iconSize: 24)
                );
              } else { // Nuova immagine selezionata
                final file = _selectedAdditionalImageFiles[index - _existingAdditionalImagePaths.length];
                heroTag = file.path; // Usa il percorso temporaneo come tag
                imageWidget = Image.file(File(file.path), fit: BoxFit.cover);
              }

              // Tile della griglia con immagine e pulsante elimina sovrapposto
              return Hero( // Aggiungi Hero qui
                tag: heroTag,
                child: GridTile(
                  footer: GridTileBar( // Barra in basso semi-trasparente
                    backgroundColor: Colors.black45,
                    trailing: IconButton( // Pulsante elimina
                      icon: const Icon(Icons.delete, color: Colors.white, size: 18),
                      tooltip: 'Rimuovi',
                      padding: EdgeInsets.zero, // Riduci padding
                      constraints: const BoxConstraints(), // Riduci vincoli dimensione
                      onPressed: () { // Chiama la funzione appropriata
                        if (isExistingImage) { _removeExistingAdditionalImage(_existingAdditionalImagePaths[index]); }
                        else { _removeNewAdditionalImage(_selectedAdditionalImageFiles[index - _existingAdditionalImagePaths.length]); }
                      },
                    ),
                  ),
                  child: ClipRRect( // Arrotonda angoli
                      borderRadius: BorderRadius.circular(4.0),
                      child: imageWidget
                  ),
                ),
              );
            },
          ),

        const SizedBox(height: 16),
        // Pulsante Aggiungi Immagini
        ElevatedButton.icon(
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Aggiungi Immagini'),
          onPressed: _pickAdditionalImages,
        ),
      ],
    );
  }

} // Fine _AddEditBookPageState


// Piccola estensione helper per trasformare stringhe vuote in null
extension StringExtension on String {
  String? get nullIfEmpty {
    return isEmpty ? null : this;
  }
}