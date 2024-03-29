#!/bin/bash
# Reference: https://serverfault.com/a/922943

printf "READY\n";

while read line; do
  echo "Processing Event: $line" >&2;
  kill -3 $(cat "/var/run/supervisord.pid")
done < /dev/stdin
