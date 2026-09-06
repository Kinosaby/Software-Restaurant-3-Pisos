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
  usuario_id INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  creado_en  TIMESTAMPTZ DEFAULT NOW()
);

-- Permite retirar cuentas antiguas sin perder el historial de pedidos.
ALTER TABLE pedidos DROP CONSTRAINT IF EXISTS pedidos_usuario_id_fkey;
ALTER TABLE pedidos
  ADD CONSTRAINT pedidos_usuario_id_fkey
  FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE SET NULL;

-- ── Tabla pedido_detalle ────────────────────────────
CREATE TABLE IF NOT EXISTS pedido_detalle (
  id          SERIAL PRIMARY KEY,
  pedido_id   INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  producto_id INTEGER NOT NULL REFERENCES productos(id),
  cantidad    INTEGER NOT NULL CHECK (cantidad > 0),
  precio_unitario NUMERIC(10, 2),
  nota        TEXT DEFAULT ''
);

-- Conserva el precio histórico aunque después cambie el menú.
ALTER TABLE pedido_detalle
  ADD COLUMN IF NOT EXISTS precio_unitario NUMERIC(10, 2);

UPDATE pedido_detalle
SET precio_unitario = (
  SELECT precio
  FROM productos
  WHERE productos.id = pedido_detalle.producto_id
)
WHERE precio_unitario IS NULL;

ALTER TABLE pedido_detalle
  ALTER COLUMN precio_unitario SET NOT NULL;

-- ── Tabla ventas ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS ventas (
  id        SERIAL PRIMARY KEY,
  pedido_id INTEGER REFERENCES pedidos(id) ON DELETE SET NULL,
  total     NUMERIC(10,2) NOT NULL,
  fecha     TIMESTAMPTZ DEFAULT NOW()
);

-- El upsert de ventas necesita un único registro por pedido. Se limpia cualquier
-- duplicado heredado antes de crear el índice para que la migración sea segura.
DELETE FROM ventas
WHERE pedido_id IS NOT NULL
  AND id NOT IN (
    SELECT MAX(id)
    FROM ventas
    WHERE pedido_id IS NOT NULL
    GROUP BY pedido_id
  );

CREATE UNIQUE INDEX IF NOT EXISTS ventas_pedido_id_unique
  ON ventas (pedido_id);

-- ── Productos de ejemplo ─────────────────────────────
INSERT INTO productos (nombre, precio, categoria, activo)
SELECT * FROM (VALUES
  ('Tacos de Carne',      45.00, 'Tacos',     true),
  ('Tacos de Pastor',     42.00, 'Tacos',     true),
  ('Torta de Milanesa',   55.00, 'Tortas',    true),
  ('Agua de Jamaica',     18.00, 'Bebidas',   true),
  ('Refresco',            22.00, 'Bebidas',   true),
  ('Enchiladas Verdes',   60.00, 'Platillos', true),
  ('Pozole Rojo',         75.00, 'Platillos', true),
  ('Guacamole',           35.00, 'Entradas',  true)
) AS semillas(nombre, precio, categoria, activo)
WHERE NOT EXISTS (SELECT 1 FROM productos);
