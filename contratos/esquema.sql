-- Gotitas: esquema SQLite (version escritorio)
-- Convenciones: fechas en texto ISO 8601, booleanos 0/1, dinero en MXN, agua en L o m3.
PRAGMA foreign_keys = ON;

-- negocios: perfil de la PyME
CREATE TABLE IF NOT EXISTS negocios (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre          TEXT    NOT NULL,
    giro            TEXT    NOT NULL CHECK (giro IN
                    ('restaurante','estetica','abarrotes','lavanderia','oficina')),
    hora_apertura   TEXT    NOT NULL,
    hora_cierre     TEXT    NOT NULL,
    dias_descanso   TEXT    NOT NULL DEFAULT '[]',
    num_empleados   INTEGER CHECK (num_empleados >= 0),
    direccion       TEXT,
    num_medidor     TEXT,
    tarifa_tipo     TEXT,
    meta_m3_dia     REAL    CHECK (meta_m3_dia > 0),
    recordatorio_apertura TEXT DEFAULT '08:00',
    recordatorio_cierre   TEXT DEFAULT '20:00',
    es_simulado     INTEGER NOT NULL DEFAULT 0 CHECK (es_simulado IN (0,1)),
    creado_en       TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- usuarios: acceso a la app (login con JWT)
CREATE TABLE IF NOT EXISTS usuarios (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    negocio_id      INTEGER NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
    nombre          TEXT    NOT NULL,
    email           TEXT    NOT NULL UNIQUE,
    password_hash   TEXT    NOT NULL,
    rol             TEXT    NOT NULL DEFAULT 'encargado' CHECK (rol IN ('dueno','encargado')),
    creado_en       TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- lecturas: 2 al dia (apertura y cierre) + recibos
-- consumo nocturno = apertura(dia siguiente) - cierre(dia)
CREATE TABLE IF NOT EXISTS lecturas (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    negocio_id      INTEGER NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
    fecha_hora      TEXT    NOT NULL,
    tipo            TEXT    NOT NULL CHECK (tipo IN ('apertura','cierre','recibo')),
    lectura_m3      REAL    NOT NULL CHECK (lectura_m3 >= 0),
    estado          TEXT    NOT NULL DEFAULT 'ok' CHECK (estado IN ('ok','sospechosa','corregida')),
    origen          TEXT    NOT NULL DEFAULT 'manual' CHECK (origen IN ('manual','importada','simulada')),
    usuario_id      INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
    nota            TEXT,
    foto_ruta       TEXT,
    creado_en       TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (negocio_id, fecha_hora, tipo)
);
CREATE INDEX IF NOT EXISTS idx_lecturas_negocio_fecha ON lecturas (negocio_id, fecha_hora);

-- tarifas: precio del m3 por rango (tarifa comercial MIAA)
CREATE TABLE IF NOT EXISTS tarifas (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    tipo            TEXT    NOT NULL DEFAULT 'comercial',
    vigente_desde   TEXT    NOT NULL,
    rango_m3_min    REAL    NOT NULL DEFAULT 0,
    rango_m3_max    REAL,
    precio_m3       REAL    NOT NULL CHECK (precio_m3 >= 0),
    CHECK (rango_m3_max IS NULL OR rango_m3_max > rango_m3_min)
);

-- alertas: anomalias detectadas por el motor
CREATE TABLE IF NOT EXISTS alertas (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    negocio_id          INTEGER NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
    tipo                TEXT    NOT NULL CHECK (tipo IN
                        ('fuga_continua','fuga_intermitente','pico','patron_ineficiente','lectura_erronea')),
    severidad           TEXT    NOT NULL CHECK (severidad IN ('baja','media','alta')),
    fecha_inicio        TEXT    NOT NULL,
    fecha_fin           TEXT,
    litros_por_hora     REAL,
    litros_total        REAL,
    costo_mensual_mxn   REAL,
    atendida            INTEGER NOT NULL DEFAULT 0 CHECK (atendida IN (0,1)),
    atendida_en         TEXT,
    creado_en           TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_alertas_negocio ON alertas (negocio_id, atendida);

-- diagnosticos: cache de respuestas del LLM
CREATE TABLE IF NOT EXISTS diagnosticos (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    negocio_id      INTEGER NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
    periodo         TEXT    NOT NULL,
    hash_entrada    TEXT    NOT NULL,
    respuesta_json  TEXT    NOT NULL,
    proveedor       TEXT,
    creado_en       TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (negocio_id, periodo, hash_entrada)
);

-- consumo_horario: SOLO datos simulados (el motor no la usa)
CREATE TABLE IF NOT EXISTS consumo_horario (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    negocio_id      INTEGER NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
    fecha_hora      TEXT    NOT NULL,
    litros          REAL    NOT NULL CHECK (litros >= 0),
    anomalia_real   TEXT    NOT NULL DEFAULT '',
    UNIQUE (negocio_id, fecha_hora)
);

-- consumos_diarios: consumo derivado de las 2 lecturas (lo calcula el motor)
CREATE TABLE IF NOT EXISTS consumos_diarios (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    negocio_id          INTEGER NOT NULL REFERENCES negocios(id) ON DELETE CASCADE,
    fecha               TEXT    NOT NULL,
    litros_dia          REAL,
    litros_noche        REAL,
    litros_hora_noche   REAL,
    completo            INTEGER NOT NULL DEFAULT 1 CHECK (completo IN (0,1)),
    anomalia_real       TEXT    NOT NULL DEFAULT '',
    UNIQUE (negocio_id, fecha)
);

-- meta: version del esquema
CREATE TABLE IF NOT EXISTS meta (
    clave   TEXT PRIMARY KEY,
    valor   TEXT NOT NULL
);
INSERT OR IGNORE INTO meta (clave, valor) VALUES ('schema_version', '2');