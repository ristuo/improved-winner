#!/bin/bash


psql "sslmode=verify-ca sslrootcert=secrets/first-contact/server-ca.pem \
    sslcert=secrets/first-contact/client-cert.pem sslkey=secrets/first-contact/client-key.pem \
    hostaddr=35.204.222.233 \
    port=5432 \
    user=postgres dbname=winner" -f sql/drop-tables.sql

