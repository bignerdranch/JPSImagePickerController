//
//  BNRStateForwardingControl.m
//  JPSImagePickerControllerDemo
//
//  Created by Nate Chandler on 7/18/14.
//  Copyright (c) 2014 JP Simard. All rights reserved.
//

#import "JPSStateForwardingControl.h"

@interface JPSStateForwardingControl ()

@end

@implementation JPSStateForwardingControl

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame forwardingTarget:(UIControl *)targetControl
{
    self = [super initWithFrame:frame];
    if (self) {
        _targetControl = targetControl;
    }
    return self;
}

#pragma mark - UIControl Overrides

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    [self.targetControl setSelected:selected];
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    [self.targetControl setEnabled:enabled];
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [self.targetControl setHighlighted:highlighted];
}

@end
