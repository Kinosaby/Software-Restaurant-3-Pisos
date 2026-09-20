/* Reuse the full web UI, replacing only operations that need local durability. */
if(window.LOCAL_POS){
 // ── Web Audio API: Campana KDS de cocina (Sonido de alerta sintetizado) ──
 let _kdsAudioCtx = null;
 function playKdsBell() {
  try {
   const AudioContext = window.AudioContext || window.webkitAudioContext;
   if (!AudioContext) return;
   if (!_kdsAudioCtx || _kdsAudioCtx.state === 'closed') {
    _kdsAudioCtx = new AudioContext();
   }
   if (_kdsAudioCtx.state === 'suspended') {
    _kdsAudioCtx.resume();
   }
   const ctx = _kdsAudioCtx;
   const now = ctx.currentTime;
   // Doble campana de comanda: fundamental 880Hz (A5) + armónico 1760Hz, y repique 1046.5Hz (C6)
   const tones = [
    { freq: 880, start: now, dur: 0.75, gain: 0.35 },
    { freq: 1760, start: now, dur: 0.45, gain: 0.15 },
    { freq: 1046.5, start: now + 0.13, dur: 0.95, gain: 0.40 },
    { freq: 2093, start: now + 0.13, dur: 0.55, gain: 0.18 }
   ];
   for (const t of tones) {
    const osc = ctx.createOscillator();
    const gainNode = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(t.freq, t.start);
    gainNode.gain.setValueAtTime(0.0001, t.start);
    gainNode.gain.exponentialRampToValueAtTime(t.gain, t.start + 0.015);
    gainNode.gain.exponentialRampToValueAtTime(0.0001, t.start + t.dur);
    osc.connect(gainNode);
    gainNode.connect(ctx.destination);
    osc.start(t.start);
    osc.stop(t.start + t.dur);
   }
  } catch (err) {
   console.warn('No se pudo reproducir campana KDS:', err);
  }
 }
 document.addEventListener('click', () => {
  if (_kdsAudioCtx && _kdsAudioCtx.state === 'suspended') { _kdsAudioCtx.resume(); }
 }, { once: false });

 const originalRequest=request;
 request=async function(method,path,body=null){
  if(method==='GET')return originalRequest(method,path,body);
  const track=path!='/api/auth/login'&&!!Auth.user;
  const digest=track?Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify([method,path,body]))))).map(n=>n.toString(16).padStart(2,'0')).join(''):'';
  const commandKey='local-command:'+Auth.user?.id+':'+digest;
  const operation=(track&&localStorage.getItem(commandKey))||crypto.randomUUID();
  if(track)localStorage.setItem(commandKey,operation);
  const headers={'Content-Type':'application/json','X-Operation-Id':operation};if(Auth.token)headers.Authorization='Bearer '+Auth.token;
  const response=await fetch(path,{method,headers,body:body?JSON.stringify(body):null});const data=await response.json();
  if(track&&(response.ok||(response.status>=400&&response.status<500&&response.status!==401)))localStorage.removeItem(commandKey);
  if(!response.ok){const e=new Error(data.error||'No se pudo completar');e.status=response.status;throw e;}return data;
 };
 const css=document.createElement('style');css.textContent='#local-status{position:sticky;top:0;z-index:1000;padding:8px 12px;background:#173d32;color:#fff;font:13px Outfit,sans-serif;display:flex;justify-content:space-between;gap:8px;align-items:center}#local-status button{font:inherit;color:inherit;background:transparent;border:1px solid #fff6;border-radius:6px;padding:5px 10px}#pending-panel{padding:12px;background:#493915;color:#fff}.topbar{position:relative!important}.local-stale{background:#624719!important}[hidden]{display:none!important}';document.head.append(css);
 const status=document.createElement('div');status.id='local-status';status.innerHTML='<span id="local-status-text">Conectando con cocina…</span><div><button id="local-pending-toggle">Pendientes</button> <button id="local-settings">Conexión</button></div>';
 const pendingPanel=document.createElement('div');pendingPanel.id='pending-panel';pendingPanel.hidden=true;document.body.prepend(pendingPanel);document.body.prepend(status);
 document.getElementById('local-pending-toggle').onclick=()=>pendingPanel.hidden=!pendingPanel.hidden;
 document.getElementById('local-settings').onclick=()=>window.PosNative?.postMessage(JSON.stringify({action:'settings',token:Auth.token}));
 function renderLocalItems(){for(const p of State.pedidos)_itemsListos[p.id]=new Set((p.productos||[]).map((i,n)=>i.listo?n:-1).filter(n=>n>=0));}
 async function loadLocalExtras(){const d=await get('/api/extras');State.extras=d.extras||[];_saveExtras();}
 let refreshing=false;
 window.addEventListener('pos-refresh',async()=>{
  if(!Auth.token||refreshing)return;refreshing=true;
  try{const p=await api.pedidos.listar();State.pedidos=p.pedidos||[];const products=await api.productos.listar();State.productos=products.productos||[];await loadLocalExtras();renderLocalItems();renderCocina();renderCocinaExtras();renderMeseroPedidos();renderMesaSelector();if(getRole()==='admin'){renderAdminProducts();renderAdminPedidos();scheduleMetricasRefresh();}if(getRole()!=='cocina')renderCatalogo();}catch(_){}finally{refreshing=false;}
 });
 checkSession=async function(){if(!Auth.token){go('screen-login');return;}try{const result=await api.auth.me();Auth.set({token:Auth.token,user:result.user});updateTopbar();initSocket();goToRolePanel();}catch(e){if(e.status===401){await doLogout();}else{go('screen-login');showLoginError(e.message);}}};
 const oldInit=initSocket;
 initSocket=function(){if(State.socket)return;oldInit();
  State.socket.on('nuevo_pedido',()=>{
   if(getRole()==='cocina'||getRole()==='admin') playKdsBell();
   State.pedidos=[...new Map(State.pedidos.map(p=>[p.id,p])).values()];renderCocina();renderMeseroPedidos();renderMesaSelector();renderAdminPedidos();
  });
  State.socket.on('connect_error',e=>{if(e.message==='INVALID_TOKEN')doLogout();});
  State.socket.on('pedido_actualizado',()=>{renderLocalItems();renderCocina();});
  State.socket.on('pedido_eliminado',d=>{State.pedidos=State.pedidos.filter(p=>p.id!==d.id);renderMeseroPedidos();renderCocina();renderAdminPedidos();scheduleMetricasRefresh();});
  for(const event of ['extras_actualizados','extra_pedido'])State.socket.on(event,async()=>{
   if(event==='extra_pedido'&&(getRole()==='cocina'||getRole()==='admin')) playKdsBell();
   await loadLocalExtras();renderCocinaExtras();
  });
  State.socket.on('catalogo_actualizado',()=>window.dispatchEvent(new Event('pos-refresh')));
 };
 const draftKey=()=> 'local-cart:'+(Auth.user?.id||'none');
 const saveDraft=()=>{if(Auth.user)localStorage.setItem(draftKey(),JSON.stringify({comensales:_comensales,active:_comensalActivo,mesa:_mesaSeleccionada,tipo:_tipoPedido}));};
 const oldRenderCart=renderCarrito;renderCarrito=function(){oldRenderCart();saveDraft();};
 const restored=new Set(),oldLoadMesero=loadMeseroData,oldLogout=doLogout;
 let loggingOut=false;
 doLogout=async function(){
  if(loggingOut)return;loggingOut=true;saveDraft();
  try{
   if(Auth.token){const response=await fetch('/api/auth/logout',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+Auth.token},body:'{}'});if(!response.ok)throw new Error('No se pudo cerrar la sesión. Vuelve a intentar.');}
   restored.clear();oldLogout();_comensales=[{nombre:'C1',items:[]}];_comensalActivo=0;limpiarMesaSeleccionada();_tipoPedido='aqui';pendingPanel.replaceChildren();localStorage.removeItem('cocina_extras');
  }catch(e){toastErr(e.message);}finally{loggingOut=false;}
 };
 const oldSetNota=setNota;setNota=function(id,note){oldSetNota(id,note);saveDraft();};document.addEventListener('change',saveDraft);
 loadMeseroData=async function(){
  if(!restored.has(draftKey())){restored.add(draftKey());try{const d=JSON.parse(localStorage.getItem(draftKey()));if(d){_comensales=d.comensales;_comensalActivo=d.active;_mesaSeleccionada=d.mesa;_tipoPedido=d.tipo;document.getElementById('mesa-num').value=d.mesa||'';document.getElementById('mesa-badge').classList.toggle('mesa-badge-activa',!!d.mesa);document.getElementById('mesa-badge-text').textContent=d.mesa===99?'Para Llevar':d.mesa?'Mesa '+d.mesa:'Seleccionar mesa';setTipoPedido(d.tipo);}}catch(_){}}
  await oldLoadMesero();renderCarrito();
 };
 submitPedido=async function(){
  const diners=_comensales.filter(c=>c.items.length),mesa=Number(document.getElementById('mesa-num').value);if(!mesa||!diners.length){toastErr('Selecciona mesa y productos');return;}if(!confirm('¿Guardar y enviar este pedido a cocina?'))return;
  const btn=document.getElementById('btn-enviar-pedido');btn.disabled=true;loading(true);
  const tempOrders=diners.map(c=>({
   id: -Date.now() - Math.floor(Math.random()*1000),
   mesa,
   tipo: _tipoPedido,
   comensal: c.nombre,
   estado: 'pendiente',
   creado_en: new Date().toISOString(),
   _optimistic: true,
   productos: c.items.map((i,idx)=>({
    id: idx+1,
    producto_id: i.producto_id,
    nombre: i.nombre || (State.productos.find(pr=>pr.id===i.producto_id)?.nombre ?? 'Producto'),
    precio: i.precio || (State.productos.find(pr=>pr.id===i.producto_id)?.precio ?? 0),
    cantidad: i.cantidad,
    nota: (i.esLlevar?'[LLEVAR] ':'')+(i.nota||''),
    listo: false
   })),
   total: c.items.reduce((s,i)=>s+(i.precio*i.cantidad),0)
  }));
  try{
   const d=await post('/api/pedidos/lote',{pedidos:diners.map(c=>({mesa,tipo:_tipoPedido,comensal:c.nombre,productos:c.items.map(i=>({producto_id:i.producto_id,cantidad:i.cantidad,nota:(i.esLlevar?'[LLEVAR] ':'')+(i.nota||'')}))}))});
   clearCarrito();limpiarMesaSeleccionada();saveDraft();
   if(d.queued&&!d.blocked){
    for(const to of tempOrders){ if(!State.pedidos.some(p=>p.id===to.id)) State.pedidos.unshift(to); }
    renderMeseroPedidos();renderMesaSelector();
   }
   toastInfo(d.blocked?'Guardado: revisa Pendientes para corregir el envío':d.queued?'Guardado aquí: PENDIENTE DE RECIBIR EN COCINA':'Cocina recibió el pedido');
   await loadMeseroData();
  }catch(e){
   // Offline sends resolve as queued; a thrown error means nothing was saved,
   // so the cart must stay intact for the waiter to fix and retry.
   toastErr(e.message);
  }finally{btn.disabled=false;loading(false);}
 };

 // ── Optimistic UI: Editar pedidos ──
 const oldEdit=api.pedidos.editar;
 api.pedidos.editar=async function(id,b){
  const p=State.pedidos.find(x=>x.id===id);
  if(p){
   if(b.mesa!==undefined) p.mesa=b.mesa;
   if(b.tipo!==undefined) p.tipo=b.tipo;
   if(b.comensal!==undefined) p.comensal=b.comensal;
   p._optimistic=true;
   renderMeseroPedidos();renderMesaSelector();renderCocina();
  }
  try{
   return await oldEdit(id,{...b,version:p?.version});
  }catch(e){
   // Nothing was saved: drop the optimistic edit and let the caller report it.
   window.dispatchEvent(new Event('pos-refresh'));
   throw e;
  }
 };

 // ── Optimistic UI: Agregar productos a pedido ──
 if(typeof confirmarAgregarProductos==='function'){
  const oldConfirmarAgregar=confirmarAgregarProductos;
  confirmarAgregarProductos=async function(){
   if(!_carritoAgregar.length){toastErr('Selecciona al menos un producto');return;}
   const btn=document.getElementById('btn-confirmar-agregar');
   if(btn) btn.disabled=true;
   loading(true);
   const pId=_pedidoAgregarId;
   const itemsToAdd=_carritoAgregar.map(i=>({
    producto_id: i.producto_id,
    nombre: i.nombre || (State.productos.find(pr=>pr.id===i.producto_id)?.nombre ?? 'Producto'),
    precio: i.precio || (State.productos.find(pr=>pr.id===i.producto_id)?.precio ?? 0),
    cantidad: i.cantidad,
    nota: i.esLlevar ? '[LLEVAR] ' + (i.nota||'').trim() : (i.nota||''),
    esLlevar: i.esLlevar
   }));
   // Actualización optimista inmediata en memoria
   const p=State.pedidos.find(x=>x.id===pId);
   if(p){
    p.productos=p.productos||[];
    for(const item of itemsToAdd){
     p.productos.push({
      id: Date.now()+Math.random(),
      producto_id: item.producto_id,
      nombre: item.nombre,
      precio: item.precio,
      cantidad: item.cantidad,
      nota: item.nota,
      listo: false
     });
    }
    p.total=(p.total||0)+itemsToAdd.reduce((s,i)=>s+(i.precio*i.cantidad),0);
    p._optimistic=true;
   }
   closeModal();
   _carritoAgregar=[];
   renderMeseroPedidos();renderMesaSelector();
   try{
    const r=await api.pedidos.agregar(pId,{
     productos: itemsToAdd.map(i=>({producto_id:i.producto_id,cantidad:i.cantidad,nota:i.nota}))
    });
    if(r?.blocked)toastErr(r.mensaje||'No se pudo agregar; revisa Pendientes');
    else if(r?.queued)toastInfo('Guardado aquí: PENDIENTE DE RECIBIR EN COCINA');
    else toastOk('Productos agregados al pedido');
   }catch(e){
    toastErr(e.message);
   }finally{
    if(btn) btn.disabled=false;
    loading(false);
    await loadMeseroData();
   }
  };
 }

 // ── Optimistic UI: Cobro inmediato de pedidos ──
 confirmarCobro=async function(){
  const btn=document.getElementById('btn-confirmar-cobro');
  if(btn) btn.disabled=true;
  loading(true);
  try{
   const ids=_pedidoCobrarId===null?[..._cobroPendientesMesa]:[_pedidoCobrarId];
   const totalEsperado=Number(_pedidoCobrarTotal.toFixed(2));
   const pagoInput=document.getElementById('cobro-pago');
   const recibidoVal=pagoInput?pagoInput.value:totalEsperado;
   const recibido=Number(recibidoVal)||totalEsperado;
   const cambio=Math.max(0,recibido-totalEsperado);
   // Actualización optimista: marcar pedidos como pagados de inmediato en la UI
   for(const id of ids){
    const p=State.pedidos.find(x=>x.id===id);
    if(p){ p.estado='pagado'; p._optimistic=true; }
   }
   _cobroPendientesMesa=[];
   closeModal();
   renderMeseroPedidos();renderMesaSelector();
   try{
    const r=await post('/api/pedidos/cobrar',{ids,total_esperado:totalEsperado,recibido:recibidoVal});
    if(r?.blocked)toastErr(r.mensaje||'No se pudo cobrar; revisa Pendientes');
    else if(r?.queued)toastInfo('Cobro guardado aquí: PENDIENTE DE CONFIRMAR EN COCINA. Cambio: '+fmt.currency(cambio));
    else toastOk('Cobro confirmado. Cambio: '+fmt.currency(r?.cambio??cambio));
   }catch(payErr){
    // Rejected before being saved: nothing was charged, so undo the paid state.
    toastErr(payErr.message);
   }
   await loadMeseroData();
  }catch(e){
   toastErr(e.message);
   window.dispatchEvent(new Event('pos-refresh'));
  }finally{
   if(btn) btn.disabled=false;
   loading(false);
  }
 };
 cobrarMesa=function(key){if(getRole()!=='admin'){toastErr('El cobro corresponde al mesero');return;}if(String(key).startsWith('llevar-'))abrirCobro(Number(String(key).split('-')[1]));else cobrarTodoMesa(Number(key));};
 const oldLoadCocina=loadCocinaData;loadCocinaData=async function(){await oldLoadCocina();try{await loadLocalExtras();}catch(_){}renderLocalItems();renderCocina();renderCocinaExtras();};
 toggleItemListo=async function(id,index){const item=State.pedidos.find(p=>p.id===id)?.productos[index];if(!item)return;try{const d=await patch(`/api/pedidos/${id}/item`,{detalle_id:item.id,listo:!item.listo});State.pedidos=State.pedidos.map(p=>p.id===id?d.pedido:p);renderLocalItems();renderCocina();}catch(e){toastErr(e.message);renderCocina();}};
 toggleExtraItem=async function(id,index){const ex=State.extras.find(e=>e._id===id);if(!ex)return;try{await patch(`/api/extras/${id}`,{item:index,listo:!ex._done?.[index]});await loadLocalExtras();renderCocinaExtras();}catch(e){toastErr(e.message);}};
 terminarExtra=async function(id){try{await patch(`/api/extras/${id}`,{done:true});await loadLocalExtras();renderCocinaExtras();toastOk('Extra listo');}catch(e){toastErr(e.message);}};
 let page=0,historyRows=[];const oldRenderAdmin=renderAdminPedidos;
 renderAdminPedidos=function(){if(_soloHoyAdmin)return oldRenderAdmin();const service=State.pedidos;try{State.pedidos=historyRows;oldRenderAdmin();}finally{State.pedidos=service;}};
 const toolbar=document.createElement('div');toolbar.style='display:flex;gap:8px;flex-wrap:wrap;padding:12px';toolbar.innerHTML='<input id="history-date" type="date"><button class="btn btn-outline btn-sm" id="history-filter">Buscar fecha</button><button class="btn btn-ghost btn-sm" id="history-prev">Anterior</button><span id="history-page"></span><button class="btn btn-ghost btn-sm" id="history-next">Siguiente</button>';toolbar.hidden=true;document.getElementById('admin-orders').append(toolbar);
 async function history(){try{const date=document.getElementById('history-date').value;const d=await get(`/api/pedidos?scope=history&page=${page}${date?'&date='+date:''}`);historyRows=d.pedidos;renderAdminPedidos();document.getElementById('history-page').textContent='Página '+(page+1);document.getElementById('history-prev').disabled=page===0;document.getElementById('history-next').disabled=!d.hasMore;}catch(e){toastErr(e.message);}}
 toggleHistorialPedidos=async function(){_soloHoyAdmin=!_soloHoyAdmin;toolbar.hidden=_soloHoyAdmin;page=0;if(_soloHoyAdmin)await loadAdminData();else await history();};
 document.getElementById('history-filter').onclick=()=>{page=0;history();};document.getElementById('history-prev').onclick=()=>{page=Math.max(0,page-1);history();};document.getElementById('history-next').onclick=()=>{page++;history();};
 const oldDeleteOrder=adminDeletePedido;adminDeletePedido=async function(id){await oldDeleteOrder(id);if(!_soloHoyAdmin)await history();};
 const backup=document.createElement('button');backup.className='btn btn-gold btn-sm';backup.textContent='Guardar respaldo';backup.onclick=()=>window.PosNative?.postMessage(JSON.stringify({action:'backup',token:Auth.token}));document.querySelector('#screen-admin .container').prepend(backup);
 const menuTools=document.createElement('div');menuTools.style='display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px';
 for(const [action,label] of [['restaurant-menu','Cargar menú del restaurante'],['import-menu','Importar menú'],['export-menu','Guardar archivo del menú']]){
  const button=document.createElement('button');button.className='btn btn-outline btn-sm';button.textContent=label;
  button.onclick=()=>window.PosNative?.postMessage(JSON.stringify({action,token:Auth.token}));menuTools.append(button);
 }
 document.querySelector('#admin-products .pane-header').after(menuTools);
 setInterval(async()=>{try{const d=await get('/api/local/status');status.classList.toggle('local-stale',!d.connected);document.getElementById('local-status-text').textContent=(d.central?'Central de cocina · operación local':d.connected?'Enlace local con cocina activo':'Sin enlace con cocina')+(d.pending.length?' · '+d.pending.length+' envíos pendientes':'');pendingPanel.replaceChildren();
  for(const e of d.pending){const line=document.createElement('p');line.textContent=(e.status==='blocked'?'Requiere revisión: '+e.error:'Pendiente de recibir en cocina')+' · '+(e.body.pedidos||[e.body]).map(p=>'Mesa '+p.mesa+' / '+(p.comensal||'Cuenta')).join(', ');pendingPanel.append(line);if(e.status==='blocked'){const retry=document.createElement('button');retry.className='btn btn-gold btn-sm';retry.textContent='Reintentar este envío';retry.onclick=async()=>{try{await post('/api/local/retry',{id:e.id});toastInfo('Envío revisado. Consulta su estado aquí.');}catch(err){toastErr(err.message);}};pendingPanel.append(retry);}}
  if(!d.pending.length)pendingPanel.textContent='Sin envíos pendientes';}catch(_){}},2000);
}
