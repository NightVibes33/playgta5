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
      send('boot', 'injected runtime diagnostics; the controller bridge loads from ios_controller.js');
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
