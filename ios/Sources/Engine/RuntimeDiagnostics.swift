import Foundation
import WebKit

enum RuntimeDiagnostics {
    static let bootstrap = """
    (() => {
      const send = (type, detail) => {
        try { window.webkit.messageHandlers.gtaDiagnostics.postMessage({type, detail: String(detail).slice(0, 2048)}); } catch (_) {}
      };
      window.addEventListener('error', e => send('error', e.message || e.error));
      window.addEventListener('unhandledrejection', e => send('promise', e.reason));
      const oldWarn = console.warn, oldError = console.error;
      console.warn = function(...args) { send('warn', args.join(' ')); oldWarn.apply(console, args); };
      console.error = function(...args) { send('error', args.join(' ')); oldError.apply(console, args); };
      try {
        const bc = new BroadcastChannel('game-progress');
        bc.onmessage = e => {
          const d = e.data || {};
          if (d.world) send('engine', 'first world frame signaled');
          else if (d.gpuLost) send('gpu', 'GPU lost: ' + d.gpuLost);
          else if (d.error) send('engine', 'error: ' + d.error);
          else if (d.compiling !== undefined) send('shaders', 'pipelines compiling: ' + d.compiling);
        };
      } catch (e) { send('warn', 'BroadcastChannel unavailable: ' + e); }
      // Exposes exact analog input; mapping below is a temporary keyboard/mouse fallback,
      // not a claim of the game's native XInput/Gamepad ABI compatibility.
      const held = new Set();
      let wasFiring = false, wasAiming = false;
      function key(code, active) {
        if (active === held.has(code)) return;
        if (active) held.add(code); else held.delete(code);
        window.dispatchEvent(new KeyboardEvent(active ? 'keydown' : 'keyup',
          { bubbles: true, code, key: code.startsWith('Key') ? code.slice(3).toLowerCase() : code }));
      }
      window.__gtaNativePad = s => {
        window.__gtaAnalogState = s;
        const t = 0.19;
        key('KeyW', (s.ly || 0) > t); key('KeyS', (s.ly || 0) < -t);
        key('KeyA', (s.lx || 0) < -t); key('KeyD', (s.lx || 0) > t);
        key('Space', (s.a || 0) > .5); key('KeyR', (s.x || 0) > .5);
        key('KeyF', (s.y || 0) > .5); key('KeyQ', (s.lb || 0) > .5);
        key('Escape', (s.b || 0) > .5);
        const canvas = document.getElementById('canvas');
        const firing = (s.rt || 0) > .3, aiming = (s.lt || 0) > .3;
        if (canvas && firing !== wasFiring) {
          (firing ? canvas : window).dispatchEvent(new MouseEvent(firing ? 'mousedown' : 'mouseup', {button: 0, bubbles: true}));
          wasFiring = firing;
        }
        if (canvas && aiming !== wasAiming) {
          (aiming ? canvas : window).dispatchEvent(new MouseEvent(aiming ? 'mousedown' : 'mouseup', {button: 2, bubbles: true}));
          wasAiming = aiming;
        }
        if (canvas && (Math.abs(s.rx || 0) > t || Math.abs(s.ry || 0) > t)) {
          const evt = new MouseEvent('mousemove', {bubbles: true});
          Object.defineProperty(evt, 'movementX', {value: Math.round((s.rx || 0) * 9)});
          Object.defineProperty(evt, 'movementY', {value: Math.round(-(s.ry || 0) * 9)});
          canvas.dispatchEvent(evt);
        }
      };
      send('boot', 'injected runtime diagnostics and controller bridge');
    })();
    """

    static func probe(_ webView: WKWebView) {
        let js = """
        (() => JSON.stringify({
          userAgent: navigator.userAgent,
          isolated: crossOriginIsolated,
          wasm: typeof WebAssembly,
          wasmJIT: 'not externally observable',
          sharedArrayBuffer: typeof SharedArrayBuffer,
          offscreenCanvas: typeof HTMLCanvasElement.prototype.transferControlToOffscreen,
          webgpu: !!navigator.gpu,
          memoryGB: navigator.deviceMemory || null,
          cores: navigator.hardwareConcurrency
        }))()
        """
        webView.evaluateJavaScript(js) { result, error in
            LogStore.shared.write("jit", error.map { "Capability probe failed: \($0)" } ?? "\(result ?? "<none>")")
        }
    }
}
