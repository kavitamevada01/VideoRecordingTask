//
//  ScreenRecordingRCTModule.m
//  React
//
//  Created by Piyush on 29/09/16.
//  Copyright © 2016 Facebook. All rights reserved.
//

#import "ScreenRecordingRCTModule.h"
#import "ASScreenRecorder.h"

@interface ScreenRecordingRCTModule()

@property (nonatomic, copy) NSDictionary *VideoSetting;
@end

@implementation ScreenRecordingRCTModule

RCT_EXPORT_MODULE()
@synthesize bridge = _bridge;
RCT_EXPORT_METHOD(StartScreenRecordingInVideoFormat:(NSDictionary *)VideoSetting  callback:(RCTResponseSenderBlock)callback)
{
  ASScreenRecorder *recorder = [ASScreenRecorder sharedInstance];

  recorder.CurrentFileName =[NSString stringWithFormat:@"%@",[VideoSetting objectForKey:@"VideoFileName"]];
  recorder.ContainFolder =@"Documents";
  
  recorder.videoWidth = [[VideoSetting objectForKey:@"VideoWidth"] integerValue];
  recorder.videoHeight = [[VideoSetting objectForKey:@"VideoHeight"] integerValue];
  recorder.videoX = [[VideoSetting objectForKey:@"VideoX"] integerValue];
  recorder.videoY = [[VideoSetting objectForKey:@"VideoY"] integerValue];
  recorder.isRecordSound = [[VideoSetting objectForKey:@"isRecordSound"] integerValue];
  recorder.isRecordGifFormat = [[VideoSetting objectForKey:@"isRecordGifFormat"] integerValue];
  recorder.screenRecordingRCTModule = self;
  _VideoSetting = VideoSetting;
  if (!recorder.isRecording)
  {
    [recorder startRecording];
    NSLog(@"Start recording");
  }
  
  NSArray *ReturnParam = [NSArray arrayWithObjects:@"Success",@"Start ScreenRecording In Video Format",nil];
  NSArray *ReturnError = [NSArray arrayWithObjects:@"No Error",nil];
  callback(@[ReturnError, ReturnParam]);
  NSLog(@"Local filePlaying start  ");
  
}
-(void)VideoRecordingError
{
//  [_bridge.eventDispatcher sendDeviceEventWithName:@"VideoRecordingCompleteListner"
//                                              body:@{@"VideoFile":@"",@"status":@"0",@"Message":@"Video Recording has error" }];
}
-(void)VideoRecordingComplete
{
  ASScreenRecorder *recorder = [ASScreenRecorder sharedInstance];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
  NSString *videoFilePath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mov",recorder.CurrentFileName]];
  NSString *gifFilePath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gif",recorder.CurrentFileName]];
  if([[_VideoSetting objectForKey:@"isRecordGifFormat"] boolValue])
  {
    [_bridge.eventDispatcher sendDeviceEventWithName:@"VideoRecordingCompleteListner"
                                              body:@{@"VideoFile":gifFilePath,@"status":@"1",@"Message":@"Video Recording Done" }];
  }else{
    [_bridge.eventDispatcher sendDeviceEventWithName:@"VideoRecordingCompleteListner"
                                                body:@{@"VideoFile":videoFilePath,@"status":@"1",@"Message":@"Video Recording Done" }];
  }
  
  
}
RCT_EXPORT_METHOD(StopScreenRecordingInVideoFormat:(RCTResponseSenderBlock)callback)
{
  __block ASScreenRecorder *recorder = [ASScreenRecorder sharedInstance];
  if (recorder.isRecording) {
    
    [recorder stopRecordingWithCompletion:^{
      NSLog(@"Finished recording");
      
      
      
      NSFileManager *fileManager = [NSFileManager defaultManager];
      NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
      NSString *videoFilePath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mov",recorder.CurrentFileName]];
      NSString *gifFilePath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gif",recorder.CurrentFileName]];
      
      NSLog(@"VideoRecordingComplete");
      NSString *FilePath;
      NSString *Message;
      if([[_VideoSetting objectForKey:@"isRecordGifFormat"] boolValue])
      {
        FilePath  = [NSString stringWithFormat:gifFilePath];
        Message=@"Gif Recording Done";
      
      }else{
        FilePath  = [NSString stringWithFormat:videoFilePath];
        Message=@"Video Recording Done";

      }
  
      
      
      NSLog(@"Return Path:",FilePath);
      
      NSArray *ReturnParam = [NSArray arrayWithObjects:@"Success",FilePath,Message,nil];
      NSArray *ReturnError = [NSArray arrayWithObjects:@"No Error",nil];
      callback(@[ReturnError, ReturnParam]);
      
      
    
    }];
   
  }

}

@end
