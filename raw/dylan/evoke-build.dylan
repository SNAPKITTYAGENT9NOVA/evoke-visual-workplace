Module: visual-workplace
Synopsis: Evocator entry — start-visual-workplace aliases boot-workplace / main.
          Point dylan-compiler at visual-workplace.lid; this file documents
          the app entry for offline / portable builds (no network, no server).

/// Alias used by the portable evoke packaging notes.
define function start-visual-workplace () => (wp :: <visual-workplace>)
  boot-workplace()
end function start-visual-workplace;

/// Optional explicit evoke hook — same as main without arg plumbing.
define function evoke-visual-workplace () => ()
  let wp = start-visual-workplace();
  format-out("evoked: %s (termux|agent mounted)\n", wp.workplace-title);
end function evoke-visual-workplace;
