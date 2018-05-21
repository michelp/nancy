#!/bin/bash
PG_VERSION="${PG_VERSION:-10}"
PROJECT="${PROJECT:-postila_ru}"
CURRENT_TS=$(date +%Y%m%d_%H%M%S_%Z)
DOCKER_MACHINE="${DOCKER_MACHINE:-nancy-$PROJECT-$CURRENT_TS}"
DOCKER_MACHINE="${DOCKER_MACHINE//_/-}"
EC2_TYPE="${EC2_TYPE:-i3.large}"
EC2_PRICE="${EC2_PRICE:-0.0087}"
EC2_KEY_PAIR=${EC2_KEY_PAIR:-awskey}
EC2_KEY_PATH=${EC2_KEY_PATH:-~/.ssh/awskey.pem}
S3_BUCKET="${S3_BUCKET:-p-dumps}"

set -ueo pipefail
set -ueox pipefail # to debug

`aws ecr get-login --no-include-email`

docker-machine create --driver=amazonec2 --amazonec2-request-spot-instance \
  --amazonec2-keypair-name="$EC2_KEY_PAIR" --amazonec2-ssh-keypath="$EC2_KEY_PATH" \
  --amazonec2-block-duration-minutes 180 --amazonec2-zone f \
  --amazonec2-instance-type=$EC2_TYPE --amazonec2-spot-price=$EC2_PRICE $DOCKER_MACHINE
#  --amazonec2-root-size 1000

eval $(docker-machine env $DOCKER_MACHINE)

containerHash=$(docker `docker-machine config $DOCKER_MACHINE` run --privileged --name="pg_nancy" \
  -v /home/ubuntu:/machine_home -dit "950603059350.dkr.ecr.us-east-1.amazonaws.com/nancy:pg96_r4.large")
dockerConfig=$(docker-machine config $DOCKER_MACHINE)

function cleanup {
  echo "Machine is alive!"
  #cmdout=$(docker-machine rm --force $DOCKER_MACHINE)
  #echo "Finished working with machine $DOCKER_MACHINE, termination requested, current status: $cmdout"
}
trap cleanup EXIT

shopt -s expand_aliases
alias sshdo='docker $dockerConfig exec -it pg_nancy '

docker-machine scp ~/.s3cfg $DOCKER_MACHINE:/home/ubuntu
docker-machine scp ~/.aws/credentials $DOCKER_MACHINE:/home/ubuntu
docker-machine scp i3.part.txt $DOCKER_MACHINE:/home/ubuntu
sshdo cp /machine_home/.s3cfg /root/.s3cfg
sshdo mkdir /root/.aws
sshdo cp /machine_home/credentials /root/.aws/credentials

#sshdo add-apt-repository -y ppa:sbates
sshdo sh -c "sudo sfdisk /dev/nvme0n1 < /machine_home/i3.part.txt"
sshdo sudo mkfs.ext4 -F /dev/nvme0n1
sshdo mkdir /postgresql
sshdo chmod a+w /postgresql
sshdo mount /dev/nvme0n1 /postgresql

#sshdo "python ebs-attach.py --volumeid vol-02bdaededd3b6aa4b --device /dev/xvdf --region us-east-1 & && jobs && bg && jobs && disown -h %1"
sshdo sh -c "mkdir /postgresql/dump && chmod a+w /postgresql/dump"
#sshdo mount --bind /dev/xvdf /pg

sshdo sh -c "mkdir /postgresql/bigspace && chmod a+w /postgresql/bigspace"
sshdo chown -R postgres:postgres /postgresql
#sshdo s3cmd sync s3://p-dumps/postila_ru.dump/prod.201805150111.dump.gz ./ # TODO: parametrize!
sshdo aws s3 sync s3://postgres-misc/postila_prod/201805151715 /postgresql/dump
sshdo s3cmd sync s3://p-dumps/dev.imgdata.ru/queries.sql ./ # TODO: parametrize!

sshdo psql -U postgres -c "create tablespace bigspace location '/postgresql/bigspace';"
sshdo psql -U postgres -c "alter database test set tablespace bigspace;"

sshdo sh -c "printf \"\\nautovacuum = off\\n\" >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
sshdo /etc/init.d/postgresql restart

sshdo pg_restore -U postgres -d test -j1 --no-owner --no-privileges --no-tablespaces /postgresql/dump
#sshdo bash -c "zcat prod.201805150111.dump.gz | psql --set ON_ERROR_STOP=on -U postgres test" # TODO: parametrize!

sshdo psql -U postgres test -c 'refresh materialized view a__news_daily_90days_denominated;' # remove me later

sshdo vacuumdb -U postgres test -j 10 --analyze
sshdo sh -c "prtinf \"\\nautovacuum = off\\n\" >> /etc/postgresql/$PG_VERSION/main/postgresql.conf"
sshdo /etc/init.d/postgresql restart

sshdo bash -c "psql -U postgres test -f ./queries.sql"

sshdo bash -c "pgbadger -j 4 --prefix '%t [%p]: [%l-1] db=%d,user=%u (%a,%h)' /var/log/postgresql/* -f stderr -o /${PROJECT}_experiment_${CURRENT_TS}.json"

sleep 600

echo Bye!
