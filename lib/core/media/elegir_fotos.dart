import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'selector_fotos.dart';

/// Pregunta de dónde sacar la foto: `true` cámara, `false` galería y `null`
/// si se cierra sin elegir.
Future<bool?> elegirOrigenFoto(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    ),
  );
}

/// Hasta [maximo] fotos. En la app pregunta si tomarla con la cámara o
/// elegirlas de la galería; en la web abre el selector del navegador, que en
/// el celular ya ofrece la cámara.
Future<List<Uint8List>> elegirFotos(
  BuildContext context, {
  required int maximo,
}) async {
  if (maximo <= 0) return const [];
  if (kIsWeb) return SelectorFotos.elegir(maximo: maximo);
  final camara = await elegirOrigenFoto(context);
  if (camara == null) return const [];
  if (!camara) return SelectorFotos.elegir(maximo: maximo);
  final foto = await SelectorFotos.una(camara: true);
  return foto == null ? const [] : [foto];
}
