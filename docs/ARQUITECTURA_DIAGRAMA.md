# ChauchaApp: diagramas de arquitectura

El detalle de cada pieza está en [ARQUITECTURA_TECNICA.md](ARQUITECTURA_TECNICA.md).

## 1. Vista general

```mermaid
flowchart LR
  USR["Cliente · Técnico · Admin"] --> APP

  subgraph CICD["CI/CD · GitHub Actions"]
    direction TB
    CI["Pruebas en cada PR"]
    CD["Despliegue al fusionar en master"]
  end

  subgraph Hosting["Firebase Hosting"]
    WEB["chauchaapp.web.app"]
  end

  APP["App Flutter<br/>Web y Android (un solo código)"]

  subgraph Supabase["Supabase (backend)"]
    direction TB
    subgraph Servicios[" "]
      direction LR
      AUTH["Auth<br/>correo + contraseña"]
      API["API REST / RPC"]
      RT["Realtime<br/>chat y avisos en vivo"]
      ST["Storage<br/>fotos y documentos"]
    end

    subgraph PG["PostgreSQL"]
      direction LR
      TBL["Tablas + RLS"]
      TRG["Triggers<br/>reglas de negocio"]
      GIS["PostGIS<br/>distancias"]
      GIST["btree_gist<br/>sin choques de horario"]
      CRON["pg_cron<br/>tareas programadas"]
      NET["pg_net + Vault<br/>webhook seguro"]
    end

    subgraph EF["Edge Functions"]
      direction TB
      F1["Identidad<br/>validar-foto-rostro · comparar-rostro-cedula<br/>verificar-rostro-sesion · verificar-rostro-postulacion"]
      F2["Avisos<br/>enviar-push"]
      F3["Rendimiento<br/>sector · presencia · anuncios"]
    end
  end

  subgraph Externos["Servicios externos"]
    direction TB
    GEM["Google Gemini<br/>calidad de foto y lectura de cédula"]
    REK["AWS Rekognition<br/>comparación de rostros"]
    FCM["Firebase Cloud Messaging<br/>push"]
    BRE["Brevo<br/>SMTP de Auth"]
    RED["Upstash Redis<br/>caché, presencia y límites"]
    OSM["OpenStreetMap<br/>mapas y barrios (Nominatim)"]
  end

  CI --> CD
  CD --> WEB
  CD --> EF
  WEB --> APP

  APP --> AUTH
  APP --> API
  APP <--> RT
  APP --> ST
  APP --> F1
  APP --> F3
  APP --> OSM

  AUTH --> BRE
  API --> TBL --> TRG
  TRG --> GIS
  TRG --> GIST
  CRON --> TRG
  TRG --> NET --> F2 --> FCM
  FCM -. "notificación con la app cerrada" .-> APP
  F1 --> GEM
  F1 --> REK
  F2 <--> RED
  F3 <--> RED
  F3 --> OSM
```

## 2. Cómo llega una notificación push

```mermaid
sequenceDiagram
  autonumber
  participant C as Cliente (app)
  participant DB as PostgreSQL
  participant N as pg_net
  participant EF as Edge Function enviar-push
  participant R as Upstash Redis
  participant F as Firebase (FCM)
  participant T as Técnico (app cerrada)

  C->>DB: envía un mensaje (INSERT en mensajes)
  DB->>DB: trigger crea la fila en notificaciones
  DB->>N: trigger trg_notificacion_push
  N->>EF: POST con el secreto de Vault
  EF->>DB: valida el secreto y busca los tokens del técnico
  EF->>R: ¿el técnico tiene ese chat abierto? (presencia)
  alt lo está viendo
    EF-->>N: no envía push (ya lo ve por Realtime)
  else no lo está viendo
    EF->>F: envía el aviso (FCM HTTP v1)
    F-->>T: notificación del sistema
    T->>T: al tocarla, abre la pestaña o el reclamo correcto
  end
```

## 3. Vida de una solicitud

```mermaid
stateDiagram-v2
  [*] --> abierta: el cliente publica (parte de la ubicación de su perfil)
  abierta --> cotizada: un técnico postula (confirma su rostro)
  cotizada --> aceptada: el cliente acepta el ticket (día y hora)
  aceptada --> por_confirmar: el técnico marca terminado
  por_confirmar --> completada: el cliente confirma
  completada --> [*]: reseñas, puntos, sanciones y 30 días de garantía

  abierta --> cancelada: el cliente cancela
  cotizada --> cancelada: expira a los 30 días (pg_cron)
  aceptada --> cotizada: se cancela el ticket aceptado
  aceptada --> cancelada
  por_confirmar --> cancelada
```

## 4. Verificación de identidad (100 % automática)

No hay revisión manual: cuando algo no está claro, se le pide al usuario
repetir la foto concreta. El admin no interviene.

```mermaid
flowchart TB
  S["Selfie en vivo"] --> V1{"validar-foto-rostro<br/>(Gemini): ¿rostro claro?"}
  V1 -- No --> R1["Repetir la selfie<br/>con el motivo"]
  V1 -- Sí --> D["Frente y reverso de la cédula"]
  D --> V2["comparar-rostro-cedula<br/>Rekognition + Gemini"]
  V2 --> F{"¿Respondió el servicio?"}
  F -- No --> R0["503: reintentar en unos minutos<br/>(no se rechaza nada)"]
  F -- Sí --> Q{"Decisión"}
  Q -- "Rostro bajo o intermedio,<br/>nombre ilegible" --> R2["Repetir el frente"]
  Q -- "Código dactilar ilegible" --> R3["Repetir el reverso"]
  Q -- "Datos que no coinciden" --> R4["Corregir los datos<br/>y se vuelve a validar"]
  Q -- "Todo coincide" --> OK["Verificado<br/>insignia y celebración"]
  OK --> L["Cada inicio de sesión y cada postulación<br/>confirman el rostro contra la foto de perfil"]
```

## 5. Reclamos y avisos al admin

```mermaid
sequenceDiagram
  autonumber
  participant U as Cliente o técnico
  participant DB as PostgreSQL
  participant A as Admin

  U->>DB: crear_reclamo (dentro de los 30 días de garantía)
  DB->>DB: trigger trg_aviso_admin_reclamo
  DB-->>A: aviso "Nuevo reclamo REC-0008" (push y campana)
  A->>DB: admin_gestionar_reclamo (en revisión, necesita info, resuelto)
  DB-->>U: aviso del cambio de estado
  U->>DB: responde en el reclamo
  DB->>DB: trigger trg_aviso_admin_respuesta
  DB-->>A: aviso "Respondieron en el reclamo REC-0008"
```

## 6. Una sola ubicación en toda la app

```mermaid
flowchart LR
  P["Perfil<br/>Usar mi ubicación actual<br/>o Seleccionar en el mapa"] --> U[("usuarios.ubicacion_registro")]
  Z["Zona de trabajo del técnico"] --> U
  U --> S["Sesión<br/>usuarioActualProvider"]
  S --> I["ubicacionInicioProvider"]
  G["GPS<br/>(solo si no hay una guardada)"] -.-> I
  I --> C["Inicio y técnicos cercanos"]
  I --> B["Barrio en la barra superior"]
  S --> N["Nueva solicitud<br/>(el mapa arranca marcado ahí)"]
```

## 7. Pasarela de pago simulada

```mermaid
sequenceDiagram
  autonumber
  participant T as Técnico (app)
  participant DB as PostgreSQL

  T->>T: valida la tarjeta en el teléfono<br/>(Luhn, marca, vencimiento, CVV)
  T->>DB: pagar_plan(marca, últimos 4 dígitos)
  Note over T,DB: nunca viaja el número completo ni el CVV
  alt termina en 0002
    DB-->>T: rechazado: fondos insuficientes
  else cualquier otra
    DB->>DB: activa la suscripción por 30 días
    DB-->>T: aprobado: comprobante PAY-000123
  end
```

## 8. Tareas programadas (pg_cron)

```mermaid
flowchart TB
  A["00:00 Ecuador<br/>expirar-solicitudes"] --> A1["Cancela abiertas o cotizadas<br/>con más de 30 días y avisa al cliente"]
  B["00:30 Ecuador<br/>recalcular-reputacion"] --> B1["Bono de rango del técnico<br/>(+500 m por reseña excelente en 90 días)"]
  B --> B2["Cliente VIP<br/>(5 cierres en 90 días, sin reseñas malas)"]
  C["Cada hora<br/>avisar-fin-sanciones"] --> C1["Avisa a quien terminó<br/>su suspensión de 7 días"]
```

## 9. CI/CD

```mermaid
flowchart LR
  PR["Pull request"] --> CI1["App Flutter<br/>analyze · test · build web"]
  PR --> CI2["Edge Functions<br/>deno check · test"]
  CI1 --> M{"¿Fusionado en master?"}
  CI2 --> M
  M -- Sí --> W["despliegue-web.yml<br/>Firebase Hosting"]
  M -- Sí --> E["edge-functions.yml<br/>despliega las 8 funciones"]
  M -. "migraciones: se aplican a mano" .-> DB[("Supabase")]
```
