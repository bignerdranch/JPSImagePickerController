//
//  BNRStateForwardingControl.h
//  JPSImagePickerControllerDemo
//
//  Created by Nate Chandler on 7/18/14.
//  Copyright (c) 2014 JP Simard. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface JPSStateForwardingControl : UIControl

@property (nonatomic, readonly) UIControl *targetControl;

- (instancetype)initWithFrame:(CGRect)frame forwardingTarget:(UIControl *)targetControl;

@end
