#!/bin/bash

# Set the name of the S3 bucket and the IAM user
BUCKET_NAME="vllm-usage-stats"
IAM_USER_NAME="s3-vllm-usage-stats-write-access-user"

# make the bucket name if not exists
if ! aws s3api head-bucket --bucket $BUCKET_NAME  2>/dev/null; then
  echo "Creating bucket $BUCKET_NAME..."
  aws s3 mb s3://$BUCKET_NAME
else
  echo "Bucket $BUCKET_NAME already exists."
fi

# Create the IAM user
aws iam create-user --user-name $IAM_USER_NAME

# Create the policy that allows writing to the specified S3 bucket
POLICY_NAME="${IAM_USER_NAME}-policy"
POLICY_DOCUMENT='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::'$BUCKET_NAME'/*"
        }
    ]
}'

# Create the policy and attach it to the user
aws iam put-user-policy --user-name $IAM_USER_NAME --policy-name $POLICY_NAME --policy-document "$POLICY_DOCUMENT"

# Create access keys for the user
ACCESS_KEYS=$(aws iam create-access-key --user-name $IAM_USER_NAME)

# Extract and print the access key ID and secret access key
ACCESS_KEY_ID=$(echo $ACCESS_KEYS | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo $ACCESS_KEYS | jq -r '.AccessKey.SecretAccessKey')

echo "export AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID"
echo "export AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY"
