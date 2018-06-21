//
//  XYQMovieObject.h
//  FFmpeg_Test
//
//  Created by mac on 17/10/21.
//  Copyright © 2016年 Gwl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#import "DecodeH264Data_YUV.h"
#import "SDL.h"


typedef struct PacketQueue {
    AVPacketList *first_pkt, *last_pkt;
    int nb_packets;
    int size;
    SDL_mutex *mutex;
    SDL_cond *cond;
} PacketQueue;

@protocol updateDecodedH264FrameDelegate <NSObject>

@optional
- (void)updateDecodedH264FrameData: (H264YUV_Frame*)yuvFrame;
- (void)updateDecodedPchDdata:(uint8_t)data withSize:(int)size;
- (void)updateActivityView:(double)diff;
@end


@interface XYQMovieObject : NSObject

/* 解码后的UIImage */
@property (nonatomic, strong, readonly) UIImage *currentImage;

/* 视频的frame高度 */
@property (nonatomic, assign, readonly) int sourceWidth, sourceHeight;

/* 输出图像大小。默认设置为源大小。 */
@property (nonatomic,assign) int outputWidth, outputHeight;

/* 视频的长度，秒为单位 */
@property (nonatomic, assign, readonly) double duration;

/* 视频的当前秒数 */
@property (nonatomic, assign, readonly) double currentTime;

/* 视频的帧率 */
@property (nonatomic, assign, readonly) double fps;

/* 视频路径。 */
- (instancetype)initWithVideo:(NSString *)moviePath;
- (void)seekTime:(double)seconds;
- (void)play;
- (void)playAndPauseAction:(int)tag;
- (void)playNext;
- (void)backgroundAction;
- (void)stopPlay;

@property (nonatomic,assign)id<updateDecodedH264FrameDelegate> updateDelegate;


@end
