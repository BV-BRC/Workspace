#!/bin/bash
set -e

MODULE=workspace
SERVICE=Workspace

DEV_CONTAINER=/disks/p3/dev_container
AUTO_DEPLOY_CFG=auto-deploy.cfg


pushd $DEV_CONTAINER
. user-env.sh

pushd modules/$MODULE

make

popd

perl auto-deploy $AUTO_DEPLOY_CFG -module $MODULE

set +e
echo "stopping service"
/disks/p3/deployment/services/$SERVICE/stop_service
set -e

sleep 5 

echo "starting service"
/disks/p3/deployment/services/$SERVICE/start_service

sleep 5

pushd modules/$MODULE
make test
