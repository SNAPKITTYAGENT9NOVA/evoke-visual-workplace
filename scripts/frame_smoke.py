#!/usr/bin/env python3
"""Pure-Python DYLN frame roundtrip smoke (no BEAM required)."""
from __future__ import annotations

import binascii
import struct
import sys
import zlib

MAGIC = b'DYLN'
OPS = {
    0x01: 'open-file',
    0x02: 'compile-c',
    0x03: 'glow-on',
    0x04: 'glow-off',
    0x05: 'key-enter',
    0x06: 'agent-ask',
    0x07: 'syscall-trace',
}


def encode(opcode: int, body: bytes, agent_id: bytes = b'\x00' * 16) -> bytes:
    assert len(agent_id) == 16
    assert 0 <= opcode <= 255
    header = MAGIC + agent_id + bytes([opcode]) + struct.pack('>H', len(body))
    crc = zlib.crc32(body) & 0xFFFFFFFF
    return header + body + struct.pack('>I', crc)


def decode(packet: bytes):
    if len(packet) < 4 + 16 + 1 + 2 + 4:
        raise ValueError('truncated')
    if packet[:4] != MAGIC:
        raise ValueError('bad magic')
    agent_id = packet[4:20]
    opcode = packet[20]
    (body_len,) = struct.unpack('>H', packet[21:23])
    body = packet[23:23 + body_len]
    if len(packet) != 23 + body_len + 4:
        raise ValueError('length mismatch')
    (crc,) = struct.unpack('>I', packet[23 + body_len:])
    if (zlib.crc32(body) & 0xFFFFFFFF) != crc:
        raise ValueError('crc mismatch')
    return agent_id, opcode, body


def main() -> int:
    for op, name in OPS.items():
        body = f'payload-{name}'.encode()
        packet = encode(op, body)
        agent, got_op, got_body = decode(packet)
        assert agent == b'\x00' * 16
        assert got_op == op
        assert got_body == body
        if body:
            bad = bytearray(packet)
            bad[23] ^= 0xFF
            try:
                decode(bytes(bad))
                print(f'FAIL: expected crc mismatch for {name}')
                return 1
            except ValueError as e:
                assert 'crc' in str(e)
        print(f'OK  op=0x{op:02x} {name} bytes={len(packet)}')
    body = b'hello.c'
    assert (zlib.crc32(body) & 0xFFFFFFFF) == (binascii.crc32(body) & 0xFFFFFFFF)
    print('frame_smoke: all DYLN workplace opcodes round-tripped')
    return 0


if __name__ == '__main__':
    sys.exit(main())
