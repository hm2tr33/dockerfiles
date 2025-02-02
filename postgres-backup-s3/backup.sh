#! /bin/sh

set -e
set -o pipefail

BAK_DATETIME=$(date +%F-%H%M)

if [ "${S3_ACCESS_KEY_ID}" = "**None**" ]; then
  echo "You need to set the S3_ACCESS_KEY_ID environment variable."
  exit 1
fi

if [ "${S3_SECRET_ACCESS_KEY}" = "**None**" ]; then
  echo "You need to set the S3_SECRET_ACCESS_KEY environment variable."
  exit 1
fi

if [ "${S3_BUCKET}" = "**None**" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ "${POSTGRES_DATABASE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_DATABASE environment variable."
  exit 1
fi

if [ "${POSTGRES_HOST}" = "**None**" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=$POSTGRES_PORT_5432_TCP_ADDR
    POSTGRES_PORT=$POSTGRES_PORT_5432_TCP_PORT
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

if [ "${POSTGRES_USER}" = "**None**" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ "${POSTGRES_PASSWORD}" = "**None**" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable or link to a container named POSTGRES."
  exit 1
fi

if [ "${S3_ENDPOINT}" == "**None**" ]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

if [ "${PASSPHRASE}" = "**None**" ]; then
  echo "You need to set the PASSPHRASE environment variable."
  exit 1
fi

if [ "${SLACK_WEBHOOK}" = "**None**" ]; then
  echo "You need to set the SLACK_WEBHOOK environment variable."
  exit 1
fi

# env vars needed for aws tools
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$S3_REGION

export PASSPHRASE=$PASSPHRASE

export PGPASSWORD=$POSTGRES_PASSWORD
POSTGRES_HOST_OPTS="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER $POSTGRES_EXTRA_OPTS"

echo "Creating dump of ${POSTGRES_DATABASE} database from ${POSTGRES_HOST}..."

if ! pg_dump $POSTGRES_HOST_OPTS $POSTGRES_DATABASE > ${POSTGRES_DATABASE}-${BAK_DATETIME}.dump.sql 2> /tmp/pgdump_error.log; then
  ERROR_MSG=$(cat /tmp/pgdump_error.log)
  echo "Backup process failed with error: $ERROR_MSG. Sending message to Slack..."
  curl -X POST -H 'Content-type: application/json' --data '{"text": ":exclamation: Backup process for '${POSTGRES_DATABASE}' failed with error: ```'"$ERROR_MSG"'```"}' $SLACK_WEBHOOK
  rm /tmp/pgdump_error.log
  exit 1
fi

rm /tmp/pgdump_error.log

7z a dump.sql.7z -t7z -m0=lzma2:d1024m -mx=9 -aoa -mfb=64 -md=32m -p"$PASSPHRASE" -ms=on ${POSTGRES_DATABASE}-${BAK_DATETIME}.dump.sql

echo "Uploading dump to $S3_BUCKET"

s3cmd $AWS_ARGS put dump.sql.7z s3://$S3_BUCKET/$S3_PREFIX/${POSTGRES_DATABASE}_$(date +"%Y-%m-%dT%H:%M:%SZ").sql.7z || exit 2

# send alert to slack
curl -X POST -H 'Content-type: application/json' --data '{"text":":approved: POSTGRES backup - '${POSTGRES_DATABASE}_$(date +"%Y-%m-%dT%H:%M:%SZ")' uploaded successfully!"}' $SLACK_WEBHOOK

rm -f ${POSTGRES_DATABASE}-${BAK_DATETIME}.dump.sql && rm -f dump.sql.7z

echo "SQL backup uploaded successfully"
