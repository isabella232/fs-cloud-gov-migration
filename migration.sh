#!/bin/bash

process_org=${1:-true}
if [ "$process_org"=="true" ]; then
    FOR_MIGRATION=true
  else
    FOR_MIGRATION=false
fi

if $FOR_MIGRATION ; then
ORGNAME = usda-forest-service
OLDORG = gsa-acq-proto

# Import Env vars
source env.sh

# Download existing apps
git clone https://github.com/18F/fs-intake-module.git
git clone https://github.com/18F/fs-middlelayer-api.git

cd fs-middlelayer-api
cf login -sso
cf t -o $ORGNAME

# Create spaces
cf create-space api-staging
cf create-space api-production
cf create-space public-staging
cf create-space public-production

#REBUILD MIDDLELAYER APPLICATION

createMiddlelayerServices()
{
cf t -s $1
cf create-service aws-rds shared-psql fs-api-db
cf create-service s3 basic fs-api-s3
cf create-service cloud-gov-service-account space-deployer fs-api-deployer
cf service-key my-service-account fs-api-deployer
nrm_services='{"SUDS_API_URL": $2, "password": $3, "username":$4}'
cf cups -p nrm-suds-url-service -p $nrm_services
auth_service='{"JWT_SECRET_KEY": $5}'
cf cups -p auth-service $auth_service
}

createMiddlelayerServices middlelayer-api-staging $NRM_SUDS_URL_SERVICE_PROD_SUDS_API_URL $NRM_SUDS_URL_SERVICE_password $NRM_SUDS_URL_SERVICE_username $AUTH_SERVICE_DEV_JWT_SECRET_KEY
createMiddlelayerServices middlelayer-api-production $NRM_SUDS_URL_SERVICE_PROD_SUDS_API_URL $NRM_SUDS_URL_SERVICE_password $NRM_SUDS_URL_SERVICE_username $AUTH_SERVICE_PROD_JWT_SECRET_KEY

freeOldOrgUrl()
{
cf t -o $OLDORG -s $1
cf unmap-route $2 app.cloud.gov --hostname $3
cf delete-route -f app.cloud.gov --hostname $3
}

if $FOR_MIGRATION; then
  #Free urls for middlelayer for both production and staging
  freeOldOrgUrl fs-api-staging fs-middlelayer-api-staging fs-middlelayer-api-staging
  freeOldOrgUrl fs-api-prod fs-middlelayer-api fs-middlelayer-api
fi
# Update cg-deploy orgs to Org name
findAndReplace()
{
  for f in $1
  do
    if [ -f $f -a -r $f ]; then
      sed -i "s/$2/$3/g" "$f"
     else
      echo "Error: Cannot read $f"
    fi
  Done
}

updateDeployementOrgs()
{
  git checkout $1
  findAndReplace $3 $4 $5
  git add .
  git commit -m $2
  git push origin $1
}

deployerChanges()
{
  updateDeployementOrgs $1 “update deployment to $ORGNAME” "cg-deploy/*" $OLDORG $ORGNAME
  updateDeployementOrgs $1 “update prod space name” "*" $2 $3
  updateDeployementOrgs $1 “update dev space name” "*" $4 $5
}

if $FOR_MIGRATION; then
# On old org-
# Delete old routes
# Change spaces
  deployerChanges dev fs-api-prod api-production fs-api-staging api-staging
  deployerChanges master fs-api-prod api-production fs-api-staging api-staging
fi

# Push app on new org
cf t -o $ORGNAME -s api-production
git checkout master # not sure if this makes sense
cf push fs-middlelayer-api -f "./cg-deploy/manifests/manifest.yml"

cf t -s api-staging
git checkout dev
cf push middlelayer-api-staging -f "./cg-deploy/manifests/manifest-staging.yml"

# INTAKE SERVICES
cd ..
cd fs-intake-module

createIntakeServices()
{
cf t -s $1
cf create-service aws-rds shared-psql intake-db
cf create-service s3 basic intake-s3
cf create-service cloud-gov-service-account space-deployer intake-deployer
cf service-key my-service-account intake-deployer
middlelayer_service='{"MIDDLELAYER_BASE_URL": $2, "MIDDLELAYER_PASSWORD": $3, "MIDDLELAYER_USERNAME": $4}'
cf cups -p middlelayer-service -p $middlelayer_service
intake_auth_service='{"INTAKE_CLIENT_BASE_URL": $5, "INTAKE_PASSWORD": $6, "INTAKE_USERNAME": $7}'
cf cups -p intake-auth-service $intake_auth_service
}

createIntakeServices public-staging $MIDDLE_SERVICE_PROD_MIDDLELAYER_BASE_URL $MIDDLE_SERVICE_PROD_MIDDLELAYER_PASSWORD $MIDDLE_SERVICE_PROD_MIDDLELAYER_USERNAME $INTAKE_CLIENT_SERVICE_PROD_INTAKE_CLIENT_BASE_URL $INTAKE_CLIENT_SERVICE_PROD_INTAKE_PASSWORD $INTAKE_CLIENT_SERVICE_PROD_INTAKE_USERNAME
createIntakeServices public-production $MIDDLE_SERVICE_DEV_MIDDLELAYER_BASE_URL $MIDDLE_SERVICE_DEV_MIDDLELAYER_PASSWORD $MIDDLE_SERVICE_DEV_MIDDLELAYER_USERNAME $INTAKE_CLIENT_SERVICE_DEV_INTAKE_CLIENT_BASE_URL $INTAKE_CLIENT_SERVICE_DEV_INTAKE_PASSWORD $INTAKE_CLIENT_SERVICE_DEV_INTAKE_USERNAME

if $FOR_MIGRATION; then
  # On old org-
  # Delete old routes
  freeOldOrgUrl fs-intake-staging fs-intake-staging fs-intake-staging
  freeOldOrgUrl fs-intake-staging fs-intake-api-staging fs-intake-api-staging
  freeOldOrgUrl fs-intake-prod fs-intake-api fs-intake-api
  freeOldOrgUrl fs-intake-prod forest-service-intake forest-service-epermit
fi

if $FOR_MIGRATION; then
# On old org-
# Delete old routes
# Change spaces
  deployerChanges dev fs-api-prod api-production fs-api-staging api-staging
  deployerChanges master fs-api-prod api-production fs-api-staging api-staging
fi
