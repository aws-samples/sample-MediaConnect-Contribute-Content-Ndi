# Script used to delete a AWS CloudFormation stack and all related resources.

if ( $args.Count -eq 0 ) {
  echo "Must provide command line arguments as shown below:"
  echo ""
  echo ".\delete_stack.ps1 <STACK_NAME> ..."
  echo ""
  echo "Example using default IAM credentials:"
  echo ".\delete_stack.ps1 MyStack"
  echo ""
  echo "(Optional) Example using an IAM profile called MyProfile:"
  echo ".\delete_stack.ps1 MyStack MyProfile"
  exit 1
}

$STACK_NAME=$args[0]
if ( $args.Count -ge 2 ) {
  $OPTIONAL_PROFILE=@("--profile", $args[1])
} else {
  $OPTIONAL_PROFILE=""
}

function get_flow_status()
{
  $FLOW_STATUS=(aws mediaconnect describe-flow --flow-arn $FLOW_ARN --query "Flow.Status" $OPTIONAL_PROFILE)
  $exit_code=$LastExitCode
  if ( "$exit_code" -ne 0 ) {
    echo ""
    return
  }

  # Remove leading and trailing double quote.
  $FLOW_STATUS=$FLOW_STATUS.Trim('"')

  echo $FLOW_STATUS
}

function stop_flow()
{
  echo "Getting stack flow ARN..."
  $FLOW_ARN=(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[].Outputs[?starts_with(OutputKey, 'FlowArn')].OutputValue" --output text $OPTIONAL_PROFILE)
  $exit_code=$LastExitCode
  if ( "$exit_code" -ne 0 ) {
    echo "Failed get flow ARN. However, will continue to try to delete stack."
    return
  }

  echo "Stack flow ARN is: $FLOW_ARN"
  echo "Getting flow status..."
  $FLOW_STATUS=$(get_flow_status)
  if ( "$FLOW_STATUS" -eq "" ) {
    echo "Failed get flow status. However, will continue to try to delete stack."
    return
  }

  # If flow is STARTING, must wait for it to start.
  echo "Flow status is: $FLOW_STATUS"
  if ( "$FLOW_STATUS" -eq "STARTING" ) {
    echo "Waiting for flow to finish starting before stopping it..."
    while ( "$FLOW_STATUS" -eq "STARTING" ) {
      $FLOW_STATUS=$(get_flow_status)
    }
  }
  if ( "$FLOW_STATUS" -eq "" ) {
    echo "Failed get flow status. However, will continue to try to delete stack."
    return
  }

  # If flow is ACTIVE, stop it.
  if ( "$FLOW_STATUS" -eq "ACTIVE" ) {
    echo "Stopping the flow..."
    aws mediaconnect stop-flow --flow-arn $FLOW_ARN $OPTIONAL_PROFILE
    $exit_code=$LastExitCode
    if ( "$exit_code" -ne 0 ) {
      echo "Failed get stop flow ARN: $FLOW_ARN. However, will continue to try to delete stack."
      return
    }
  }
  $FLOW_STATUS=$(get_flow_status)
  if ( "$FLOW_STATUS" -eq "" ) {
    echo "Failed get flow status. However, will continue to try to delete stack."
    return
  }

  # If flow is STOPPING, must wait for it to stop.
  if ( "$FLOW_STATUS" -eq "STOPPING" ) {
    echo "Waiting for flow to stop..."
    while ( "$FLOW_STATUS" -eq "STOPPING" ) {
      $FLOW_STATUS=$(get_flow_status)
    }
    if ( "$FLOW_STATUS" -eq "" ) {
      echo "Failed get flow status. However, will continue to try to delete stack."
      return
    }
  }
}

function delete_stack()
{
  echo "Deleting the stack called: $STACK_NAME"
  aws cloudformation delete-stack --stack-name $STACK_NAME $OPTIONAL_PROFILE
  $exit_code=$LastExitCode
  if ( "$exit_code" -ne 0 ) {
    echo "Failed to delete the stack."
    exit $exit_code
  }
}

function wait_for_delete_to_complete()
{
  echo "Waiting for stack deletion to complete. This may take 10-15 minutes..."
  aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME $OPTIONAL_PROFILE
  $exit_code=$LastExitCode
  if ( "$exit_code" -ne 0 ) {
    echo "Failed waiting to delete the stack."
    echo "Ensure that you have stopped the MediaConnect flow. Then retry the delete command."
    exit $exit_code
  } else {
    echo "Completed."
    echo "Verify that all AWS resources no longer exist by checking the AWS console."
  }
}

# Run all the functions.
stop_flow
delete_stack
wait_for_delete_to_complete
