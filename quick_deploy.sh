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

# running tests. this section is still under development.

echo "deleting mongo database"
mongo WorkspaceBuild --eval "db.dropDatabase()"

echo "deleting db-path"
if [ -d /disks/p3/workspace/P3WSDB ] ; then
  rm -r /disks/p3/workspace/P3WSDB/
fi

source /disks/p3/deployment/user-env.sh

perl t/client-tests/ws.t
if [ $? -ne 0 ] ; then
        echo "BUILD ERROR: problem running make test"
        exit 1
fi

perl t/client-tests/create.t
if [ $? -ne 0 ] ; then
        echo "BUILD ERROR: problem running make test"
        exit 1
fi

perl t/client-tests/create_subdir.t
if [ $? -ne 0 ] ; then
        echo "BUILD ERROR: problem running make test"
        exit 1
fi


