#!/bin/bash

read -r -d '' params <<PARAMS
  --run-on aws --aws-keypair-name awskey --pg-version 9.6 \
  --aws-ssh-key-path "/home/someuser/.ssh/awskey.pem" \
  --aws-ec2-type "r4.large" \
  --s3cfg-path "/home/someuser/.s3cfg" \
  --workload-real "s3://somebucket/db.sql.30min.pgreplay" \
  --tmp-path tmp \
  --db-dump-path "s3://somebucket/dump.sql.bz2" \
  --target-ddl-do "create\tindex\ti_zzz\ton\tsometable(col1);"
PARAMS

output=$(${BASH_SOURCE%/*}/../nancy_run.sh $params 2>&1)

if [[ $output =~ "ERROR: DDL code must have do and undo part." ]]; then
  echo -e "\e[36mOK\e[39m"
else
  >&2 echo -e "\e[31mFAILED\e[39m"
  >&2 echo -e "Output: $output"
fi
