# Serverless-image-processor
A python library to process images uploaded to S3 using lambda services. When a user uploads an image to S3 bucket, SNS notifications from S3 bucket will invoke the lambda function. The object is picked from the source bucket, processed and uploaded to destination buckets based on size.
![Fig 1 : Valaxy-Serverless-Image-Processor](https://raw.githubusercontent.com/miztiik/serverless-image-processor/master/img/Valaxy-Serverless-Image-Processor.png)
## Pre-Requisities
 - AWS CLI Installed and Configured
 -- For instructions to install `aws` cli refer [here](https://github.com/miztiik/AWS-Demos/tree/master/How-To/setup-aws-cli)
- IAM Lambda Service Role: `serverless-image-processor`
  - Permissions to `AWSS3FullAccess`
  - Permissions to `AWSLambdaExecute`
- Source S3 Bucket : `serverless-image-processor`
- Destination S3 Bucket : `processed-image-data`
  - Three Sub-Directories under destination bucket
    - `cover`
    - `profile`
    - `thumbnail`
 
_Note : You might not be able to use the same bucket names, so choose your own bucket names and use accordingly_


### Create Python Work Environment
Install the Boto3 package if it not there already - For packaging to lambda it is not necessary as it is provided by AWS by default, so we can install it outside our virtual environment. _If `pip` is not found install by following the instructions [here](https://github.com/miztiik/AWS-Demos/tree/master/How-To/setup-aws-cli)_

#### Setup Environment Variables
Set up environment variables describing the associated resources,
```sh
# Change to your own unique S3 bucket name:
awsRegion=ap-south-1
srcBucket=serverless-image-processor
destBucket=processed-image-data
funcName=serverless-image-processor
lambda_exec_iam_role_name=${funcName}-role
lambda_exec_iam_role_name_arn=$(aws iam get-role --role-name ${lambda_exec_iam_role_name} --output text --query 'Role.Arn')
accountID=$(aws sts get-caller-identity --output text --query 'Account')
```


# Setup the AWS bash profile
```sh
export PATH=~/.local/bin:$PATH
source ~/.bash_profile
```

```sh
yum -y install zip
pip install boto3 virtualenv
virtualenv /var/${funcName}
cd /var/${funcName}
source bin/activate
pip install --upgrade pip
```
We will be using the python `Pillow` package for doing the image processing.
```sh
pip install Pillow
pip install python-resize-image
pip freeze > requirements.txt
```

### Lets Package the bin for lambda
```sh
cd /var/${funcName}/lib/python2.7/site-packages
zip -r9 /var/${funcName}.zip *
```

### Image Resizing Code
The source, destination buckets needs to be updated to **your bucket names**
```sh
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
```

### Add our `resizer.py` to the zip file
```sh
cd /var/${funcName}
zip -g /var/${funcName}.zip image-resizer.py
```

#### Upload zip file to S3 bucket
```sh
aws s3 cp /var/${funcName}.zip s3://lambda-image-resizer-source-code
##### The URI for the s3 object should be something like,
https://s3.ap-south-1.amazonaws.com/lambda-image-resizer-source-code/serverless-image-processor.zip
```

Copy the url `https://s3.ap-south-1.amazonaws.com/lambda-image-resizer-source-code/serverless-image-processor.zip` from s3 and update the lambda function configuration

### Create the Lambda Function
You may find it easier to do the below steps from the GUI console, But be sure to provide the same values,

```sh
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
```

#### Add Lambda Permissions to receive trigger notifications
```sh
aws lambda add-permission \
--function-name ${funcName} \
--region ${awsRegion} \
--statement-id some-unique-id \
--action "lambda:InvokeFunction" \
--principal s3.amazonaws.com \
--source-arn arn:aws:s3:::${srcBucket} \
--source-account ${accountID} 
```

#### Create S3 Notifications to trigger Lambda
```sh
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
```

### Test the function
Go ahead and upload an object to your S3 source bucket and you should be able to find smaller images in the destination bucket after few seconds. _Allow few seconds for the lambda function to run:)_
