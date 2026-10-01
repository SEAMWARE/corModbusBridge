#!/bin/bash
#
# FILE            demo.sh
#
# AUTHOR          Ken Zangelin
#
# Copyright 2026 Seamware
# SPDX-License-Identifier: Apache-2.0
#
# The Modbus demo, step by step - see ../DEMO.md. Run it from this directory with the stack up:
#
#   CORAINE_IMAGE=<image> docker compose up -d --build
#   ./demo.sh             # pauses between steps; DEMO_NOPAUSE=1 to run straight through
#
CORAINE_URL=${CORAINE_URL:-http://localhost:1026}
TANK=urn:ngsi-ld:Tank:1

step()  { echo; echo "=== $1"; echo; }
pause() { [ -n "$DEMO_NOPAUSE" ] || read -r -p "--- press Enter for the next step " _; }
tank()  { curl -s "$CORAINE_URL/ngsi-ld/v1/entities/$TANK?options=keyValues" | python3 -c 'import sys, json
e = json.load(sys.stdin)
print("  level %5.1f %%   pump %-5s   alarm %-5s   setpoint %5.1f %%   outflow %.2f %%/s" %
      (e.get("level", 0), e.get("pumpOn"), e.get("alarm"), e.get("setpoint", 0), e.get("outflow", 0)))'; }
watchTank() { for _ in $(seq 1 "$1"); do tank; sleep 1; done; }
setAttr()   { curl -s -o /dev/null -w "  PATCH $1=$2 -> %{http_code}\n" -X PATCH "$CORAINE_URL/ngsi-ld/v1/entities/$TANK/attrs/$1" \
                -H 'Content-Type: application/json' -d "{\"value\": $2}"; }


step "0. Waiting for the tank to appear - the bridge creates it on the first poll"
for _ in $(seq 1 60); do
  curl -sf "$CORAINE_URL/ngsi-ld/v1/entities/$TANK" > /dev/null && break
  sleep 1
done
curl -s "$CORAINE_URL/ngsi-ld/v1/entities/$TANK" | python3 -m json.tool
pause

step "1. The PLC runs the tank; the broker follows it - a value goes in only when it changed (level: by more than its 0.5 % deadband)"
watchTank 15
pause

step "2. GET /ngsi-ld/v1/channels - one Channel per Modbus address, how to read it in channelInfo"
curl -s "$CORAINE_URL/ngsi-ld/v1/channels" | python3 -c 'import sys, json
for c in sorted(json.load(sys.stdin), key=lambda c: c["channelTarget"]):
  print("  %-14s -> %-9s %-7s %s" % (c["channelTarget"], c.get("entityAttribute", ""), c.get("status"), json.dumps(c.get("channelInfo", []))))'
pause

step "3. A subscription: tell the listener when the tank overfills (q=alarm==true)"
curl -s -o /dev/null -w "  POST /subscriptions -> %{http_code}\n" -X POST "$CORAINE_URL/ngsi-ld/v1/subscriptions" \
  -H 'Content-Type: application/json' -d '{
    "id": "urn:ngsi-ld:Subscription:tank-alarm",
    "type": "Subscription",
    "entities": [ { "type": "Tank" } ],
    "watchedAttributes": [ "alarm" ],
    "q": "alarm==true",
    "notification": { "format": "keyValues", "endpoint": { "uri": "http://listener:8000/notify", "accept": "application/json" } }
  }'
pause

step "4. Raise the setpoint to 95 % - an NGSI-LD PATCH becomes a Modbus write to the PLC (holding 1024)"
setAttr setpoint 95
echo "  the pump runs until the level passes 90 % and the alarm trips:"
for _ in $(seq 1 60); do
  tank
  curl -s "$CORAINE_URL/ngsi-ld/v1/entities/$TANK?options=keyValues" | grep -q '"alarm": *true' && break
  sleep 1
done
sleep 1
echo
echo "  the listener got:"
docker compose logs listener 2>/dev/null | grep NOTIFICATION | tail -3
pause

step "5. Back to 60 %, and open the outlet wider (outflow 1 %/s) - it drains faster"
setAttr setpoint 60
setAttr outflow 1
watchTank 15
pause

step "6. History (TRoE): the last level values the broker stored"
curl -s "$CORAINE_URL/ngsi-ld/v1/temporal/entities/$TANK?attrs=level&lastN=10&options=temporalValues" | python3 -c 'import sys, json
for v, t in json.load(sys.stdin)["level"]["values"]: print("  %-26s %s" % (t, v))' 
pause

step "7. The PLC goes away - the attribute keeps its last known value and says why (modbusStatus)"
docker compose stop openplc
sleep 3
curl -s "$CORAINE_URL/ngsi-ld/v1/entities/$TANK?attrs=level" | python3 -m json.tool
pause

step "8. ... and comes back - a restarted PLC starts its tank from scratch, and the broker follows"
docker compose start openplc
for _ in $(seq 1 30); do
  curl -s "$CORAINE_URL/ngsi-ld/v1/entities/$TANK?attrs=level" | grep -q '"unreachable"' || break
  sleep 1
done
curl -s "$CORAINE_URL/ngsi-ld/v1/entities/$TANK?attrs=level" | python3 -m json.tool
echo
echo "Done. The PLC side is at http://localhost:8080 (OpenPLC's web UI)."
