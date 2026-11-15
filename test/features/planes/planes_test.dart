import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tecnicos_app/core/supabase/supabase_guard.dart';
import 'package:tecnicos_app/features/auth/data/models/tecnico_cercano_model.dart';
import 'package:tecnicos_app/features/perfil_puntos/data/models/perfil_tecnico_model.dart';
import 'package:tecnicos_app/features/perfil_puntos/domain/entities/perfil_tecnico.dart';
import 'package:tecnicos_app/features/planes/data/models/plan_model.dart';
import 'package:tecnicos_app/features/planes/domain/entities/plan.dart';

PerfilTecnico _perfil(Map<String, dynamic> extra) =>
    PerfilTecnicoModel.fromJson({
      'usuario_id': 't1',
      'tarifa_base': 10,
      'rango_cobertura_m': 12000,
      'rango_bonus_m': 1500,
      ...extra,
    }).aEntidad();

void main() {
  group('PlanModel', () {
    test('lee un plan con propuestas ilimitadas', () {
      final plan = PlanModel.desdeFila({
        'codigo': 'plus',
        'nombre': 'Plus',
        'precio_mensual': '12.00',
        'cotizaciones_mes': null,
        'rango_max_m': 30000,
        'oficios_max': 8,
        'prioridad': 3,
        'destacado': true,
      });

      expect(plan.cotizacionesMes, isNull);
      expect(plan.cotizacionesTexto, 'Propuestas ilimitadas');
      expect(plan.precioTexto, r'$12 al mes');
      expect(plan.rangoTexto, 'Hasta 30 km de rango');
      expect(plan.destacado, isTrue);
      expect(plan.esGratis, isFalse);
    });

    test('el plan Gratis muestra su tope de propuestas', () {
      final plan = PlanModel.desdeFila({
        'codigo': 'gratis',
        'nombre': 'Gratis',
        'precio_mensual': 0,
        'cotizaciones_mes': 15,
        'rango_max_m': 5000,
        'oficios_max': 3,
        'prioridad': 1,
        'destacado': false,
      });

      expect(plan.esGratis, isTrue);
      expect(plan.precioTexto, 'Gratis');
      expect(plan.cotizacionesTexto, '15 propuestas al mes');
      expect(plan.oficiosTexto, '3 oficios activos');
    });

    test('sin fila, mi plan es Gratis', () {
      final mio = PlanModel.miPlanDesdeFila(null);
      expect(mio.codigo, 'gratis');
      expect(mio.cotizacionesUsadas, 0);
      expect(mio.fin, isNull);
    });

    test('lee mi plan con su fecha de vencimiento', () {
      final mio = PlanModel.miPlanDesdeFila({
        'codigo': 'pro',
        'fin': '2026-12-15T10:00:00Z',
        'cotizaciones_usadas': 4,
      });
      expect(mio.codigo, 'pro');
      expect(mio.cotizacionesUsadas, 4);
      expect(mio.fin, isNotNull);
    });
  });

  group('LimitePlan', () {
    test('reconoce los códigos del servidor', () {
      expect(
        LimitePlan.desdeCodigo('plan:limite_cotizaciones'),
        LimitePlan.cotizaciones,
      );
      expect(LimitePlan.desdeCodigo('plan:limite_oficios'), LimitePlan.oficios);
      expect(LimitePlan.desdeCodigo('plan:fuera_de_rango'), LimitePlan.rango);
      expect(
        LimitePlan.desdeCodigo('plan:oficio_pausado'),
        LimitePlan.oficioPausado,
      );
      expect(LimitePlan.desdeCodigo('P0001'), isNull);
      expect(LimitePlan.desdeCodigo(null), isNull);
    });

    test('el código del error sale del HINT solo si es del plan', () {
      expect(
        codigoPostgrest(
          const PostgrestException(
            message: 'Ya enviaste las 15 propuestas',
            code: 'P0001',
            hint: 'plan:limite_cotizaciones',
          ),
        ),
        'plan:limite_cotizaciones',
      );
      expect(
        codigoPostgrest(
          const PostgrestException(
            message: 'x',
            code: '42501',
            hint: 'otra pista',
          ),
        ),
        '42501',
      );
    });
  });

  group('Perfil con plan', () {
    test('el rango usa el tope del plan y suma el bono encima', () {
      final perfil = _perfil({
        'plan_codigo': 'gratis',
        'plan_rango_max_m': 5000,
      });
      expect(perfil.planCodigo, 'gratis');
      expect(perfil.rangoEfectivoM, 6500);
    });

    test('si el rango elegido es menor que el tope, se respeta', () {
      final perfil = _perfil({
        'rango_cobertura_m': 3000,
        'plan_rango_max_m': 15000,
      });
      expect(perfil.rangoEfectivoM, 4500);
    });

    test('sin datos del plan no hay tope', () {
      expect(_perfil({}).rangoEfectivoM, 13500);
    });

    test('los oficios pausados no cuentan como activos', () {
      final perfil = _perfil({
        'plan_oficios_max': 3,
        'tecnico_oficios': [
          {'oficio_id': 1, 'tarifa_visita': 10, 'activo': true},
          {'oficio_id': 2, 'tarifa_visita': 12, 'activo': false},
          {'oficio_id': 3, 'tarifa_visita': 15},
        ],
      });
      expect(perfil.oficioIds, [1, 3]);
      expect(perfil.oficiosPausados, [2]);
      expect(perfil.oficiosMaxPlan, 3);
      // El precio del pausado se conserva para cuando lo reactive.
      expect(perfil.tarifaPara(2), 12);
    });
  });

  group('Técnico cercano', () {
    test('lee el plan y el sello destacado', () {
      final t = TecnicoCercanoModel.fromJson({
        'tecnico_id': 't9',
        'lat': -0.2,
        'lng': -78.5,
        'plan': 'plus',
        'destacado': true,
      }).aEntidad();
      expect(t.plan, 'plus');
      expect(t.destacado, isTrue);
      expect(t.prioridadPlan, 3);
    });

    test('sin datos del plan es Gratis y no destacado', () {
      final t = TecnicoCercanoModel.fromJson({
        'tecnico_id': 't9',
        'lat': -0.2,
        'lng': -78.5,
      }).aEntidad();
      expect(t.plan, 'gratis');
      expect(t.destacado, isFalse);
      expect(t.prioridadPlan, 1);
    });
  });
}
