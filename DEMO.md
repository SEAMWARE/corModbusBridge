# The tank demo - a PLC on Modbus, a sensor on MQTT, one NGSI-LD entity

A real PLC runtime, [OpenPLC](https://autonomylogic.com/), runs a small control program. coraine
reads it and writes to it over Modbus TCP through this bridge. The tank then *is* an NGSI-LD
entity: queryable, subscribable and with history, and writable back to the PLC.

Next to it, an MQTT temperature sensor publishes on `plant/tank1/temperature`, and coraine's MQTT
bridge ([corMqttBridge](https://github.com/SEAMWARE/corMqttBridge)) makes that the same tank's
`temperature`. Alarm notifications go out over HTTP and over MQTT, side by side.

There is no hardware and no glue code. The only thing that ties the PLC and the sensor to NGSI-LD
is [`demo/bridges.json`](demo/bridges.json).

```
 ┌──────────────── OpenPLC ────────────────┐  Modbus TCP  ┌──────── coraine ────────┐   NGSI-LD
 │ tank.st, 100 ms scan cycle              │ ◀──────────▶ │ modbus.so               │ ◀────────▶ clients
 │   level, pump, alarm   (PLC outputs)    │   poll 250ms │ urn:ngsi-ld:Tank:1      │            subscriptions
 │   setpoint, outflow    (memory words)   │   + writes   │ corDB + TRoE (Timescale)│ ─────────▶ listener
 └─────────────────────────────────────────┘              └─────────────────────────┘  notifies
                                                             ▲             │ mqtt:// notifications
 ┌── sensor ──┐  plant/tank1/temperature  ┌── mosquitto ──┐  │ MQTT        ▼
 │ every 3 s  │ ────────────────────────▶ │   :1883       │ ─┘     plant/tank1/alarm ──▶ mqtt-monitor
 └────────────┘                           └───────────────┘                               (one line per message)
```

## The tank

[`demo/openplc/tank.st`](demo/openplc/tank.st) is IEC 61131-3 Structured Text, the language PLCs
are programmed in. The PLC simulates the process itself:

- **Level.** It rises 2 %/s while the pump runs and falls through an outlet at `outflow` %/s.
- **Pump.** The pump switches with a 5 % hysteresis around `setpoint`: on below `setpoint - 5`,
  off above `setpoint + 5`.
- **Alarm.** The high-level alarm trips above 90 %.

## The mapping

OpenPLC's Modbus server exposes the program's located variables. Each one is a Channel of this
bridge and an attribute of `urn:ngsi-ld:Tank:1`:

| PLC variable | Modbus address | Attribute | channelInfo | Who writes it |
|---|---|---|---|---|
| `%QW0` | `holding/0` | `level` | scale 0.1, deadband 0.5 | the PLC, every cycle |
| `%QX0.0` | `coil/0` | `pumpOn` | - | the PLC, every cycle |
| `%QX0.1` | `coil/1` | `alarm` | - | the PLC, every cycle |
| `%MW0` | `holding/1024` | `setpoint` | scale 0.1 | **the broker** (a PATCH) |
| `%MW1` | `holding/1025` | `outflow` | scale 0.01 | **the broker** (a PATCH) |

And one MQTT Channel, on the bridge's own connection to the demo's mosquitto:

| MQTT topic | Attribute | Direction |
|---|---|---|
| `plant/tank1/temperature` | `temperature` | in (the sensor publishes a plain number; a JSON payload is the value) |

The PLC owns its outputs (`%QW`, `%QX`) and overwrites them on every scan. A PATCH of `level`
reaches the device, but the next cycle replaces it, exactly as it would on a real PLC. Settings
that come from outside live in memory words (`%MW`), which the program reads and never
overwrites after start-up.

`scale` turns the PLC's integer registers into engineering units: register 600 is `setpoint`
60.0. It is inverted on the way out, so a PATCH of `95` writes 950. The level's `deadband` keeps
a value that moves 0.05 % per cycle from becoming ten attribute writes, ten notifications and ten
TRoE rows per second.

## Running it

You need Docker with compose, plus `curl` and `python3` on the host. You also need a coraine image
that carries `modbus.so` and `mqtt.so`. Name it exactly; there is no default. Export it rather than prefixing
one command with it, because `demo.sh` runs `docker compose` itself and every compose command
needs it:

```bash
cd demo
export CORAINE_IMAGE=<coraine image>
docker compose up -d --build     # OpenPLC compiles once, a few minutes
./demo.sh                        # Enter between steps; DEMO_NOPAUSE=1 to run through
docker compose down -v
```

`demo.sh` talks to `http://localhost:1026`; set `CORAINE_URL` to change that.

Every MQTT message on the plant's topics is printed, one line each, by the `mqtt-monitor`
container: `docker compose logs -f mqtt-monitor` in a second terminal is the MQTT side of the
demo. The demo's mosquitto is also on the host's port **1884** - not 1883, which a host often uses
for a mosquitto of its own.

To build a coraine image from source, run `make docker` in the coraine repo.

OpenPLC's web UI is at <http://localhost:8080>; log in with OpenPLC's own default user. Its
*Monitoring* page shows the same variables from the PLC side, next to the broker's view. The
Modbus server is also on the host's port 5020, for any Modbus client.

## What `demo.sh` shows

| Step | What happens | What it shows |
|---|---|---|
| 0 | The tank entity appears | The bridge creates the entity on the first poll, with no provisioning |
| 1 | `level` and `pumpOn` follow the PLC | Polled registers become attribute values, sent only on a change |
| 2 | `GET /ngsi-ld/v1/channels` | One Channel per address, with its `channelInfo` |
| 3 | The sensor publishes on MQTT | An MQTT topic becomes an attribute of the same entity - two transports, one tank |
| 4 | Two subscriptions with `q=alarm==true` | One to the HTTP listener, one to `mqtt://mosquitto:1883/plant/tank1/alarm` (TS 104 243) |
| 5 | PATCH `setpoint` to 95 | An NGSI-LD write becomes a Modbus write; the PLC reacts, the alarm trips, and both subscribers are told - the MQTT one as the binding's `{metadata, body}` envelope |
| 6 | PATCH `setpoint` 60 and `outflow` 1 | Two settings changed live, in engineering units |
| 7 | A temporal query of `level` (TimescaleDB) | History (TRoE) of a PLC value |
| 8 | `docker compose stop openplc` | The attribute keeps its last known value and gains `modbusStatus` |
| 9 | `docker compose start openplc` | `modbusStatus` goes back to `ok`, and the values flow again |

For a live audience, keep OpenPLC's *Monitoring* page open beside the terminal. The setpoint
changes there the moment the PATCH returns.

## Files

| File | What it is |
|---|---|
| `demo/openplc/tank.st` | The PLC program |
| `demo/openplc/Dockerfile` | OpenPLC Runtime v3, pinned, with `tank.st` compiled in and set to start in RUN mode |
| `demo/bridges.json` | The Bridge (the PLC's host and port, poll period) and its Channels |
| `demo/docker-compose.yml` | OpenPLC, coraine (`--database corDB --troe timescale --bridges modbus,mqtt`), TimescaleDB, mosquitto, the sensor, the MQTT monitor and the HTTP listener |
| `demo/mosquitto.conf` | The demo's MQTT server: one anonymous listener |
| `demo/listener/listener.py` | Prints the notifications it receives |
| `demo/demo.sh` | The walkthrough |

**Why TimescaleDB.** The corDB TRoE backend records history but does not read it back yet, so
the demo uses the TimescaleDB backend for step 6. The current state stays in corDB, in memory.

## Known issues, seen in this demo

- **A restarted PLC starts over.** OpenPLC runs here without persistent storage. After step 8 the
  tank starts again at 40 %, with the default setpoint and outflow, and the broker follows.

**Why OpenPLC v3 and not v4.** v4 accepts a program only as a zip compiled by the OpenPLC
Editor and uploaded through its API. v3 compiles a `.st` file itself, so the whole PLC side is
one text file in this repo.
