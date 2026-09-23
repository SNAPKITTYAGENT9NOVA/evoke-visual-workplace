Module: visual-workplace
Synopsis: Application entry — boots Visual Workplace and mounts
          the Termux | Agent demo screen (ColorForth `demo` word).

define function boot-workplace () => (wp :: <visual-workplace>)
  let wp = make(<visual-workplace>);
  mount-termux-agent-screen!(wp.workplace-workbench);
  // Drive UI through the Dylan event protocol (same opcodes the
  // preview JS simulates when labels say open-file! / compile-c!).
  on-dylan-event(wp, make-event(#"open-file", payload: "hello.c"));
  on-dylan-event(wp, make-event(#"glow-on", payload: "hello.c"));
  wp
end function boot-workplace;

define function main (#rest args) => ()
  ignore(args);
  let wp = boot-workplace();
  format-out("Visual Workplace (Dylan) booted: %s\n",
             wp.workplace-title);
  format-out("  workbench title: %s\n",
             wp.workplace-workbench.workbench-title);
  format-out("  termux glow: %=\n",
             wp.workplace-workbench.workbench-termux.termux-glow.glow-active?);
  format-out("Educational stub — run under Open Dylan when available.\n");
end function main;
