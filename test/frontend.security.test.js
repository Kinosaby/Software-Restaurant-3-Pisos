const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
function frontend() {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, { innerHTML: '', textContent: '', style: {}, classList: { add() {}, remove() {}, toggle() {} }, appendChild() {}, replaceChildren() {}, append() {} });
    return elements.get(id);
  };
  const context = vm.createContext({ window: { LOCAL_POS: true },
    document: { getElementById: element, querySelector: element, addEventListener() {}, querySelectorAll: () => [], createElement: () => element('created') },
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} }, setTimeout() {}, setInterval() {}, console });
  for (const file of ['api','main','mesero','cocina','admin']) vm.runInContext(fs.readFileSync(`restaurante-app/js/${file}.js`, 'utf8'), context);
  return { context, element, run: code => vm.runInContext(code, context) };
}
test('Cart names and notes cannot inject HTML or input event attributes', () => {
  const { run, element, context } = frontend();
  context.attack = '\"><img src=x onerror=alert(1)><input autofocus onfocus=alert(2) value="';
  run(`_comensales=[{nombre:attack,items:[{producto_id:1,nombre:attack,nota:attack,precio:18,cantidad:1}]}];renderCarrito();`);
  for (const id of ['carrito-body','comensal-tabs']) {
    const html = element(id).innerHTML;
    assert.ok(!html.includes('<img')); assert.ok(!html.includes('<input autofocus')); assert.ok(html.includes('&lt;img'));
  }
  run(`State.pedidos=[{id:1,mesa:1,estado:'pendiente',total:18,productos:[{cantidad:1,nombre:attack,nota:attack}]}];openModal=()=>{};verDetallePedido(1);`);
  assert.ok(!element('detalle-content').innerHTML.includes('<img'));
});
test('Admin action attributes contain only record IDs, never user-provided names', () => {
  const { run, element, context } = frontend(); context.attack = "');alert(1);//<img src=x>";
  run(`State.usuarios=[{id:1,username:attack,role:'admin'}];State.productos=[{id:1,nombre:attack,categoria:attack,precio:18,activo:true}];renderAdminUsers();renderAdminProducts();`);
  const html = ['#table-users tbody','#table-products tbody'].map(id => element(id).innerHTML).join('');
  assert.ok(html.includes('deleteUser(1)')); assert.ok(html.includes('deleteProduct(1)'));
  assert.ok(!html.includes('<img')); assert.ok(!html.includes("deleteUser(1,'"));
});
