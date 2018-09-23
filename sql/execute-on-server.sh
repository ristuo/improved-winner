#!/bin/bash
[ -z $PGPASSWORD ] && echo "Set PGPASSWORD" && exit 78
username=superuser
filename="$1"
url=improved-winner.ce172ffedvvk.eu-west-2.rds.amazonaws.com
psql -U $username -d betting -h $url -f $filename
