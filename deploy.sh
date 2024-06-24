#!/bin/bash

# Use environment variables or prompt the user
SERVICE_NAME=${SERVICE_NAME:-$(read -p "Enter your service name: " SERVICE_NAME && echo $SERVICE_NAME)}
BUCKET_NAME=${BUCKET_NAME:-$(read -p "Enter your bucket name: " BUCKET_NAME && echo $BUCKET_NAME)}
BUCKET_NAME_2=${BUCKET_NAME_2:-$(read -p "Enter your bucket name 2: " BUCKET_NAME_2 && echo $BUCKET_NAME_2)}
# DATASET_NAME=${DATASET_NAME:-$(read -p "Enter your dataset name: " DATASET_NAME && echo $DATASET_NAME)}
# TABLE_NAME=${TABLE_NAME:-$(read -p "Enter your table name: " TABLE_NAME && echo $TABLE_NAME)}
# S3_BUCKET_NAME=${S3_BUCKET_NAME:-$(read -p "Enter your S3 bucket name: " S3_BUCKET_NAME && echo $S3_BUCKET_NAME)}

REGION="us-central1"
GIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG=sha-$GIT_SHA

# assert there's AWS_SECRET_ACCESS_KEY and AWS_ACCESS_KEY_ID set
# if [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
#   echo "
#   Please set the following environment variables:
#   - AWS_SECRET_ACCESS_KEY
#   - AWS_ACCESS_KEY_ID
#   "
#   exit 1
# fi

# echo all the variables, and wait for confirmation
echo "SERVICE_NAME: $SERVICE_NAME"
echo "BUCKET_NAME: $BUCKET_NAME"
echo "BUCKET_NAME_2: $BUCKET_NAME_2"
# echo "S3_BUCKET_NAME: $S3_BUCKET_NAME"
# echo "DATASET_NAME: $DATASET_NAME"
# echo "TABLE_NAME: $TABLE_NAME"
echo "REGION: $REGION"
echo "IMAGE_TAG: $IMAGE_TAG"
read -p "Do you want to continue? " -n 1 -r
echo


# Create Cloud Storage bucket if it doesn't exist
# if ! gsutil ls -b gs://$BUCKET_NAME &>/dev/null; then
#   echo "Creating bucket $BUCKET_NAME..."
#   gsutil mb gs://$BUCKET_NAME
# else
#   echo "Bucket $BUCKET_NAME already exists."
# fi

# # assert the bucket exists
# if ! gsutil ls -b gs://$BUCKET_NAME &>/dev/null; then
#   echo "Bucket $BUCKET_NAME does not exist."
#   exit 1
# fi

# assert the access key can write to the bucket by using s3 cli to upload a file
# echo "Testing S3 bucket access..."
# echo "Hello, world!" > /tmp/hello.txt
# aws s3 cp /tmp/hello.txt s3://$S3_BUCKET_NAME
# if [ $? -ne 0 ]; then
#   echo "Failed to upload to S3 bucket $S3_BUCKET_NAME."
#   exit 1
# fi
# aws s3 rm s3://$S3_BUCKET_NAME/hello.txt
# echo "S3 bucket access test passed."
# exit

# Deploy Cloud Run service if it doesn't exist
echo "Deploying Cloud Run service $SERVICE_NAME..."
gcloud run deploy $SERVICE_NAME \
	--image simonmok/uji:$IMAGE_TAG \
	--allow-unauthenticated \
	--region $REGION \
	--set-env-vars GCS_BUCKET_NAME=$BUCKET_NAME \
  --set-env-vars GCS_BUCKET_NAME_2=$BUCKET_NAME_2 \
  --set-env-vars S3_BUCKET_NAME=$S3_BUCKET_NAME
  # --set-env-vars AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  # --set-env-vars AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  # --set-env-vars AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION


# # NOTE(simon) We don't need this anymore after migrating to Databricks
# # Create BigQuery dataset if it doesn't exist
# if ! bq show $DATASET_NAME &>/dev/null; then
#   echo "Creating BigQuery dataset $DATASET_NAME..."
#   bq mk $DATASET_NAME
# else
#   echo "BigQuery dataset $DATASET_NAME already exists."
# fi

# # Create BigQuery external table if it doesn't exist
# if ! bq show $DATASET_NAME.$TABLE_NAME &>/dev/null; then
#   echo "Creating BigQuery external table $DATASET_NAME.$TABLE_NAME..."
#   bq mkdef --source_format=NEWLINE_DELIMITED_JSON --autodetect=true \
#     "gs://$BUCKET_NAME/*" > /tmp/uji-table-def

#   cat /tmp/uji-table-def

#   bq mk --table --external_table_definition=/tmp/uji-table-def \
#     $DATASET_NAME.$TABLE_NAME
# else
#   echo "BigQuery table $DATASET_NAME.$TABLE_NAME already exists."
# fi

