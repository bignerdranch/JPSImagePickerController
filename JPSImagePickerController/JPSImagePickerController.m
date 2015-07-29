//
//  JPSImagePickerController.m
//  JPSImagePickerController
//
//  Created by JP Simard on 1/31/2014.
//  Copyright (c) 2014 JP Simard. All rights reserved.
//

#import "JPSImagePickerController.h"
#import "JPSCameraButton.h"
#import <AVFoundation/AVFoundation.h>
#import "JPSVolumeButtonHandler.h"
#import "NSLayoutConstraint+BNRMatchingSuperviewAdditions.h"
#import "JPSAVCaptureVideoPreviewLayerHostingView.h"
#import "BNRStateForwardingControl.h"

static AVCaptureVideoOrientation AVCaptureVideoOrientationFromUIDeviceOrientation(UIDeviceOrientation deviceOrientation);

static CGFloat JPSImagePickerControllerButtonInset = 15.5;

typedef NS_ENUM(NSInteger, JPSImagePickerControllerState) {
    JPSImagePickerControllerStateError = -1,
    JPSImagePickerControllerStateUnknown = 0,
    JPSImagePickerControllerStateBeginningCapture,
    JPSImagePickerControllerStateCapturing,
    JPSImagePickerControllerStateCaptured,
};

@interface JPSImagePickerController (/*Lifetime State: Views*/)
@property (nonatomic) UIImageView *previewImageView;
@property (nonatomic) JPSAVCaptureVideoPreviewLayerHostingView *capturePreviewView;

@property (nonatomic) UIView *capturingToolbarView;
@property (nonatomic) UIView *editingToolbarView;
@property (nonatomic) UIButton *cameraButton;
@property (nonatomic) UIButton *cancelButton;
@property (nonatomic) UIControl *cancelOverlayControl;
@property (nonatomic) UIButton *flashButton;
@property (nonatomic) UIControl *flashOverlayControl;
@property (nonatomic) UIButton *cameraSwitchButton;
@property (nonatomic) UIControl *cameraSwitchOverlayControl;
@property (nonatomic) UIButton *retakeButton;
@property (nonatomic) UIControl *retakeOverlayControl;
@property (nonatomic) UIButton *useButton;
@property (nonatomic) UIControl *useOverlayControl;
@end

@interface JPSImagePickerController (/*Lifetime State*/)
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureStillImageOutput *captureStillImageOutput;
@property (nonatomic) NSOperationQueue *captureQueue;
@property (nonatomic) JPSVolumeButtonHandler *volumeButtonHandler;
@end

@interface JPSImagePickerController (/*State*/)
@property (nonatomic) JPSImagePickerControllerState state;

@property (nonatomic) UIImage *previewImage;
@property (nonatomic) UIImageOrientation imageOrientation;
@end

@implementation JPSImagePickerController

#pragma mark - Lifecycle

- (id)init {
    self = [super init];
    if (self) {
        _captureQueue = ^{
            NSOperationQueue *operationQueue = [[NSOperationQueue alloc] init];
            
            operationQueue.maxConcurrentOperationCount = 1;
            
            return operationQueue;
        }();
        
        _frontCameraEnabled = YES;
        _editingEnabled = YES;
        _volumeButtonTakesPicture = YES;
    }
    return self;
}

- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]];
    view.tintColor = [UIColor whiteColor];
    view.backgroundColor = [UIColor blackColor];
    self.view = view;
    
    [self addSubviews];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self setupSession];
    [self setupRotationObservation];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self setupVolumeButtonHandler];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self teardownVolumeButtonHandler];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [self teardownRotationObservation];
    [self teardownSession];
}

#pragma mark - Accessors

- (void)setSession:(AVCaptureSession *)session
{
    _session = session;
    
    self.capturePreviewView.layer.session = session;
    [self updateCapturePreviewViewLayerConnectionVideoOrientationFromDeviceOrientation];
}

- (void)setPreviewImage:(UIImage *)previewImage
{
    _previewImage = previewImage;
    
    self.previewImageView.image = previewImage;
}

- (void)setState:(JPSImagePickerControllerState)state
{
    [self setState:state andUpdateSubviewsHidden:YES];
}

- (void)setState:(JPSImagePickerControllerState)state andUpdateSubviewsHidden:(BOOL)update
{
    _state = state;
    
    if (update) {
        [self updateSubviewsHiddenFromState];
    }
}

#pragma mark - Accessors: Capture Devices

- (AVCaptureDevice *)frontCamera
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (device.position == AVCaptureDevicePositionFront) {
            return device;
        }
    }
    return nil;
}

- (AVCaptureDevice *)currentDevice
{
    return [(AVCaptureDeviceInput *)self.session.inputs.firstObject device];
}

- (AVCaptureDevice *)captureDeviceForCaptureDevicePosition:(AVCaptureDevicePosition)position
{
    AVCaptureDevice *result = nil;
    
    switch (position) {
        case AVCaptureDevicePositionBack: {
            result = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        } break;
        case AVCaptureDevicePositionFront: {
            result = [self frontCamera];
        } break;
        case AVCaptureDevicePositionUnspecified: {
            result = nil;
        } break;
    }
    
    return result;
}

- (AVCaptureDevicePosition)captureDevicePositionAfterCaptureDevicePosition:(AVCaptureDevicePosition)currentPosition
{
    AVCaptureDevicePosition result = AVCaptureDevicePositionUnspecified;
    
    switch (currentPosition) {
        case AVCaptureDevicePositionFront: {
            result = AVCaptureDevicePositionBack;
        } break;
        case AVCaptureDevicePositionBack: {
            result = AVCaptureDevicePositionFront;
        } break;
        case AVCaptureDevicePositionUnspecified: {
            result = AVCaptureDevicePositionUnspecified;
        } break;
    }
    
    return result;
}


- (UIImageOrientation)imageOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation captureDevicePosition:(AVCaptureDevicePosition)position
{
    UIImageOrientation result = UIImageOrientationUp;
    
    switch (position) {
        case AVCaptureDevicePositionBack: {
            switch (deviceOrientation) {
                case UIDeviceOrientationLandscapeLeft: {
                    result = UIImageOrientationUp;
                } break;
                case UIDeviceOrientationLandscapeRight: {
                    result = UIImageOrientationDown;
                } break;
                case UIDeviceOrientationPortraitUpsideDown: {
                    result = UIImageOrientationLeft;
                } break;
                case UIDeviceOrientationPortrait: {
                    result = UIImageOrientationRight;
                } break;
                default: {
                    //TODO: Determine: Is this right for face-up, face-down?
                    result = UIImageOrientationRight;
                } break;
            }
        } break;
        case AVCaptureDevicePositionFront: {
            switch (deviceOrientation) {
                case UIDeviceOrientationLandscapeLeft: {
                    result = UIImageOrientationDown;
                } break;
                case UIDeviceOrientationLandscapeRight: {
                    result = UIImageOrientationUp;
                } break;
                case UIDeviceOrientationPortraitUpsideDown: {
                    result = UIImageOrientationLeft;
                } break;
                case UIDeviceOrientationPortrait: {
                    result = UIImageOrientationRight;
                } break;
                default: {
                    //TODO: Determine: Is this right for face-up, face-down?
                    result = UIImageOrientationRight;
                } break;
            }
        } break;
        case AVCaptureDevicePositionUnspecified: {
            //TODO: Determine: Does this make sense?
            result = UIImageOrientationRight;
        } break;
    }
    
    return result;
}

#pragma mark - UIViewController Overrides

- (void)updateViewConstraints
{
    [super updateViewConstraints];
    
}

#pragma mark - Setup UI

- (void)addSubviews
{
    [self addPreviewImageView];
    [self addCapturePreviewView];
    
    [self addCapturingToolbarView];
    [self addCameraSwitchButton];
    [self addCameraSwitchOverlayControl];
    [self addCameraButton];
    [self addCancelButton];
    [self addCancelOverlayControl];
    
    [self addEditingToolbarView];
    [self addUseButton];
    [self addUseOverlayControl];
    [self addRetakeButton];
    [self addRetakeOverlayControl];
    
    [self addFlashButton];
    [self addFlashOverlayControl];
    
    [self updateSubviewsHiddenFromState];
}

- (void)addCapturingToolbarView
{
    UIView *view = self.view;
    
    // View
    UIView *capturingToolbarView = [[UIView alloc] initWithFrame:view.bounds];
    capturingToolbarView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    
    [view addSubview:capturingToolbarView];
    self.capturingToolbarView = capturingToolbarView;
    
    // Constraints
    capturingToolbarView.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *topConstraint = [NSLayoutConstraint constraintWithItem:capturingToolbarView
                                                                     attribute:NSLayoutAttributeTop
                                                                     relatedBy:NSLayoutRelationEqual
                                                                        toItem:view
                                                                     attribute:NSLayoutAttributeTop
                                                                    multiplier:1.0
                                                                      constant:0.0];
    NSLayoutConstraint *rightConstraint = [NSLayoutConstraint constraintWithItem:capturingToolbarView
                                                                       attribute:NSLayoutAttributeRight
                                                                       relatedBy:NSLayoutRelationEqual
                                                                          toItem:view
                                                                       attribute:NSLayoutAttributeRight
                                                                      multiplier:1.0
                                                                        constant:0.0];
    NSLayoutConstraint *bottomConstraint = [NSLayoutConstraint constraintWithItem:capturingToolbarView
                                                                        attribute:NSLayoutAttributeBottom
                                                                        relatedBy:NSLayoutRelationEqual
                                                                           toItem:view
                                                                        attribute:NSLayoutAttributeBottom
                                                                       multiplier:1.0
                                                                         constant:0.0];
    NSLayoutConstraint *widthConstraint = [NSLayoutConstraint constraintWithItem:capturingToolbarView
                                                                       attribute:NSLayoutAttributeWidth
                                                                       relatedBy:NSLayoutRelationEqual
                                                                          toItem:nil
                                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                                      multiplier:1.0
                                                                        constant:89.0];
    [view addConstraints:@[topConstraint, rightConstraint, bottomConstraint, widthConstraint]];
}

- (void)addEditingToolbarView
{
    UIView *view = self.view;
    
    // View
    UIView *editingToolbarView = [[UIView alloc] initWithFrame:view.bounds];
    editingToolbarView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    
    [view addSubview:editingToolbarView];
    self.editingToolbarView = editingToolbarView;
    
    // Constraints
    editingToolbarView.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *leftConstraint = [NSLayoutConstraint constraintWithItem:editingToolbarView
                                                                      attribute:NSLayoutAttributeLeft
                                                                      relatedBy:NSLayoutRelationEqual
                                                                         toItem:view
                                                                      attribute:NSLayoutAttributeLeft
                                                                     multiplier:1.0
                                                                       constant:0.0];
    NSLayoutConstraint *rightConstraint = [NSLayoutConstraint constraintWithItem:editingToolbarView
                                                                       attribute:NSLayoutAttributeRight
                                                                       relatedBy:NSLayoutRelationEqual
                                                                          toItem:view
                                                                       attribute:NSLayoutAttributeRight
                                                                      multiplier:1.0
                                                                        constant:0.0];
    NSLayoutConstraint *bottomConstraint = [NSLayoutConstraint constraintWithItem:editingToolbarView
                                                                        attribute:NSLayoutAttributeBottom
                                                                        relatedBy:NSLayoutRelationEqual
                                                                           toItem:view
                                                                        attribute:NSLayoutAttributeBottom
                                                                       multiplier:1.0
                                                                         constant:0.0];
    NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:editingToolbarView
                                                                        attribute:NSLayoutAttributeHeight
                                                                        relatedBy:NSLayoutRelationEqual
                                                                           toItem:nil
                                                                        attribute:NSLayoutAttributeNotAnAttribute
                                                                       multiplier:1.0
                                                                         constant:89.0];
    [view addConstraints:@[leftConstraint, rightConstraint, bottomConstraint, heightConstraint]];
}

- (void)addCameraButton
{
    UIView *capturingToolbarView = self.capturingToolbarView;
    
    // View
    UIButton *cameraButton = [JPSCameraButton button];
    [cameraButton addTarget:self action:@selector(didPressCameraButton:) forControlEvents:UIControlEventTouchUpInside];
    
    [capturingToolbarView addSubview:cameraButton];
    self.cameraButton = cameraButton;
    
    // Constraints
    cameraButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *vertical = [NSLayoutConstraint constraintWithItem:cameraButton
                                                                attribute:NSLayoutAttributeCenterY
                                                                relatedBy:NSLayoutRelationEqual
                                                                   toItem:capturingToolbarView
                                                                attribute:NSLayoutAttributeCenterY
                                                               multiplier:1.0f
                                                                 constant:0];
    NSLayoutConstraint *horizontal = [NSLayoutConstraint constraintWithItem:cameraButton
                                                                  attribute:NSLayoutAttributeCenterX
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:capturingToolbarView
                                                                  attribute:NSLayoutAttributeCenterX
                                                                 multiplier:1.0
                                                                   constant:0.0];
    NSLayoutConstraint *width = [NSLayoutConstraint constraintWithItem:cameraButton
                                                             attribute:NSLayoutAttributeWidth
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:nil
                                                             attribute:NSLayoutAttributeNotAnAttribute
                                                            multiplier:1.0f
                                                              constant:66.0f];
    NSLayoutConstraint *height = [NSLayoutConstraint constraintWithItem:cameraButton
                                                              attribute:NSLayoutAttributeHeight
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:nil
                                                              attribute:NSLayoutAttributeNotAnAttribute
                                                             multiplier:1.0f
                                                               constant:66.0f];
    [capturingToolbarView addConstraints:@[vertical, horizontal, width, height]];
}

- (void)addCancelButton
{
    UIView *capturingToolbarView = self.capturingToolbarView;
    
    // View
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelButton.titleLabel.font = [UIFont systemFontOfSize:18.0f];
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    
    [capturingToolbarView addSubview:cancelButton];
    self.cancelButton = cancelButton;
    
    // Constraints
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *horizontal = [NSLayoutConstraint constraintWithItem:cancelButton
                                                             attribute:NSLayoutAttributeCenterX
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:capturingToolbarView
                                                             attribute:NSLayoutAttributeCenterX
                                                            multiplier:1.0f
                                                              constant:0.0f];
    NSLayoutConstraint *bottom = [NSLayoutConstraint constraintWithItem:cancelButton
                                                              attribute:NSLayoutAttributeBottom
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:capturingToolbarView
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0f
                                                               constant:-19.5f];
    [capturingToolbarView addConstraints:@[horizontal, bottom]];
}

- (void)addCancelOverlayControl
{
    UIView *capturingToolbarView = self.capturingToolbarView;
    UIButton *cancelButton = self.cancelButton;
    
    // View
    UIControl *cancelOverlayControl = [[BNRStateForwardingControl alloc] initWithFrame:CGRectMake(0, 0, 100, 100)
                                                                      forwardingTarget:cancelButton];
    [cancelOverlayControl addTarget:self action:@selector(didPressCancelButton:) forControlEvents:UIControlEventTouchUpInside];
    
    [capturingToolbarView addSubview:cancelOverlayControl];
    self.cancelOverlayControl = cancelOverlayControl;
    
    // Constraints
    cancelOverlayControl.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *right = [NSLayoutConstraint constraintWithItem:cancelOverlayControl
                                                             attribute:NSLayoutAttributeRight
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:capturingToolbarView
                                                             attribute:NSLayoutAttributeRight
                                                            multiplier:1.0
                                                              constant:0.0];
    NSLayoutConstraint *bottom = [NSLayoutConstraint constraintWithItem:cancelOverlayControl
                                                              attribute:NSLayoutAttributeBottom
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:capturingToolbarView
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0
                                                               constant:0.0];
    NSLayoutConstraint *left = [NSLayoutConstraint constraintWithItem:cancelOverlayControl
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:capturingToolbarView
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0
                                                             constant:0.0];
    NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:cancelOverlayControl
                                                           attribute:NSLayoutAttributeTop
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:cancelButton
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1.0
                                                            constant:-JPSImagePickerControllerButtonInset];
    [capturingToolbarView addConstraints:@[right, bottom, left, top]];
}

- (void)addFlashButton
{
    UIView *view = self.view;
    
    // View
    UIButton *flashButton = [UIButton buttonWithType:UIButtonTypeSystem];
    flashButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *flashButtonImage = [[UIImage imageNamed:@"JPSImagePickerController.bundle/flash_button"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    [flashButton setImage:flashButtonImage forState:UIControlStateNormal];
    [flashButton setTitle:@" On" forState:UIControlStateNormal];
    
    [view addSubview:flashButton];
    self.flashButton = flashButton;
    
    // Constraints
    NSLayoutConstraint *left = [NSLayoutConstraint constraintWithItem:flashButton
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:view
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0f
                                                             constant:8.0f];
    NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:flashButton
                                                           attribute:NSLayoutAttributeTop
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:view
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1.0f
                                                            constant:9.5f];
    [view addConstraints:@[left, top]];
}

- (void)addFlashOverlayControl
{
    UIView *view = self.view;
    
    UIButton *flashButton = self.flashButton;
    
    // View
    UIControl *flashOverlayControl = [[BNRStateForwardingControl alloc] initWithFrame:CGRectMake(0, 0, 100, 100)
                                                                     forwardingTarget:flashButton];
    [flashOverlayControl addTarget:self action:@selector(didPressFlashButton:) forControlEvents:UIControlEventTouchUpInside];
    
    [view addSubview:flashOverlayControl];
    self.flashOverlayControl = flashOverlayControl;
    
    // Constraints
    NSLayoutConstraint *left = [NSLayoutConstraint constraintWithItem:flashOverlayControl
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:view
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0
                                                             constant:0.0];
    NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:flashOverlayControl
                                                           attribute:NSLayoutAttributeTop
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:view
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1.0
                                                            constant:0.0];
    NSLayoutConstraint *right = [NSLayoutConstraint constraintWithItem:flashOverlayControl
                                                             attribute:NSLayoutAttributeRight
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:flashButton
                                                             attribute:NSLayoutAttributeRight
                                                            multiplier:1.0
                                                              constant:JPSImagePickerControllerButtonInset];
    NSLayoutConstraint *bottom = [NSLayoutConstraint constraintWithItem:flashOverlayControl
                                                              attribute:NSLayoutAttributeBottom
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:flashButton
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0
                                                               constant:JPSImagePickerControllerButtonInset];
    [view addConstraints:@[left, top, right, bottom]];
}

- (void)addCameraSwitchButton
{
    UIView *capturingToolbarView = self.capturingToolbarView;
    
    // View
    UIButton *cameraSwitchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cameraSwitchButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cameraSwitchButton setBackgroundImage:[UIImage imageNamed:@"JPSImagePickerController.bundle/camera_switch_button"] forState:UIControlStateNormal];
    
    [capturingToolbarView addSubview:cameraSwitchButton];
    self.cameraSwitchButton = cameraSwitchButton;
    
    // Constraints
    NSLayoutConstraint *horizontal = [NSLayoutConstraint constraintWithItem:cameraSwitchButton
                                                                  attribute:NSLayoutAttributeCenterX
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:capturingToolbarView
                                                                  attribute:NSLayoutAttributeCenterX
                                                                 multiplier:1.0
                                                                   constant:0.0];
    NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:cameraSwitchButton
                                                           attribute:NSLayoutAttributeTop
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:capturingToolbarView
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1.0
                                                            constant:JPSImagePickerControllerButtonInset];
    [capturingToolbarView addConstraints:@[horizontal, top]];
}

- (void)addCameraSwitchOverlayControl
{
    UIView *capturingToolbarView = self.capturingToolbarView;
    UIButton *cameraSwitchButton = self.cameraSwitchButton;
    
    // View
    UIControl *cameraSwitchOverlayControl = [[BNRStateForwardingControl alloc] initWithFrame:CGRectMake(0, 0, 100, 100)
                                                                            forwardingTarget:cameraSwitchButton];
    [cameraSwitchOverlayControl addTarget:self action:@selector(didPressCameraSwitchButton:) forControlEvents:UIControlEventTouchUpInside];
    
    [capturingToolbarView addSubview:cameraSwitchOverlayControl];
    self.cameraSwitchOverlayControl = cameraSwitchOverlayControl;
    
    // Constraints
    cameraSwitchOverlayControl.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *left = [NSLayoutConstraint constraintWithItem:cameraSwitchOverlayControl
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:capturingToolbarView
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0
                                                             constant:0.0];
    NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:cameraSwitchOverlayControl
                                                           attribute:NSLayoutAttributeTop
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:capturingToolbarView
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1.0
                                                            constant:0.0];
    NSLayoutConstraint *right = [NSLayoutConstraint constraintWithItem:cameraSwitchOverlayControl
                                                             attribute:NSLayoutAttributeRight
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:capturingToolbarView
                                                             attribute:NSLayoutAttributeRight
                                                            multiplier:1.0
                                                              constant:0.0];
    NSLayoutConstraint *bottom = [NSLayoutConstraint constraintWithItem:cameraSwitchOverlayControl
                                                              attribute:NSLayoutAttributeBottom
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:cameraSwitchButton
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0
                                                               constant:JPSImagePickerControllerButtonInset];
    [capturingToolbarView addConstraints:@[left, top, right, bottom]];
}

- (void)addPreviewImageView
{
    UIView *view = self.view;
    
    // View
    UIImageView *previewImageView = [[UIImageView alloc] initWithFrame:view.bounds];
    previewImageView.contentMode = UIViewContentModeScaleAspectFit;
    
    [view addSubview:previewImageView];
    self.previewImageView = previewImageView;

    // Constraints
    previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *constraints = [NSLayoutConstraint bnr_constraintsForView:previewImageView toMatchFrameOfView:view];
    [view addConstraints:constraints];
}

- (void)addCapturePreviewView
{
    UIView *view = self.view;
    
    // View
    JPSAVCaptureVideoPreviewLayerHostingView *capturePreviewView = [[JPSAVCaptureVideoPreviewLayerHostingView alloc] initWithFrame:view.bounds];
    capturePreviewView.layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    self.capturePreviewView = capturePreviewView;
    [view insertSubview:capturePreviewView atIndex:0];
    
    // Constraints
    capturePreviewView.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *constraints = [NSLayoutConstraint bnr_constraintsForView:capturePreviewView toMatchFrameOfView:view];
    [view addConstraints:constraints];
}

- (void)addRetakeButton
{

    UIView *editingToolbarView = self.editingToolbarView;
    
    // View
    UIButton *retakeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UILabel *titleLabel = retakeButton.titleLabel;
    titleLabel.font = [UIFont systemFontOfSize:18.0f];
    titleLabel.textColor = [UIColor whiteColor];
    [retakeButton setTitle:@"Retake" forState:UIControlStateNormal];
    
    [editingToolbarView addSubview:retakeButton];
    self.retakeButton = retakeButton;
    
    // Constraints
    retakeButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *left = [NSLayoutConstraint constraintWithItem:retakeButton
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:editingToolbarView
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0
                                                             constant:JPSImagePickerControllerButtonInset];
    NSLayoutConstraint *vertical = [NSLayoutConstraint constraintWithItem:retakeButton
                                                                attribute:NSLayoutAttributeCenterY
                                                                relatedBy:NSLayoutRelationEqual
                                                                   toItem:editingToolbarView
                                                                attribute:NSLayoutAttributeCenterY
                                                               multiplier:1.0
                                                                 constant:0.0];
    [editingToolbarView addConstraints:@[left, vertical]];
}

- (void)addRetakeOverlayControl
{
    UIView *editingToolbarView = self.editingToolbarView;
    UIButton *retakeButton = self.retakeButton;
    
    // View
    UIControl *retakeOverlayControl = [[BNRStateForwardingControl alloc] initWithFrame:CGRectMake(0, 0, 100, 100)
                                                                      forwardingTarget:retakeButton];
    [retakeOverlayControl addTarget:self action:@selector(retake:) forControlEvents:UIControlEventTouchUpInside];
    
    [editingToolbarView addSubview:retakeOverlayControl];
    self.retakeOverlayControl = retakeOverlayControl;
    
    // Constraints
    retakeOverlayControl.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:retakeOverlayControl
                                                           attribute:NSLayoutAttributeTop
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:editingToolbarView
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1.0
                                                            constant:0.0];
    NSLayoutConstraint *left = [NSLayoutConstraint constraintWithItem:retakeOverlayControl
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:editingToolbarView
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0
                                                             constant:0.0];
    NSLayoutConstraint *bottom = [NSLayoutConstraint constraintWithItem:retakeOverlayControl
                                                              attribute:NSLayoutAttributeBottom
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:editingToolbarView
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0
                                                               constant:0.0];
    NSLayoutConstraint *right = [NSLayoutConstraint constraintWithItem:retakeOverlayControl
                                                             attribute:NSLayoutAttributeTrailing
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:retakeButton
                                                             attribute:NSLayoutAttributeTrailing
                                                            multiplier:1.0
                                                              constant:JPSImagePickerControllerButtonInset];
    [editingToolbarView addConstraints:@[top, right, bottom, left]];
}

- (void)addUseButton
{
    UIView *editingToolbarView = self.editingToolbarView;
    
    // View
    UIButton *useButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UILabel *titleLabel = useButton.titleLabel;
    titleLabel.font = [UIFont systemFontOfSize:18.0f];
    titleLabel.textColor = [UIColor whiteColor];
    [useButton setTitle:@"Use Photo" forState:UIControlStateNormal];
    
    [editingToolbarView addSubview:useButton];
    self.useButton = useButton;
    
    // Constraints
    useButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *right = [NSLayoutConstraint constraintWithItem:useButton
                                                             attribute:NSLayoutAttributeRight
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:editingToolbarView
                                                             attribute:NSLayoutAttributeRight
                                                            multiplier:1.0
                                                              constant:-JPSImagePickerControllerButtonInset];
    NSLayoutConstraint *vertical = [NSLayoutConstraint constraintWithItem:useButton
                                                                attribute:NSLayoutAttributeCenterY
                                                                relatedBy:NSLayoutRelationEqual
                                                                   toItem:editingToolbarView
                                                                attribute:NSLayoutAttributeCenterY
                                                               multiplier:1.0
                                                                 constant:0.0];
    [editingToolbarView addConstraints:@[right, vertical]];
}

- (void)addUseOverlayControl
{
    UIView *editingToolbarView = self.editingToolbarView;
    UIButton *useButton = self.useButton;
    
    // View
    UIControl *useOverlayControl = [[BNRStateForwardingControl alloc] initWithFrame:CGRectMake(0, 0, 100, 100)
                                                                  forwardingTarget:useButton];
    [useOverlayControl addTarget:self action:@selector(didPressUseButton:) forControlEvents:UIControlEventTouchUpInside];
    
    [editingToolbarView addSubview:useOverlayControl];
    self.useOverlayControl = useOverlayControl;
    
    // Constraints
    useOverlayControl.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:useOverlayControl
                                                           attribute:NSLayoutAttributeTop
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:editingToolbarView
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1.0
                                                            constant:0.0];
    NSLayoutConstraint *right = [NSLayoutConstraint constraintWithItem:useOverlayControl
                                                             attribute:NSLayoutAttributeRight
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:editingToolbarView
                                                             attribute:NSLayoutAttributeRight
                                                            multiplier:1.0
                                                              constant:0.0];
    NSLayoutConstraint *bottom = [NSLayoutConstraint constraintWithItem:useOverlayControl
                                                              attribute:NSLayoutAttributeBottom
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:editingToolbarView
                                                              attribute:NSLayoutAttributeBottom
                                                             multiplier:1.0
                                                               constant:0.0];
    NSLayoutConstraint *left = [NSLayoutConstraint constraintWithItem:useOverlayControl
                                                            attribute:NSLayoutAttributeLeading
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:useButton
                                                            attribute:NSLayoutAttributeLeading
                                                           multiplier:1.0
                                                             constant:-JPSImagePickerControllerButtonInset];
    [editingToolbarView addConstraints:@[top, right, bottom, left]];
}

#pragma mark - Update UI

- (void)updateSubviewsHiddenFromState
{
    [self updateCapturePreviewViewHidden];
    [self updatePreviewImageViewHidden];
    
    [self updateCapturingToolbarViewHidden];
    [self updateCameraSwitchButtonAndOverlayControlHidden];
    [self updateCameraButtonHidden];
    [self updateCancelButtonAndOverlayControlHidden];
    
    [self updateEditingToolbarViewHidden];
    [self updateRetakeButtonAndOverlayControlHidden];
    [self updateUseButtonAndOverlayControlHidden];
    
    [self updateFlashButtonAndOverlayControlHidden];
}

- (void)updateCapturingToolbarViewHidden
{
    JPSImagePickerControllerState state = self.state;
    
    BOOL capturing = (state == JPSImagePickerControllerStateCapturing);
    BOOL beginning = (state == JPSImagePickerControllerStateBeginningCapture);
    
    BOOL visible = (beginning ||capturing);
    
    self.capturingToolbarView.hidden = !visible;
}

- (void)updateEditingToolbarViewHidden
{
    BOOL captured = (self.state == JPSImagePickerControllerStateCaptured);
    
    BOOL visible = captured;
    
    self.editingToolbarView.hidden = !visible;
}

- (void)updateFlashButtonAndOverlayControlHidden
{
    BOOL capturing = (self.state == JPSImagePickerControllerStateCapturing);
    BOOL deviceHasFlash = self.currentDevice.hasFlash;
    
    BOOL visible = deviceHasFlash && !capturing;
    
    self.flashButton.hidden = !visible;
    self.flashOverlayControl.hidden = !visible;
}

- (void)updateCameraSwitchButtonAndOverlayControlHidden
{
    JPSImagePickerControllerState state = self.state;
    
    BOOL frontCameraEnabled = self.frontCameraEnabled;
    BOOL capturing = (state == JPSImagePickerControllerStateCapturing);
    BOOL beginning = (state == JPSImagePickerControllerStateBeginningCapture);
    
    BOOL frontCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceFront];
    BOOL rearCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
    BOOL twoCamerasAvailable = frontCameraAvailable && rearCameraAvailable;
    
    BOOL visible = frontCameraEnabled
                    && (beginning || capturing)
                    && twoCamerasAvailable;
    
    self.cameraSwitchButton.hidden = !visible;
    self.cameraSwitchOverlayControl.hidden = !visible;
}

- (void)updateCapturePreviewViewHidden
{
    BOOL capturing = (self.state == JPSImagePickerControllerStateCapturing);
    
    BOOL visible = capturing;
    
    self.capturePreviewView.hidden = !visible;
}

- (void)updatePreviewImageViewHidden
{
    BOOL captured = (self.state == JPSImagePickerControllerStateCaptured);
    
    BOOL visible = captured;
    
    self.previewImageView.hidden = !visible;
}

- (void)updateRetakeButtonAndOverlayControlHidden
{
    BOOL captured = (self.state == JPSImagePickerControllerStateCaptured);
    
    BOOL visible = captured;
    
    self.retakeButton.hidden = !visible;
    self.retakeOverlayControl.hidden = !visible;
}

- (void)updateUseButtonAndOverlayControlHidden
{
    BOOL captured = (self.state == JPSImagePickerControllerStateCaptured);
    
    BOOL visible = captured;
    
    self.useButton.hidden = !visible;
    self.useOverlayControl.hidden = !visible;
}

- (void)updateCameraButtonHidden
{
    JPSImagePickerControllerState state = self.state;
    
    BOOL capturing = (state == JPSImagePickerControllerStateCapturing);
    BOOL beginning = (state == JPSImagePickerControllerStateBeginningCapture);
    
    BOOL visible = (beginning || capturing);
    
    self.cameraButton.hidden = !visible;
}

- (void)updateCancelButtonAndOverlayControlHidden
{
    JPSImagePickerControllerState state = self.state;
    
    BOOL capturing = (state == JPSImagePickerControllerStateCapturing);
    BOOL beginning = (state == JPSImagePickerControllerStateBeginningCapture);
    
    BOOL visible = (beginning || capturing);
    
    self.cancelButton.hidden = !visible;
    self.cancelOverlayControl.hidden = !visible;
}

- (void)updateCapturePreviewViewLayerConnectionVideoOrientationFromDeviceOrientation
{
    UIDevice *device = [UIDevice currentDevice];
    [self updateCapturePreviewViewLayerConnectionVideoOrientationFromDeviceOrientation:device.orientation];
}

- (void)updateCapturePreviewViewLayerConnectionVideoOrientationFromDeviceOrientation:(UIDeviceOrientation)orientation
{
    self.capturePreviewView.layer.connection.videoOrientation = AVCaptureVideoOrientationFromUIDeviceOrientation(orientation);
}

#pragma mark - Helpers: Volume Button Handler

- (void)setupVolumeButtonHandler
{
    if (self.volumeButtonTakesPicture) {
        __weak typeof(self) weak_self = self;
        self.volumeButtonHandler = [JPSVolumeButtonHandler volumeButtonHandlerWithUpBlock:^{
            __strong typeof(self) strong_self = weak_self;
            if (strong_self) {
                [strong_self didPressCameraButton:nil];
            }
        }
                                                                                downBlock:nil];
    }
}

- (void)teardownVolumeButtonHandler
{
    self.volumeButtonHandler = nil;
}

#pragma mark - UIViewController Overrides

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - Helpers: Rotation

- (void)setupRotationObservation
{
    UIDevice *device = [UIDevice currentDevice];
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter addObserver:self
                           selector:@selector(receiveDeviceOrientationDidChangeNotification:)
                               name:UIDeviceOrientationDidChangeNotification
                             object:device];
    [device beginGeneratingDeviceOrientationNotifications];
}

- (void)receiveDeviceOrientationDidChangeNotification:(NSNotification *)note
{
    UIDevice *device = note.object;
    [self updateCapturePreviewViewLayerConnectionVideoOrientationFromDeviceOrientation:device.orientation];
}

- (void)teardownRotationObservation
{
    UIDevice *device = [UIDevice currentDevice];
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    [device endGeneratingDeviceOrientationNotifications];
    [notificationCenter removeObserver:self
                                  name:UIDeviceOrientationDidChangeNotification
                                object:device];
}

#pragma mark - Helpers: Capture Session

- (void)setupSession
{
    self.state = JPSImagePickerControllerStateBeginningCapture;
    
    __weak typeof(self) weak_self = self;
    NSOperation *setupOperation = [NSBlockOperation blockOperationWithBlock:^{
        __strong typeof(self) strong_self = weak_self;
        if (strong_self) {
            AVCaptureSession *session = [[AVCaptureSession alloc] init];
            session.sessionPreset = AVCaptureSessionPresetPhoto;
            AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            NSError *error = nil;
            
            AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
            if (!input) return;
            
            [session addInput:input];
            
            // Turn on point autofocus for middle of view
            NSError *lockError = nil;
            BOOL lockSuccess = [device lockForConfiguration:&lockError];
            if (lockSuccess) {
                if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
                    device.focusPointOfInterest = CGPointMake(0.5,0.5);
                    device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
                }
                if ([device isFlashModeSupported:AVCaptureFlashModeOn]) {
                    device.flashMode = AVCaptureFlashModeOn;
                }
            }
            [device unlockForConfiguration];
            
            // Still Image Output
            AVCaptureStillImageOutput *stillOutput = [[AVCaptureStillImageOutput alloc] init];
            stillOutput.outputSettings = @{AVVideoCodecKey: AVVideoCodecJPEG};
            [session addOutput:stillOutput];
            
            strong_self.captureStillImageOutput = stillOutput;
            
            [session startRunning];
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                __strong typeof(self) strong_self = weak_self;
                if (strong_self) {
                    strong_self.session = session;
                    
                    if (session) {
                        strong_self.state = JPSImagePickerControllerStateCapturing;
                    } else {
                        strong_self.state = JPSImagePickerControllerStateError;
                    }
                }
            });
        }
    }];
    
    setupOperation.queuePriority = NSOperationQueuePriorityVeryHigh;
    [self.captureQueue addOperation:setupOperation];
}

- (void)teardownSession
{
    [self.captureQueue cancelAllOperations];
    
    __weak typeof(self) weak_self = self;
    NSOperation *teardownOperation = [NSBlockOperation blockOperationWithBlock:^{
        __strong typeof(self) strong_self = weak_self;
        if (strong_self) {
            AVCaptureSession *session = strong_self.session;
            [session stopRunning];
            for (AVCaptureInput *input in session.inputs) {
                [session removeInput:input];
            }
            for (AVCaptureOutput *output in session.outputs) {
                [session removeOutput:output];
            }
            strong_self.session = nil;
        }
    }];
    teardownOperation.queuePriority = NSOperationQueuePriorityVeryHigh;
    [self.captureQueue addOperation:teardownOperation];
}

#pragma mark - Actions

- (IBAction)didPressCameraButton:(id)sender
{
    if (!self.cameraButton.enabled) return;
    
    AVCaptureStillImageOutput *output = self.captureStillImageOutput;
    AVCaptureConnection *videoConnection = output.connections.lastObject;
    if (!videoConnection) return;
    
    self.cameraButton.enabled = NO;

    __weak typeof(self) weak_self = self;
    [output captureStillImageAsynchronouslyFromConnection:videoConnection
                                        completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
                                            __strong typeof(self) strong_self = weak_self;
                                            if (strong_self) {
                                                [self doCaptureStillImageCompletionWithImageDataSampleBuffer:imageDataSampleBuffer error:error];
                                            }
                                        }];
}

- (void)doCaptureStillImageCompletionWithImageDataSampleBuffer:(CMSampleBufferRef)imageDataSampleBuffer error:(NSError *)error
{
    if (imageDataSampleBuffer) {
        NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
        UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
        AVCaptureDeviceInput *input = self.session.inputs.firstObject;
        AVCaptureDevicePosition currentCaptureDevicePosition =
        input.device.position;
        UIImageOrientation imageOrientation = [self imageOrientationForDeviceOrientation:deviceOrientation
                                                                   captureDevicePosition:currentCaptureDevicePosition];
        self.imageOrientation = imageOrientation;
        UIImage *image = [UIImage imageWithCGImage:[[[UIImage alloc] initWithData:imageData] CGImage]
                                             scale:1.0f
                                       orientation:imageOrientation];
        self.previewImage = image;
        [self setState:JPSImagePickerControllerStateCaptured andUpdateSubviewsHidden:NO];
        
        [self delegateCalloutDidCaptureImage:image];
        if (self.editingEnabled) {
            [self updateSubviewsHiddenFromState];
        } else {
            [self delegateCalloutDidConfirmImage:image];
        }
    } else {
        self.cameraButton.enabled = YES;
    }
}

- (IBAction)didPressCancelButton:(id)sender
{
    [self delegateCalloutDidCancel];
}

- (IBAction)didPressFlashButton:(id)sender
{
    // Expand to show flash modes
    AVCaptureDevice *device = [self currentDevice];
    // Turn on point autofocus for middle of view
    NSError *lockError = nil;
    BOOL lockSuccess = [device lockForConfiguration:&lockError];
    if (lockSuccess) {
        if (device.flashMode == AVCaptureFlashModeOff) {
            device.flashMode = AVCaptureFlashModeOn;
            [self.flashButton setTitle:@" On" forState:UIControlStateNormal];
        } else {
            device.flashMode = AVCaptureFlashModeOff;
            [self.flashButton setTitle:@" Off" forState:UIControlStateNormal];
        }
    }
    [device unlockForConfiguration];
}

- (IBAction)didPressCameraSwitchButton:(id)sender
{
    if (!self.cameraSwitchButton.enabled) return;
    self.cameraSwitchButton.enabled = NO;
    // Input Switch
    __weak typeof(self) weak_self = self;
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        __strong typeof(self) strong_self = weak_self;
        if (strong_self) {
            AVCaptureSession *session = strong_self.session;
            AVCaptureDeviceInput *input = session.inputs.firstObject;
            
            [session stopRunning];
            [session removeInput:input];
            
            AVCaptureDevicePosition currentCaptureDevicePosition =
            input.device.position;
            AVCaptureDevicePosition newCaptureDevicePosition =
            [strong_self captureDevicePositionAfterCaptureDevicePosition:currentCaptureDevicePosition];
            AVCaptureDevice *device =
            [strong_self captureDeviceForCaptureDevicePosition:newCaptureDevicePosition];
            
            NSError *error = nil;
            input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                          error:&error];
            if (!input) {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    self.cameraSwitchButton.enabled = YES;
                });
                return;
            }
            
            [session addInput:input];
            [session startRunning];
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                __strong typeof(self) strong_self = weak_self;
                strong_self.capturePreviewView.alpha = 1.0;
                self.cameraSwitchButton.enabled = YES;
            });
        }
    }];
    operation.queuePriority = NSOperationQueuePriorityVeryHigh;
    [self.captureQueue addOperation:operation];
    
    // Flip Animation
    [UIView transitionWithView:self.capturePreviewView
                      duration:0.5
                       options:UIViewAnimationOptionTransitionFlipFromLeft | UIViewAnimationOptionAllowAnimatedContent
                    animations:^{
                        __strong typeof(self) strong_self = weak_self;
                        strong_self.capturePreviewView.alpha = 0.2;
                    }
                    completion:nil];
}

- (IBAction)retake:(id)sender
{
    self.state = JPSImagePickerControllerStateCapturing;
    self.cameraButton.enabled = YES;
}

- (IBAction)didPressUseButton:(id)sender
{
    [self delegateCalloutDidConfirmImage:self.previewImage];
}

#pragma mark - Delegate Indirection

- (void)delegateCalloutDidCaptureImage:(UIImage *)image
{
    if ([self.delegate respondsToSelector:@selector(picker:didCaptureImage:)]) {
        [self.delegate picker:self didCaptureImage:image];
    }
}

- (void)delegateCalloutDidConfirmImage:(UIImage *)image
{
    if ([self.delegate respondsToSelector:@selector(picker:didConfirmImage:)]) {
        [self.delegate picker:self didConfirmImage:image];
    }
}

- (void)delegateCalloutDidCancel
{
    if ([self.delegate respondsToSelector:@selector(pickerDidCancel:)]) {
        [self.delegate pickerDidCancel:self];
    }
}

@end

static AVCaptureVideoOrientation AVCaptureVideoOrientationFromUIDeviceOrientation(UIDeviceOrientation deviceOrientation)
{
    static NSDictionary *dictionary = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *mutableDictionary = [[NSMutableDictionary alloc] init];
        
#undef SetVideoOrientationForDeviceOrientation
#define SetVideoOrientationForDeviceOrientation( videoOrientation , deviceOrientation ) \
    do { \
        mutableDictionary[@(deviceOrientation)] = @(videoOrientation); \
    } while(0)
        
        SetVideoOrientationForDeviceOrientation( AVCaptureVideoOrientationPortrait , UIDeviceOrientationPortrait );
        SetVideoOrientationForDeviceOrientation( AVCaptureVideoOrientationPortraitUpsideDown , UIDeviceOrientationPortraitUpsideDown );
        SetVideoOrientationForDeviceOrientation( AVCaptureVideoOrientationLandscapeRight , UIDeviceOrientationLandscapeRight );
        SetVideoOrientationForDeviceOrientation( AVCaptureVideoOrientationLandscapeLeft , UIDeviceOrientationLandscapeLeft );
        
#undef SetVideoOrientationForDeviceOrientation
        
        dictionary = [mutableDictionary copy];
    });
    
    NSNumber *resultNumber = dictionary[@(deviceOrientation)];
    AVCaptureVideoOrientation result = resultNumber.integerValue;
    return result;
}
