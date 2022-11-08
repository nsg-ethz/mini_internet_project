#!/bin/bash

set -e

psql -v ON_ERROR_STOP=1 --user irrd -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
