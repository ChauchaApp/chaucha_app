import 'package:flutter_test/flutter_test.dart';
import 'package:tecnicos_app/features/chat/domain/entities/resumen_chat.dart';

ResumenChat _chat(
  String conversacionId, {
  String otroId = 't1',
  String? oficio,
  String? ultimoMensaje,
  int? dia,
}) => ResumenChat(
  conversacionId: conversacionId,
  otroNombre: 'Juan Pérez',
  esMio: false,
  otroId: otroId,
  oficio: oficio,
  ultimoMensaje: ultimoMensaje,
  enviadoEn: dia == null ? null : DateTime(2026, 11, dia),
);

void main() {
  group('ResumenChat.agruparPorPersona', () {
    test('dos solicitudes con el mismo técnico dan un solo chat', () {
      final chats = ResumenChat.agruparPorPersona([
        _chat(
          'k2',
          oficio: 'Electricidad',
          ultimoMensaje: 'Mañana voy',
          dia: 16,
        ),
        _chat('k1', oficio: 'Plomería', ultimoMensaje: 'Gracias', dia: 10),
      ]);

      expect(chats, hasLength(1));
      final chat = chats.single;
      expect(chat.conversacionId, 'k2');
      expect(chat.ultimoMensaje, 'Mañana voy');
      expect(chat.enviadoEn, DateTime(2026, 11, 16));
      expect(chat.ids, ['k2', 'k1']);
      expect(chat.oficio, 'Electricidad, Plomería');
    });

    test('no repite el oficio si las dos solicitudes son del mismo', () {
      final chats = ResumenChat.agruparPorPersona([
        _chat('k2', oficio: 'Plomería', dia: 16),
        _chat('k1', oficio: 'Plomería', dia: 10),
      ]);

      expect(chats.single.oficio, 'Plomería');
    });

    test('personas distintas siguen en filas separadas y en orden', () {
      final chats = ResumenChat.agruparPorPersona([
        _chat('k3', otroId: 't2', dia: 17),
        _chat('k2', dia: 16),
        _chat('k1', dia: 10),
      ]);

      expect([for (final c in chats) c.conversacionId], ['k3', 'k2']);
      expect(chats.first.ids, ['k3']);
    });

    test('sin otroId conocido no junta conversaciones', () {
      final chats = ResumenChat.agruparPorPersona([
        _chat('k2', otroId: ''),
        _chat('k1', otroId: ''),
      ]);

      expect(chats, hasLength(2));
    });
  });
}
