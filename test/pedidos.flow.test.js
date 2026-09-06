const test = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const request = require('supertest');
const { newDb } = require('pg-mem');

process.env.JWT_SECRET = 'integration-test-secret';
process.env.DATABASE_URL = 'postgresql://test:test@localhost:5432/test';
process.env.NODE_ENV = 'test';

const db = newDb({ autoCreateForeignKeyIndices: true });
db.public.none(`
  CREATE TABLE usuarios (
    id SERIAL PRIMARY KEY,
    username VARCHAR(30) UNIQUE NOT NULL,
    password TEXT NOT NULL,
    role VARCHAR(10) NOT NULL
  );
  CREATE TABLE productos (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    precio NUMERIC(10,2) NOT NULL,
    categoria VARCHAR(50),
    activo BOOLEAN DEFAULT TRUE
  );
  CREATE TABLE pedidos (
    id SERIAL PRIMARY KEY,
    mesa INTEGER NOT NULL,
    estado VARCHAR(15) NOT NULL DEFAULT 'pendiente',
    total NUMERIC(10,2) NOT NULL DEFAULT 0,
    tipo VARCHAR(10) NOT NULL DEFAULT 'aqui',
    comensal VARCHAR(50),
    usuario_id INTEGER REFERENCES usuarios(id),
    creado_en TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE pedido_detalle (
    id SERIAL PRIMARY KEY,
    pedido_id INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id),
    cantidad INTEGER NOT NULL,
    precio_unitario NUMERIC(10,2) NOT NULL,
    nota TEXT
  );
  CREATE TABLE ventas (
    id SERIAL PRIMARY KEY,
    pedido_id INTEGER UNIQUE REFERENCES pedidos(id),
    total NUMERIC(10,2) NOT NULL,
    fecha TIMESTAMPTZ DEFAULT NOW()
  );
`);

const adapter = db.adapters.createPg();
const pool = new adapter.Pool();
const dbModulePath = require.resolve('../src/config/db');
require.cache[dbModulePath] = {
  id: dbModulePath,
  filename: dbModulePath,
  loaded: true,
  exports: pool,
};

const app = require('../src/app');
app.set('io', { emit() {} });

test.before(async () => {
  const password = await bcrypt.hash('password123', 4);
  await pool.query(
    `INSERT INTO usuarios (username, password, role) VALUES
      ('mesero1', $1, 'mesero'),
      ('cocina1', $1, 'cocina')`,
    [password]
  );
  await pool.query(
    `INSERT INTO productos (nombre, precio, categoria, activo)
     VALUES ('Hamburguesa', 85, 'Comida', true)`
  );
});

test.after(async () => {
  await pool.end();
});

test('flujo completo: mesero crea, cocina prepara y mesero cobra', async () => {
  const meseroLogin = await request(app)
    .post('/api/auth/login')
    .send({ username: 'mesero1', password: 'password123' })
    .expect(200);
  const cocinaLogin = await request(app)
    .post('/api/auth/login')
    .send({ username: 'cocina1', password: 'password123' })
    .expect(200);
  const meseroToken = meseroLogin.body.token;
  const cocinaToken = cocinaLogin.body.token;

  const create = await request(app)
    .post('/api/pedidos')
    .set('Authorization', `Bearer ${meseroToken}`)
    .send({
      mesa: 4,
      tipo: 'aqui',
      comensal: 'Ana',
      productos: [{ producto_id: 1, cantidad: 2, nota: 'Sin cebolla' }],
    })
    .expect(201);

  const pedidoId = create.body.pedido.id;
  assert.equal(create.body.pedido.total, 170);
  assert.equal(create.body.pedido.productos[0].precio, 85);

  await request(app)
    .put(`/api/pedidos/${pedidoId}/estado`)
    .set('Authorization', `Bearer ${cocinaToken}`)
    .send({ estado: 'preparando' })
    .expect(200);

  const forbidden = await request(app)
    .put(`/api/pedidos/${pedidoId}/estado`)
    .set('Authorization', `Bearer ${cocinaToken}`)
    .send({ estado: 'pagado' })
    .expect(403);
  assert.equal(forbidden.body.code, 'INVALID_STATUS_TRANSITION');

  await request(app)
    .put(`/api/pedidos/${pedidoId}/estado`)
    .set('Authorization', `Bearer ${cocinaToken}`)
    .send({ estado: 'listo' })
    .expect(200);

  await request(app)
    .put(`/api/pedidos/${pedidoId}/estado`)
    .set('Authorization', `Bearer ${meseroToken}`)
    .send({ estado: 'pagado' })
    .expect(200);

  const { rows: ventas } = await pool.query(
    'SELECT pedido_id, total FROM ventas WHERE pedido_id = $1',
    [pedidoId]
  );
  assert.equal(ventas.length, 1);
  assert.equal(Number(ventas[0].total), 170);
});
