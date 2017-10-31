Repo for development of the P3 Workspace Service

SERVICE DEPENDENCIES:
typecomp
shock

SETUP

1) A mongodb instance must be up and running.
2) The connected Shock server must be up and running.
3) make
4) if you want to run tests: make test
5) make deploy
6) fill in deploy.cfg and set KB_DEPLOYMENT_CONFIG appropriately
7) /kb/deployment/services/Workspace/start_service

If the server doesn't start up correctly, check /var/log/syslog 
for debugging information.