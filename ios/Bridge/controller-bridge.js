/* GTAiOS controller-to-existing-WASM-input bridge.
 * Captures the COMPLETE hardware pad state. The supplied engine binary exposes
 * only a keyboard/mouse input block; true analog movement/vehicle acceleration
 * requires a new engine input ABI, which is not in this public repository.
 * Right-stick camera uses direct mouse-delta writes into the existing shared
 * input block rather than synthetic MouseEvents, which WebKit cannot pointer-lock.
 */
(function () {
  'use strict';
  const keysHeld = new Set();
  let memory = null, input = null, latest = { connected: 0 };
  let oldButtons = 0, oldMenu = false, menuOpen = false;
  let dxFraction = 0, dyFraction = 0;
  let profile = 'foot';
  let customMappings = {};
  let oldChord = false;
  let sensitivity = 1;
  let lastDiagnostic = '';
  const modeKeys = new Set(['KeyW','KeyA','KeyS','KeyD','ShiftLeft','ControlLeft',
    'Space','KeyR','KeyF','KeyQ','KeyE','KeyC','Tab','KeyM','Escape','Enter',
    'ArrowUp','ArrowDown','ArrowLeft','ArrowRight',
    'Numpad2','Numpad4','Numpad6','Numpad8']);
  const keyNames = {
    ShiftLeft: 'Shift', ControlLeft: 'Control', Space: ' ', Tab: 'Tab',
    Escape: 'Escape', Enter: 'Enter', ArrowUp: 'ArrowUp',
    ArrowDown: 'ArrowDown', ArrowLeft: 'ArrowLeft', ArrowRight: 'ArrowRight'
  };

  function pressed(v, threshold = 0.5) { return Number(v || 0) >= threshold; }
  function keyboard(code, active) {
    if (!modeKeys.has(code) || keysHeld.has(code) === active) return;
    if (active) keysHeld.add(code); else keysHeld.delete(code);
    const key = keyNames[code] || (code.startsWith('Key') ? code.slice(3).toLowerCase() : code);
    // The existing homepage installInput() listener accepts keyboard events.
    window.dispatchEvent(new KeyboardEvent(active ? 'keydown' : 'keyup',
      { code, key, bubbles: true, cancelable: true }));
  }
  function releaseAll() {
    for (const code of [...keysHeld]) keyboard(code, false);
    if (input) {
      if (oldButtons) Atomics.and(input, 5, ~oldButtons);
      oldButtons = 0;
      // restore pointer-lock state to actual browser pointer-lock state
      Atomics.store(input, 7, document.pointerLockElement ? 1 : 0);
    }
    dxFraction = 0; dyFraction = 0;
    menuOpen = false; oldMenu = false;
  }
  function mouseBit(bit, yes) {
    if (!input) return;
    if (yes) { Atomics.or(input, 5, bit); oldButtons |= bit; }
    else if (oldButtons & bit) { Atomics.and(input, 5, ~bit); oldButtons &= ~bit; }
  }
  function writeCamera(x, y) {
    if (!input) return;
    // WebKit does not allow synthetic pointer lock. Write the existing
    // Emscripten mouse-delta shared-memory ABI directly.
    const speed = 15 * sensitivity;
    dxFraction += Number(x || 0) * speed;
    dyFraction -= Number(y || 0) * speed;
    const dx = Math.trunc(dxFraction), dy = Math.trunc(dyFraction);
    dxFraction -= dx; dyFraction -= dy;
    if (dx) Atomics.add(input, 2, dx);
    if (dy) Atomics.add(input, 3, dy);
    Atomics.store(input, 7, 1);
  }
  function sync(s) {
    if (!s || !pressed(s.connected)) { releaseAll(); return; }
    if (!input) return;
    // A native Bluetooth gamepad is an active input source without mouse pointer-lock.
    Atomics.store(input, 6, 1);
    Atomics.store(input, 7, 1);
    const loading = document.getElementById('loading');
    const loadingVisible = !!loading && !loading.classList.contains('done');
    const menu = pressed(s.menu);
    if (menu && !oldMenu && !loadingVisible) menuOpen = !menuOpen;
    oldMenu = menu;
    const chord = pressed(s.options) && pressed(s.y);
    if (chord && !oldChord && !loadingVisible) {
      profile = profile === 'foot' ? 'drive' : profile === 'drive' ? 'air' : 'foot';
      console.info('[controller] profile from gamepad:', profile);
      try { window.webkit.messageHandlers.gtaDiagnostics.postMessage({type:'controllerProfile', detail:profile}); } catch (_) {}
    }
    oldChord = chord;
    const inMenu = loadingVisible || menuOpen;
    const wants = new Set();
    function key(code, active) { if (code && active) wants.add(code); }
    const mapped = (button, original) => Object.prototype.hasOwnProperty.call(customMappings, button) ? customMappings[button] : original;

    if (inMenu) {
      key('ArrowUp', pressed(s.up) || Number(s.ly || 0) > 0.5);
      key('ArrowDown', pressed(s.down) || Number(s.ly || 0) < -0.5);
      key('ArrowLeft', pressed(s.left) || Number(s.lx || 0) < -0.5);
      key('ArrowRight', pressed(s.right) || Number(s.lx || 0) > 0.5);
      key('Enter', pressed(s.a));
      key('Escape', pressed(s.b) || menu);
    } else {
      const drive = profile === 'drive', air = profile === 'air';
      // Movement, driving and flight are digital in this engine's public input ABI.
      // Raw analog values remain available in window.__gtaPadAxes for a future
      // native gamepad-specific engine interface.
      key('KeyW', Number(s.ly || 0) > 0.19 || ((drive || air) && pressed(s.rt, 0.15)));
      key('KeyS', Number(s.ly || 0) < -0.19 || ((drive || air) && pressed(s.lt, 0.15)));
      key('KeyA', Number(s.lx || 0) < -0.19);
      key('KeyD', Number(s.lx || 0) > 0.19);
      key(mapped('a', 'ShiftLeft'), pressed(s.a) && !drive && !air);
      key(drive ? 'Space' : mapped('x', 'Space'), pressed(s.x) || (drive && pressed(s.rb)));
      key(mapped('y', 'KeyF'), pressed(s.y) && !chord);
      key(mapped('b', 'KeyR'), pressed(s.b) && !drive && !air);
      key(mapped('rb', 'KeyQ'), pressed(s.rb) && !drive && !air);
      key(mapped('lb', 'Tab'), pressed(s.lb));
      key(mapped('l3', 'ControlLeft'), pressed(s.l3));
      key(mapped('r3', 'KeyC'), pressed(s.r3));
      key('KeyM', pressed(s.options) && !pressed(s.y));
      key(mapped('menu', 'Escape'), menu);
      key('ArrowUp', pressed(s.up));
      key('ArrowDown', pressed(s.down));
      key('ArrowLeft', pressed(s.left));
      key('ArrowRight', pressed(s.right));
      if (air) {
        key('Numpad8', Number(s.ry || 0) > 0.19);
        key('Numpad2', Number(s.ry || 0) < -0.19);
        key('Numpad4', Number(s.rx || 0) < -0.19);
        key('Numpad6', Number(s.rx || 0) > 0.19);
      } else {
        writeCamera(s.rx, s.ry);
      }
    }
    // Diff-based press/release prevents key spam and stuck keys on disconnect.
    for (const code of keysHeld) if (!wants.has(code)) keyboard(code, false);
    for (const code of wants) keyboard(code, true);
    if (inMenu || profile === 'drive' || profile === 'air') {
      mouseBit(1, false); mouseBit(2, false);
    } else {
      mouseBit(1, pressed(s.rt, 0.15)); // left mouse: fire
      mouseBit(2, pressed(s.lt, 0.15)); // right mouse: aim
    }
  }
  const bridge = {
    attach(sharedKeys, sharedWords) {
      // Input memory belongs to existing homepage installInput() function.
      if (!sharedKeys || !sharedWords || !(sharedWords.buffer instanceof SharedArrayBuffer)) {
        console.warn('[controller] shared input ABI not available');
        return;
      }
      memory = sharedKeys; input = sharedWords;
      releaseAll();
      sync(latest);
      console.info('[controller] attached to WASM keyboard/mouse ABI');
    },
    update(snapshot) {
      latest = snapshot || { connected: 0 };
      window.__gtaPadAxes = latest;
      sync(latest);
    },
    setProfile(mode) {
      if (!['foot','drive','air'].includes(mode)) return;
      releaseAll(); profile = mode; sync(latest);
      if (mode !== lastDiagnostic) {
        lastDiagnostic = mode;
        console.info('[controller] input profile:', mode);
      }
    },
    setMappings(values) {
      customMappings = values && typeof values === 'object' ? values : {};
      releaseAll(); sync(latest);
    },
    setSensitivity(value) {
      const n = Number(value);
      if (Number.isFinite(n)) sensitivity = Math.max(0.25, Math.min(3, n));
    },
    disconnect: releaseAll,
    get profile() { return profile; }
  };
  window.GTAInputBridge = bridge;
  window.__gtaNativePad = snapshot => bridge.update(snapshot);
  window.__gtaNativePadProfile = mode => bridge.setProfile(mode);
  window.__gtaNativePadSensitivity = n => bridge.setSensitivity(n);
  window.__gtaNativePadMappings = values => bridge.setMappings(values);
  window.addEventListener('pagehide', releaseAll);
})();
