# corModbusBridge

The **Modbus TCP bridge** for coraine: a `modbus.so` that carries values between
Modbus registers and NGSI-LD entity attributes - polled registers in, attribute
writes out.

The user documentation - configuration, Channels, `channelInfo`, what is and is
not supported - is coraine's
[doc/modbus-bridge.md](https://github.com/SEAMWARE/coraine/blob/main/doc/modbus-bridge.md),
and its functional test (`bridge_modbus.test`, with the `ftModbus.py` simulator)
lives in coraine as well: a bridge is tested through the broker that loads it.

**A demo** - an OpenPLC water tank, read and controlled over NGSI-LD - is in [DEMO.md](DEMO.md).

## The shape of it

- **One Bridge is one Modbus server** (`host:port`, default unit, poll interval).
- **One Channel is one value in it.** The endpoint is the *address* -
  `[unit/<n>/]coil|discrete|holding|input/<address>` - and how to read it (type,
  word order, scale, poll, deadband) is the Channel's `channelInfo`, key-value
  pairs as NGSI-LD's `receiverInfo` (bridge ABI 9).
- **Modbus pushes nothing**, so the plugin polls - one thread per Bridge, one
  request at a time - and reports a value only when it changed beyond its
  deadband.
- **A write is queued** and sent by that same thread, never from the broker
  thread that changed the attribute.

## The contract

`corBridge` holds it: `BridgeDriver.h` is what this fills in, `BridgeBroker.h`
is what the broker hands back. The plugin never learns what an entity is -
which register corresponds to which attribute is a Channel, and Channels live
in the broker.

## Building

No dependency beyond libc: Modbus TCP is a socket and a seven-byte header.

    make                  # modbus.so, debug (traces compiled in)
    make BUILD=release
    make install          # to /opt/seamware/plugins/bridge (PLUGIN_DIR)
    make contract         # does it still satisfy BridgeDriver.h?

The sibling cor repos are expected beside this one (`COR_LIBS ?= ..`); the
corLibs umbrella clones and builds it with the rest.
