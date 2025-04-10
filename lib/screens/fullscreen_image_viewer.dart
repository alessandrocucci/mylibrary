import 'dart:io'; // Per File
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart'; // Importa il package
import 'package:photo_view/photo_view_gallery.dart'; // Importa la galleria

// Questo widget mostra una o più immagini a schermo intero con zoom/pan
class FullscreenImageViewer extends StatefulWidget {
  // Lista dei percorsi delle immagini da visualizzare
  final List<String> imagePaths;
  // Indice dell'immagine da mostrare inizialmente nella lista
  final int initialIndex;

  const FullscreenImageViewer({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0, // Default alla prima immagine
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late PageController _pageController; // Controller per gestire lo swipe tra immagini
  late int _currentIndex; // Indice dell'immagine attualmente visualizzata

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // Inizializza il PageController partendo dall'indice specificato
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose(); // Pulisci il controller
    super.dispose();
  }

  // Callback chiamato quando la pagina (immagine) cambia nello swipe
  void onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determina se abbiamo una sola immagine o una galleria
    final bool isGallery = widget.imagePaths.length > 1;

    return Scaffold(
      // Usiamo uno Stack per sovrapporre l'AppBar (se vogliamo) all'immagine
      body: Stack(
        children: <Widget>[
          // Il widget principale di photo_view per la galleria
          PhotoViewGallery.builder(
            // --- Configurazione Base ---
            itemCount: widget.imagePaths.length, // Numero di immagini
            pageController: _pageController, // Controller per lo swipe
            onPageChanged: onPageChanged, // Callback al cambio pagina
            scrollPhysics: const BouncingScrollPhysics(), // Effetto rimbalzo allo swipe

            // --- Costruttore per ogni Immagine ---
            builder: (context, index) {
              final imagePath = widget.imagePaths[index];
              // Usa FileImage per caricare da percorso locale
              final imageProvider = FileImage(File(imagePath));

              return PhotoViewGalleryPageOptions(
                // --- Visualizzazione Immagine Singola ---
                imageProvider: imageProvider,
                // Impostazioni di PhotoView per zoom/pan
                initialScale: PhotoViewComputedScale.contained * 0.98, // Scala iniziale (leggermente più piccola del contenuto)
                minScale: PhotoViewComputedScale.contained * 0.8,   // Scala minima zoom out
                maxScale: PhotoViewComputedScale.covered * 2.5,    // Scala massima zoom in
                heroAttributes: PhotoViewHeroAttributes(tag: imagePath), // Per animazione Hero (opzionale)
                // --- Gestione Errori Caricamento ---
                errorBuilder: (context, error, stackTrace) {
                   print("Errore caricamento immagine full-screen: $imagePath, Errore: $error");
                   return const Center(
                       child: Column(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: [
                            Icon(Icons.broken_image_outlined, size: 80, color: Colors.white54),
                            SizedBox(height: 16),
                            Text("Impossibile caricare l'immagine", style: TextStyle(color: Colors.white70)),
                         ],
                       ),
                   );
                },
                // --- Indicatore di Caricamento (opzionale) ---
                // loadingBuilder: (context, event) => const Center(
                //   child: SizedBox(
                //       width: 30.0,
                //       height: 30.0,
                //       child: CircularProgressIndicator(
                //           // value: event == null ? 0 : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1), // Mostra progresso
                //            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                //       ),
                //   ),
                // ),
              );
            },

            // --- Sfondo della Galleria ---
            backgroundDecoration: const BoxDecoration(color: Colors.black),

            // --- Indicatore di Pagina (pallini in basso) ---
            // Non necessario se c'è solo un'immagine, lo mostriamo condizionalmente
            // (lo mettiamo fuori dal PhotoViewGallery nello Stack per posizionarlo)
          ),

          // --- AppBar semi-trasparente in cima ---
          Positioned(
            top: 0.0,
            left: 0.0,
            right: 0.0,
            child: AppBar(
              backgroundColor: Colors.black.withOpacity(0.5), // Sfondo semi-trasparente
              elevation: 0, // Nessuna ombra
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(), // Torna indietro
              ),
              // Mostra il numero immagine corrente se è una galleria
              title: isGallery
                ? Text(
                    '${_currentIndex + 1} / ${widget.imagePaths.length}',
                    style: const TextStyle(color: Colors.white),
                  )
                : null, // Nessun titolo se immagine singola
              centerTitle: true,
            ),
          ),

          // --- Indicatore di Pagina (pallini) in basso (solo se galleria) ---
          if (isGallery)
             Positioned(
                bottom: 0.0,
                left: 0.0,
                right: 0.0,
                child: Container(
                  padding: const EdgeInsets.all(20.0),
                  // Usiamo una Row di cerchietti
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: widget.imagePaths.asMap().entries.map((entry) {
                        return Container(
                          width: 8.0,
                          height: 8.0,
                          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // Colore diverso per l'indicatore attivo
                            color: (Theme.of(context).colorScheme.secondary) // Usa un colore dal tema
                                .withOpacity(_currentIndex == entry.key ? 0.9 : 0.4), // Opacità diversa
                          ),
                        );
                      }).toList(),
                  ),
                ),
             ),
        ],
      ),
    );
  }
}