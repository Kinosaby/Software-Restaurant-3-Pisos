// Socket-compatible local events. No external server or CDN.
window.LOCAL_POS = true;
window.io = function () {
  const handlers = {};
  let stopped = false, cursor = -1, connected = false, timer;
  function emit(name, data) {
    for (const fn of handlers[name] || []) {
      try { Promise.resolve(fn(data)).catch(() => {}); }
      catch (error) { console.error(error); }
    }
  }
  async function poll() {
    if (stopped) return;
    try {
      const data = await get('/api/local/events?after=' + cursor);
      if (stopped) return;
      if (!connected) { connected = true; emit('connect'); }
      cursor = data.cursor;
      if (data.reset) window.dispatchEvent(new Event('pos-refresh'));
      for (const event of data.events || []) emit(event.name, event.data);
    } catch (error) {
      if (connected) { connected = false; emit('disconnect'); }
      if (error.status === 401) emit('connect_error', new Error('INVALID_TOKEN'));
    } finally {
      if (!stopped) timer = setTimeout(poll, 1200);
    }
  }
  timer = setTimeout(poll, 10);
  return {
    on(name, fn) { (handlers[name] ??= []).push(fn); return this; },
    disconnect() { stopped = true; clearTimeout(timer); emit('disconnect'); },
  };
};
