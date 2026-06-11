async function testFlow() {
  const BASE_URL = 'http://localhost:3000/api';
  
  try {
    console.log('---  Iniciando Pruebas de Integración ---');

    // 0. Autenticarse para obtener token
    console.log('0. Iniciando sesión...');
    let token = '';
    let resLogin = await fetch(`${BASE_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'admin', password: 'admin123' })
    });
    
    let loginData = await resLogin.json();
    if (loginData.success) {
      token = loginData.token;
      console.log('✅ Autenticado con éxito (password: admin123).');
    } else {
      // Intentar con la contraseña de schema.sql
      resLogin = await fetch(`${BASE_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: 'admin', password: 'Admin3Pisos' })
      });
      loginData = await resLogin.json();
      if (loginData.success) {
        token = loginData.token;
        console.log('✅ Autenticado con éxito (password: Admin3Pisos).');
      } else {
        throw new Error('No se pudo autenticar con las contraseñas por defecto.');
      }
    }

    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    };

    // 1. Obtener productos
    console.log('1. Obteniendo productos...');
    const resProductos = await fetch(`${BASE_URL}/productos`, { headers });
    const resProdJson = await resProductos.json();
    const productos = resProdJson.productos || [];
    console.log(`✅ ${productos.length} productos disponibles.`);

    if (productos.length === 0) throw new Error('No hay productos para probar');

    // 2. Crear un pedido (Simulando Mesero)
    console.log('2. Creando un pedido (Mesa 5)...');
    const pedidoPayload = {
      mesa: 5,
      tipo: 'aqui',
      productos: [
        { producto_id: productos[0].id, cantidad: 2, nota: 'Sin cebolla' },
        { producto_id: productos[1].id, cantidad: 1, nota: 'Bien cocido' }
      ]
    };

    const resCrear = await fetch(`${BASE_URL}/pedidos`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pedidoPayload)
    });
    const nuevoPedido = await resCrear.json();
    if (!nuevoPedido.success) {
      throw new Error(`Error al crear pedido: ${nuevoPedido.error || JSON.stringify(nuevoPedido)}`);
    }
    console.log(' Pedido creado:', nuevoPedido.pedido);
    const pedidoId = nuevoPedido.pedido.id;

    // 3. Verificar en cocina (Obtener todos los pedidos)
    console.log('3. Verificando pedido en la lista de cocina...');
    const resPedidos = await fetch(`${BASE_URL}/pedidos`, { headers });
    const todosLosPedidosJson = await resPedidos.json();
    const todosLosPedidos = todosLosPedidosJson.pedidos || [];
    const pedidoEncontrado = todosLosPedidos.find(p => p.id === pedidoId);
    
    if (pedidoEncontrado) {
      console.log(` Pedido #${pedidoId} encontrado en cocina.`);
      console.log(`   Estado: ${pedidoEncontrado.estado}`);
      console.log(`   Items: ${pedidoEncontrado.productos.length}`);
    } else {
      throw new Error('El pedido no apareció en la lista');
    }

    // 4. Cambiar a "preparando" (Simulando Chef)
    console.log('4. Cambiando estado a "preparando"...');
    const resUpdate1 = await fetch(`${BASE_URL}/pedidos/${pedidoId}/estado`, {
      method: 'PUT',
      headers,
      body: JSON.stringify({ estado: 'preparando' })
    });
    const update1Data = await resUpdate1.json();
    if (!update1Data.success) {
      throw new Error(`Error al actualizar a preparando: ${update1Data.error}`);
    }
    console.log('✅ Estado actualizado a preparando.');

    // 5. Cambiar a "listo" (Simulando Chef)
    console.log('5. Cambiando estado a "listo"...');
    const resUpdate2 = await fetch(`${BASE_URL}/pedidos/${pedidoId}/estado`, {
      method: 'PUT',
      headers,
      body: JSON.stringify({ estado: 'listo' })
    });
    const pedidoFinal = await resUpdate2.json();
    if (!pedidoFinal.success) {
      throw new Error(`Error al actualizar a listo: ${pedidoFinal.error}`);
    }
    console.log('✅ Estado final:', pedidoFinal.pedido.estado);

    console.log('--- 🏆 Pruebas completadas con éxito ---');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error durante las pruebas:', error);
    process.exit(1);
  }
}

testFlow();
