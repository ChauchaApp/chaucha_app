import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/geo/geo_mapper.dart';
import '../../../../core/media/elegir_fotos.dart';
import '../../../../core/providers/core_providers.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/barra_accion.dart';
import '../../../../core/widgets/boton_carga.dart';
import '../../../../core/widgets/campos.dart';
import '../../../../core/widgets/encabezado_pantalla.dart';
import '../../../../core/widgets/mapa_ubicacion.dart';
import '../../../../core/widgets/mensajes.dart';
import '../../../../core/widgets/pantalla_secundaria.dart';
import '../../../../core/widgets/responsive_layout.dart';
import '../../../../core/widgets/seccion.dart';
import '../../../../core/widgets/tarjeta_app.dart';
import '../../../auth/presentation/providers/sesion_provider.dart';
import '../../../catalogo/domain/entities/oficio.dart';
import '../../../catalogo/presentation/providers/oficios_provider.dart';
import '../../../catalogo/presentation/widgets/icono_oficio.dart';
import '../../../perfil_puntos/presentation/views/aviso_verificacion_cliente.dart';
import '../../domain/entities/nueva_solicitud.dart';
import '../../domain/entities/vehiculo.dart';
import '../providers/crear_solicitud_provider.dart';
import '../widgets/solicitud_publicada.dart';

class CrearSolicitudView extends ConsumerStatefulWidget {
  const CrearSolicitudView({super.key, this.oficioId, this.descripcion});

  final int? oficioId;
  final String? descripcion;

  @override
  ConsumerState<CrearSolicitudView> createState() => _CrearSolicitudViewState();
}

class _CrearSolicitudViewState extends ConsumerState<CrearSolicitudView> {
  final _formKey = GlobalKey<FormState>();
  final _descripcion = TextEditingController();
  final _direccion = TextEditingController();
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _anio = TextEditingController();
  TipoVehiculo? _tipoVehiculo;

  int? _oficioId;
  LatLng _ubicacion = GeoMapper.quito;
  bool _buscandoGps = false;

  /// La ubicación vino del perfil (se avisa debajo del mapa).
  bool _desdePerfil = false;
  List<Uint8List> _fotos = const [];

  /// Id de la solicitud recién publicada: con él se muestra el éxito.
  String? _creadaId;

  @override
  void initState() {
    super.initState();
    _oficioId = widget.oficioId;
    _descripcion.text = widget.descripcion ?? '';
    // Arranca en la ubicación guardada en el perfil; solo sin ella se usa
    // el GPS.
    final guardada = ref.read(usuarioActualProvider)?.ubicacionRegistro;
    if (guardada != null) {
      _ubicacion = guardada;
      _desdePerfil = true;
    } else {
      unawaited(_buscarUbicacion());
    }
    unawaited(refrescarVerificacion(ref));
  }

  @override
  void dispose() {
    for (final c in [_descripcion, _direccion, _marca, _modelo, _anio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _obtenerUbicacion() {
    setState(() => _buscandoGps = true);
    return _buscarUbicacion();
  }

  Future<bool> _buscarUbicacion() async {
    final actual = await ref.read(ubicacionServiceProvider).obtenerActual();
    if (!mounted) return false;
    setState(() {
      _buscandoGps = false;
      if (actual != null) {
        _ubicacion = actual;
        _desdePerfil = false;
      }
    });
    return actual != null;
  }

  Future<void> _usarGps() async {
    final ok = await _obtenerUbicacion();
    if (!ok && mounted) {
      context.mostrarMensaje(
        'No pudimos obtener tu ubicación. Toca el mapa para marcarla.',
        tipo: TipoMensaje.error,
      );
    }
  }

  Future<void> _agregarFotos() async {
    final nuevas = await elegirFotos(
      context,
      maximo: NuevaSolicitud.maximoFotos - _fotos.length,
    );
    if (!mounted) return;
    setState(() {
      _fotos = [..._fotos, ...nuevas].take(NuevaSolicitud.maximoFotos).toList();
    });
  }

  void _quitarFoto(int indice) {
    setState(() => _fotos = [..._fotos]..removeAt(indice));
  }

  Future<void> _enviar() async {
    if (!await exigirVerificado(context, ref)) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final id = await ref
        .read(crearSolicitudProvider.notifier)
        .crear(
          oficioId: _oficioId,
          descripcion: _descripcion.text,
          direccion: _direccion.text,
          ubicacion: _ubicacion,
          fotos: _fotos,
          vehiculo: _esVehiculo ? _vehiculo() : null,
        );
    if (!mounted) return;
    if (id != null) {
      setState(() => _creadaId = id);
    } else if (ref.read(crearSolicitudProvider) case AsyncError(:final error)) {
      context.mostrarMensaje(
        AsyncValueView.mensajeDe(error),
        tipo: TipoMensaje.error,
      );
    }
  }

  /// El oficio elegido es de vehículos (mecánica, llantería...).
  bool get _esVehiculo {
    final oficios = ref.read(oficiosProvider).value ?? const <Oficio>[];
    return oficios.any((o) => o.id == _oficioId && o.esVehiculo);
  }

  Vehiculo _vehiculo() => Vehiculo(
    tipo: _tipoVehiculo,
    marca: _marca.text,
    modelo: _modelo.text,
    anio: int.tryParse(_anio.text.trim()),
  );

  static String? _validarAnio(String? v) {
    final texto = (v ?? '').trim();
    if (texto.isEmpty) return null;
    final anio = int.tryParse(texto);
    final maximo = DateTime.now().year + 1;
    if (anio == null || anio < 1950 || anio > maximo) {
      return 'Año entre 1950 y $maximo.';
    }
    return null;
  }

  /// Datos opcionales del vehículo, para que el técnico sepa qué llevar.
  Widget _datosVehiculo() {
    final textos = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Espacios.l),
        Text(
          'Datos del vehículo',
          style: textos.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          'Opcional · ayudan al técnico a saber qué llevar.',
          style: textos.bodySmall?.copyWith(color: Colores.tintaSuave),
        ),
        const SizedBox(height: Espacios.s),
        Wrap(
          spacing: Espacios.s,
          runSpacing: Espacios.s,
          children: [
            for (final tipo in TipoVehiculo.values)
              ChoiceChip(
                label: Text(tipo.etiqueta),
                selected: _tipoVehiculo == tipo,
                onSelected: (sel) =>
                    setState(() => _tipoVehiculo = sel ? tipo : null),
              ),
          ],
        ),
        const SizedBox(height: Espacios.m),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _marca,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Marca',
                  hintText: 'Chevrolet',
                ),
              ),
            ),
            const SizedBox(width: Espacios.m),
            Expanded(
              child: TextFormField(
                controller: _modelo,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Modelo',
                  hintText: 'Aveo',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Espacios.m),
        SizedBox(
          width: 160,
          child: TextFormField(
            controller: _anio,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              labelText: 'Año',
              hintText: '2015',
            ),
            validator: _validarAnio,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ya publicada: éxito en lugar del formulario.
    if (_creadaId case final id?) {
      return PantallaSecundaria(
        titulo: 'Solicitud publicada',
        cuerpo: SolicitudPublicada(
          onVerSolicitud: () => context.pop(id),
          onVolver: () => context.pop(),
        ),
      );
    }

    final publicando = ref.watch(crearSolicitudProvider).isLoading;
    final verificado = ref.watch(usuarioActualProvider)?.verificado ?? true;
    final aviso = verificado
        ? const SizedBox.shrink()
        : const Padding(
            padding: EdgeInsets.only(bottom: Espacios.l),
            child: AvisoVerificacionCliente(),
          );
    final escritorio = ResponsiveLayout.isDesktop(context);
    final boton = BotonCarga(
      texto: 'Publicar solicitud',
      icono: Icons.send_outlined,
      cargando: publicando,
      onPressed: _enviar,
    );

    const intro = Padding(
      padding: EdgeInsets.only(bottom: Espacios.xl),
      child: EncabezadoPantalla(
        titulo: 'Pide un técnico',
        subtitulo:
            'Cuéntanos qué pasa y recibe ofertas de técnicos '
            'cerca de ti.',
      ),
    );
    final servicio = BloqueTarjeta(
      numero: 1,
      titulo: 'Tipo de servicio',
      child: _selectorOficio(),
    );
    final problema = BloqueTarjeta(
      numero: 2,
      titulo: 'Describe el problema',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoEtiquetado(
            etiqueta: '¿Qué problema tienes?',
            child: TextFormField(
              controller: _descripcion,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: _esVehiculo
                    ? 'Ej.: el carro no arranca y hace un clic'
                    : 'Ej.: la llave del lavabo gotea desde ayer',
              ),
              validator: (v) =>
                  FormValidators.requerido(v, campo: 'La descripción'),
            ),
          ),
          if (_esVehiculo) _datosVehiculo(),
          const SizedBox(height: Espacios.l),
          CampoEtiquetado(
            etiqueta: 'Referencia de la dirección',
            ayuda: 'Opcional',
            child: TextFormField(
              controller: _direccion,
              decoration: const InputDecoration(
                hintText: 'Ej.: casa esquinera, portón negro',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
          ),
        ],
      ),
    );
    final ubicacion = BloqueTarjeta(
      numero: 3,
      titulo: 'Ubicación',
      subtitulo: 'Toca el mapa para mover el pin al lugar exacto.',
      child: _mapa(),
    );
    final fotos = BloqueTarjeta(
      numero: 4,
      titulo: 'Fotos del problema',
      subtitulo: 'Opcional · hasta ${NuevaSolicitud.maximoFotos} fotos',
      child: _fotosSeleccionadas(),
    );

    return PantallaSecundaria(
      titulo: 'Nueva solicitud',
      barraInferior: escritorio ? null : BarraAccion(child: boton),
      cuerpo: Form(
        key: _formKey,
        child: ScrollOpcional(
          padding: EdgeInsets.all(escritorio ? Espacios.xl : Espacios.l),
          child: AnchoMaximo(
            ancho: escritorio ? 1100 : 900,
            child: escritorio
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      aviso,
                      intro,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [servicio, problema, fotos],
                            ),
                          ),
                          const SizedBox(width: Espacios.xl),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [ubicacion, boton],
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      aviso,
                      intro,
                      servicio,
                      problema,
                      ubicacion,
                      fotos,
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Oficios como chips (se ven todos de un vistazo). Es un campo del
  /// formulario para validar que se elija uno.
  Widget _selectorOficio() {
    return AsyncValueView<List<Oficio>>(
      value: ref.watch(oficiosProvider),
      onRetry: () => ref.invalidate(oficiosProvider),
      onData: (context, oficios) => FormField<int>(
        initialValue: _oficioId,
        validator: (v) => v == null ? 'Selecciona el tipo de servicio.' : null,
        builder: (campo) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Espacios.s,
              runSpacing: Espacios.s,
              children: [
                for (final oficio in oficios)
                  ChoiceChip(
                    avatar: Icon(iconoOficio(oficio.nombre), size: 18),
                    label: Text(oficio.nombre),
                    selected: _oficioId == oficio.id,
                    onSelected: (_) {
                      setState(() => _oficioId = oficio.id);
                      campo.didChange(oficio.id);
                    },
                  ),
              ],
            ),
            if (campo.errorText case final error?)
              Padding(
                padding: const EdgeInsets.only(top: Espacios.s),
                child: Text(
                  error,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colores.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mapa() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MapaUbicacion(
          punto: _ubicacion,
          mostrarSector: true,
          onCambio: (punto) => setState(() {
            _ubicacion = punto;
            _desdePerfil = false;
          }),
        ),
        if (_desdePerfil) ...[
          const SizedBox(height: Espacios.s),
          Text(
            'Usamos la ubicación de tu perfil. Toca el mapa si el trabajo es '
            'en otro lugar.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colores.tintaSuave),
          ),
        ],
        const SizedBox(height: Espacios.m),
        OutlinedButton.icon(
          onPressed: _buscandoGps ? null : _usarGps,
          icon: const Icon(Icons.my_location),
          label: Text(_buscandoGps ? 'Buscando...' : 'Usar mi ubicación'),
        ),
      ],
    );
  }

  Widget _fotosSeleccionadas() {
    const lado = 96.0;
    final blanco = Theme.of(context).colorScheme.onPrimary;
    return Wrap(
      spacing: Espacios.s,
      runSpacing: Espacios.s,
      children: [
        for (var i = 0; i < _fotos.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radios.medio),
                child: Image.memory(
                  _fotos[i],
                  width: lado,
                  height: lado,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: Espacios.xs,
                top: Espacios.xs,
                child: Material(
                  color: Colores.tinta.withValues(alpha: 0.7),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _quitarFoto(i),
                    child: Padding(
                      padding: const EdgeInsets.all(Espacios.xs),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: blanco,
                        semanticLabel: 'Quitar foto',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (_fotos.length < NuevaSolicitud.maximoFotos)
          SizedBox.square(
            dimension: lado,
            child: Material(
              color: Colores.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radios.medio),
                side: const BorderSide(
                  color: Colores.primarioClaro,
                  width: 1.5,
                ),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radios.medio),
                ),
                onTap: _agregarFotos,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      color: Colores.primario,
                    ),
                    const SizedBox(height: Espacios.xs),
                    Text(
                      'Agregar',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: Colores.primario),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
