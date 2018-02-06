#!/bin/bash
RED=`tput setaf 1`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
RESET=`tput sgr0`

###############################################
##### funtion to display the script usage #####
###############################################
function Usage()
{
   echo "${GREEN}###################################################################"
   echo " Usage: $0 --environment=<ENVIRONMENT> "
   echo "###################################################################${RESET}"
   exit 0
}

################################################
##### function to get the lambda functions #####
################################################
function getLambdaFunctions()
{
  echo "${BLUE}--> fetching lambda functions for environment[$ENVIRONMENT], please wait..."
  if [ "$ENVIRONMENT" = "production" ]; then
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --region ap-southeast-2 | grep "$GREP_COMMAND" | cut -f2 -d ':' | cut -f2 -d '"' | grep -v 'dev_' | grep -v 'test_')
  else
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --region ap-southeast-2 | grep "$GREP_COMMAND" | cut -f2 -d ':' | cut -f2 -d '"')
  fi
  if [ -z "$LAMBDA_FUNCTIONS" ]; then
    echo "${RED}ERROR => failed to get the lambda functions for environment[$ENVIRONMENT], exiting...${RESET}"
    exit 1
  fi
  echo "${GREEN}--> found below lambda functions for environment[$ENVIRONMENT]..."
  for lambda in $LAMBDA_FUNCTIONS; do
    echo "--> $lambda"
  done
  echo $RESET
}

###################################################
##### function to invoke the lambda functions #####
###################################################
function invokeLambdaFunction()
{
   for lambda in $LAMBDA_FUNCTIONS; do
     echo "${GREEN}--> invoking lambda function $lambda, please wait...${RESET}"
     if [ "$ENVIRONMENT" = "development" ] || [ "$ENVIRONMENT" = "staging" ]; then
       FUNCTION_NAME=$(echo $lambda | cut -f2- -d '_')
       PAYLOAD_FILE="$LAMBDA_JSON_DIRECTORY/${FUNCTION_NAME}.json"
       LOGOUT_JSON_FILE="$LAMBDA_LOGS_DIRECTORY/${FUNCTION_NAME}.json"
       LOGOUT_STATUS_FILE="$LAMBDA_LOGS_DIRECTORY/${FUNCTION_NAME}.log"
     fi
     if [ ! -s "$PAYLOAD_FILE" ]; then
        echo "${RED}--> $lambda${RESET}"
     else
        LAMBDA_INVOKE_OUTPUT=$(aws lambda invoke --invocation-type RequestResponse --payload file://$PAYLOAD_FILE --function-name $lambda --region $REGION --log-type Tail $LOGOUT_JSON_FILE | tee $LOGOUT_STATUS_FILE)
        if [ -s "$LOGOUT_STATUS_FILE" ]; then
          STATUS_CODE=$(cat $LOGOUT_STATUS_FILE | grep 'StatusCode' | cut -f2 -d ':' | tr -d ' ')
          if [ $STATUS_CODE -ne 200 ]; then
             echo "${RED}--> get status code $STATUS_CODE for lambda function $lambda, failed to invalidate...${RESET}"
             exit 1
          fi
          ENCRYPT_LOGOUTPUT=$(cat $LOGOUT_STATUS_FILE | grep '"LogResult":' | cut -f4 -d '"' | base64 --decode)
          echo $ENCRYPT_LOGOUTPUT
        fi
     fi
   done
}

for i in "$@"
do
case $i in
    --environment=*)
     ENVIRONMENT="${i#*=}"
     shift
     ;;
    --help=*)
     Usage
     shift
     ;;
    *)
     Usage
     exit 1
    ;;
esac
done

LAMBDA_FUNCTIONS=
LOGOUT_FILE=
LAMBDA_JSON_DIRECTORY='/var/lib/jenkins/lambda'
LAMBDA_LOGS_DIRECTORY="$LAMBDA_JSON_DIRECTORY/logs/$ENVIRONMENT"
REGION="ap-southeast-2"

if [ -z "$ENVIRONMENT" ]; then
   echo "${RED}ERROR => pass environment with --environment=<ENVIRONMENT> switch, exiting...${RESET}"
   exit 1
fi
if [ ! -d "$LAMBDA_JSON_DIRECTORY" ]; then
  echo "${RED}ERROR => $LAMBDA_JSON_DIRECTORY directory does not exist, exiting...${RESET}"
  exit 1
fi

case $ENVIRONMENT in
   'development')
      GREP_COMMAND='"FunctionName": "dev_'
      ;;
   'staging')
      GREP_COMMAND='"FunctionName": "test_'
      ;;
   'production')
      GREP_COMMAND='"FunctionName":'
      ;;
    *)
      echo "${RED}ERROR => unsupported environment $ENVIRONMENT, exiting...${RESET}"
      exit 1
      ;;
esac

if [ ! -d "$LAMBDA_LOGS_DIRECTORY" ]; then
  mkdir -p "$LAMBDA_LOGS_DIRECTORY"
fi

getLambdaFunctions
invokeLambdaFunction
