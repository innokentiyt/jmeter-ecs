#!/bin/sh
#
# Main entrypoint for our Docker image - runs Gru, Minions or other commands

# any .jmx file passed in the command line we act as 'Gru'
if [ ${1##*.} = 'jmx' ]; then

  if [ "$MINION_HOSTS" = '' ]; then
    echo "MINION_HOSTS must be specified - a command separated list of hostnames or IP addresses"
    exit 1
  fi
  echo "Connecting to $MINION_HOSTS"

  # AWS Public HOSTNAME API
  echo "Detecting an AWS Environment"
  PUBLIC_HOSTNAME=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-hostname)

  if [ "$PUBLIC_HOSTNAME" = '' ]; then
    echo "Not running in AWS.  Using Gru HOSTNAME $HOSTNAME"
  else
    HOSTNAME=$PUBLIC_HOSTNAME
    echo "Using Gru AWS Public HOSTNAME $HOSTNAME"
  fi
  # empty the logs directory, or jmeter may fail
  rm -rf /logs/report /logs/*.log /logs/*.jtl

  if [ "$S3_BUCKET" != '' ]; then
    echo "Pulling $1 from $S3_BUCKET"
    aws s3 cp s3://$S3_BUCKET/$1 $1

    # run jmeter in client (gru) mode
    jmeter -n $JMETER_FLAGS \
      -R $MINION_HOSTS \
      -Dclient.rmi.localport=51000 \
      -Djava.rmi.server.hostname=${PUBLIC_HOSTNAME} \
      -l $RESULTS_LOG \
      -t $1 \
      -e -o /logs/report \
      -X

    if [ $? != 0 ]; then
      echo "jmeter failed with error $?"
      exit $?
    fi

    # remove the jmx file then copy all the results back to s3
    rm $1
    FOLDER_NAME=$(date -I'seconds')
    aws s3 cp --recursive --acl public-read . "s3://$S3_BUCKET/$FOLDER_NAME"

    FOLDER_ENCODED=$(python -c "import sys, urllib as ul; print ul.quote(\"$FOLDER_NAME\")")

    echo "*******************"
    echo "Results url:"
    echo "https://s3-$AWS_DEFAULT_REGION.amazonaws.com/$S3_BUCKET/$FOLDER_ENCODED/report/index.html"
    echo "*******************"

    exit 0
  else
    # run jmeter in client (gru) mode
    exec jmeter -n $JMETER_FLAGS \
      -R $MINION_HOSTS \
      -Dclient.rmi.localport=51000 \
      -Djava.rmi.server.hostname=${PUBLIC_HOSTNAME} \
      -l $RESULTS_LOG \
      -t $1 \
      -e -o /logs/report
  fi
fi

# act as a 'Minion'
if [ "$1" = 'minion' ]; then

  # AWS Public HOSTNAME API
  echo "Detecting an AWS Environment"
  PUBLIC_HOSTNAME=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-hostname)

  if [ "$PUBLIC_HOSTNAME" = '' ]; then
    echo "Not running in AWS.  Using Minion HOSTNAME $HOSTNAME"
  else
    HOSTNAME=$PUBLIC_HOSTNAME
    echo "Using Minion AWS Public HOSTNAME $HOSTNAME"
  fi
  # run jmeter in server (minion) mode
  exec jmeter-server -n \
    -Dserver.rmi.localport=50000 \
    -Djava.rmi.server.hostname=${HOSTNAME}

fi

exec "$@"
