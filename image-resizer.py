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