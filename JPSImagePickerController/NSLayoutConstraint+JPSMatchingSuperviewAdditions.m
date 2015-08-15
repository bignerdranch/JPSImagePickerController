//
//  NSLayoutConstraint+JPSMatchingSuperviewAdditions.m
//  JPSImagePickerControllerDemo
//
//  Created by Nate Chandler on 7/17/14.
//  Copyright (c) 2014 JP Simard. All rights reserved.
//

#import "NSLayoutConstraint+JPSMatchingSuperviewAdditions.h"

@implementation NSLayoutConstraint (JPSMatchingSuperviewAdditions)

+ (NSArray/*NSLayoutConstraint*/ *)jps_constraintsForView:(UIView *)view toMatchFrameOfView:(UIView *)matchedView;
{
    NSArray *result = nil;
    
    if (view && matchedView) {
        NSLayoutConstraint *topConstraint = [NSLayoutConstraint constraintWithItem:view
                                                                         attribute:NSLayoutAttributeTop
                                                                         relatedBy:NSLayoutRelationEqual
                                                                            toItem:matchedView
                                                                         attribute:NSLayoutAttributeTop
                                                                        multiplier:1.0
                                                                          constant:0.0];
        NSLayoutConstraint *bottomConstraint = [NSLayoutConstraint constraintWithItem:view
                                                                            attribute:NSLayoutAttributeBottom
                                                                            relatedBy:NSLayoutRelationEqual
                                                                               toItem:matchedView
                                                                            attribute:NSLayoutAttributeBottom
                                                                           multiplier:1.0
                                                                             constant:0.0];
        NSLayoutConstraint *leftConstraint = [NSLayoutConstraint constraintWithItem:view
                                                                          attribute:NSLayoutAttributeLeft
                                                                          relatedBy:NSLayoutRelationEqual
                                                                             toItem:matchedView
                                                                          attribute:NSLayoutAttributeLeft
                                                                         multiplier:1.0
                                                                           constant:0.0];
        NSLayoutConstraint *rightConstraint = [NSLayoutConstraint constraintWithItem:view
                                                                           attribute:NSLayoutAttributeRight
                                                                           relatedBy:NSLayoutRelationEqual
                                                                              toItem:matchedView
                                                                           attribute:NSLayoutAttributeRight
                                                                          multiplier:1.0
                                                                            constant:0.0];
        result = @[topConstraint, bottomConstraint, leftConstraint, rightConstraint];
    } else {
        result = nil;
    }
    
    return result;
}

@end
