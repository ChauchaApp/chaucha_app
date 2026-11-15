import 'package:latlong2/latlong.dart';

import '../../../../core/geo/geo_mapper.dart';
import '../../../../core/utils/json_utils.dart';
import '../../domain/entities/perfil_tecnico.dart';

class PerfilTecnicoModel {
  const PerfilTecnicoModel({
    required this.usuarioId,
    required this.tarifaBase,
    required this.rangoCoberturaM,
    required this.puntos,
    required this.calificacionPromedio,
    required this.totalResenas,
    required this.verificado,
    required this.nivelNombre,
    required this.comisionPorcentaje,
    required this.oficioIds,
    this.tarifas = const {},
    this.ubicacionActual,
    this.rangoBonusM = 0,
    this.planCodigo = 'gratis',
    this.rangoMaxPlanM,
    this.oficiosMaxPlan,
    this.oficiosPausados = const [],
  });

  factory PerfilTecnicoModel.fromJson(Map<String, dynamic> json) {
    final nivel = anidado(json['niveles_gamificacion']);
    final filas = ((json['tecnico_oficios'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>();
    // Sin la columna `activo` (datos viejos), todos cuentan como activos.
    bool activo(Map<String, dynamic> f) => f['activo'] as bool? ?? true;
    final oficios = filas.where(activo);
    return PerfilTecnicoModel(
      usuarioId: json['usuario_id'] as String,
      tarifaBase: aDouble(json['tarifa_base']),
      rangoCoberturaM: aInt(json['rango_cobertura_m'], porDefecto: 5000),
      rangoBonusM: aInt(json['rango_bonus_m']),
      ubicacionActual: GeoMapper.fromDb(json['ubicacion_actual']),
      puntos: aInt(json['puntos']),
      calificacionPromedio: aDouble(json['calificacion_promedio']),
      totalResenas: aInt(json['total_resenas']),
      verificado: json['verificado'] as bool? ?? false,
      nivelNombre: nivel?['nombre'] as String? ?? 'Sin nivel',
      comisionPorcentaje: aDouble(nivel?['comision_porcentaje']),
      oficioIds: [for (final fila in oficios) aInt(fila['oficio_id'])],
      oficiosPausados: [
        for (final fila in filas)
          if (!activo(fila)) aInt(fila['oficio_id']),
      ],
      planCodigo: json['plan_codigo'] as String? ?? 'gratis',
      rangoMaxPlanM: json['plan_rango_max_m'] == null
          ? null
          : aInt(json['plan_rango_max_m']),
      oficiosMaxPlan: json['plan_oficios_max'] == null
          ? null
          : aInt(json['plan_oficios_max']),
      tarifas: {
        for (final fila in filas)
          if (fila['tarifa_visita'] != null)
            aInt(fila['oficio_id']): aDouble(fila['tarifa_visita']),
      },
    );
  }

  /// Columnas que se piden en el `select`, con los joins a nivel y oficios.
  static const String columnas =
      'usuario_id, tarifa_base, rango_cobertura_m, rango_bonus_m, '
      'ubicacion_actual, puntos, calificacion_promedio, total_resenas, '
      'verificado, niveles_gamificacion(nombre, comision_porcentaje), '
      'tecnico_oficios(oficio_id, tarifa_visita, activo), '
      'plan_codigo, plan_rango_max_m, plan_oficios_max';

  final String usuarioId;
  final double tarifaBase;
  final int rangoCoberturaM;
  final int rangoBonusM;
  final LatLng? ubicacionActual;
  final int puntos;
  final double calificacionPromedio;
  final int totalResenas;
  final bool verificado;
  final String nivelNombre;
  final double comisionPorcentaje;
  final List<int> oficioIds;
  final Map<int, double> tarifas;
  final String planCodigo;
  final int? rangoMaxPlanM;
  final int? oficiosMaxPlan;
  final List<int> oficiosPausados;

  PerfilTecnico aEntidad() => PerfilTecnico(
    usuarioId: usuarioId,
    tarifaBase: tarifaBase,
    rangoCoberturaM: rangoCoberturaM,
    rangoBonusM: rangoBonusM,
    ubicacionActual: ubicacionActual,
    puntos: puntos,
    calificacionPromedio: calificacionPromedio,
    totalResenas: totalResenas,
    verificado: verificado,
    nivelNombre: nivelNombre,
    comisionPorcentaje: comisionPorcentaje,
    oficioIds: oficioIds,
    tarifas: tarifas,
    planCodigo: planCodigo,
    rangoMaxPlanM: rangoMaxPlanM,
    oficiosMaxPlan: oficiosMaxPlan,
    oficiosPausados: oficiosPausados,
  );
}
