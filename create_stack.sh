#!/bin/bash
# Script used to create an AWS CloudFormation stack using a set of templates.

if [ $# -eq 0 ]; then
  echo "Must provide command line arguments as shown below:"
  echo ""
  echo "$0 <S3_BUCKET_NAME> <S3_FOLDER> <STACK_NAME> <PREFIX> <RDP_CIDR_BLOCK> <SRT_CIDR_BLOCK> <PORT> ..."
  echo ""
  echo "Example using default IAM credentials:"
  echo "$0 MyS3Bucket MyFolder MyStack MyResource \"192.0.2.0/24\" \"192.0.2.0/24\" 5000"
  echo ""
  echo "(Optional) Example using an IAM profile called MyProfile:"
  echo "$0 MyS3Bucket MyFolder MyStack MyResource \"192.0.2.0/24\" \"192.0.2.0/24\" 5000 MyProfile"
  exit 1
fi

S3_BUCKET_NAME=$1
S3_FOLDER=$2
STACK_NAME=$3
PREFIX=$4
RDP_CIDR_BLOCK=$5
SRT_CIDR_BLOCK=$6
PORT=$7
if [ $# -ge 8 ]; then
  OPTIONAL_PROFILE="--profile $8"
else
  OPTIONAL_PROFILE=""
fi

function upload_templates_to_s3()
{
  echo "Creating CloudFormation root template and uploading template files to S3: $S3_BUCKET_NAME/$S3_FOLDER"
  aws cloudformation package --template-file ./RootStack.yml --output-template-file RootStack-generate.yml \
  --s3-bucket $S3_BUCKET_NAME --s3-prefix $S3_FOLDER $OPTIONAL_PROFILE
  exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "Failed to upload CloudFormation templates."
    exit $exit_code
  fi
}

function create_stack()
{
  echo "Creating the stack called: $STACK_NAME"
  aws cloudformation create-stack --stack-name $STACK_NAME --capabilities CAPABILITY_NAMED_IAM \
  --template-body "file://RootStack-generate.yml" --parameters ParameterKey=PrefixName,ParameterValue=$PREFIX \
  ParameterKey=RdpTrustedIpRange,ParameterValue=$RDP_CIDR_BLOCK \
  ParameterKey=SrtTrustedIpRange,ParameterValue=$SRT_CIDR_BLOCK \
  ParameterKey=SrtTrafficPort,ParameterValue=$PORT \
  $OPTIONAL_PROFILE
  exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "Failed to create the stack."
    exit $exit_code
  fi
}

function wait_for_create_to_complete()
{
  echo "Waiting for stack creation to complete. This may take 10-15 minutes..."
  aws cloudformation wait stack-create-complete --stack-name $STACK_NAME $OPTIONAL_PROFILE
  exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "Failed waiting to create the stack."
    exit $exit_code
  fi
}

function show_stack_outputs()
{
    echo "Retrieving stack outputs..."
    aws cloudformation describe-stacks --stack-name $STACK_NAME --query Stacks[].Outputs[] --output text $OPTIONAL_PROFILE
}

function download_pem_file()
{
  local KEY_NAME=${PREFIX}KeyPair

  echo "Downloading key file..."
  local KEY=$(aws ec2 describe-key-pairs --filters Name=key-name,Values=$KEY_NAME --query KeyPairs[*].KeyPairId --output text $OPTIONAL_PROFILE)
  exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "Failed to get key identifier."
    exit $exit_code
  fi

  aws ssm get-parameter --name /ec2/keypair/$KEY --with-decryption --query Parameter.Value --output text $OPTIONAL_PROFILE > ${KEY_NAME}.pem
  exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "Failed to download the key file."
    exit $exit_code
  else
   echo "Downloaded ${KEY_NAME}.pem to current working folder."
  fi
}

# Run all the functions.
upload_templates_to_s3
create_stack
wait_for_create_to_complete
show_stack_outputs
download_pem_file
