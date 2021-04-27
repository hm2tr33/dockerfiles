#! /bin/sh

# exit if a command fails
set -e


apk update

# install pg_dump
apk add postgresql

# install s3 tools
apk add python3 py3-pip
pip3 install awscli
pip3 install --ignore-installed six
#apk del py3-pip

# install go-cron
apk add curl
curl -L --insecure https://github.com/odise/go-cron/releases/download/v0.0.6/go-cron-linux.gz | zcat > /usr/local/bin/go-cron
chmod u+x /usr/local/bin/go-cron
apk del curl


# cleanup
rm -rf /var/cache/apk/*