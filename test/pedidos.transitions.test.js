const test = require('node:test');
const assert = require('node:assert/strict');

process.env.JWT_SECRET ||= 'test-secret';
process.env.DATABASE_URL ||= 'postgresql://test:test@localhost:5432/test';

const { puedeCambiarEstado } = require('../src/services/pedidos.service');

test('cocina solo avanza pendiente a preparando y preparando a listo', () => {
  assert.equal(puedeCambiarEstado('pendiente', 'preparando', 'cocina'), true);
  assert.equal(puedeCambiarEstado('preparando', 'listo', 'cocina'), true);
  assert.equal(puedeCambiarEstado('listo', 'pagado', 'cocina'), false);
  assert.equal(puedeCambiarEstado('pendiente', 'cancelado', 'cocina'), false);
});

test('mesero cobra pedidos listos y cancela pedidos activos', () => {
  assert.equal(puedeCambiarEstado('listo', 'pagado', 'mesero'), true);
  assert.equal(puedeCambiarEstado('pendiente', 'cancelado', 'mesero'), true);
  assert.equal(puedeCambiarEstado('preparando', 'cancelado', 'mesero'), true);
  assert.equal(puedeCambiarEstado('pendiente', 'listo', 'mesero'), false);
});

test('un pedido pagado o cancelado no se reabre', () => {
  for (const role of ['admin', 'mesero', 'cocina']) {
    assert.equal(puedeCambiarEstado('pagado', 'preparando', role), false);
    assert.equal(puedeCambiarEstado('cancelado', 'pendiente', role), false);
  }
});

test('repetir el mismo estado es idempotente', () => {
  assert.equal(puedeCambiarEstado('preparando', 'preparando', 'cocina'), true);
});
