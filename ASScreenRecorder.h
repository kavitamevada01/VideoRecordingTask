//
//  ASScreenRecorder.h
//  ScreenRecorder
//
//  Created by Alan Skipp on 23/04/2014.
//  Copyright (c) 2014 Alan Skipp. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "NSGIF.h"
#import "ScreenRecordingRCTModule.h"

typedef void (^VideoCompletionBlock)(void);
@protocol ASScreenRecorderDelegate;

@interface ASScreenRecorder : NSObject<AVAudioRecorderDelegate, AVAudioPlayerDelegate>
{
  AVAudioRecorder *recorder;
  
}

@property (nonatomic, readonly) BOOL isRecording;

// delegate is only required when implementing ASScreenRecorderDelegate - see below
@property (nonatomic, weak) id <ASScreenRecorderDelegate> delegate;

// if saveURL is nil, video will be saved into camera roll
// this property can not be changed whilst recording is in progress
@property (strong, nonatomic) NSURL *videoURL;
@property (strong, nonatomic) NSString *CurrentFileName;
@property (strong, nonatomic) NSString *DocumentPath;
@property (strong, nonatomic) NSString *ContainFolder;
@property (strong, nonatomic) ScreenRecordingRCTModule *screenRecordingRCTModule;
@property (readwrite, nonatomic) NSInteger videoWidth;
@property (readwrite, nonatomic) NSInteger videoHeight;
@property (readwrite, nonatomic) NSInteger videoX;
@property (readwrite, nonatomic) NSInteger videoY;
@property (readwrite, nonatomic) Boolean isRecordSound;
@property (readwrite, nonatomic) Boolean isRecordGifFormat;

@property(nonatomic,retain)AVURLAsset* videoAsset;
@property(nonatomic,retain)AVURLAsset* audioAsset;
+ (instancetype)sharedInstance;
+ (instancetype)newInstance;
- (BOOL)startRecording;
- (void)stopRecordingWithCompletion:(VideoCompletionBlock)completionBlock;
@end


// If your view contains an AVCaptureVideoPreviewLayer or an openGL view
// you'll need to write that data into the CGContextRef yourself.
// In the viewcontroller responsible for the AVCaptureVideoPreviewLayer / openGL view
// set yourself as the delegate for ASScreenRecorder.
// [ASScreenRecorder sharedInstance].delegate = self
// Then implement 'writeBackgroundFrameInContext:(CGContextRef*)contextRef'
// use 'CGContextDrawImage' to draw your view into the provided CGContextRef
@protocol ASScreenRecorderDelegate <NSObject>
- (void)writeBackgroundFrameInContext:(CGContextRef*)contextRef;
@end
