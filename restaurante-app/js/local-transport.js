// Socket-compatible local event polling; no external server or CDN.
window.LOCAL_POS=true;
window.io=function(){
 const handlers={};let stopped=false,cursor=-1,connected=false,timer;
 const emit=(name,data)=>{for(const fn of handlers[name]||[]){try{Promise.resolve(fn(data)).catch(()=>{});}catch(e){console.error(e);}};
 async function poll(){if(stopped)return;try{const d=await get('/api/local/events?after='+cursor);if(stopped)return;if(!connected){connected=true;emit('connect');}cursor=d.cursor;if(d.reset)window.dispatchEvent(new Event('pos-refresh'));for(const e of d.events||[])emit(e.name,e.data);}catch(e){if(connected){connected=false;emit('disconnect');}if(e.status===401)emit('connect_error',new Error('INVALID_TOKEN'));}finally{if(!stopped)timer=setTimeout(poll,1200);}}
 timer=setTimeout(poll,10);return {on(name,fn){(handlers[name]??=[]).push(fn);return this;},disconnect(){stopped=true;clearTimeout(timer);emit('disconnect');}};
};
