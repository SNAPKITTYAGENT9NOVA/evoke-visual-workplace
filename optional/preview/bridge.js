/* Preview bridge: JS calls simulated ColorForth words + Dylan methods.
   Labels/logs show both language attributions when actions fire. */

window.CF = {
  stack: [],
  lastWord: null,
  trace: [],
  call(word, note) {
    this.lastWord = word;
    this.trace.push({ lang: 'colorforth', name: word, note: note || '' });
    logBridge('cf', word, note);
    return word;
  }
};

window.Dylan = {
  lastMethod: null,
  trace: [],
  call(method, note) {
    this.lastMethod = method;
    this.trace.push({ lang: 'dylan', name: method, note: note || '' });
    logBridge('dylan', method, note);
    return method;
  }
};

function logBridge(lang, name, note) {
  const el = document.getElementById('bridgeLog');
  if (!el) return;
  const row = document.createElement('div');
  row.className = 'bridge-row ' + lang;
  const tag = lang === 'cf' ? 'ColorForth' : 'Dylan';
  row.innerHTML = `<span class="bridge-tag">${tag}</span><code>${escapeHtml(name)}</code>` +
    (note ? `<span class="bridge-note">${escapeHtml(note)}</span>` : '');
  el.appendChild(row);
  el.scrollTop = el.scrollHeight;
  const badge = document.getElementById('bridgeBadge');
  if (badge) {
    badge.textContent = lang === 'cf' ? `cf · ${name}` : `dylan · ${name}`;
    badge.dataset.lang = lang;
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  })[c]);
}

window.WorkplaceBridge = {
  openFile(path) {
    CF.call('open-file', path);
    Dylan.call('open-file!', path);
    CF.call('c-check', path);
    if (/\.c$/i.test(path) || /hello\.c/i.test(path)) {
      this.glowOn(false);
    }
  },
  glowOn(compileBoost) {
    CF.call(compileBoost ? 'compile-live' : 'c-live');
    Dylan.call('set-glow!', compileBoost ? 'on + compile-boost?' : 'on');
    setCGlow(true, !!compileBoost);
  },
  glowOff() {
    CF.call('glow-off');
    Dylan.call('set-glow!', 'off');
    setCGlow(false, false);
  },
  keyEnter(line) {
    CF.call('key-enter', line);
    Dylan.call('handle-key-enter!', line);
  },
  keyType(fragment) {
    CF.call('key-type');
    if (looksLikeC(fragment)) {
      CF.call('looks-like-c?');
      this.glowOn(false);
    }
  },
  handleCmd(line) {
    CF.call('handle-cmd', line);
    const cmd = line.trim().split(/\s+/)[0] || '';
    if (cmd === 'gcc' || cmd === 'clang') {
      CF.call('do-gcc', line);
      Dylan.call('compile-c!', line);
    } else if (cmd === 'help') {
      CF.call('do-help');
    } else if (cmd === 'ls') {
      CF.call('do-ls');
    } else if (cmd === 'cat') {
      CF.call('do-cat');
    } else if (cmd === './a.out' || cmd === 'a.out') {
      CF.call('do-run');
    }
  },
  agentAsk(q) {
    CF.call('agent-ask', q);
    Dylan.call('agent-ask!', q);
  },
  agentSyscall(msg) {
    CF.call('agent-syscall', msg);
    Dylan.call('on-dylan-event', 'syscall-trace');
  },
  agentSay(msg) {
    CF.call('agent-say');
  },
  mountDemo() {
    CF.call('demo');
    CF.call('screen-termux-agent');
    CF.call('mount-termux');
    Dylan.call('mount-termux-agent-screen!');
    Dylan.call('boot-workplace');
  },
  encodeFrame(op, body) {
    Dylan.call('encode-frame', `${op} ${body || ''}`);
    CF.call('sys-frame', op);
  }
};
