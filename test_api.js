async function testFlow() {
  const BASE_URL = 'http://localhost:3000/api';
  
  try {
    console.log('--- 🧪 Iniciando Pruebas de Integración ---');

    // 1. Obtener productos
    console.log('1. Obteniendo productos...');
    const resProductos = await fetch(`${BASE_URL}/productos`);
    const productos = await resProductos.json();
    console.log(`✅ ${productos.length} productos disponibles.`);

    if (productos.length === 0) throw new Error('No hay productos para probar');

    // 2. Crear un pedido (Simulando Mesero)
    console.log('2. Creando un pedido (Mesa 5)...');
    const pedidoPayload = {
      mesa: 5,
      productos: [
        { producto_id: productos[0].id, cantidad: 2, nota: 'Sin cebolla' },
        { producto_id: productos[1].id, cantidad: 1, nota: 'Bien cocido' }
      ]
    };

    const resCrear = await fetch(`${BASE_URL}/pedidos`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(pedidoPayload)
    });
    const nuevoPedido = await resCrear.json();
    console.log('✅ Pedido creado:', nuevoPedido.pedido);
    const pedidoId = nuevoPedido.pedido.id;

    // 3. Verificar en cocina (Obtener todos los pedidos)
    console.log('3. Verificando pedido en la lista de cocina...');
    const resPedidos = await fetch(`${BASE_URL}/pedidos`);
    const todosLosPedidos = await resPedidos.json();
    const pedidoEncontrado = todosLosPedidos.find(p => p.id === pedidoId);
    
    if (pedidoEncontrado) {
      console.log(`✅ Pedido #${pedidoId} encontrado en cocina.`);
      console.log(`   Estado: ${pedidoEncontrado.estado}`);
      console.log(`   Items: ${pedidoEncontrado.productos.length}`);
    } else {
      throw new Error('El pedido no apareció en la lista');
    }

    // 4. Cambiar a "preparando" (Simulando Chef)
    console.log('4. Cambiando estado a "preparando"...');
    const resUpdate1 = await fetch(`${BASE_URL}/pedidos/${pedidoId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ estado: 'preparando' })
    });
    console.log('✅ Estado actualizado a preparando.');

    // 5. Cambiar a "listo" (Simulando Chef)
    console.log('5. Cambiando estado a "listo"...');
    const resUpdate2 = await fetch(`${BASE_URL}/pedidos/${pedidoId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ estado: 'listo' })
    });
    const pedidoFinal = await resUpdate2.json();
    console.log('✅ Estado final:', pedidoFinal.pedido.estado);

    console.log('--- 🏆 Pruebas completadas con éxito ---');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error durante las pruebas:', error);
    process.exit(1);
  }
}

testFlow();
