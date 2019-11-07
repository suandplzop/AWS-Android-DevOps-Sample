#!/bin/bash

set -eu

BUILD_DIR=lambda_build
SSM_PARAM_NAME="Android-DevOps-Sample-Github-OAuthToken"
RESOURCE_BUCKET="instrumentation-lambdas-resources-bucket"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <prefix>"
    exit 1
fi

ProjectName=$1

if [[ -d ${BUILD_DIR} ]]; then
    rm -r "${BUILD_DIR}"
fi

(
    unset "${!AWS_@}"

    for pkg in "device-farm-resources"; do
        echo "Packaging $pkg"
        pushd $pkg
            target="../${BUILD_DIR}/build/${pkg}"
            mkdir -p ${target}
            echo 'target dir:'$target
            ls
            pipenv lock --requirements > ${target}/requirements.txt
            pipenv run pip install --quiet --target ${target} --requirement ${target}/requirements.txt
            pipenv run pip install --quiet --target ${target} .
        popd
    done
)

cp -r ./slack_notifier/. ./${BUILD_DIR}/build/device-farm-resources/


echo "S3_BUCKET=$RESOURCE_BUCKET"
if aws s3 ls "s3://$RESOURCE_BUCKET" | grep -q 'AllAccessDisabled'    
then
    echo "$RESOURCE_BUCKET doesn\'t exist please check again"
    aws s3 mb s3://{$RESOURCE_BUCKET}}
    exit
fi

echo "Packaging device-farm custom resource lambdas"
aws cloudformation package \
    --template-file coustom_resources.ymal \
    --output-template-file lambda_build/template-resources.yaml \
    --s3-bucket $RESOURCE_BUCKET

resources_stack_name="${ProjectName}-Device-Farm-Resources"
echo "Deploying resources to ${resources_stack_name}"
aws cloudformation deploy \
    --template-file lambda_build/template-resources.yaml \
    --stack-name ${resources_stack_name} \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides "Prefix=${ProjectName}"

echo "Packaging pipeline"
aws cloudformation package \
    --template-file ci.yaml \
    --output-template-file lambda_build/template-ci.yaml \
    --s3-bucket     $RESOURCE_BUCKET

cloudformation_stack_name="${ProjectName}-DevOps"
echo "Deploying pipeline to ${cloudformation_stack_name}"
aws cloudformation deploy \
    --template-file lambda_build/template-ci.yaml \
    --stack-name ${cloudformation_stack_name} \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides "Prefix=${ProjectName}"
