-- =====================================================
--  SCHEMA: Restaurante 3 Pisos — POS
--  Compatible con Railway PostgreSQL
-- =====================================================

-- ── Tabla usuarios ──────────────────────────────────
CREATE TABLE IF NOT EXISTS usuarios (
  id         SERIAL PRIMARY KEY,
  username   VARCHAR(30) UNIQUE NOT NULL,
  password   TEXT NOT NULL,
  role       VARCHAR(10) NOT NULL DEFAULT 'mesero'
               CHECK (role IN ('admin', 'mesero', 'cocina')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabla productos ─────────────────────────────────
CREATE TABLE IF NOT EXISTS productos (
  id         SERIAL PRIMARY KEY,
  nombre     VARCHAR(100) NOT NULL,
  precio     NUMERIC(10, 2) NOT NULL CHECK (precio > 0),
  categoria  VARCHAR(50),
  activo     BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabla pedidos ───────────────────────────────────
CREATE TABLE IF NOT EXISTS pedidos (
  id         SERIAL PRIMARY KEY,
  mesa       INTEGER NOT NULL CHECK (mesa > 0),
  estado     VARCHAR(15) NOT NULL DEFAULT 'pendiente'
               CHECK (estado IN ('pendiente','preparando','listo','pagado','cancelado')),
  total      NUMERIC(10, 2) NOT NULL DEFAULT 0,
  tipo       VARCHAR(10) NOT NULL DEFAULT 'aqui' CHECK (tipo IN ('aqui','llevar')),
  comensal   VARCHAR(50) DEFAULT NULL,
  usuario_id INTEGER REFERENCES usuarios(id),
  creado_en  TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabla pedido_detalle ────────────────────────────
CREATE TABLE IF NOT EXISTS pedido_detalle (
  id          SERIAL PRIMARY KEY,
  pedido_id   INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  producto_id INTEGER NOT NULL REFERENCES productos(id),
  cantidad    INTEGER NOT NULL CHECK (cantidad > 0),
  nota        TEXT DEFAULT ''
);

-- ── Tabla ventas ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS ventas (
  id        SERIAL PRIMARY KEY,
  pedido_id INTEGER REFERENCES pedidos(id) ON DELETE SET NULL,
  total     NUMERIC(10,2) NOT NULL,
  fecha     TIMESTAMPTZ DEFAULT NOW()
);

-- ── Admin por defecto ────────────────────────────────
-- Contraseña: Admin3Pisos
INSERT INTO usuarios (username, password, role) VALUES
  ('admin', '$2b$12$BpJrMqpHiHJe1d1VJ25k0.z2gXCxkIPrTJVJoxkF9z.KXNVxxUu5q', 'admin')
ON CONFLICT (username) DO NOTHING;

-- ── Productos de ejemplo ─────────────────────────────
INSERT INTO productos (nombre, precio, categoria, activo) VALUES
  ('Tacos de Carne',      45.00, 'Tacos',     true),
  ('Tacos de Pastor',     42.00, 'Tacos',     true),
  ('Torta de Milanesa',   55.00, 'Tortas',    true),
  ('Agua de Jamaica',     18.00, 'Bebidas',   true),
  ('Refresco',            22.00, 'Bebidas',   true),
  ('Enchiladas Verdes',   60.00, 'Platillos', true),
  ('Pozole Rojo',         75.00, 'Platillos', true),
  ('Guacamole',           35.00, 'Entradas',  true)
ON CONFLICT DO NOTHING;
