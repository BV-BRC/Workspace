#!/bin/bash
set -e

SERVICE=Workspace

DEV_CONTAINER=/disks/p3/dev_container
AUTO_DEPLOY_CFG=auto-deploy.cfg


pushd $DEV_CONTAINER
. user-env.sh

pushd modules/$SERVICE

make

popd

perl auto-deploy $AUTO_DEPLOY_CFG -module $SERVICE

set +e
echo "stopping service"
/disks/p3/deployment/services/$SERVICE/stop_service
set -e

sleep 5 

echo "starting service"
/disks/p3/deployment/services/$SERVICE/start_service

sleep 5

pushd modules/$SERVICE
make test
