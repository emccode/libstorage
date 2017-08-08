#!/usr/bin/env bash

# This script cleans up the infrastructure used for tests

#set -e

CF_STACK_NAME=${CF_STACK_NAME:-$1}

# Make sure that jq is installed
hash curl 2>/dev/null || {
  if [ -e "/etc/redhat-release" -o \
         -e "/etc/redhat-version" ]; then
    sudo yum -y install curl
  elif [ -e "/etc/debian-release" -o \
         -e "/etc/debian-version" -o \
         -e "/etc/lsb-release" ]; then
    sudo apt-get install -y curl
  else
    sudo brew install curl
  fi
}
# Make sure that aws cli is installed
hash aws 2>/dev/null || {
  curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "/tmp/awscli-bundle.zip"
  unzip /tmp/awscli-bundle.zip
  sudo /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
}
# Make sure that jq is installed
hash jq 2>/dev/null || {
  if [ -e "/etc/redhat-release" -o \
         -e "/etc/redhat-version" ]; then
    sudo yum -y install jq
  elif [ -e "/etc/debian-release" -o \
         -e "/etc/debian-version" -o \
         -e "/etc/lsb-release" ]; then
    sudo apt-get install -y jq
  else
    sudo brew install jq
  fi
}

usage() {
  echo "Usage: ${0} stack-name"
  echo ""
  echo "   stack-name: AWS stack name. Must be uniquely identifiable"
}

if [ -z "${CF_STACK_NAME}" ]; then
  usage
  exit 1
fi

# Get stack ID
CF_STACK_ID=$(aws cloudformation describe-stacks \
  --stack-name ${CF_STACK_NAME} \
  --output text \
  --query 'Stacks[0].StackId')

# Delete cloud formation stack
aws cloudformation delete-stack \
  --stack-name ${CF_STACK_NAME}

echo "Waiting for CF stack to get deleted ..."

aws cloudformation wait stack-delete-complete \
  --stack-name ${CF_STACK_ID}

rm -f ~/.aws/config
rm -f ~/.aws/credentials
rm -f ./keyfile
rm -f ./output*.txt

echo "Stack has been deleted"
