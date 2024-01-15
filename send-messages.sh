#!/bin/bash

sqs_topic_url="https://sqs.us-west-2.amazonaws.com/317630533282/keda-test-queue"

while true; do
    message="Hello, AWS SQS!"
    aws sqs send-message --queue-url ${sqs_topic_url} \
    --message-body  "${message}" 
    sleep 5
done