-- Semilla de demostración de ChauchaApp: 60 técnicos y 90 clientes en todo
-- Quito (norte, centro, sur y valles), con historial completo.
--
-- Se ejecuta por secciones (cada "-- @@" es una llamada). La contraseña de
-- las cuentas NO va en el repo: reemplaza __CLAVE__ al ejecutar.
-- Las cuentas usan el dominio @semilla.chaucha.app.
--
-- Las historias pasan por las mismas funciones que la app (iniciar_chat,
-- enviar_tarifa, aceptar_cotizacion, crear_reclamo), así respetan las
-- reglas reales: rango y tope del plan, choques de horario y reseñas solo
-- de servicios completados.

-- @@ 1. Borrar todo menos el admin
begin;
create temp table _fuera on commit drop as
  select id from public.usuarios where rol is distinct from 'admin';
delete from public.resenas;
delete from public.comisiones;
delete from public.historial_puntos;
delete from public.mensajes;
delete from public.conversaciones;
delete from public.cotizaciones;
delete from public.solicitudes_servicio;
delete from public.eventos;
delete from public.notificaciones;
delete from auth.users where id in (select id from _fuera);
commit;

-- @@ 2. Funciones auxiliares (temporales, viven en esta sesión)
create or replace function pg_temp.como(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
           case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, false),
         set_config('request.jwt.claim.sub', coalesce(p::text, ''), false);
$$;

-- Hora de Ecuador: hoy + p_dias, a las p_hora.
create or replace function pg_temp.hora_ec(p_dias int, p_hora numeric) returns timestamptz language sql as $$
  select (date_trunc('day', now() at time zone 'America/Guayaquil')
          + make_interval(days => p_dias) + make_interval(mins => (p_hora * 60)::int))
         at time zone 'America/Guayaquil';
$$;

-- Primer horario libre (1 h) para técnico y cliente entre esos días.
create or replace function pg_temp.slot_libre(p_tec uuid, p_cli uuid, p_dmin int, p_dmax int)
returns timestamptz language plpgsql as $$
declare t timestamptz; k int;
begin
  for k in 1..200 loop
    t := pg_temp.hora_ec(p_dmin + floor(random() * (p_dmax - p_dmin + 1))::int,
                         (array[8, 9, 10, 11, 14, 15, 16, 17])[1 + floor(random() * 8)::int]);
    if not exists (
         select 1 from public.cotizaciones c join public.solicitudes_servicio s on s.id = c.solicitud_id
          where c.inicio_visita is not null and c.estado in ('pendiente', 'aceptada')
            and (c.tecnico_id = p_tec or s.cliente_id = p_cli)
            and tstzrange(c.inicio_visita, c.fin_visita) && tstzrange(t, t + interval '1 hour')) then
      return t;
    end if;
  end loop;
  raise exception 'sin horario libre';
end $$;

-- @@ 3. Usuarios, perfiles, oficios, planes, pagos y certificaciones
do $$
declare
  nombres_h text[] := array['Andrés','Carlos','Diego','Fernando','Gabriel','Javier','Jorge','José Luis',
    'Juan Carlos','Luis','Marco','Mateo','Miguel','Pablo','Patricio','Ricardo','Santiago','Sebastián',
    'Xavier','Wilson','Édison','Byron','Christian','Freddy','Hernán','Bryan','Darwin','Fabián','Galo',
    'Iván','Jaime','Kevin','Leonardo','Manuel','Nelson','Óscar','Rafael','Roberto','Segundo','Stalin',
    'Vicente','Washington','Alex','Danilo','Esteban','Franklin','Geovanny','Henry'];
  nombres_m text[] := array['Ana','Andrea','Belén','Carla','Carolina','Cristina','Daniela','Diana',
    'Gabriela','Jessica','Johanna','Karina','Lorena','María José','María Fernanda','Mónica','Paola',
    'Paulina','Silvia','Sofía','Valeria','Verónica','Ximena','Estefanía','Camila','Alexandra','Elena',
    'Fernanda','Gissela','Isabel','Janeth','Katherine','Lucía','Marcela','Natalia','Patricia','Rocío',
    'Sandra','Tatiana','Vanessa','Wendy','Yolanda','Adriana','Bertha','Cecilia','Doris','Erika','Fátima'];
  apellidos text[] := array['Andrade','Benítez','Cevallos','Chávez','Espinosa','Guerrero','Herrera',
    'Jácome','León','Mora','Naranjo','Ortiz','Paredes','Pazmiño','Proaño','Quishpe','Ruiz','Salazar',
    'Tapia','Torres','Vásconez','Villacís','Yépez','Zambrano','Carrera','Cueva','Morales','Gallegos',
    'Almeida','Calderón','Pilataxi','Chiluisa','Tipán','Guamán','Simbaña','Toapanta','Cabascango',
    'Lema','Sánchez','Rodríguez','Vega','Flores','Castillo','Romero','Jaramillo','Montalvo','Rosero',
    'Báez','Endara','Haro','Iza','Loachamín','Molina','Narváez','Oña','Pinto','Rivadeneira','Suárez'];
  -- [barrio, lat, lng, peso]: todo Quito, más gente donde vive más gente.
  barrios jsonb := '[
    ["Carcelén",-0.0905,-78.4735,3],["Comité del Pueblo",-0.1150,-78.4640,3],["El Condado",-0.1035,-78.5030,3],
    ["Cotocollao",-0.1150,-78.4985,3],["Ponceano",-0.1095,-78.4860,2],["San Carlos",-0.1300,-78.5010,2],
    ["La Kennedy",-0.1490,-78.4790,2],["El Inca",-0.1555,-78.4700,2],["Quito Tennis",-0.1605,-78.4950,2],
    ["Monteserrín",-0.1700,-78.4600,1],["Rumipamba",-0.1700,-78.4950,2],["Iñaquito",-0.1760,-78.4850,3],
    ["La Carolina",-0.1850,-78.4850,3],["El Batán",-0.1800,-78.4700,2],["Bellavista",-0.1900,-78.4750,2],
    ["Las Casas",-0.1950,-78.5050,2],["La Gasca",-0.2000,-78.5040,2],["La Mariscal",-0.2030,-78.4920,3],
    ["Guápulo",-0.2030,-78.4780,1],["La Floresta",-0.2100,-78.4850,2],["San Juan",-0.2150,-78.5120,2],
    ["Centro Histórico",-0.2200,-78.5120,3],["La Tola",-0.2220,-78.5050,2],["San Blas",-0.2150,-78.5060,1],
    ["Chimbacalle",-0.2450,-78.5180,2],["Villaflora",-0.2480,-78.5200,2],["La Magdalena",-0.2520,-78.5300,3],
    ["El Recreo",-0.2550,-78.5220,2],["Solanda",-0.2700,-78.5400,3],["Chillogallo",-0.2800,-78.5550,3],
    ["La Ecuatoriana",-0.2900,-78.5550,2],["Quitumbe",-0.2950,-78.5450,3],["Guamaní",-0.3300,-78.5500,2],
    ["Conocoto",-0.2900,-78.4800,3],["San Rafael",-0.3000,-78.4550,2],["Cumbayá",-0.2000,-78.4300,3],
    ["Tumbaco",-0.2120,-78.4000,2],["Nayón",-0.1650,-78.4400,1],["Calderón",-0.1000,-78.4200,3],
    ["Carapungo",-0.0950,-78.4450,2],["Pomasqui",-0.0500,-78.4550,2]]';
  -- Oficios por popularidad (los de hogar primero).
  oficios_peso int[] := array[1,1,1,2,2,2,5,5,4,3,6,7,7,8,8,9,10,20,20,15,17,11,12,13,14,16,18,19,21,21,22,23,24];
  pool_barrios int[] := '{}';
  i int; k int; uid uuid; es_h boolean; nombre text; ap1 text; ap2 text; base text; v_email text;
  ced text; dig int[]; suma int; v int; b jsonb; lat float8; lng float8; meta jsonb;
  ofs int[]; n_of int; o int; plan text; tarifa numeric; inicio timestamptz; sus uuid; n_h int := 0; n_m int := 0;
begin
  perform setseed(0.2026);
  for k in 0..jsonb_array_length(barrios) - 1 loop
    for v in 1..(barrios->k->>3)::int loop pool_barrios := pool_barrios || k; end loop;
  end loop;

  for i in 1..150 loop
    -- 1..60 técnicos (45 hombres, 15 mujeres); 61..150 clientes (mitad y mitad).
    es_h := case when i <= 60 then i <= 45 else i % 2 = 0 end;
    if es_h then n_h := n_h + 1; nombre := nombres_h[1 + (n_h - 1) % array_length(nombres_h, 1)];
    else n_m := n_m + 1; nombre := nombres_m[1 + (n_m - 1) % array_length(nombres_m, 1)]; end if;
    ap1 := apellidos[1 + floor(random() * array_length(apellidos, 1))::int];
    ap2 := apellidos[1 + floor(random() * array_length(apellidos, 1))::int];
    base := lower(translate(split_part(nombre, ' ', 1) || '.' || ap1, 'áéíóúÁÉÍÓÚñÑü', 'aeiouAEIOUnNu'));
    v_email := base || '@semilla.chaucha.app';
    k := 2;
    while exists (select 1 from auth.users au where au.email = v_email) loop
      v_email := base || k || '@semilla.chaucha.app'; k := k + 1;
    end loop;
    -- Cédula de Pichincha válida (módulo 10).
    loop
      dig := array[1, 7, floor(random() * 6)::int];
      for k in 4..9 loop dig := dig || floor(random() * 10)::int; end loop;
      suma := 0;
      for k in 1..9 loop
        v := dig[k] * case when k % 2 = 1 then 2 else 1 end;
        suma := suma + case when v > 9 then v - 9 else v end;
      end loop;
      ced := array_to_string(dig, '') || ((10 - suma % 10) % 10)::text;
      exit when not exists (select 1 from public.identidades where cedula = ced);
    end loop;
    b := barrios->pool_barrios[1 + floor(random() * array_length(pool_barrios, 1))::int];
    lat := (b->>1)::float8 + (random() - 0.5) * 0.012;
    lng := (b->>2)::float8 + (random() - 0.5) * 0.012;
    uid := gen_random_uuid();
    meta := jsonb_build_object('rol', case when i <= 60 then 'tecnico' else 'cliente' end, 'cedula', ced,
      'nombres', nombre, 'apellidos', ap1 || ' ' || ap2, 'ciudad', 'Quito',
      'genero', case when es_h then 'h' else 'm' end, 'barrio', b->>0);
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, email_change_token_current, phone_change, phone_change_token,
      reauthentication_token)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', v_email,
      extensions.crypt('__CLAVE__', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', meta,
      now() - make_interval(days => 120 + floor(random() * 120)::int), now(), '', '', '', '', '', '', '', '');
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (uid, uid, jsonb_build_object('sub', uid, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());

    update public.usuarios set foto_perfil_ruta = uid || '/perfil.jpg', foto_rostro_validada = true,
      verificado_manual = true, ciudad = 'Quito', verificacion_vista = true,
      ubicacion_registro = st_setsrid(st_makepoint(lng, lat), 4326)::geography,
      creado_en = (select created_at from auth.users where id = uid)
    where id = uid;

    if i <= 60 then
      -- Planes: 8 Plus, 12 Pro, 40 Gratis.
      plan := case when i % 15 in (1, 8) then 'plus' when i % 5 = 2 then 'pro' else 'gratis' end;
      tarifa := (array[12, 15, 15, 18, 20, 20, 20, 25, 25, 30])[1 + floor(random() * 10)::int];
      update public.perfiles_tecnicos set tarifa_base = tarifa,
        rango_cobertura_m = (array[5000, 8000, 10000, 12000, 15000])[1 + floor(random() * 5)::int],
        ubicacion_actual = st_setsrid(st_makepoint(lng, lat), 4326)::geography
      where usuario_id = uid;
      if plan <> 'gratis' then
        inicio := now() - make_interval(days => 2 + floor(random() * 25)::int);
        insert into public.suscripciones (tecnico_id, plan_codigo, inicio, fin, origen)
        values (uid, plan, inicio, inicio + interval '30 days', 'pago');
      end if;
      -- Oficios: Gratis 1-3, Pro 2-4, Plus 3-6 (sin pasar el tope del plan).
      n_of := case plan when 'plus' then 3 + floor(random() * 4)::int
                        when 'pro' then 2 + floor(random() * 3)::int
                        else 1 + floor(random() * 3)::int end;
      -- Solo hay 4 oficios de vehículos.
      if i between 3 and 10 then n_of := least(n_of, 4); end if;
      ofs := '{}';
      -- Los primeros 8 técnicos hombres son mecánicos (oficios de vehículos).
      if i between 3 and 10 then ofs := array[(array[21, 21, 22, 23, 24, 21, 22, 24])[i - 2]]; end if;
      while coalesce(array_length(ofs, 1), 0) < n_of loop
        o := case when i between 3 and 10 then (array[21, 22, 23, 24])[1 + floor(random() * 4)::int]
                  else oficios_peso[1 + floor(random() * array_length(oficios_peso, 1))::int] end;
        if not o = any(ofs) then ofs := ofs || o; end if;
      end loop;
      foreach o in array ofs loop
        insert into public.tecnico_oficios (tecnico_id, oficio_id, tarifa_visita)
        values (uid, o, case when o >= 21 then tarifa + 10 else tarifa end
                        + (array[0, 0, 0, 5, -3, 5, 10])[1 + floor(random() * 7)::int]);
      end loop;
      -- Certificaciones: 1 de cada 3 técnicos tiene una aprobada; algunos, una pendiente.
      if i % 3 = 0 then
        insert into public.certificaciones_tecnico (tecnico_id, nombre, entidad, anio, ruta_archivo, estado, revisado_en)
        values (uid,
          (array['Técnico en instalaciones eléctricas', 'Plomería y gasfitería residencial',
                 'Mantenimiento de electrodomésticos', 'Instalación de sistemas de gas',
                 'Seguridad y salud en el trabajo', 'Mecánica automotriz básica',
                 'Pintura y acabados de construcción', 'Refrigeración y climatización'])[1 + floor(random() * 8)::int],
          (array['SECAP', 'SECAP', 'Instituto Tecnológico Central Técnico', 'CEFOSER', 'Cámara de la Construcción de Quito'])[1 + floor(random() * 5)::int],
          2015 + floor(random() * 11)::int, uid || '/certificado.pdf', 'aprobada', now() - interval '20 days');
      elsif i % 7 = 0 then
        insert into public.certificaciones_tecnico (tecnico_id, nombre, entidad, anio, ruta_archivo, estado)
        values (uid, 'Curso de electricidad domiciliaria', 'SECAP', 2025, uid || '/certificado.pdf', 'pendiente');
      end if;
    end if;
    perform public.recalcular_verificacion(uid);
  end loop;

end $$;

-- @@ 4. Historias: solicitudes en todos los estados, chats, tickets,
-- agenda, cierres y reseñas. Necesita las funciones de la sección 2.
do $$
declare
  textos jsonb := '{
    "1": ["Se rompió la llave de paso de la cocina y gotea sin parar.", "El inodoro no deja de correr agua desde ayer.", "Hay una fuga debajo del lavamanos del baño.", "La ducha casi no tiene presión, creo que es la tubería.", "Se tapó el desagüe del lavaplatos."],
    "2": ["Se fue la luz en la mitad del departamento y el breaker se baja solo.", "Necesito instalar tres tomacorrientes nuevos en la sala.", "Los focos del pasillo parpadean y huele a quemado.", "Quiero cambiar el tablero eléctrico, es muy antiguo."],
    "3": ["Se cuarteó una pared del patio y entra humedad.", "Necesito resanar el filo de las gradas de entrada.", "Quiero levantar un muro pequeño para la lavandería."],
    "4": ["La puerta del dormitorio no cierra, está descuadrada.", "Arreglar las bisagras de los muebles de cocina.", "Quiero un mueble de madera a medida para el televisor."],
    "5": ["Quiero pintar la sala y el comedor, unos 40 m².", "Hay manchas de humedad en el techo del baño.", "Pintar la fachada de la casa, dos pisos."],
    "6": ["Me quedé fuera de la casa, se trabó la cerradura.", "Cambiar la chapa de la puerta principal por una de seguridad."],
    "7": ["El calefón se prende y se apaga a los pocos minutos.", "El calefón hace clic pero no prende la llama.", "Mantenimiento del calefón, hace dos años no lo revisan."],
    "8": ["La lavadora no centrifuga y deja la ropa empapada.", "La refrigeradora no enfría la parte de abajo.", "La secadora hace un ruido fuerte al girar."],
    "9": ["Limpieza profunda del departamento antes de la mudanza.", "Limpieza de alfombras y muebles de la sala."],
    "10": ["Cortar el césped y podar los arbustos del jardín.", "Sembrar plantas en las jardineras de la entrada."],
    "11": ["Soldar la puerta metálica del garaje que se desprendió.", "Reforzar la reja de la ventana del patio."],
    "12": ["Se rompió el vidrio de la ventana de la sala.", "Instalar una mampara de vidrio en la ducha."],
    "13": ["Hay cucarachas en la cocina, necesito fumigar.", "Fumigación de la casa antes de mudarnos."],
    "14": ["Se filtra agua por la losa cuando llueve.", "Impermeabilizar la terraza antes del invierno."],
    "15": ["El aire acondicionado de la oficina gotea agua.", "Mantenimiento de dos equipos split."],
    "16": ["Instalar cielo raso de gypsum en la sala.", "Se cayó una parte del cielo raso del baño."],
    "17": ["Instalar 4 cámaras de seguridad en la casa.", "Una cámara dejó de grabar y no aparece en el celular."],
    "18": ["Mudanza de un departamento de dos habitaciones.", "Llevar una refrigeradora y una cama al otro lado de la ciudad."],
    "19": ["Retapizar un juego de sala de tres piezas.", "Cambiar la tela de cuatro sillas del comedor."],
    "20": ["Varias cositas: colgar cuadros, cambiar focos y arreglar una repisa.", "Revisar goteras del techo antes del invierno."],
    "21": ["El carro no prende en las mañanas, creo que es la batería o el arranque.", "Suena un golpeteo en la suspensión delantera.", "Necesito el cambio de aceite y revisión de frenos."],
    "22": ["La moto pierde fuerza en las subidas.", "Mantenimiento general de una moto de 150 cc."],
    "23": ["Las luces del carro se apagan solas.", "No funcionan los vidrios eléctricos del lado del conductor."],
    "24": ["Se me bajó una llanta en la casa, no tengo repuesto.", "Cambiar dos llantas y alinear."]
  }';
  explicaciones jsonb := '{"hogar": ["Reviso el problema en sitio, le explico qué hay que hacer y el costo antes de empezar.", "Hago un diagnóstico, llevo herramientas y repuestos comunes para resolverlo en la misma visita.", "Primero evalúo la causa para no gastar de más. Si hace falta material, se lo detallo antes."], "vehiculos": ["Voy a donde está el vehículo con mis herramientas y hago el diagnóstico con escáner.", "Reviso en sitio, le digo qué repuesto necesita y, si es rápido, lo arreglo ahí mismo."]}';
  chat_c text[] := array['Hola, buenas. Vi su propuesta, ¿me puede contar un poco más?', 'Hola, ¿cuándo podría venir a ver?', 'Buenas tardes, ¿el precio incluye la revisión?', 'Hola, ¿tiene disponibilidad esta semana?'];
  chat_t text[] := array['Hola, claro. Primero hago una revisión y le explico qué hay que hacer.', 'Buenas, sí. Puedo pasar esta semana, usted me dice el horario.', 'Hola, sí incluye. Si hace falta material se lo detallo antes.', 'Con gusto. Tengo espacio en las mañanas.'];
  chat_c2 text[] := array['Perfecto, me parece bien. ¿Me manda el ticket con la fecha?', 'Listo, entonces le espero. Mándeme el ticket por favor.', 'Ok, de acuerdo. ¿Qué día tiene libre?'];
  chat_t2 text[] := array['Ya le envío el ticket. Cualquier cosa me escribe por aquí.', 'Le mando el ticket ahora mismo.', 'Tengo espacio, le envío la propuesta de fecha.'];
  cierre_t text[] := array['Listo, ya quedó funcionando. Gracias por la confianza.', 'Trabajo terminado. Cualquier novedad me avisa.'];
  cierre_c text[] := array['Muchas gracias, quedó muy bien.', 'Gracias, todo perfecto.', 'Excelente, muy agradecida.'];
  com_t text[] := array['Muy puntual y explicó todo.', 'Excelente trabajo, lo recomiendo.', 'Dejó todo limpio y funcionando.', 'Buen precio y muy amable.', 'Resolvió el problema rápido.', 'Muy profesional.', null, null];
  com_c text[] := array['Muy amable, todo claro.', 'Cliente puntual y respetuoso.', null, null, null];
  etq_t text[] := array['Puntual', 'Trabajo limpio', 'Buen trato', 'Buen precio', 'Resolvió el problema', 'Buena comunicación'];
  etq_c text[] := array['Amable', 'Explicó bien el problema', 'Estuvo disponible', 'Respetuoso', 'Acceso fácil'];
  -- G completada, F por confirmar, E agendada, D ticket enviado, C chat,
  -- B postulaciones, A abierta, H cancelada.
  plan_tipos text[];
  v_tipo text; cli record; vip uuid[]; sol uuid; ofi int; descr text; lat float8; lng float8; veh jsonb;
  n_post int; tecs uuid[]; t uuid; cid uuid; conv uuid; precio numeric; fecha timestamptz; s_t timestamptz;
  lineas int; k int; intento int; nota int; etq text[]; com text; hrs int; malas jsonb := '{}';
  g_vip int := 0; autor uuid; dest uuid; para_t boolean;
begin
  perform setseed(0.7);
  plan_tipos := array_fill('G'::text, array[120]) || array_fill('F'::text, array[8]) || array_fill('E'::text, array[22])
             || array_fill('D'::text, array[12]) || array_fill('C'::text, array[15]) || array_fill('B'::text, array[22])
             || array_fill('A'::text, array[25]) || array_fill('H'::text, array[10]);
  select array_agg(u.id order by u.id) into vip from (
    select u.id from public.usuarios u join auth.users a on a.id = u.id
     where a.email like '%@semilla.chaucha.app' and u.rol = 'cliente' order by u.id limit 3) u;

  foreach v_tipo in array plan_tipos loop
    for intento in 1..8 loop
      -- Cliente (los VIP se llevan 5 cierres cada uno) y oficio.
      if v_tipo = 'G' and g_vip < 15 then
        select u.id, st_y(u.ubicacion_registro::geometry) lat, st_x(u.ubicacion_registro::geometry) lng into cli
          from public.usuarios u where u.id = vip[1 + g_vip % 3];
      else
        select u.id, st_y(u.ubicacion_registro::geometry) lat, st_x(u.ubicacion_registro::geometry) lng into cli
          from public.usuarios u join auth.users a on a.id = u.id
         where a.email like '%@semilla.chaucha.app' and u.rol = 'cliente' order by random() limit 1;
      end if;
      lat := cli.lat + (random() - 0.5) * 0.006;
      lng := cli.lng + (random() - 0.5) * 0.006;
      -- Oficio que alguien cerca ofrece.
      select t2.oficio_id into ofi from public.tecnico_oficios t2
        join public.perfiles_tecnicos p on p.usuario_id = t2.tecnico_id and t2.activo
        cross join lateral public.plan_de(p.usuario_id) pl
       where st_dwithin(p.ubicacion_actual, st_setsrid(st_makepoint(lng, lat), 4326)::geography,
                        least(least(p.rango_cobertura_m, pl.rango_max_m) + p.rango_bonus_m, 50000))
       order by random() limit 1;
      n_post := case v_tipo when 'A' then 0 when 'H' then floor(random() * 2)::int
                when 'B' then 1 + floor(random() * 3)::int else 1 + floor(random() * 2)::int end;
      -- Técnicos que llegan (rango del plan) y con propuestas disponibles este mes.
      select coalesce(array_agg(x.usuario_id), '{}') into tecs from (
        select p.usuario_id from public.perfiles_tecnicos p
          join public.tecnico_oficios t2 on t2.tecnico_id = p.usuario_id and t2.oficio_id = ofi and t2.activo
          cross join lateral public.plan_de(p.usuario_id) pl
         where st_dwithin(p.ubicacion_actual, st_setsrid(st_makepoint(lng, lat), 4326)::geography,
                          least(least(p.rango_cobertura_m, pl.rango_max_m) + p.rango_bonus_m, 50000))
           and (pl.cotizaciones_mes is null or (select count(*) from public.cotizaciones c
                 where c.tecnico_id = p.usuario_id and c.creado_en >= public.inicio_mes_ecuador()) < pl.cotizaciones_mes - 1)
         -- Los de mejor plan salen antes, pero no se llevan todo el trabajo.
         order by random() * (1 + 0.4 * pl.prioridad) desc limit n_post) x;
      exit when ofi is not null and coalesce(array_length(tecs, 1), 0) >= n_post;
    end loop;
    if ofi is null then continue; end if;
    if coalesce(array_length(tecs, 1), 0) < n_post then
      if v_tipo in ('B', 'H') then n_post := coalesce(array_length(tecs, 1), 0);
      else v_tipo := 'A'; n_post := 0; tecs := '{}'; end if;
    end if;
    if v_tipo = 'G' and cli.id = any(vip) then g_vip := g_vip + 1; end if;

    descr := (textos->(ofi::text))->>floor(random() * jsonb_array_length(textos->(ofi::text)))::int;
    veh := case when ofi >= 21 then jsonb_build_object(
             'tipo', case when ofi = 22 then 'moto' else (array['auto', 'auto', 'camioneta'])[1 + floor(random() * 3)::int] end,
             'marca', case when ofi = 22 then (array['Honda', 'Yamaha', 'Suzuki'])[1 + floor(random() * 3)::int]
                           else (array['Chevrolet', 'Kia', 'Hyundai', 'Toyota', 'Mazda'])[1 + floor(random() * 5)::int] end,
             'modelo', case when ofi = 22 then 'CB 150' else (array['Aveo', 'Sail', 'Rio', 'Tucson', 'Hilux', 'CX-5'])[1 + floor(random() * 6)::int] end,
             'anio', 2008 + floor(random() * 17)::int) end;
    sol := gen_random_uuid();
    perform pg_temp.como(null);
    insert into public.solicitudes_servicio (id, cliente_id, oficio_id, descripcion, ubicacion, direccion_referencia, vehiculo)
    values (sol, cli.id, ofi, descr, st_setsrid(st_makepoint(lng, lat), 4326)::geography,
            (select raw_user_meta_data->>'barrio' from auth.users where id = cli.id) || ', '
              || (array['cerca del parque', 'junto a la panadería', 'frente a la tienda', 'a media cuadra de la esquina', 'casa esquinera'])[1 + floor(random() * 5)::int],
            veh);
    foreach t in array tecs loop
      insert into public.cotizaciones (solicitud_id, tecnico_id, detalle)
      values (sol, t, (explicaciones->(case when ofi >= 21 then 'vehiculos' else 'hogar' end))
                        ->>floor(random() * jsonb_array_length(explicaciones->(case when ofi >= 21 then 'vehiculos' else 'hogar' end)))::int);
    end loop;

    if v_tipo = 'H' then
      update public.solicitudes_servicio set estado = 'cancelada' where id = sol;
    end if;

    if v_tipo in ('C', 'D', 'E', 'F', 'G') then
      t := tecs[1];
      select id into cid from public.cotizaciones where solicitud_id = sol and tecnico_id = t;
      perform pg_temp.como(cli.id);
      perform public.iniciar_chat(sol, t);
      select id into conv from public.conversaciones where solicitud_id = sol and tecnico_id = t;
      lineas := case when v_tipo = 'C' and random() < 0.5 then 2 else 4 end;
      for k in 1..lineas loop
        insert into public.mensajes (conversacion_id, autor_id, contenido, enviado_en)
        values (conv, case when k % 2 = 1 then cli.id else t end,
                case k when 1 then chat_c[1 + floor(random() * 4)::int] when 2 then chat_t[1 + floor(random() * 4)::int]
                       when 3 then chat_c2[1 + floor(random() * 3)::int] else chat_t2[1 + floor(random() * 3)::int] end,
                now() - make_interval(mins => 30 - k));
      end loop;

      if v_tipo in ('D', 'E', 'F', 'G') then
        precio := (select tarifa_visita from public.tecnico_oficios where tecnico_id = t and oficio_id = ofi)
                  + (array[0, 0, 5, 10])[1 + floor(random() * 4)::int];
        fecha := case when v_tipo = 'D' then pg_temp.slot_libre(t, cli.id, 2, 9)
                      when v_tipo = 'E' then pg_temp.slot_libre(t, cli.id, 1, 8)
                      else pg_temp.slot_libre(t, cli.id, 40, 120) end;
        perform pg_temp.como(t);
        perform public.enviar_tarifa(cid, precio, 0, fecha);
      end if;
      if v_tipo in ('E', 'F', 'G') then
        perform pg_temp.como(cli.id);
        perform public.aceptar_cotizacion(cid);
      end if;
      perform pg_temp.como(null);

      if v_tipo in ('F', 'G') then
        -- La visita pasa al pasado, con su historial de fechas.
        s_t := case when v_tipo = 'F' then pg_temp.slot_libre(t, cli.id, -2, -1)
                    when cli.id = any(vip) then pg_temp.slot_libre(t, cli.id, -80, -3)
                    else pg_temp.slot_libre(t, cli.id, -120, -3) end;
        update public.cotizaciones set fecha_servicio = s_t, inicio_visita = s_t, fin_visita = s_t + interval '1 hour',
               creado_en = s_t - interval '3 days' + interval '3 hours' where id = cid;
        update public.cotizaciones set creado_en = s_t - interval '3 days' + make_interval(hours => 4 + floor(random() * 16)::int)
         where solicitud_id = sol and id <> cid;
        update public.solicitudes_servicio set creado_en = s_t - interval '3 days' where id = sol;
        update public.conversaciones set creado_en = s_t - interval '3 days' + interval '4 hours' where id = conv;
        update public.mensajes m set enviado_en = s_t - interval '3 days' + interval '4 hours' + make_interval(mins => (x.n * 7)::int)
          from (select mm.id, row_number() over (order by mm.enviado_en, mm.id) n from public.mensajes mm
                 where mm.conversacion_id = conv and mm.tipo = 'texto') x where m.id = x.id;
        update public.mensajes set enviado_en = s_t - interval '2 days',
               contenido = format('Ticket enviado: precio de la visita $%s, para el %s.', to_char(precio, 'FM9990.00'),
                                  to_char(s_t at time zone 'America/Guayaquil', 'DD/MM/YYYY "a las" HH24:MI')),
               datos = datos || jsonb_build_object('fecha_servicio', s_t)
         where conversacion_id = conv and datos->>'accion' = 'tarifa_enviada';
        update public.mensajes set enviado_en = s_t - interval '2 days' + interval '1 hour',
               contenido = format('El cliente confirmó el servicio para el %s por un total de $%s. Ya pueden coordinar los detalles.',
                                  to_char(s_t at time zone 'America/Guayaquil', 'DD/MM/YYYY "a las" HH24:MI'), to_char(precio, 'FM9990.00')),
               datos = datos || jsonb_build_object('fecha_servicio', s_t)
         where conversacion_id = conv and datos->>'accion' = 'tarifa_aceptada';

        update public.solicitudes_servicio set estado = 'por_confirmar' where id = sol;
        insert into public.mensajes (conversacion_id, autor_id, contenido, enviado_en)
        values (conv, t, cierre_t[1 + floor(random() * 2)::int], s_t + interval '90 minutes');
      end if;

      if v_tipo = 'G' then
        update public.solicitudes_servicio set estado = 'completada' where id = sol;
        update public.solicitudes_servicio set completada_en = s_t + interval '3 hours' where id = sol;
        insert into public.mensajes (conversacion_id, autor_id, contenido, enviado_en)
        values (conv, cli.id, cierre_c[1 + floor(random() * 3)::int], s_t + interval '3 hours');
        update public.eventos ev set creado_en = s_t + interval '3 hours'
         where ev.tipo = 'negocio_cerrado' and payload->>'solicitud_id' = sol::text;

        -- Reseñas: casi todas buenas; como mucho una mala por persona.
        for k in 1..2 loop
          para_t := k = 1;
          autor := case when para_t then cli.id else t end;
          dest := case when para_t then t else cli.id end;
          continue when not para_t and random() < 0.08;
          nota := case when random() < 0.04 and coalesce((malas->>dest::text)::int, 0) = 0 then 1 + floor(random() * 2)::int
                       when random() < 0.12 then 3 when random() < 0.25 then 4 else 5 end;
          if nota <= 2 then malas := malas || jsonb_build_object(dest::text, 1); end if;
          if nota >= 4 then
            select array_agg(e) into etq from (select e from unnest(case when para_t then etq_t else etq_c end) e
                                                 order by random() limit 1 + floor(random() * 3)::int) z;
            com := case when para_t then com_t[1 + floor(random() * 8)::int] else com_c[1 + floor(random() * 5)::int] end;
          elsif nota = 3 then
            etq := '{}'; com := (array['Cumplió, aunque llegó un poco tarde.', 'Trabajo cumplido.'])[1 + floor(random() * 2)::int];
          else
            etq := case when para_t then array['Llegó tarde', 'Trabajo incompleto'] else array['Tiempo de espera'] end;
            com := case when para_t then 'Llegó tarde y no terminó el trabajo.' else 'No estuvo a la hora acordada.' end;
          end if;
          insert into public.resenas (solicitud_id, autor_id, destinatario_id, calificacion, comentario, etiquetas, creado_en)
          values (sol, autor, dest, nota, com, coalesce(etq, '{}'), s_t + make_interval(hours => 4 + floor(random() * 30)::int));
        end loop;
        update public.historial_puntos set creado_en = s_t + interval '1 day' where solicitud_id = sol;
      end if;
    end if;

    if v_tipo in ('A', 'B', 'C', 'D', 'E', 'H') then
      hrs := case when v_tipo in ('A', 'B', 'C') then 2 + floor(random() * 70)::int else 24 + floor(random() * 72)::int end;
      update public.solicitudes_servicio set creado_en = now() - make_interval(hours => hrs) where id = sol;
      update public.cotizaciones set creado_en = now() - make_interval(hours => hrs) + make_interval(mins => 30 + floor(random() * 150)::int)
       where solicitud_id = sol;
      if v_tipo in ('C', 'D', 'E') then
        update public.conversaciones set creado_en = now() - make_interval(hours => greatest(hrs - 4, 1)) where id = conv;
        update public.mensajes m set enviado_en = now() - make_interval(hours => greatest(hrs - 4, 1)) + make_interval(mins => (x.n * 9)::int)
          from (select mm.id, row_number() over (order by mm.enviado_en, mm.id) n from public.mensajes mm
                 where mm.conversacion_id = conv and mm.tipo = 'texto') x where m.id = x.id;
        update public.mensajes set enviado_en = now() - make_interval(hours => greatest(hrs - 4, 1)) + interval '50 minutes'
         where conversacion_id = conv and datos->>'accion' = 'tarifa_enviada';
        update public.mensajes set enviado_en = now() - make_interval(hours => greatest(hrs - 4, 1)) + interval '2 hours'
         where conversacion_id = conv and datos->>'accion' = 'tarifa_aceptada';
      end if;
    end if;
  end loop;
  perform pg_temp.como(null);
end $$;

-- @@ 5. Reclamos, niveles, favoritos, reputación y notificaciones.
do $$
declare r record; v_admin uuid := (select id from public.usuarios where rol = 'admin' limit 1);
  cats text[] := array['falla_trabajo', 'no_se_presento', 'trato', 'cobro_indebido', 'falla_trabajo', 'otro', 'falla_trabajo'];
  descs text[] := array[
    'La fuga volvió a aparecer a los dos días de la reparación y el agua sigue saliendo.',
    'El técnico no llegó a la hora acordada y tuve que esperar toda la mañana sin aviso.',
    'El trato no fue el adecuado, respondió de mala manera cuando le pregunté por el trabajo.',
    'Me cobró más de lo que decía el ticket de la visita sin explicarme el motivo.',
    'El arreglo no quedó bien, el equipo se volvió a dañar a la semana.',
    'Dejó residuos de material en la sala y no limpió al terminar el trabajo.',
    'La instalación quedó floja y se desprendió una parte al día siguiente.'];
  estados text[] := array['recibido', 'en_revision', 'necesita_info', 'resuelto', 'resuelto', 'en_revision', 'recibido'];
  rec uuid; k int := 0;
begin
  perform setseed(0.31);
  -- Reclamos sobre servicios recientes (dentro de los 30 días de garantía).
  for r in
    select s.id, s.cliente_id from public.solicitudes_servicio s
     where s.estado = 'completada' and s.completada_en > now() - interval '25 days'
     order by s.completada_en desc limit 7
  loop
    k := k + 1;
    perform pg_temp.como(r.cliente_id);
    perform public.crear_reclamo(r.id, cats[k], descs[k], '{}');
    perform pg_temp.como(null);
    select id into rec from public.reclamos where solicitud_id = r.id;
    update public.reclamos set creado_en = now() - make_interval(days => k), estado = estados[k],
           asesor_id = case when estados[k] <> 'recibido' then v_admin end,
           resolucion = case when estados[k] = 'resuelto' then 'Hablamos con ambas partes. El técnico volvió a revisar el trabajo sin costo y el cliente quedó conforme.' end,
           cerrado_en = case when estados[k] = 'resuelto' then now() - make_interval(hours => k * 5) end,
           actualizado_en = now() - make_interval(hours => k * 6)
     where id = rec;
    if estados[k] <> 'recibido' then
      insert into public.reclamo_mensajes (reclamo_id, autor_id, es_asesor, texto, creado_en)
      values (rec, v_admin, true, 'Hola, recibimos tu reclamo y ya lo estamos revisando. Te escribimos apenas tengamos novedades.',
              now() - make_interval(days => k) + interval '3 hours');
    end if;
    if estados[k] = 'necesita_info' then
      insert into public.reclamo_mensajes (reclamo_id, autor_id, es_asesor, texto, creado_en)
      values (rec, v_admin, true, '¿Nos puedes enviar una foto de cómo quedó el trabajo para continuar con la revisión?',
              now() - make_interval(days => k) + interval '20 hours');
    elsif estados[k] = 'resuelto' then
      insert into public.reclamo_mensajes (reclamo_id, autor_id, es_asesor, texto, creado_en)
      values (rec, r.cliente_id, false, 'Gracias, el técnico ya vino de nuevo y quedó bien.',
              now() - make_interval(hours => k * 5 + 2));
    end if;
  end loop;

  -- Trayectoria: los mejores calificados suben a Oro (4) y Plata (9).
  insert into public.historial_puntos (tecnico_id, puntos, motivo, creado_en)
  select usuario_id, objetivo - puntos, 'trayectoria_demo', now() - interval '60 days'
  from (select p.usuario_id, p.puntos,
               case when row_number() over w <= 4 then 480 + (row_number() over w) * 40
                    when row_number() over w <= 13 then 160 + (row_number() over w) * 20 end objetivo
          from public.perfiles_tecnicos p join auth.users a on a.id = p.usuario_id
         where a.email like '%@semilla.chaucha.app' and p.total_resenas > 0
        window w as (order by p.calificacion_promedio desc, p.total_resenas desc, p.usuario_id)) x
  where objetivo is not null and objetivo > puntos;

  -- Favoritos: cada cliente guarda a los técnicos con los que cerró y le fue bien.
  insert into public.favoritos (cliente_id, tecnico_id, creado_en)
  select distinct r2.autor_id, r2.destinatario_id, r2.creado_en
    from public.resenas r2 join public.usuarios u on u.id = r2.autor_id and u.rol = 'cliente'
   where r2.calificacion = 5 and random() < 0.4
  on conflict do nothing;

  perform public.recalcular_reputacion_reciente();

  -- Avisos con la fecha de lo que anuncian; los de hace más de 2 días, leídos.
  update public.notificaciones n set creada_en = x.f
    from (select s.id ref, coalesce(s.completada_en, s.creado_en) f from public.solicitudes_servicio s
          union all select c.id, c.creado_en from public.cotizaciones c
          union all select c.id, c.creado_en from public.conversaciones c
          union all select r3.id, r3.creado_en from public.reclamos r3) x
   where n.referencia_id = x.ref;
  update public.notificaciones set leida = true where creada_en < now() - interval '2 days';
end $$;

-- @@ 6. Pagos de la pasarela simulada (necesita la migración pagos_demo).
-- Un pago aprobado por cada suscripción, la mitad ya había renovado el mes
-- anterior, y dos intentos rechazados con la tarjeta de prueba 0002.
insert into public.pagos (referencia, tecnico_id, plan_codigo, monto, marca, ultimos4, estado, suscripcion_id, creado_en)
select 'PAY-' || lpad(nextval('public.pagos_numero_seq')::text, 6, '0'), x.*
from (
  select s.tecnico_id, s.plan_codigo, pl.precio_mensual,
         (array['visa', 'mastercard', 'visa', 'diners'])[1 + (abs(hashtext(s.tecnico_id::text)) % 4)],
         lpad((1000 + abs(hashtext(s.id::text)) % 9000)::text, 4, '0'), 'aprobado', s.id, s.inicio
    from public.suscripciones s join public.planes pl on pl.codigo = s.plan_codigo
   where s.origen = 'pago'
  union all
  select s.tecnico_id, s.plan_codigo, pl.precio_mensual, 'visa', '4242', 'aprobado', null::uuid, s.inicio - interval '30 days'
    from public.suscripciones s join public.planes pl on pl.codigo = s.plan_codigo
   where s.origen = 'pago' and abs(hashtext(s.id::text)) % 2 = 0
  order by 8
) x;
insert into public.pagos (referencia, tecnico_id, plan_codigo, monto, marca, ultimos4, estado, motivo, creado_en)
select 'PAY-' || lpad(nextval('public.pagos_numero_seq')::text, 6, '0'), p.usuario_id, 'pro', 6, 'visa', '0002',
       'rechazado', 'El banco rechazó la tarjeta por fondos insuficientes.', now() - interval '6 days'
from public.perfiles_tecnicos p join auth.users a on a.id = p.usuario_id
where a.email like '%@semilla.chaucha.app' and public.plan_codigo(p) = 'gratis'
order by p.usuario_id limit 2;
