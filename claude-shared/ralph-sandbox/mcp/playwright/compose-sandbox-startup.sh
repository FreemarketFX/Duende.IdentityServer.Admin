#!/bin/bash
set -e
# Post-startup: inject proxy CA cert into playwright container
CONTAINER="playwright"
CERT_SRC="/usr/local/share/ca-certificates/proxy-ca.crt"
CERT_DST="/usr/local/share/ca-certificates/proxy-ca.crt"

# Wait for container to be running
for i in $(seq 1 30); do
  docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true && break
  sleep 1
done

# Copy CA cert from sandbox host into the container
docker exec --user root "$CONTAINER" mkdir -p /usr/local/share/ca-certificates
docker cp "$CERT_SRC" "$CONTAINER:$CERT_DST"

# Register cert in Chromium's NSS database
docker exec --user root "$CONTAINER" sh -c '
  apt-get update && apt-get install -y libnss3-tools >/dev/null
  for HOME_DIR in /home/node /root; do
    NSS=$HOME_DIR/.pki/nssdb
    mkdir -p $NSS
    [ -f $NSS/cert9.db ] || certutil -d sql:$NSS -N --empty-password
    certutil -d sql:$NSS -D -n proxy-ca 2>/dev/null || true
    certutil -d sql:$NSS -A -t "CT,c,c" -n proxy-ca -i /usr/local/share/ca-certificates/proxy-ca.crt
  done
  chown -R node:node /home/node/.pki
'
