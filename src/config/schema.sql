-- =====================================================
--  SCHEMA: Restaurante 3 Pisos — POS
--  Ejecutar en PostgreSQL: psql -U postgres -d Tres_Pisos -f schema.sql
-- =====================================================

-- Enum de roles de usuario
DO $$ BEGIN
  CREATE TYPE rol_usuario AS ENUM ('admin', 'mesero', 'cocina');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Enum de estados de pedido
DO $$ BEGIN
  CREATE TYPE estado_pedido AS ENUM ('pendiente', 'preparando', 'listo', 'entregado', 'cancelado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Tabla usuarios ──────────────────────────────────
CREATE TABLE IF NOT EXISTS usuarios (
  id         SERIAL PRIMARY KEY,
  username   VARCHAR(30) UNIQUE NOT NULL,
  password   TEXT NOT NULL,              -- bcrypt hash
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
  disponible BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabla pedidos ───────────────────────────────────
CREATE TABLE IF NOT EXISTS pedidos (
  id         SERIAL PRIMARY KEY,
  mesa       INTEGER NOT NULL CHECK (mesa > 0),
  estado     VARCHAR(15) NOT NULL DEFAULT 'pendiente'
               CHECK (estado IN ('pendiente','preparando','listo','entregado','cancelado')),
  total      NUMERIC(10, 2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── Tabla pedido_detalle ────────────────────────────
CREATE TABLE IF NOT EXISTS pedido_detalle (
  id          SERIAL PRIMARY KEY,
  pedido_id   INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  producto_id INTEGER NOT NULL REFERENCES productos(id),
  cantidad    INTEGER NOT NULL CHECK (cantidad > 0),
  nota        TEXT DEFAULT ''
);

-- ── Datos iniciales (admin por defecto) ─────────────
-- Contraseña: admin123  (bcrypt hash generado con cost 12)
INSERT INTO usuarios (username, password, role) VALUES
  ('admin', '$2b$12$1uz25X4QeOSOawtgWg/s.OdLJTUBe9togdi.Ib.wiVLCSOAXfdhBSC', 'admin')
ON CONFLICT (username) DO NOTHING;

-- ── Productos de ejemplo ─────────────────────────────
INSERT INTO productos (nombre, precio, categoria) VALUES
  ('Tacos de Carne',      45.00, 'Tacos'),
  ('Tacos de Pastor',     42.00, 'Tacos'),
  ('Torta de Milanesa',   55.00, 'Tortas'),
  ('Agua de Jamaica',     18.00, 'Bebidas'),
  ('Refresco',            22.00, 'Bebidas'),
  ('Enchiladas Verdes',   60.00, 'Platillos'),
  ('Pozole Rojo',         75.00, 'Platillos'),
  ('Guacamole',           35.00, 'Entradas')
ON CONFLICT DO NOTHING;
