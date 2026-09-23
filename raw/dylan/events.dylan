Module: visual-workplace-events
Synopsis: Dylan frame / event protocol bridging UI updates
          (open-file, compile-c, glow-on) — educational stubs

/// Opcodes shared with the ColorForth word names in spirit
define constant $op-open-file     :: <byte> = #x01;
define constant $op-compile-c     :: <byte> = #x02;
define constant $op-glow-on       :: <byte> = #x03;
define constant $op-glow-off      :: <byte> = #x04;
define constant $op-key-enter     :: <byte> = #x05;
define constant $op-agent-ask     :: <byte> = #x06;
define constant $op-syscall-trace :: <byte> = #x07;

define constant $frame-magic :: <byte-vector>
  = as(<byte-vector>, #[#x44, #x59, #x4C, #x4E]); // "DYLN"

define class <dylan-event> (<object>)
  constant slot event-kind :: <symbol>,
    required-init-keyword: kind:;
  constant slot event-payload :: <object> = #f,
    init-keyword: payload:;
  constant slot event-timestamp :: <float> = 0.0,
    init-keyword: timestamp:;
end class <dylan-event>;

define class <dylan-frame> (<object>)
  constant slot frame-magic :: <byte-vector> = $frame-magic,
    init-keyword: magic:;
  constant slot frame-opcode :: <byte>,
    required-init-keyword: opcode:;
  constant slot frame-body :: <byte-string> = "",
    init-keyword: body:;
  constant slot frame-crc :: <integer> = 0,
    init-keyword: crc:;
end class <dylan-frame>;

define function make-event
    (kind :: <symbol>, #key payload, timestamp = 0.0)
 => (e :: <dylan-event>)
  make(<dylan-event>, kind: kind, payload: payload, timestamp: timestamp)
end function make-event;

/// Educational CRC32-IEEE stub — folds bytes; not a production codec.
/// BEAM Evoke.DylanProtocol uses :erlang.crc32/1 over the same body bytes
/// (magic DYLN + opcode + body + CRC). See evoke-bridge.dylan.
define function crc32-ieee-stub (data :: <byte-string>) => (c :: <integer>)
  let c :: <integer> = #xffffffff;
  for (ch in data)
    c := logxor(c, as(<integer>, ch));
    for (i from 0 below 8)
      if (logand(c, 1) ~= 0)
        c := logxor(ash(c, -1), #xedb88320);
      else
        c := ash(c, -1);
      end if;
    end for;
  end for;
  logxor(c, #xffffffff)
end function crc32-ieee-stub;

define function encode-frame
    (opcode :: <byte>, body :: <byte-string>)
 => (frame :: <dylan-frame>)
  make(<dylan-frame>,
       opcode: opcode,
       body: body,
       crc: crc32-ieee-stub(body))
end function encode-frame;

define function decode-frame
    (frame :: <dylan-frame>)
 => (event :: false-or(<dylan-event>))
  unless (frame.frame-crc = crc32-ieee-stub(frame.frame-body))
    #f
  else
    let kind
      = select (frame.frame-opcode)
          $op-open-file     => #"open-file";
          $op-compile-c     => #"compile-c";
          $op-glow-on       => #"glow-on";
          $op-glow-off      => #"glow-off";
          $op-key-enter     => #"key-enter";
          $op-agent-ask     => #"agent-ask";
          $op-syscall-trace => #"syscall-trace";
          otherwise         => #"unknown";
        end select;
    make-event(kind, payload: frame.frame-body)
  end unless
end function decode-frame;
