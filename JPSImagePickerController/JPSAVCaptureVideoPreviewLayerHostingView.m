//
//  JPSAVCaptureVideoPreviewLayerHostingView.m
//  JPSImagePickerControllerDemo
//
//  Created by Nate Chandler on 7/17/14.
//  Copyright (c) 2014 JP Simard. All rights reserved.
//

#import "JPSAVCaptureVideoPreviewLayerHostingView.h"

@implementation JPSAVCaptureVideoPreviewLayerHostingView

@dynamic layer;

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

@end
