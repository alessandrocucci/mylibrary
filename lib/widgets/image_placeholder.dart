import 'package:flutter/material.dart';

// Un widget riutilizzabile per mostrare un placeholder per le immagini.
class ImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final double iconSize;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final double borderRadius;

  const ImagePlaceholder({
    super.key,
    this.width,
    this.height,
    this.iconSize = 40.0, // Dimensione icona di default
    this.icon = Icons.book_outlined, // Icona di default
    this.backgroundColor = const Color(0xFFE0E0E0), // Grigio chiaro (Colors.grey[300])
    this.iconColor = const Color(0xFF9E9E9E), // Grigio medio (Colors.grey[500])
    this.borderRadius = 4.0, // Leggero arrotondamento angoli
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      // Decora il container con sfondo e bordi arrotondati
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        // Potremmo aggiungere un bordo leggero:
        // border: Border.all(color: Colors.grey[400]!, width: 0.5),
      ),
      // ClipRRect per assicurare che l'icona non esca dai bordi arrotondati
      child: ClipRRect(
         borderRadius: BorderRadius.circular(borderRadius),
         // Centra l'icona nel container
         child: Center(
           child: Icon(
             icon,
             size: iconSize,
             color: iconColor,
           ),
         ),
      ),
    );
  }
}