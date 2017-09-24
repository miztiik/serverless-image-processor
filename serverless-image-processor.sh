#!/bin/bash
set -ex

# Change to your own unique S3 bucket name:
awsRegion=ap-south-1
srcBucket=serverless-image-processor
destBucket=processed-image-data
funcName=serverless-image-processor
lambda_exec_iam_role_name=${funcName}-role
lambda_exec_iam_role_name_arn=$(aws iam get-role --role-name ${lambda_exec_iam_role_name} --output text --query 'Role.Arn')
accountID=$(aws sts get-caller-identity --output text --query 'Account')

export PATH=~/.local/bin:$PATH
source ~/.bash_profile
yum -y install zip
pip install boto3 virtualenv
virtualenv /var/${funcName}
cd /var/${funcName}
source bin/activate
pip install --upgrade pip

pip install Pillow
pip install python-resize-image
pip freeze > requirements.txt

cd /var/${funcName}/lib/python2.7/site-packages
zip -r9 /var/${funcName}.zip *

cat > /var/${funcName}/image-resizer.py << "EOF"
from __future__ import print_function

import boto3
import os
import sys
import uuid

from PIL import Image
import PIL.Image
from resizeimage import resizeimage

# Set the global variables

import boto3

globalVars  = {}
globalVars['REGION_NAME']           = "ap-south-1"
globalVars['tagName']               = "valaxy-lambda-demo"
globalVars['S3-SourceBucketName']   = "serverless-image-processor"
globalVars['S3-DestBucketName']     = "processed-image-data"
globalVars['ImgCoverSize']          = [250, 250]
globalVars['ImgProfileSize']        = [200, 200]
globalVars['ImgThumbnailSize']      = [200, 150]

s3Client = boto3.client('s3')

"""
Create the cover sized image
"""
def image_cover(image_source_path, resized_cover_path):
    with Image.open(image_source_path) as image:
        cover = resizeimage.resize_cover(image, globalVars['ImgCoverSize'])
        cover.save(resized_cover_path, image.format)

"""
Create the profile sized image
"""
def image_profile(image_source_path, resized_profile_path):
    with Image.open(image_source_path) as image:
        profile = resizeimage.resize_cover(image, globalVars['ImgProfileSize'])
        profile.save(resized_profile_path, image.format)
 
"""
Create the thumbnail sized image
"""
def image_thumbnail(image_source_path, resized_thumbnail_path):
    with Image.open(image_source_path) as image:
        thumbnail = resizeimage.resize_thumbnail(image, globalVars['ImgThumbnailSize'])
        thumbnail.save(resized_thumbnail_path, image.format)
 
 
def handler(event, context):
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        download_path = '/tmp/{}{}'.format(uuid.uuid4(), key)
        upload_path_cover = '/tmp/cover-{}'.format(key)
        upload_path_profile = '/tmp/profile-{}'.format(key)
        upload_path_thumbnail = '/tmp/thumbnail-{}'.format(key)
 
        s3Client.download_file(globalVars['S3-SourceBucketName'], key, download_path)
        fname=key.rsplit('.', 1)[0]
        fextension=key.rsplit('.', 1)[1]

        image_cover(download_path, upload_path_cover)
        s3Client.upload_file(upload_path_cover, globalVars['S3-DestBucketName'], 'cover/{0}-cover.{1}'.format(fname,fextension))
 
        image_profile(download_path, upload_path_profile)
        s3Client.upload_file(upload_path_profile, globalVars['S3-DestBucketName'], 'profile/{0}-profile.{1}'.format(fname,fextension))
 
        image_thumbnail(download_path, upload_path_thumbnail)
        s3Client.upload_file(upload_path_thumbnail, globalVars['S3-DestBucketName'], 'thumbnail/{0}-thumbnail.{1}'.format(fname,fextension))
    return key
EOF

# Add our resizer.py to the zip file
cd /var/${funcName}
zip -g /var/${funcName}.zip image-resizer.py

# Upload zip file to S3 bucket
aws s3 cp /var/${funcName}.zip s3://lambda-image-resizer-source-code

# Create the Lambda Function
aws lambda create-function \
--description "This function processess newly uploaded s3 images and uploads them to destination bucket" \
--region ${awsRegion} \
--function-name ${funcName} \
--code S3Bucket=lambda-image-resizer-source-code,S3Key=${funcName}.zip \
--role ${lambda_exec_iam_role_name_arn} \
--handler image-resizer.handler \
--runtime python2.7 \
--timeout 10 \
--memory-size 128

# Add Lambda Permissions to receive trigger notifications

aws lambda add-permission \
--function-name ${funcName} \
--region ${awsRegion} \
--statement-id some-unique-id \
--action "lambda:InvokeFunction" \
--principal s3.amazonaws.com \
--source-arn arn:aws:s3:::${srcBucket} \
--source-account ${accountID}

# Create S3 Notifications to trigger Lambda

# Get the Lambda ARN
lambda_function_arn=$(aws lambda get-function-configuration \
  --function-name "${funcName}" \
  --output text \
  --region ${awsRegion} \
  --query 'FunctionArn'
)

# Set the notification in S3 Bucket
aws s3api put-bucket-notification \
  --bucket ${srcBucket} \
  --notification-configuration '{
    "CloudFunctionConfiguration": {
      "CloudFunction": "'${lambda_function_arn}'",
      "Event": "s3:ObjectCreated:*"
    }
  }'
