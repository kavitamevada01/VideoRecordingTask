//
//  ASScreenRecorder.m
//  ScreenRecorder
//
//  Created by Alan Skipp on 23/04/2014.
//  Copyright (c) 2014 Alan Skipp. All rights reserved.
//

#import "ASScreenRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AssetsLibrary/AssetsLibrary.h>

@interface ASScreenRecorder()
@property (strong, nonatomic) AVAssetWriter *videoWriter;
@property (strong, nonatomic) AVAssetWriterInput *videoWriterInput;
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor *avAdaptor;
@property (strong, nonatomic) CADisplayLink *displayLink;
@property (strong, nonatomic) NSDictionary *outputBufferPoolAuxAttributes;
@property (strong, nonatomic) NSString *outputPath;
@property (nonatomic) CFTimeInterval firstTimeStamp;
@property (nonatomic) BOOL isRecording;

@end

@implementation ASScreenRecorder
{
  dispatch_queue_t _render_queue;
  dispatch_queue_t _append_pixelBuffer_queue;
  dispatch_semaphore_t _frameRenderingSemaphore;
  dispatch_semaphore_t _pixelAppendSemaphore;
  NSString *_documentsPath;
  CGSize _viewSize;
  CGSize _videoSize;
  CGRect _cropRect;
  CGFloat _scale;
  CMTime _VideoFirstRecordedTime;
  CMTime videoFrametime;

  int newSecond;
  NSDateFormatter *_formatter;
  CGColorSpaceRef _rgbColorSpace;
  CVPixelBufferPoolRef _outputBufferPool;
}
@synthesize videoAsset,audioAsset,CurrentFileName,videoWidth,videoHeight,videoX,videoY,ContainFolder,DocumentPath,screenRecordingRCTModule,isRecordSound,isRecordGifFormat;
#pragma mark - initializers

+ (instancetype)sharedInstance {
  static ASScreenRecorder *sharedInstance;
  if(sharedInstance == nil)
  {
    sharedInstance = [[self alloc] init];
  }
  return sharedInstance;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
   _formatter = [[NSDateFormatter alloc] init];
    [self ResetVideoTimeFrame];
    [_formatter setDateFormat:@"ddhhmmss"];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    _documentsPath = [paths objectAtIndex:0]; //Get the docs directory

    _viewSize = [UIApplication sharedApplication].delegate.window.bounds.size;
    _scale = [UIScreen mainScreen].scale;
    // record half size resolution for retina iPads
    if ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) && _scale > 1) {
      _scale = 1.0;
    }
    _isRecording = NO;
    
    _append_pixelBuffer_queue = dispatch_queue_create("ASScreenRecorder.append_queue", DISPATCH_QUEUE_SERIAL);
    _render_queue = dispatch_queue_create("ASScreenRecorder.render_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(_render_queue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    _frameRenderingSemaphore = dispatch_semaphore_create(1);
    _pixelAppendSemaphore = dispatch_semaphore_create(1);
  }
  return self;
}

#pragma mark - public

- (void)setVideoURL:(NSURL *)videoURL
{
  NSAssert(!_isRecording, @"videoURL can not be changed whilst recording is in progress");
  _videoURL = videoURL;
}

- (void)StartNewRecordingAudioFile
{
  
  NSString *Filename =[NSString stringWithFormat:@"%@.m4a",self.CurrentFileName];
  
  
  // Set the audio file
  NSArray *pathComponents = [NSArray arrayWithObjects:
                             [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                             Filename,
                             nil];
  NSURL *outputFileURL = [NSURL fileURLWithPathComponents:pathComponents];
  
  // Setup audio session
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
  
  // Define the recorder setting
  NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc] init];
  
  [recordSetting setValue:[NSNumber numberWithInt:kAudioFormatMPEG4AAC] forKey:AVFormatIDKey];//kAudioFormatMPEG4AAC
  [recordSetting setValue:[NSNumber numberWithFloat:44100.0] forKey:AVSampleRateKey];
  [recordSetting setValue:[NSNumber numberWithInt: 2] forKey:AVNumberOfChannelsKey];
  
  // Initiate and prepare the recorder
  recorder = [[AVAudioRecorder alloc] initWithURL:outputFileURL settings:recordSetting error:NULL];
  recorder.delegate = self;
  recorder.meteringEnabled = YES;
  [recorder prepareToRecord];
  if (!recorder.recording) {
    [recorder record];
  }
}
- (void) stopRecodingAudioFile;
{
  [recorder stop];
  AVAudioSession *audioSession = [AVAudioSession sharedInstance];
  [audioSession setActive:NO error:nil];
  
}

- (BOOL)startRecording
{
  if (!_isRecording) {
    newSecond =0;
    _VideoFirstRecordedTime = CMTimeMakeWithSeconds(0,10);
    _videoSize = CGSizeMake(videoWidth, videoHeight);
    _cropRect  =CGRectMake(videoX, videoY, videoWidth, videoHeight);
    
    [self setUpWriter];
    _isRecording = (_videoWriter.status == AVAssetWriterStatusWriting);
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(writeVideoFrame)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self StartNewRecordingAudioFile];
  }
  return _isRecording;
}

- (void)stopRecordingWithCompletion:(VideoCompletionBlock)completionBlock;
{
  if (_isRecording) {
    _isRecording = NO;
    [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self completeRecordingSession:completionBlock];
  }
}

#pragma mark - private

-(void)setUpWriter
{
  _rgbColorSpace = CGColorSpaceCreateDeviceRGB();
  
  NSDictionary *bufferAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                     (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                                     (id)kCVPixelBufferWidthKey : @(_viewSize.width * _scale),
                                     (id)kCVPixelBufferHeightKey : @(_viewSize.height * _scale),
                                     (id)kCVPixelBufferBytesPerRowAlignmentKey : @(_viewSize.width * _scale * 4)
                                     };
  
  _outputBufferPool = NULL;
  CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)(bufferAttributes), &_outputBufferPool);
  
  
  NSError* error = nil;
  _videoWriter = [[AVAssetWriter alloc] initWithURL:self.videoURL ?: [self tempFileURL]
                                           fileType:AVFileTypeQuickTimeMovie
                                              error:&error];
  NSParameterAssert(_videoWriter);
  
  NSInteger pixelNumber = _viewSize.width * _viewSize.height * _scale;
  NSDictionary* videoCompression = @{AVVideoAverageBitRateKey: @(pixelNumber * 11.4)};
  
  NSDictionary* videoSettings = @{AVVideoCodecKey: AVVideoCodecH264,
                                  AVVideoWidthKey: [NSNumber numberWithInt:videoWidth*_scale],
                                  AVVideoHeightKey: [NSNumber numberWithInt:videoHeight*_scale],
                                  AVVideoCompressionPropertiesKey: videoCompression};
  
  _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
  NSParameterAssert(_videoWriterInput);
  
  _videoWriterInput.expectsMediaDataInRealTime = YES;
  _videoWriterInput.transform = [self videoTransformForDeviceOrientation];
  
  _avAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput sourcePixelBufferAttributes:nil];
  
  [_videoWriter addInput:_videoWriterInput];
  
  [_videoWriter startWriting];
  [_videoWriter startSessionAtSourceTime:CMTimeMake(0, 1000)];
}

- (CGAffineTransform)videoTransformForDeviceOrientation
{
  CGAffineTransform videoTransform;
  switch ([UIDevice currentDevice].orientation) {
    case UIDeviceOrientationLandscapeLeft:
      videoTransform = CGAffineTransformMakeRotation(-M_PI_2);
      break;
    case UIDeviceOrientationLandscapeRight:
      videoTransform = CGAffineTransformMakeRotation(M_PI_2);
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      videoTransform = CGAffineTransformMakeRotation(M_PI);
      break;
    default:
      videoTransform = CGAffineTransformIdentity;
  }
  return videoTransform;
}

- (NSURL*)tempFileURL
{
  
  _outputPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@.mp4",self.ContainFolder,self.CurrentFileName]];
  /*
   NSString *Filename = @"screenCapture.mp4";
   
   NSArray *pathComponents = [NSArray arrayWithObjects:
   [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
   Filename,
   nil];
   NSURL *outputFileURL = [NSURL fileURLWithPathComponents:pathComponents];
   NSString *outputPath =[outputFileURL absoluteString];
   */
  
  [self removeTempFilePath:_outputPath];
  return [NSURL fileURLWithPath:_outputPath];
}

- (void)removeTempFilePath:(NSString*)filePath
{
  NSFileManager* fileManager = [NSFileManager defaultManager];
  if ([fileManager fileExistsAtPath:filePath]) {
    NSError* error;
    if ([fileManager removeItemAtPath:filePath error:&error] == NO) {
      NSLog(@"Could not delete old recording:%@", [error localizedDescription]);
    }
  }
}

- (void)completeRecordingSession:(VideoCompletionBlock)completionBlock;
{
  dispatch_async(_render_queue, ^{
  //  dispatch_sync(_append_pixelBuffer_queue, ^{
      
      [_videoWriterInput markAsFinished];
    
      [_videoWriter finishWritingWithCompletionHandler:^{
        
        void (^completion)(void) = ^() {
         
          dispatch_async(dispatch_get_main_queue(), ^{
            
            [self stopRecodingAudioFile];
            [self cleanup];
            if(isRecordGifFormat)
            {
              NSString *movfilePath = [_documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4",self.CurrentFileName]];
              NSURL *video_url =[NSURL fileURLWithPath:movfilePath];
               NSLog(@"start generating GIF: %@", self.CurrentFileName);
              [NSGIF optimalGIFfromURL:video_url loopCount:0 completion:^(NSURL *GifURL)
               {
                 
                 NSLog(@"Finished generating GIF: %@", self.CurrentFileName);
                 NSError *error;
                 NSFileManager *fileManager = [NSFileManager defaultManager];
                 NSString *audiofilePath = [_documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a",self.CurrentFileName]];
                 BOOL success = [fileManager removeItemAtPath:audiofilePath error:&error];
                 NSString *oldVideofilePath = [_documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4",self.CurrentFileName]];
                 success = [fileManager removeItemAtPath:oldVideofilePath error:&error];
                 if (completionBlock) completionBlock();
               }];
              
            }
            else{
                [self mergeAndSave:completionBlock];
            }
            
            /*
             ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
             [library writeVideoAtPathToSavedPhotosAlbum:_videoWriter.outputURL completionBlock:^(NSURL *assetURL, NSError *error) {
             if (error) {
             NSLog(@"Error copying video to camera roll:%@", [error localizedDescription]);
             } else {
             // [self removeTempFilePath:_videoWriter.outputURL.path];
             completion();
             }
             }];
             */
            
            });
        };
          completion();
        
      }];
  //  });
  });
}
-(void)ResetVideoTimeFrame
{
    videoFrametime = CMTimeMake(0,30);
}
- (void)cleanup
{
  [self ResetVideoTimeFrame];

  self.firstTimeStamp = 0;
  
  self.avAdaptor = nil;
  self.videoWriterInput = nil;
  self.videoWriter = nil;
  self.outputBufferPoolAuxAttributes = nil;
  CGColorSpaceRelease(_rgbColorSpace);
 /* CVPixelBufferPoolRelease(_outputBufferPool); */
}
/*
 - (void)writeVideoFrame
 {
 // throttle the number of frames to prevent meltdown
 // technique gleaned from Brad Larson's answer here: http://stackoverflow.com/a/5956119
 if (dispatch_semaphore_wait(_frameRenderingSemaphore, DISPATCH_TIME_NOW) != 0) {
 return;
 }
 dispatch_async(_render_queue, ^{
 if (![_videoWriterInput isReadyForMoreMediaData]) return;
 
 if (!self.firstTimeStamp) {
 self.firstTimeStamp = _displayLink.timestamp;
 }
 CFTimeInterval elapsed = (_displayLink.timestamp - self.firstTimeStamp);
 CMTime time = CMTimeMakeWithSeconds(elapsed, 1000);
 
 CVPixelBufferRef pixelBuffer = NULL;
 CGContextRef bitmapContext = [self createPixelBufferAndBitmapContext:&pixelBuffer];
 
 if (self.delegate) {
 [self.delegate writeBackgroundFrameInContext:&bitmapContext];
 }
 // draw each window into the context (other windows include UIKeyboard, UIAlert)
 // FIX: UIKeyboard is currently only rendered correctly in portrait orientation
 dispatch_sync(dispatch_get_main_queue(), ^{
 UIGraphicsPushContext(bitmapContext); {
 for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
 [window drawViewHierarchyInRect:CGRectMake(0, 0, _viewSize.width, _viewSize.height) afterScreenUpdates:NO];
 }
 } UIGraphicsPopContext();
 });
 
 
 CGImageRef cgImageRef = CGBitmapContextCreateImage(bitmapContext);
 
 UIImage* CaptureImage = [UIImage imageWithCGImage:cgImageRef];
 
 CGImageRef croppedImage = CGImageCreateWithImageInRect(CaptureImage.CGImage, _cropRect);
 
 
 
 
 NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
 [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
 [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
 nil];
 
 size_t width =  CGImageGetWidth(croppedImage);
 size_t height = CGImageGetHeight(croppedImage);
 size_t bytesPerRow = CGImageGetBytesPerRow(croppedImage);
 
 CFDataRef  dataFromImageDataProvider = CGDataProviderCopyData(CGImageGetDataProvider(croppedImage));
 GLubyte  *imageData = (GLubyte *)CFDataGetBytePtr(dataFromImageDataProvider);
 
 CVPixelBufferCreateWithBytes(kCFAllocatorDefault,width,height,kCVPixelFormatType_32BGRA,imageData,bytesPerRow,NULL,NULL,(__bridge CFDictionaryRef)options,&pixelBuffer);
 
 CFRelease(dataFromImageDataProvider);
 // append pixelBuffer on a async dispatch_queue, the next frame is rendered whilst this one appends
 // must not overwhelm the queue with pixelBuffers, therefore:
 // check if _append_pixelBuffer_queue is ready
 // if it’s not ready, release pixelBuffer and bitmapContext
 if (dispatch_semaphore_wait(_pixelAppendSemaphore, DISPATCH_TIME_NOW) == 0) {
 dispatch_async(_append_pixelBuffer_queue, ^{
 
 
 CVPixelBufferRelease(pixelBuffer);
 BOOL success = [_avAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
 if (!success) {
 NSLog(@"Warning: Unable to write buffer to video");
 }
 CGContextRelease(bitmapContext);
 CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
 CVPixelBufferRelease(pixelBuffer);
 
 dispatch_semaphore_signal(_pixelAppendSemaphore);
 });
 } else {
 CGContextRelease(bitmapContext);
 CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
 CVPixelBufferRelease(pixelBuffer);
 }
 
 dispatch_semaphore_signal(_frameRenderingSemaphore);
 });
 }
 */

- (void)writeVideoFrame{
  dispatch_async(_render_queue, ^{
    if (![_videoWriterInput isReadyForMoreMediaData]){
      return;
    }
    
    BOOL isAppendPixel = false;
    @autoreleasepool {
      

    CVPixelBufferRef pixelBuffer = NULL;
    
    
    CVPixelBufferCreate(kCFAllocatorDefault, _viewSize.width, _viewSize.height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef _Nullable)(_outputBufferPoolAuxAttributes), &pixelBuffer);
    
    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    
    //creating bitmap context
    CGContextRef bitmapContext = NULL;
    bitmapContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer),
                                          CVPixelBufferGetWidth(pixelBuffer),
                                          CVPixelBufferGetHeight(pixelBuffer),
                                          8, CVPixelBufferGetBytesPerRow(pixelBuffer), _rgbColorSpace,
                                          kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
                                          );
    
   // CGContextScaleCTM(bitmapContext, _scale, _scale);
    CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, _viewSize.height);
    CGContextConcatCTM(bitmapContext, flipVertical);
  
    //CGContextRef bitmapContext = [self createPixelBufferAndBitmapContext:&pixelBuffer];
    

    dispatch_sync(dispatch_get_main_queue(), ^{
      UIGraphicsPushContext(bitmapContext); {
        [[UIApplication sharedApplication].keyWindow drawViewHierarchyInRect:CGRectMake(0, 0, _viewSize.width, _viewSize.height) afterScreenUpdates:NO];
      } UIGraphicsPopContext();
      
      
    });
    
    // start Crop imange from capture image
    CGImageRef cgImageRef = CGBitmapContextCreateImage(bitmapContext);
    CGImageRef croppedImage = CGImageCreateWithImageInRect(cgImageRef, _cropRect);
    
    // End Crop imange from capture image
    
    
    //start code for: Again resize pixel buffer and context ref as per cropped image size
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    
//    size_t width =  CGImageGetWidth(croppedImage);
//    size_t height = CGImageGetHeight(croppedImage);
//    size_t bytesPerRow = CGImageGetBytesPerRow(croppedImage);
//    
    CFDataRef  dataFromImageDataProvider = CGDataProviderCopyData(CGImageGetDataProvider(croppedImage));
    GLubyte  *imageData = (GLubyte *)CFDataGetBytePtr(dataFromImageDataProvider);
    
   if(bitmapContext != nil)
   {
      CGContextRelease(bitmapContext);   }
   if(pixelBuffer != nil )
   {
     CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
     pixelBuffer=nil;
    // CVPixelBufferRelease(pixelBuffer);
   }
    
    CVPixelBufferCreate(kCFAllocatorDefault, _videoSize.width, _videoSize.height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef _Nullable)(_outputBufferPoolAuxAttributes), &pixelBuffer);
    
    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    
    //creating bitmap context
  
    bitmapContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer),
                                          CVPixelBufferGetWidth(pixelBuffer),
                                          CVPixelBufferGetHeight(pixelBuffer),
                                          8, CVPixelBufferGetBytesPerRow(pixelBuffer), _rgbColorSpace,
                                          kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
                                          );
    
    flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, _videoSize.height);
    CGContextConcatCTM(bitmapContext, flipVertical);
    
    //end code for: Again resize pixel buffer and context ref as per cropped image size
    
    
    //Save Cropped image intp context ref
    CVPixelBufferCreateWithBytes(kCFAllocatorDefault, CGImageGetWidth(croppedImage),CGImageGetHeight(croppedImage),kCVPixelFormatType_32BGRA,imageData,CGImageGetBytesPerRow(croppedImage),NULL,NULL,(__bridge CFDictionaryRef)options,&pixelBuffer);
    
    
       /*
    
    // start code for save crop image in document folder with name of captured time
    
    UIImage* UIImagesData = [UIImage imageWithCGImage:croppedImage];
    NSData *pngData = UIImagePNGRepresentation(UIImagesData);
    
    
    NSString *stringFromDate = [_formatter stringFromDate:[NSDate date]] ;
    NSInteger integerDate = [stringFromDate integerValue];
    
    NSString *filePath = [_documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%dimage.png",integerDate]]; //Add the file name
    [pngData writeToFile:filePath atomically:YES]; //Write the file
    
     // end  code for save crop image in document folder with name of captured time
    
    
    */
    
     if (dispatch_semaphore_wait(_pixelAppendSemaphore, DISPATCH_TIME_NOW) == 0) {
       [_avAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:videoFrametime];
       videoFrametime.value +=1;
       isAppendPixel = true;
     }
      CGContextRelease(bitmapContext);
      CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
      CVPixelBufferRelease(pixelBuffer);
      
      CGImageRelease(cgImageRef);
      CGImageRelease(croppedImage);
      CFRelease(dataFromImageDataProvider);
    }
    
    if(isAppendPixel)
    {
      dispatch_semaphore_signal(_pixelAppendSemaphore);
    }
   
    dispatch_semaphore_signal(_frameRenderingSemaphore);
  });
}
- (CGContextRef)createNewPixelBufferAndBitmapContext:(CVPixelBufferRef *)pixelBuffer
{
  
  CVPixelBufferCreate(kCFAllocatorDefault, _viewSize.width, _viewSize.height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef _Nullable)(_outputBufferPoolAuxAttributes), &pixelBuffer);
  
  CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
  
  //creating bitmap context
  CGContextRef bitmapContext = NULL;
  bitmapContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer),
                                        CVPixelBufferGetWidth(pixelBuffer),
                                        CVPixelBufferGetHeight(pixelBuffer),
                                        8, CVPixelBufferGetBytesPerRow(pixelBuffer), _rgbColorSpace,
                                        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
                                        );
  
  CGContextScaleCTM(bitmapContext, _scale, _scale);
  CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, _viewSize.height);
  CGContextConcatCTM(bitmapContext, flipVertical);
  return bitmapContext;
  
}
- (CGContextRef)createPixelBufferAndBitmapContext:(CVPixelBufferRef *)pixelBuffer
{
  CVPixelBufferPoolCreatePixelBuffer(NULL, _outputBufferPool, pixelBuffer);
  CVPixelBufferLockBaseAddress(*pixelBuffer, 0);
  
  CGContextRef bitmapContext = NULL;
  bitmapContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(*pixelBuffer),
                                        CVPixelBufferGetWidth(*pixelBuffer),
                                        CVPixelBufferGetHeight(*pixelBuffer),
                                        8, CVPixelBufferGetBytesPerRow(*pixelBuffer), _rgbColorSpace,
                                        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
                                        );
  CGContextScaleCTM(bitmapContext, _scale, _scale);
  CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, _viewSize.height);
  CGContextConcatCTM(bitmapContext, flipVertical);
  return bitmapContext;
}

-(void)mergeAndSave:(VideoCompletionBlock)completionBlock
{
  //Create AVMutableComposition Object which will hold our multiple AVMutableCompositionTrack or we can say it will hold our video and audio files.
  AVMutableComposition* mixComposition = [AVMutableComposition composition];
  
  //Now first load your audio file using AVURLAsset. Make sure you give the correct path of your videos.
  // NSURL *audio_url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"screenCapture" ofType:@"m4a"]];
  
  if(isRecordSound & !isRecordGifFormat)
  {
    
    /*NSArray *pathComponentsForAudio = [NSArray arrayWithObjects:
                                       [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                                       [NSString stringWithFormat:@"%@.m4a",self.CurrentFileName],
                                       nil];
    NSURL *audio_url = [NSURL fileURLWithPathComponents:pathComponentsForAudio]; */
    
    
    NSString *m4afilePath = [_documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a",self.CurrentFileName]];
    NSURL *audio_url =[NSURL fileURLWithPath:m4afilePath];
    
    audioAsset = [[AVURLAsset alloc]initWithURL:audio_url options:nil];
    CMTimeRange audio_timeRange = CMTimeRangeMake(kCMTimeZero, audioAsset.duration);
    float audioDurationSeconds = CMTimeGetSeconds(audioAsset.duration);
    if(audioDurationSeconds > 0.0)
    {
      //Now we are creating the first AVMutableCompositionTrack containing our audio and add it to our AVMutableComposition object.
      AVMutableCompositionTrack *b_compositionAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
      [b_compositionAudioTrack insertTimeRange:audio_timeRange ofTrack:[[audioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0] atTime:kCMTimeZero error:nil];
    }
    
  }
  
  //Now we will load video file.
  //  NSURL *video_url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"screenCapture" ofType:@"mp4"]];
  
 /* NSArray *pathComponentsForVideo = [NSArray arrayWithObjects:
                                     [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                                     [NSString stringWithFormat:@"%@.mp4",self.CurrentFileName],
                                     nil];
  
  NSURL *video_url = [NSURL fileURLWithPathComponents:pathComponentsForVideo]; */
  
  NSString *mp4filePath = [_documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4",self.CurrentFileName]];
  NSURL *video_url =[NSURL fileURLWithPath:mp4filePath];
  
  videoAsset = [[AVURLAsset alloc]initWithURL:video_url options:nil];
  CMTimeRange video_timeRange = CMTimeRangeMake(kCMTimeZero,videoAsset.duration);
  
  float videoDurationSeconds = CMTimeGetSeconds(videoAsset.duration);
  if(videoDurationSeconds > 0.0)
  {
    //Now we are creating the second AVMutableCompositionTrack containing our video and add it to our AVMutableComposition object.
    AVMutableCompositionTrack *a_compositionVideoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    [a_compositionVideoTrack insertTimeRange:video_timeRange ofTrack:[[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] atTime:kCMTimeZero error:nil];
  }
  
  //decide the path where you want to store the final video created with audio and video merge.
  NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *docsDir = [dirPaths objectAtIndex:0];
  NSString *outputFilePath = [docsDir stringByAppendingPathComponent:[NSString stringWithFormat:[NSString stringWithFormat:@"%@.mov",self.CurrentFileName ]]];
  NSURL *outputFileUrl = [NSURL fileURLWithPath:outputFilePath];
  if ([[NSFileManager defaultManager] fileExistsAtPath:outputFilePath])
    [[NSFileManager defaultManager] removeItemAtPath:outputFilePath error:nil];
  
  //Now create an AVAssetExportSession object that will save your final video at specified path.
  AVAssetExportSession* _assetExport = [[AVAssetExportSession alloc] initWithAsset:mixComposition presetName:AVAssetExportPresetHighestQuality];
  _assetExport.outputFileType = @"com.apple.quicktime-movie";
  _assetExport.outputURL = outputFileUrl;
  
  [_assetExport exportAsynchronouslyWithCompletionHandler:
   ^(void ) {
     dispatch_async(dispatch_get_main_queue(), ^{
       
         NSError *error;
         NSFileManager *fileManager = [NSFileManager defaultManager];
       
        NSString *audiofilePath = [_documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a",self.CurrentFileName]];
         BOOL success = [fileManager removeItemAtPath:audiofilePath error:&error];
         NSString *oldVideofilePath = [_documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4",self.CurrentFileName]];
         success = [fileManager removeItemAtPath:oldVideofilePath error:&error];
       
        
         if (completionBlock) completionBlock();
       
      
     });
   }
   ];
  
}

@end
