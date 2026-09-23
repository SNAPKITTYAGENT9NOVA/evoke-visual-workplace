Module: visual-workplace
Synopsis: Evoke BEAM mesh bridge notes — Dylan DYLN frames ↔ WorkplaceBridge.

/// ============================================================================
/// Evoke BEAM mesh ↔ Dylan frames
/// ============================================================================
///
/// Shared wire format with Evoke.DylanProtocol / Evoke.WorkplaceBridge:
///
///   Magic[4]     = "DYLN" (#x44 #x59 #x4C #x4E)
///   Agent_ID[16] = BEAM mesh routing id (zeros when unused on Dylan side)
///   Opcode[1]
///   BodyLen[2]   (big-endian)
///   Body[N]
///   CRC32[4]     = CRC32-IEEE over Body only
///
/// Opcodes (events.dylan $op-* / Elixir workplace_opcodes/0):
///   #x01 open-file | #x02 compile-c | #x03 glow-on | #x04 glow-off
///   #x05 key-enter | #x06 agent-ask | #x07 syscall-trace
///
/// Path on the mesh:
///   UI event → Evoke.WorkplaceBridge.fan_event/3
///            → AgentNode.encode(DYLN) → Registry "dylan_transport"
///            → decode_event/1 → kind atom → on-dylan-event(wp, event)
///
/// Dylan educational CRC (`crc32-ieee-stub`) mirrors the IEEE polynomial;
/// BEAM uses `:erlang.crc32/1` for the production codec.

define function evoke-bridge-banner () => ()
  format-out("Evoke bridge: DYLN frames → on-dylan-event (opcodes 0x01–0x07)\n");
end function evoke-bridge-banner;

/// Decode a logical frame and drive the workplace (same path the mesh uses).
define function apply-mesh-frame!
    (wp :: <visual-workplace>, frame :: <dylan-frame>) => ()
  let event = decode-frame(frame);
  if (event)
    on-dylan-event(wp, event);
  end if;
end function apply-mesh-frame!;

/// Convenience: build a frame from an opcode/body and apply it.
define function evoke-mesh-event!
    (wp :: <visual-workplace>, opcode :: <byte>, body :: <byte-string>) => ()
  apply-mesh-frame!(wp, encode-frame(opcode, body));
end function evoke-mesh-event!;
