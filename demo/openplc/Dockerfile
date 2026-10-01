#
# FILE            Dockerfile
#
# AUTHOR          Ken Zangelin
#
# Copyright 2026 Seamware
# SPDX-License-Identifier: Apache-2.0
#
# OpenPLC Runtime v3 with the tank program compiled in and set to start in RUN mode -
# nothing to upload, nothing to click. Its Modbus TCP server is on 502 (OpenPLC's default),
# its web UI on 8080 for watching the PLC side of the demo.
#
# v3 and not v4: v4 takes a program only as a zip compiled by the OpenPLC Editor, through
# its API. v3 compiles a .st file itself, so the program is a text file in this directory.
#
FROM debian:trixie-20251020

#
# Pinned: OpenPLC_v3 has no releases, and master is what install.sh builds.
#
ARG OPENPLC_REF=b5d41356dab4aeadca0dd7ca64ba542f870b595d

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && git clone https://github.com/thiagoralves/OpenPLC_v3.git /workdir \
 && git -C /workdir checkout "$OPENPLC_REF"

WORKDIR /workdir
RUN ./install.sh docker

#
# Compile the program now, not at start: the container is then in RUN mode within a second.
# compile_program.sh records it as the active program; the Programs row is what the
# webserver looks it up by, and Start_run_mode makes it start without a click.
#
COPY tank.st /workdir/webserver/st_files/tank.st
RUN cd webserver \
 && ./scripts/compile_program.sh tank.st \
 && python3 -c "import sqlite3; c = sqlite3.connect('openplc.db'); \
c.execute(\"INSERT INTO Programs (Name, Description, File, Date_upload) VALUES ('Tank', 'The coraine Modbus demo - a simulated water tank', 'tank.st', strftime('%s','now'))\"); \
c.execute(\"UPDATE Settings SET Value = 'true' WHERE Key = 'Start_run_mode'\"); \
c.commit()"

EXPOSE 502 8080
ENTRYPOINT ["./start_openplc.sh"]
