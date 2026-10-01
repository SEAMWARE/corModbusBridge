(*
 * FILE            tank.st
 *
 * AUTHOR          Ken Zangelin
 *
 * Copyright 2026 Seamware
 * SPDX-License-Identifier: Apache-2.0
 *
 * A water tank, simulated by the PLC itself - no I/O hardware needed.
 *
 * The level rises while the pump runs and falls through an outlet. The pump is switched
 * around a setpoint with a 5 % hysteresis, and a high-level alarm trips above 90 %.
 *
 * ⚠ The located declarations below keep ONE space around AT and ':' - not aligned. OpenPLC's
 * Monitoring page splits each line on single spaces to find the address, and a padded line shows
 * as 0 there for good (the PLC itself is fine).
 *
 * What the Modbus server shows (OpenPLC's default map):
 *
 *   %QW0   holding register 0      level      0.1 %     (the PLC writes it every cycle)
 *   %QX0.0 coil 0                  pump                 (the PLC writes it every cycle)
 *   %QX0.1 coil 1                  alarm                (the PLC writes it every cycle)
 *   %MW0   holding register 1024   setpoint   0.1 %     (written from outside - the broker)
 *   %MW1   holding register 1025   outflow    0.01 %/s  (written from outside - the broker)
 *)
PROGRAM tank
  VAR
    level_reg AT %QW0 : UINT;
    pump AT %QX0.0 : BOOL;
    alarm AT %QX0.1 : BOOL;
    setpoint AT %MW0 : UINT;
    outflow AT %MW1 : UINT;
  END_VAR
  VAR
    level       : REAL := 40.0;
    sp          : REAL;
    initialised : BOOL := FALSE;
  END_VAR

  (* The memory words start at 0 - give them their defaults once, then they belong to whoever writes them *)
  IF NOT initialised THEN
    setpoint    := 600;
    outflow     := 50;
    initialised := TRUE;
  END_IF;

  (* One cycle is 100 ms: the pump adds 2 %/s, the outlet takes outflow/100 %/s *)
  IF pump THEN
    level := level + 0.2;
  END_IF;
  level := level - UINT_TO_REAL(outflow) / 1000.0;

  IF level < 0.0 THEN
    level := 0.0;
  END_IF;
  IF level > 100.0 THEN
    level := 100.0;
  END_IF;

  sp := UINT_TO_REAL(setpoint) / 10.0;
  IF level < sp - 5.0 THEN
    pump := TRUE;
  ELSIF level > sp + 5.0 THEN
    pump := FALSE;
  END_IF;

  alarm     := level > 90.0;
  level_reg := REAL_TO_UINT(level * 10.0);
END_PROGRAM


CONFIGURATION Config0
  RESOURCE Res0 ON PLC
    TASK task0(INTERVAL := T#100ms, PRIORITY := 0);
    PROGRAM instance0 WITH task0 : tank;
  END_RESOURCE
END_CONFIGURATION
