Module: dylan-user
Synopsis: Modules for the Visual Workplace Dylan front end

define module visual-workplace-events
  use common-dylan;
  use streams;

  export
    <dylan-event>,
    <dylan-frame>,
    event-kind, event-payload, event-timestamp,
    frame-magic, frame-opcode, frame-body, frame-crc,
    encode-frame, decode-frame,
    make-event,
    $op-open-file, $op-compile-c, $op-glow-on, $op-glow-off,
    $op-key-enter, $op-agent-ask, $op-syscall-trace;
end module visual-workplace-events;

define module visual-workplace-ui
  use common-dylan;
  use visual-workplace-events;

  export
    <visual-workplace>,
    <workbench-window>,
    <navigator-pane>,
    <editor-pane>,
    <termux-pane>,
    <syscall-agent>,
    <c-glow-state>,
    <dock>,
    <menubar>,
    workplace-title, workplace-menubar, workplace-dock, workplace-workbench,
    workbench-navigator, workbench-editor, workbench-termux, workbench-agent,
    glow-active?, glow-compile-boost?,
    open-file!, compile-c!, set-glow!, handle-key-enter!, agent-ask!,
    mount-termux-agent-screen!,
    on-dylan-event;
end module visual-workplace-ui;

define module visual-workplace
  use common-dylan;
  use visual-workplace-events;
  use visual-workplace-ui;

  export
    main,
    boot-workplace,
    start-visual-workplace,
    evoke-visual-workplace,
    evoke-bridge-banner,
    apply-mesh-frame!,
    evoke-mesh-event!;
end module visual-workplace;
