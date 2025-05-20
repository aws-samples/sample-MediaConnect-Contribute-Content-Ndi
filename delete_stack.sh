#!/bin/bash
# Script used to delete a AWS CloudFormation stack and all related resources.

if [ $# -eq 0 ]; then
  echo "Must provide command line arguments as shown below:"
  echo ""
  echo "$0 <STACK_NAME> ..."
  echo ""
  echo "Example using default IAM credentials:"
  echo "$0 MyStack"
  echo ""
  echo "(Optional) Example using an IAM profile called MyProfile:"
  echo "$0 MyStack MyProfile"
  exit 1
fi

STACK_NAME=$1
if [ $# -ge 2 ]; then
  OPTIONAL_PROFILE="--profile $2"
else
  OPTIONAL_PROFILE=""
fi

function get_flow_status()
{
    local FLOW_STATUS=$(aws mediaconnect describe-flow --flow-arn $FLOW_ARN --query "Flow.Status" $OPTIONAL_PROFILE)
    exit_code=$?
    if [[ "$exit_code" -ne 0 ]]; then
        echo ""
        return
    fi

    # Remove leading double quote.
    FLOW_STATUS="${FLOW_STATUS#\"}"
    # Remove trailing double quote.
    FLOW_STATUS="${FLOW_STATUS%\"}"

    echo $FLOW_STATUS
}

function stop_flow()
{
    echo "Getting stack flow ARN..."
    FLOW_ARN=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].Outputs[?starts_with(OutputKey, 'FlowArn')].OutputValue" --output text $OPTIONAL_PROFILE)
    exit_code=$?
    if [[ "$exit_code" -ne 0 ]]; then
        echo "Failed get flow ARN. However, will continue to try to delete stack."
        return
    fi

  echo "Stack flow ARN is: $FLOW_ARN"
  echo "Getting flow status..."
    local FLOW_STATUS=$(get_flow_status)
    if [[ "$FLOW_STATUS" == "" ]]; then
        echo "Failed get flow status. However, will continue to try to delete stack."
        return
    fi

    # If flow is STARTING, must wait for it to start.
    echo "Flow status is: $FLOW_STATUS"
    if [[ "$FLOW_STATUS" == "STARTING" ]]; then
        echo "Waiting for flow to finish starting before stopping it..."
        while [[ "$FLOW_STATUS" == "STARTING" ]]
        do
            FLOW_STATUS=$(get_flow_status)
        done
    fi
    if [[ "$FLOW_STATUS" == "" ]]; then
        echo "Failed get flow status. However, will continue to try to delete stack."
        return
    fi

    # If flow is ACTIVE, stop it.
    if [[ "$FLOW_STATUS" == "ACTIVE" ]]; then
        echo "Stopping the flow..."
        aws mediaconnect stop-flow --flow-arn $FLOW_ARN $OPTIONAL_PROFILE
        exit_code=$?
        if [[ "$exit_code" -ne 0 ]]; then
            echo "Failed get stop flow ARN: $FLOW_ARN. However, will continue to try to delete stack."
            return
        fi
    fi
    FLOW_STATUS=$(get_flow_status)
    if [[ "$FLOW_STATUS" == "" ]]; then
        echo "Failed get flow status. However, will continue to try to delete stack."
        return
    fi

    # If flow is STOPPING, must wait for it to stop.
    if [[ "$FLOW_STATUS" == "STOPPING" ]]; then
        echo "Waiting for flow to stop..."
        while [[ "$FLOW_STATUS" == "STOPPING" ]]
        do
            FLOW_STATUS=$(get_flow_status)
        done
        if [[ "$FLOW_STATUS" == "" ]]; then
            echo "Failed get flow status. However, will continue to try to delete stack."
            return
        fi
    fi
}

function delete_stack()
{
  echo "Deleting the stack called: $STACK_NAME"
  aws cloudformation delete-stack --stack-name $STACK_NAME $OPTIONAL_PROFILE
  exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "Failed to delete the stack."
    exit $exit_code
  fi
}

function wait_for_delete_to_complete()
{
  echo "Waiting for stack deletion to complete. This may take 10-15 minutes..."
  aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME $OPTIONAL_PROFILE
  exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    echo "Failed waiting to delete the stack."
    echo "Ensure that you have stopped the MediaConnect flow. Then retry the delete command."
    exit $exit_code
  else
    echo "Completed."
    echo "Verify that all AWS resources no longer exist by checking the AWS console."
  fi
}

# Run all the functions.
stop_flow
delete_stack
wait_for_delete_to_complete
