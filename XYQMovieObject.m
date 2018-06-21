//
//  XYQMovieObject.m
//  FFmpeg_Test
//
//  Created by mac on 17/10/21.
//  Copyright © 2016年 Gwl. All rights reserved.
//

#import "XYQMovieObject.h"
#import "swresample.h"
#import "SDL_thread.h"
#import "avstring.h"
#import "time.h"
#import "NetacFileOption.h"
#import "ProgressHUD.h"


#define MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio
#define SDL_AUDIO_BUFFER_SIZE 1024 * 2

#define FF_ALLOC_EVENT   (SDL_USEREVENT)
#define FF_REFRESH_EVENT (SDL_USEREVENT + 1)
#define FF_QUIT_EVENT (SDL_USEREVENT + 2)
#define FF_SEEK_EVENT   (SDL_USEREVENT + 3)
#define FF_PAUSE_EVENT  (SDL_USEREVENT + 4)

#define MAX_AUDIOQ_SIZE ( 16 * 1024)
#define MAX_VIDEOQ_SIZE (5 * 256 * 1024 * 5)

#define AV_SYNC_THRESHOLD 0.01
#define AV_NOSYNC_THRESHOLD 10.0
#define SAMPLE_CORRECTION_PERCENT_MAX 10
#define AUDIO_DIFF_AVG_NB 10
#define VIDEO_PICTURE_QUEUE_SIZE 1

#define DEFAULT_AV_SYNC_TYPE AV_SYNC_AUDIO_MASTER

@interface XYQMovieObject()
@property (nonatomic, copy) NSString *cruutenPath;
@end

@implementation XYQMovieObject
{
    double              currentTime;
    double              duration;
    const char *        filePh;
    int                 pauseTag;
}

typedef struct VideoPicture {
    H264YUV_Frame    yuvFrame;
    int width, height;
    int allocated;
    double pts;
} VideoPicture;

enum {
    AV_SYNC_AUDIO_MASTER,
    AV_SYNC_VIDEO_MASTER,
    AV_SYNC_EXTERNAL_MASTER,
};

typedef struct VideoState {
    char filename[1024];//大小为1024的char数组
    AVFormatContext *ic;
    int videoStream, audioStream;
    AVStream *audio_st;
    AVFrame *audio_frame;
    PacketQueue audioq;
    unsigned int audio_buf_size;
    unsigned int audio_buf_index;
    AVPacket audio_pkt;
    uint8_t *audio_pkt_data;
    int audio_pkt_size;
    uint8_t *audio_buf;
    DECLARE_ALIGNED(16,uint8_t,audio_buf2) [MAX_AUDIO_FRAME_SIZE * 4];
    enum AVSampleFormat audio_src_fmt;
    enum AVSampleFormat audio_tgt_fmt;
    int audio_src_channels;
    int audio_tgt_channels;
    int64_t audio_src_channel_layout;
    int64_t audio_tgt_channel_layout;
    int audio_src_freq;
    int audio_tgt_freq;
    struct SwrContext *swr_ctx;
    SDL_Thread *parse_tid;
    int quit;
    
    ///
    double audio_diff_cum;
    double audio_diff_avg_coef;
    double audio_diff_threshold;
    int audio_diff_avg_count;
    double frame_timer;
    double frame_last_pts;
    double frame_last_delay;
    double video_clock;
    double video_current_pts;
    int64_t video_current_pts_time;
    AVStream *video_st;
    PacketQueue videoq;
    SDL_Thread *video_tid;
    struct SwsContext *sws_ctx;
    double audio_clock;
    int av_sync_type;
    SDL_mutex *pictq_mutex;
    SDL_cond *pictq_cond;
    int pictq_size, pictq_rindex, pictq_windex ;
    VideoPicture pictq[VIDEO_PICTURE_QUEUE_SIZE];
    
    int seek_req;
    int seek_flags;
    int64_t seek_pos;
    int paused;
    int last_paused;
    int read_pause_return;
    const char *        filePh;
    
} VideoState;
NetacFileOption *fileOption;
AVPacket current_pkt;
AVPacket flush_pkt;
VideoState *global_video_state;
static id object ;
int flag;
double              second;
SDL_TimerID timer;
uint64_t global_video_pkt_pts = AV_NOPTS_VALUE;
int backgroundTag;
int stopFlag;

- (instancetype)initWithVideo:(NSString *)moviePath {
    
    if (!(self=[super init])) return nil;
    if ([self initializeResources:[moviePath UTF8String]]) {
        self.cruutenPath = [moviePath copy];
        return self;
    } else {
        return nil;
    }
}
- (BOOL)initializeResources:(const char *)filePath {
    
    filePh = filePath;
    object = self;
    return YES;
}
int stream_component_close(VideoState *vs, int stream_index)
{
    AVFormatContext *pFormatCtx = vs->ic;
    
    if (stream_index < 0 || stream_index >= pFormatCtx->nb_streams)
    {
        return - 1;
    }
    
    pFormatCtx->streams[stream_index]->discard = AVDISCARD_ALL;
    
    if (vs->sws_ctx)
    {
        sws_freeContext(vs->sws_ctx);
        vs->sws_ctx = NULL;
    }
    
    if (stream_index == vs->videoStream && vs->video_st)
    {
        avcodec_close(vs->video_st->codec);
        vs->video_st = NULL;
        vs->videoStream = -1;
    }
    else if (stream_index == vs->audioStream && vs->audio_st)
    {
        avcodec_close(vs->audio_st->codec);
        vs->audio_st = NULL;
        vs->audioStream = -1;
    }
    
    return 0;
}
void packet_queue_destroy(PacketQueue *q)
{
    packet_queue_flush(q);
    SDL_DestroyMutex(q->mutex);
    SDL_DestroyCond(q->cond);
}

- (void)playNext {

    VideoState *is = global_video_state;
    is->quit = 1;
    SDL_CloseAudio();
    SDL_RemoveTimer(timer);
    
    packet_queue_destroy(&is->videoq);
    packet_queue_destroy(&is->audioq);
    stream_component_close(is, is->videoStream);
    stream_component_close(is, is->audioStream);
    avformat_close_input(&is->ic);
    avformat_free_context(is->ic);
    memset(is->audio_buf2, 0, 0);
    memset(is->audio_pkt_data, 0, 0);
    memset(is->audio_buf, 0, 0);
    memset(&is->audio_pkt, 0, 0);
    memset(&is->videoq, 0, 0);
    memset(&is->audioq, 0, 0);
    
    av_free(is->audio_st);
    av_free(is->video_st);
    is->video_st = NULL;
    is->audio_st = NULL;
    is->audio_buf_size = 0;
    is->pictq_rindex = 0;
    is->pictq_size = 0;
    is->pictq_windex = 0;
    avformat_network_deinit();
    SDL_DestroyMutex(is->pictq_mutex);
    SDL_DestroyCond(is->pictq_cond);
    SDL_DetachThread(is->parse_tid);
    SDL_DetachThread(is->video_tid);
    is->video_tid = NULL;
    is->parse_tid = NULL;
    NSLog(@"next _____________++++++++++++++__________");
    
    is = (VideoState *) av_mallocz(sizeof(VideoState));
    global_video_state = is;
    
    SDL_SetMainReady();
    if (SDL_Init(SDL_INIT_AUDIO)) {
        fprintf(stderr, "Could not initialize SDL - %s\n", SDL_GetError());
        exit(1);
    }
    //指向const的指针不能被赋给指向非const的指针,所以应该用strcpy，也就是另开一块内存，把字符一个个复制过去
    av_strlcpy(is->filename, filePh, sizeof(is->filename));
    
    //初始化互斥变量,条件变量
    if (!is->pictq_mutex) {
        is->pictq_mutex = SDL_CreateMutex();
        is->pictq_cond = SDL_CreateCond();
    }
    
    schedule_refresh(is, 40);
    
    is->av_sync_type = DEFAULT_AV_SYNC_TYPE;
    
    const char *name = "ooo" ;
    is->parse_tid = SDL_CreateThread(decode_thread, name, is);
    
}

- (void)stopPlay {
    stopFlag = 1;
    VideoState *is = global_video_state;
    is->quit = 1;
    SDL_CloseAudio();
    SDL_RemoveTimer(timer);
   
    packet_queue_destroy(&is->videoq);
    packet_queue_destroy(&is->audioq);
    stream_component_close(is, is->videoStream);
    stream_component_close(is, is->audioStream);
    avformat_close_input(&is->ic);
    avformat_free_context(is->ic);
    memset(is->audio_buf2, 0, 0);
    memset(is->audio_pkt_data, 0, 0);
    memset(is->audio_buf, 0, 0);
    memset(&is->audio_pkt, 0, 0);
    memset(&is->videoq, 0, 0);
    memset(&is->audioq, 0, 0);

    av_free(is->audio_st);
    av_free(is->video_st);
    is->video_st = NULL;
    is->audio_st = NULL;
    is->audio_buf_size = 0;
    is->pictq_rindex = 0;
    is->pictq_size = 0;
    is->pictq_windex = 0;
    avformat_network_deinit();
    SDL_DestroyMutex(is->pictq_mutex);
    SDL_DestroyCond(is->pictq_cond);
    SDL_DetachThread(is->parse_tid);
    SDL_DetachThread(is->video_tid);
    is->video_tid = NULL;
    is->parse_tid = NULL;
    
    SDL_Quit();
    
    NSLog(@"__________stop__________");
}

- (void)play {
    SDL_Event event;
    VideoState *is;
    is = (VideoState *) av_mallocz(sizeof(VideoState));
    stopFlag = 0;
    av_register_all();
    SDL_SetMainReady();
    if (SDL_Init(SDL_INIT_AUDIO)) {
        fprintf(stderr, "Could not initialize SDL - %s\n", SDL_GetError());
        exit(1);
    }
    //指向const的指针不能被赋给指向非const的指针,所以应该用strcpy，也就是另开一块内存，把字符一个个复制过去
    av_strlcpy(is->filename, filePh, sizeof(is->filename));
    is->filePh = filePh;
    //初始化互斥变量,条件变量
    if (!is->pictq_mutex) {
        is->pictq_mutex = SDL_CreateMutex();
        is->pictq_cond = SDL_CreateCond();
    }
    
    
    schedule_refresh(is, 40);
    
    is->av_sync_type = DEFAULT_AV_SYNC_TYPE;
    
    const char *name = "ppp" ;
    is->parse_tid = SDL_CreateThread(decode_thread, name, is);
    if (!is->parse_tid) {
        av_free(is);
    }
    
    for (;;) {
        if (stopFlag == 1) {
            SDL_WaitEventTimeout(&event, 0);
            return;
        }
        double incr, pos;
        SDL_WaitEvent(&event);
        switch (event.type) {
            case FF_SEEK_EVENT:
                incr = second;
                if (global_video_state) {
                    pos = get_master_clock(global_video_state);
                    pos += incr;
                    stream_seek(global_video_state, (int64_t)(pos * AV_TIME_BASE), incr);
                }
                break;
            case FF_QUIT_EVENT:
            case SDL_QUIT:
                global_video_state->quit = 1;
                SDL_CondSignal(global_video_state->audioq.cond);
                SDL_CondSignal(global_video_state->videoq.cond);
                SDL_Quit();
            
                break;
            case FF_PAUSE_EVENT:
                toggle_pause();
                break;
            case FF_ALLOC_EVENT:
                alloc_picture(event.user.data1);
                break;
            case FF_REFRESH_EVENT:
                video_refresh_timer(event.user.data1);
                break;
            default:
                break;
        }
    }

}
NFIL fp;
NetacFileOption *fileOption;
int read_buffer(void *opaque, uint8_t *buf, int buf_size){

    unsigned int btr = buf_size;
    N_RESULT result = n_read(&fp, &buf, buf_size, &btr);
    if (result != N_OK) {
        [ProgressHUD show:@"读取文件失败!"];
        return -1;
    }else{
        if(sizeof(buf)>0){
            return sizeof(buf);
        }else{
            return -1;
        }
    }

    //buf = (uint8_t*)fileBuffer;
    
    
}
static int decode_thread(void *arg) {
    fileOption = [NetacFileOption sharedNetacFileOpt];
    
    n_open(&fp, [fileOption gbk_encode:@"/3.wmv"], FA_READ | FA_OPEN_EXISTING);
    
    VideoState *is = (VideoState *) arg;

    AVFormatContext *ic = NULL;
    ic = avformat_alloc_context();
    
    //unsigned char * iobuffer=(unsigned char *)av_malloc(32768);
    
   unsigned char *aviobuffer=(unsigned char *)av_malloc(1024);
    
    
  
    AVIOContext *avio = avio_alloc_context(aviobuffer, 1024,0,NULL,read_buffer,NULL,NULL);

    ic->pb=avio;
    
    //avformat_open_input(&ic, "nothing", NULL, NULL);

    //AVFormatContext *ic = NULL;
    AVPacket pkt1, *packet = &pkt1;
    int ret, i, audio_index = -1, video_index = -1;
    int64_t p = 0;
    is->audioStream = -1;
    is->videoStream = -1;

    global_video_state = is;
//    if (avformat_open_input(&ic, is->filename, NULL, NULL) != 0) {
//        return -1;
//    }
    is->ic = ic;

    //打开流
    if (avformat_open_input(&ic, NULL, NULL, NULL) != 0) {
        [ProgressHUD show:@"open_failed"];
        return -1;
    }
    if (avformat_find_stream_info(ic, NULL) < 0) {
        [ProgressHUD show:@"find_failed"];
        return -1;
    }

    av_dump_format(ic, 0, is->filename, 0);
    for (i = 0; i < ic->nb_streams; i++) {
        if (ic->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO
            && audio_index < 0) {
            audio_index = i;
        }
        if (ic->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO
            && video_index < 0) {
            video_index = i;
        }
    }
    if (audio_index >= 0) {
        stream_component_open(is, audio_index);
    }
    if (video_index >= 0) {
        stream_component_open(is, video_index);
    }
    
    if (is->videoStream < 0 || is->audioStream < 0) {
        fprintf(stderr, "%s: could not open codecs\n", is->filename);
        goto fail;
    }
    // main decode loop
    
    av_init_packet(&flush_pkt);
    flush_pkt.data = (unsigned char *) "FLUSH";
    
    for (;;) {
        if (stopFlag == 1) {
            packet_queue_flush(&is->audioq);
            packet_queue_flush(&is->videoq);
            return -1;
        }
        if (is->quit)
            break;
        
        if (is->paused != is->last_paused) {
            is->last_paused = is->paused;
            if (is->paused)
                is->read_pause_return = av_read_pause(ic);
            else
                av_read_play(ic);
        }
        
        
        if (is->seek_req) {
            int stream_index= -1;
            int64_t seek_target = is->seek_pos;
            
            if (is->videoStream >= 0) {
                stream_index = is->videoStream;
            } else if (is->audioStream >= 0) {
                stream_index = is->audioStream;
            }
            
            if (stream_index >= 0){
                seek_target= av_rescale_q(seek_target, AV_TIME_BASE_Q, ic->streams[stream_index]->time_base);
            }
            if (av_seek_frame(is->ic, stream_index, seek_target, is->seek_flags) < 0) {
                fprintf(stderr, "%s: error while seeking\n", is->ic->filename);
            } else {
                if (is->audioStream >= 0) {
                    
                    packet_queue_flush(&is->audioq);
                    packet_queue_put(&is->audioq, &flush_pkt);
                }
                if (is->videoStream >= 0) {
                    packet_queue_flush(&is->videoq);
                    packet_queue_put(&is->videoq, &flush_pkt);
                }
            }
            
            is->seek_req = 0;
            flag = 1;
            p = 0;
        }
        
        
        if (is->audioq.size > MAX_AUDIOQ_SIZE || is->videoq.size > MAX_VIDEOQ_SIZE) {
            SDL_Delay(30);
            continue;
        }
        
        ret = av_read_frame(is->ic, packet);
        if (ret < 0) {
            if (ret == AVERROR_EOF || url_feof(is->ic->pb)) {
                break;
            }
            if (is->ic->pb && is->ic->pb->error) {
                break;
            }
            continue;
        }
        
        if (packet->stream_index == is->audioStream) {
//            NSLog(@"audio put %f", packet->pts *av_q2d(is->audio_st->time_base));
            PacketQueue *q = &is->audioq;
            AVPacketList *pkt1 = q->last_pkt;
            if (pkt1 != nil && pkt1->pkt.data == flush_pkt.data) {
                p = packet->pts;
//                NSLog(@"audio put111 %f", packet->pts *av_q2d(is->audio_st->time_base));
            }
            packet_queue_put(&is->audioq, packet);
         
        }else if (packet->stream_index == is->videoStream) {
//            NSLog(@"video put %f", packet->pts *av_q2d(is->video_st->time_base));
            
            PacketQueue *q = &is->audioq;
            AVPacketList *pkt1 = q->first_pkt;
            if (current_pkt.pts + second < 2) {
                packet_queue_put(&is->videoq, packet);
                continue;
            }
            if (pkt1 != nil && pkt1->pkt.data == flush_pkt.data) {
                if (p *av_q2d(is->audio_st->time_base) - packet->pts*av_q2d(is->video_st->time_base) > 0.5) {
                    
                    packet_queue_flush(&is->videoq);
                    packet_queue_put(&is->videoq, &flush_pkt);
                    NSLog(@"1111");
                }else {
                    if (flag == 1) {
                        if (packet->flags == AV_PKT_FLAG_KEY ) {
                            packet_queue_put(&is->videoq, packet);
                            flag = 0;
                        }
                    }else {
                        packet_queue_put(&is->videoq, packet);
                    }
                    
                }
                //NSLog(@"ptk seek ++++ %f", packet->pts *av_q2d(is->video_st->time_base));
            }else {
                //NSLog(@"ptk -- %f", packet->pts *av_q2d(is->video_st->time_base));
                packet_queue_put(&is->videoq, packet);
            }
            
        } else {
            av_packet_unref(packet);//释放指向packet的指针
        }
    }

    while (!is->quit) {
        SDL_Delay(100);
    }
    
fail: {
    SDL_Event event;
    event.type = FF_QUIT_EVENT;
    event.user.data1 = is;
    SDL_PushEvent(&event);
}
    return 0;
}

void toggle_pause() {
    
    if (global_video_state->paused != 1) {
        SDL_PauseAudio(1);
        global_video_state->paused = 1;
    }else {
        SDL_PauseAudio(0);
        global_video_state->paused = 0;
    }
}

void stream_seek(VideoState *is, int64_t pos, int rel) {
    
    if (!is->seek_req) {
        is->seek_pos = pos;
        is->seek_flags = rel < 0 ? AVSEEK_FLAG_BACKWARD : 0;
        is->seek_req = 1;
    }
}

void alloc_picture(void *userdata) {
    VideoState *is = (VideoState *)userdata;
    VideoPicture *vp;
    
    vp = &is->pictq[is->pictq_windex];
    if (vp->yuvFrame.luma.length) {
        // We already have one make another, bigger/smaller.
        free(vp->yuvFrame.luma.dataBuffer);
        free(vp->yuvFrame.chromaB.dataBuffer);
        free(vp->yuvFrame.chromaR.dataBuffer);
    }
    // Allocate a place to put our YUV image on that screen.
    
    memset(&vp->yuvFrame, 0, sizeof(H264YUV_Frame));
    vp->width = is->video_st->codec->width;
    vp->height = is->video_st->codec->height;
    
    SDL_LockMutex(is->pictq_mutex);
    vp->allocated = 1;
    SDL_CondSignal(is->pictq_cond);
    SDL_UnlockMutex(is->pictq_mutex);
    
}
- (void)playAndPauseAction:(int)tag {
    SDL_Event event;
    // We have to do it in the main thread.
    event.type = FF_PAUSE_EVENT;
    pauseTag = tag;
    SDL_PushEvent(&event);
}

- (void)seekTime:(double)seconds {
    
    SDL_Event event;
    // We have to do it in the main thread.
    event.type = FF_SEEK_EVENT;
    second = seconds;
    SDL_PushEvent(&event);
    
}
- (void)updateActivityViewAtion:(double)diff {
    [self.updateDelegate updateActivityView:diff];
}
- (void)backgroundAction {
    global_video_state->frame_timer = (double)av_gettime() / 1000000.0;
}

static void schedule_refresh(VideoState *is, int delay) {
    
    timer = SDL_AddTimer(delay, sdl_refresh_timer_cb, is);
    
}
static Uint32 sdl_refresh_timer_cb(Uint32 interval, void *opaque) {
    
    SDL_Event event;
    
    event.type = FF_REFRESH_EVENT;
    
    event.user.data1 = opaque;
    
    SDL_PushEvent(&event);
    
    return 0;
    
}
void video_refresh_timer(void *userdata) {
    VideoState *is = (VideoState *)userdata;
    VideoPicture *vp;
    double actual_delay, delay, sync_threshold, ref_clock, diff;
    
    if (is->video_st) {
        if (is->pictq_size == 0) {
            schedule_refresh(is, 1);
        } else {
            //测试什么时候进入的这个条件?视频队列有数据?
            
            //视频队列-序列号-视频帧
            vp = &is->pictq[is->pictq_rindex];
            current_pkt.pts = vp->pts;
            is->video_current_pts = vp->pts;
            is->video_current_pts_time = av_gettime();//当前pts的毫秒值
            
            delay = vp->pts - is->frame_last_pts; // 显示间隔
            if (delay <= 0 || delay >= 1.0) {
                // delay 不正确,使用上一个正确的delay.
                delay = is->frame_last_delay;
            }
            // Save for next time.
            is->frame_last_delay = delay;
            is->frame_last_pts = vp->pts;
            
//            NSLog(@"%f,%f ++++++ %f, %f",vp->pts, is->video_clock, is->audio_clock,get_audio_clock(is));
//            NSLog(@"*****************************/////////////////    %f", is->video_clock - get_audio_clock(is));
            
            // Update delay to sync to audio if not master source.同步到音频,音频为主
            if (is->av_sync_type != AV_SYNC_VIDEO_MASTER) {
                ref_clock = get_master_clock(is);
                diff = is->video_clock - ref_clock;
                //NSLog(@"vp %f", vp->pts);
                // Skip or repeat the frame. Take delay into account FFPlay still doesn't "know if this is the best guess.".
                sync_threshold = (delay > AV_SYNC_THRESHOLD) ? delay : AV_SYNC_THRESHOLD;
                if (fabs(diff) < AV_NOSYNC_THRESHOLD) {
                    if (diff <= -sync_threshold) {
                        delay = 0;
                    } else if (diff >= sync_threshold) {
                        delay = 2 * delay;
                        //[object updateActivityViewAtion:0.5];
                    }
                }
            }
            if (is->paused) {
                delay = is->frame_last_delay;
            }
            
            is->frame_timer += delay;
            
//            NSLog(@"frame_timer %f",is->frame_timer);
            // Computer the REAL delay.
            actual_delay = is->frame_timer - (av_gettime() / 1000000.0);
//            NSLog(@"delay %f", actual_delay);
            if (actual_delay < 0.010) {
                // Really it should skip the picture instead.
                actual_delay = 0.010;
            }
            schedule_refresh(is, (int)(actual_delay * 1000 + 0.5));
                        // Show the picture!
            
            if (is->paused) {
                return;
            }
            video_display(is);
            // NSLog(@"video_display");
            // Update queue for next picture!
            if (++is->pictq_rindex == VIDEO_PICTURE_QUEUE_SIZE) {
                is->pictq_rindex = 0;
            }
            SDL_LockMutex(is->pictq_mutex);
            is->pictq_size--;
            SDL_CondSignal(is->pictq_cond);
            SDL_UnlockMutex(is->pictq_mutex);
        }
    } else {
        schedule_refresh(is, 100);
    }
}
void video_display(VideoState *is) {
    VideoPicture *vp;
    
    vp = &is->pictq[is->pictq_rindex];
    //NSLog(@"vp--- %@", vp);
    
    [object updateYUVFrameOnMainThread:(H264YUV_Frame*)&vp->yuvFrame];
    
    free(vp->yuvFrame.luma.dataBuffer);
    free(vp->yuvFrame.chromaB.dataBuffer);
    free(vp->yuvFrame.chromaR.dataBuffer);
}

void audio_callback(void *userdata, Uint8 *stream, int len) {
    VideoState *is = (VideoState *) userdata;
    int len1, audio_data_size;
    double pts;
    
    while (len > 0) {
        if (stopFlag == 1) {
            is->audio_buf_size = 0;
            memset(is->audio_buf, 0, is->audio_buf_size);
            stream = 0;
            return;
        }
        if (is->audio_buf_index >= is->audio_buf_size) {
            audio_data_size = audio_decode_frame(is, &pts);
            
            if (audio_data_size < 0) {
                /* silence */
                is->audio_buf_size = 1024;
                memset(is->audio_buf, 0, is->audio_buf_size);
            } else {
                //audio_data_size = synchronize_audio(is, (int16_t *)is->audio_buf, audio_data_size, pts);
                is->audio_buf_size = audio_data_size;
            }
            is->audio_buf_index = 0;
        }
        
        len1 = is->audio_buf_size - is->audio_buf_index;
        if (len1 > len) {
            len1 = len;
        }
//        SDL_MixAudio(stream, (uint8_t*)is->audio_buf + is->audio_buf_index, len, SDL_MIX_MAXVOLUME);
        memcpy(stream, (uint8_t *) is->audio_buf + is->audio_buf_index, len1);
        len -= len1;
        stream += len1;
        is->audio_buf_index += len1;
    }  
}

//获取视频pts
double synchronize_video(VideoState *is, AVFrame *src_frame, double pts) {
    double frame_delay;
    
    if (pts != 0) {
        // If we have pts, set video clock to it.
        is->video_clock = pts;
    } else {
        // If we aren't given a pts, set it to the clock.
        pts = is->video_clock;
    }
//    NSLog(@"++++video pts ---%f", pts);
    // Update the video clock.
    frame_delay = av_q2d(is->video_st->codec->time_base);
    // If we are repeating a frame, adjust clock accordingly.
    frame_delay += src_frame->repeat_pict * (frame_delay * 0.5);
    is->video_clock += frame_delay;
//    NSLog(@"++++video pts ---%f", pts);
    return pts;
}

int synchronize_audio(VideoState *is, short *samples, int samples_size, double pts) {
    int n;
    double ref_clock;
    
    n = 2 * is->audio_st->codec->channels;
    
    if (is->av_sync_type != AV_SYNC_AUDIO_MASTER) {
        double diff, avg_diff;
        int wanted_size, min_size, max_size; //, nb_samples
        
        ref_clock = get_master_clock(is);
        diff = get_audio_clock(is) - ref_clock;
        NSLog(@"*********************** %f,", diff );

        if (diff < AV_NOSYNC_THRESHOLD) {
            // Accumulate the diffs.
            is->audio_diff_cum = diff + is->audio_diff_avg_coef
            * is->audio_diff_cum;
            if (is->audio_diff_avg_count < AUDIO_DIFF_AVG_NB) {
                is->audio_diff_avg_count++;
            } else {
                avg_diff = is->audio_diff_cum * (1.0 - is->audio_diff_avg_coef);
                if (fabs(avg_diff) >= is->audio_diff_threshold) {
                    wanted_size = samples_size + ((int) (diff * is->audio_st->codec->sample_rate) * n);
                    min_size = samples_size * ((100 - SAMPLE_CORRECTION_PERCENT_MAX) / 100);
                    max_size = samples_size * ((100 + SAMPLE_CORRECTION_PERCENT_MAX) / 100);
                    if (wanted_size < min_size) {
                        wanted_size = min_size;
                    } else if (wanted_size > max_size) {
                        wanted_size = max_size;
                    }
                    if (wanted_size < samples_size) {
                        // Remove samples.
                        samples_size = wanted_size;
                    } else if (wanted_size > samples_size) {
                        uint8_t *samples_end, *q;
                        int nb;
                        
                        // Add samples by copying final sample.
                        nb = (samples_size - wanted_size);
                        samples_end = (uint8_t *) samples + samples_size - n;
                        q = samples_end + n;
                        while (nb > 0) {
                            memcpy(q, samples_end, n);
                            q += n;
                            nb -= n;
                        }
                        samples_size = wanted_size;
                    }
                }
            }
        } else {
            // Difference is too big, reset diff stuff.
            is->audio_diff_avg_count = 0;
            is->audio_diff_cum = 0;
            
        }
    }
    return samples_size;
}

//有了Audio clock后，在外面获取该值的时候却不能直接返回该值，因为audio缓冲区的可能还有未播放的数据，需要减去这部分的时间,用audio缓冲区中剩余的数据除以每秒播放的音频数据得到剩余数据的播放时间，从Audio clock中减去这部分的值就是当前的audio的播放时长
double get_audio_clock(VideoState *is) {
    double pts;
    int hw_buf_size, bytes_per_sec, n;
    pts = is->audio_clock; // maintained in the audio thread.
    hw_buf_size = is->audio_buf_size - is->audio_buf_index;
    bytes_per_sec = 0;
    n = is->audio_st->codec->channels * 2;
    if (is->audio_st) {
        bytes_per_sec = is->audio_st->codec->sample_rate * n;
    }
    if (bytes_per_sec) {
        pts -= (double)hw_buf_size / bytes_per_sec;
    }
    return pts;
}

//double get_video_clock(VideoState *is) {
//    double delta;
//
//    delta = (av_gettime() - is->video_current_pts_time) / 1000000.0;
//    NSLog(@"pts video----%f",is->video_current_pts + delta);
//    return is->video_current_pts + delta;
//}
//
//double get_external_clock(VideoState *is) {
//    return av_gettime() / 1000000.0;
//}

double get_master_clock(VideoState *is) {
    
    return get_audio_clock(is);
    
//    if (is->av_sync_type == AV_SYNC_VIDEO_MASTER) {
//        return get_video_clock(is);
//    } else if (is->av_sync_type == AV_SYNC_AUDIO_MASTER) {
//        return get_audio_clock(is);
//    } else {
//        return get_external_clock(is);
//    }
}

void packet_queue_init(PacketQueue *q) {
    memset(q, 0, sizeof(PacketQueue));
    q->mutex = SDL_CreateMutex();
    q->cond = SDL_CreateCond();
}

int packet_queue_put(PacketQueue *q, AVPacket *pkt) {
    AVPacketList *pkt1;
//    if (pkt != &flush_pkt && av_packet_ref(pkt, pkt) < 0) {
//        return -1;
//    }
    if (pkt != &flush_pkt && av_dup_packet(pkt) < 0)
    {
        return -1;
    }
    pkt1 = (AVPacketList *) av_malloc(sizeof(AVPacketList));
    if (!pkt1) {
        return -1;
    }
    pkt1->pkt = *pkt;
    pkt1->next = NULL;
    
    SDL_LockMutex(q->mutex);
    
    if (!q->last_pkt) {
        q->first_pkt = pkt1;
    } else {
        q->last_pkt->next = pkt1;
    }
    
    q->last_pkt = pkt1;
    q->nb_packets++;
    q->size += pkt1->pkt.size;
    SDL_CondSignal(q->cond);
    SDL_UnlockMutex(q->mutex);
    return 0;
}

static int packet_queue_get(PacketQueue *q, AVPacket *pkt, int block) {
    AVPacketList *pkt1;
    int ret;
    
    SDL_LockMutex(q->mutex);
    
    for (;;) {
        if (stopFlag == 1) {
            ret = -1;
            if (q->first_pkt) {
                av_free(&q->first_pkt->pkt);
            }
            return -1;
        }
        if (global_video_state->quit) {
            ret = -1;
            break;
        }
        
        pkt1 = q->first_pkt;
        if (pkt1) {
            q->first_pkt = pkt1->next;
            if (!q->first_pkt) {
                q->last_pkt = NULL;
            }
            q->nb_packets--;
            q->size -= pkt1->pkt.size;
            *pkt = pkt1->pkt;
            
            av_free(pkt1);
            ret = 1;
            break;
        } else if (!block) {
            ret = 0;
            break;
        } else {
            SDL_CondWait(q->cond, q->mutex);
        }
    }
    
    SDL_UnlockMutex(q->mutex);
    
    return ret;  
}
int audio_decode_frame(VideoState *is, double *pts_ptr) {
    int len1, len2, decoded_data_size;
    int n;
    AVPacket *pkt = &is->audio_pkt;
    int got_frame = 0;
    int64_t dec_channel_layout;
    int wanted_nb_samples, resampled_data_size;
    
    double pts;
    
    if (is->paused) {
        return -1;
    }
    
    for (;;) {
        if (stopFlag == 1) {
            return -1;
        }
        while (is->audio_pkt_size > 0) {
            if (stopFlag == 1) {
                av_free_packet(pkt);
                return -1;
            }
            if (!is->audio_frame) {
                if (!(is->audio_frame = av_frame_alloc())) {
                    return AVERROR(ENOMEM);
                }
            } else
                av_frame_unref(is->audio_frame);
            
            /**
             * 当AVPacket中装得是音频时，有可能一个AVPacket中有多个AVFrame，
             * 而某些解码器只会解出第一个AVFrame，这种情况我们必须循环解码出后续AVFrame
             */
            len1 = avcodec_decode_audio4(is->audio_st->codec, is->audio_frame,
                                         &got_frame, pkt);
            if (len1 < 0) {
                // error, skip the frame
                is->audio_pkt_size = 0;
                break;
            }
            
            is->audio_pkt_data += len1;
            is->audio_pkt_size -= len1;
            
            if (is-> video_clock - get_audio_clock(is) > 0.5) {
                continue;
            }
            
            if (!got_frame)
                continue;
            //执行到这里我们得到了一个AVFrame
            //计算音频尺寸所占字节数
            decoded_data_size = av_samples_get_buffer_size(NULL,is->audio_frame->channels, is->audio_frame->nb_samples,is->audio_frame->format, 1);
            
            //得到这个AvFrame的声音布局，比如立体声
            dec_channel_layout =
            (is->audio_frame->channel_layout
             && is->audio_frame->channels
             == av_get_channel_layout_nb_channels(
                                                  is->audio_frame->channel_layout)) ?
            is->audio_frame->channel_layout :
            av_get_default_channel_layout(
                                          is->audio_frame->channels);
            
            //这个AVFrame每个声道的采样数
            wanted_nb_samples = is->audio_frame->nb_samples;
            
            
            /**
             * 接下来判断我们之前设置SDL时设置的声音格式(AV_SAMPLE_FMT_S16)，声道布局，
             * 采样频率，每个AVFrame的每个声道采样数与
             * 得到的该AVFrame分别是否相同，如有任意不同，我们就需要swr_convert该AvFrame，
             * 然后才能符合之前设置好的SDL的需要，才能播放
             */
            if (is->audio_frame->format != is->audio_src_fmt
                || dec_channel_layout != is->audio_src_channel_layout
                || is->audio_frame->sample_rate != is->audio_src_freq
                || (wanted_nb_samples != is->audio_frame->nb_samples
                    && !is->swr_ctx)) {
                    if (is->swr_ctx)
                        swr_free(&is->swr_ctx);
                    is->swr_ctx = swr_alloc_set_opts(NULL,
                                                     is->audio_tgt_channel_layout, is->audio_tgt_fmt,
                                                     is->audio_tgt_freq, dec_channel_layout,
                                                     is->audio_frame->format, is->audio_frame->sample_rate,
                                                     0, NULL);
                    if (!is->swr_ctx || swr_init(is->swr_ctx) < 0) {
                        fprintf(stderr, "swr_init() failed\n");
                        break;
                    }
                    is->audio_src_channel_layout = dec_channel_layout;
                    is->audio_src_channels = is->audio_st->codec->channels;
                    is->audio_src_freq = is->audio_st->codec->sample_rate;
                    is->audio_src_fmt = is->audio_st->codec->sample_fmt;
                }
            
            /**
             * 如果上面if判断失败，就会初始化好swr_ctx，就会如期进行转换
             */
            if (is->swr_ctx) {
                // const uint8_t *in[] = { is->audio_frame->data[0] };
                const uint8_t **in =
                (const uint8_t **) is->audio_frame->extended_data;
                uint8_t *out[] = { is->audio_buf2 };
                if (wanted_nb_samples != is->audio_frame->nb_samples) {
                    fprintf(stdout, "swr_set_compensation \n");
                    if (swr_set_compensation(is->swr_ctx,
                                             (wanted_nb_samples - is->audio_frame->nb_samples)
                                             * is->audio_tgt_freq
                                             / is->audio_frame->sample_rate,
                                             wanted_nb_samples * is->audio_tgt_freq
                                             / is->audio_frame->sample_rate) < 0) {
                        fprintf(stderr, "swr_set_compensation() failed\n");
                        break;
                    }
                }
                
                /**
                 * 转换该AVFrame到设置好的SDL需要的样子，有些旧的代码示例最主要就是少了这一部分，
                 * 往往一些音频能播，一些不能播，这就是原因，比如有些源文件音频恰巧是AV_SAMPLE_FMT_S16的。
                 * swr_convert 返回的是转换后每个声道(channel)的采样数
                 */
                len2 = swr_convert(is->swr_ctx, out,
                                   sizeof(is->audio_buf2) / is->audio_tgt_channels
                                   / av_get_bytes_per_sample(is->audio_tgt_fmt),
                                   in, is->audio_frame->nb_samples);
                if (len2 < 0) {
                    fprintf(stderr, "swr_convert() failed\n");
                    break;
                }
                if (len2
                    == sizeof(is->audio_buf2) / is->audio_tgt_channels
                    / av_get_bytes_per_sample(is->audio_tgt_fmt)) {
                    fprintf(stderr,
                            "warning: audio buffer is probably too small\n");
                    swr_init(is->swr_ctx);
                }
                is->audio_buf = is->audio_buf2;
                
        
                //每声道采样数 x 声道数 x 每个采样字节数
                resampled_data_size = len2 * is->audio_tgt_channels
                * av_get_bytes_per_sample(is->audio_tgt_fmt);
            } else {
                resampled_data_size = decoded_data_size;
                is->audio_buf = is->audio_frame->data[0];
            }
            
            //由于一个packet中可以包含多个帧，packet中的PTS比真正的播放的PTS可能会早很多，可以根据Sample Rate 和 Sample Format来计算出该packet中的数据可以播放的时长，再次更新Audio clock
            // 每秒钟音频播放的字节数 sample_rate * channels * sample_format(一个sample占用的字节数)
            pts = is->audio_clock;
            *pts_ptr = pts;
            //乘以2是因为sample format是16位的无符号整型，占用2个字节。
            n = 2 * is->audio_st->codec->channels;
            is->audio_clock += (double)resampled_data_size /
            (double)(n * is->audio_st->codec->sample_rate);
//            NSLog(@"++++aaudio pts ---%f", pts);
            // We have data, return it and come back for more later
            return resampled_data_size;
        }
        
        if (pkt->data)  
            av_free_packet(pkt);  
        memset(pkt, 0, sizeof(*pkt));
        if (is->quit)  
            return -1;  
        if (packet_queue_get(&is->audioq, pkt, 1) < 0)  
            return -1;
        if (pkt->data == flush_pkt.data) {
            avcodec_flush_buffers(is->audio_st->codec);
            continue;
        }

        is->audio_pkt_data = pkt->data;  
        is->audio_pkt_size = pkt->size;
        
        if (pkt->pts != AV_NOPTS_VALUE) {
            is->audio_clock = av_q2d(is->audio_st->time_base) * pkt->pts;
        }
    }  
}

int stream_component_open(VideoState *is, int stream_index) {
    AVFormatContext *ic = is->ic;
    AVCodecContext *codecCtx;
    AVCodec *codec;
    SDL_AudioSpec wanted_spec, spec;
    int64_t wanted_channel_layout = 0;
    int wanted_nb_channels;
    const int next_nb_channels[] = { 0, 0, 1, 6, 2, 6, 4, 6 };
    
    if (stream_index < 0 || stream_index >= ic->nb_streams) {
        return -1;
    }
    
    codecCtx = ic->streams[stream_index]->codec;
    if (codecCtx->codec_type == AVMEDIA_TYPE_AUDIO) {
        wanted_nb_channels = codecCtx->channels;
        if (!wanted_channel_layout
            || wanted_nb_channels
            != av_get_channel_layout_nb_channels(
                                                 wanted_channel_layout)) {
                wanted_channel_layout = av_get_default_channel_layout(
                                                                      wanted_nb_channels);
                wanted_channel_layout &= ~AV_CH_LAYOUT_STEREO_DOWNMIX;
            }
        
        wanted_spec.channels = av_get_channel_layout_nb_channels(wanted_channel_layout);
        wanted_spec.freq = codecCtx->sample_rate;
        if (wanted_spec.freq <= 0 || wanted_spec.channels <= 0) {
            fprintf(stderr, "Invalid sample rate or channel count!\n");
            return -1;
        }
        wanted_spec.format = AUDIO_S16SYS;
        wanted_spec.silence = 0;
        wanted_spec.samples = SDL_AUDIO_BUFFER_SIZE;
        wanted_spec.callback = audio_callback;
        wanted_spec.userdata = is;
        
        while (SDL_OpenAudio(&wanted_spec, &spec) < 0) {
            fprintf(stderr, "SDL_OpenAudio (%d channels): %s\n",
                    wanted_spec.channels, SDL_GetError());
            wanted_spec.channels = next_nb_channels[FFMIN(7, wanted_spec.channels)];
            if (!wanted_spec.channels) {
                fprintf(stderr,
                        "No more channel combinations to tyu, audio open failed\n");
                return -1;
            }
            wanted_channel_layout = av_get_default_channel_layout(
                                                                  wanted_spec.channels);
        }
        
        if (spec.format != AUDIO_S16SYS) {
            fprintf(stderr, "SDL advised audio format %d is not supported!\n",
                    spec.format);
            return -1;
        }
        if (spec.channels != wanted_spec.channels) {
            wanted_channel_layout = av_get_default_channel_layout(spec.channels);
            if (!wanted_channel_layout) {
                fprintf(stderr, "SDL advised channel count %d is not supported!\n",
                        spec.channels);
                return -1;
            }
        }
        fprintf(stderr, "%d: wanted_spec.format = %d\n", __LINE__,
                wanted_spec.format);
        fprintf(stderr, "%d: wanted_spec.samples = %d\n", __LINE__,
                wanted_spec.samples);
        fprintf(stderr, "%d: wanted_spec.channels = %d\n", __LINE__,
                wanted_spec.channels);
        fprintf(stderr, "%d: wanted_spec.freq = %d\n", __LINE__, wanted_spec.freq);
        
        fprintf(stderr, "%d: spec.format = %d\n", __LINE__, spec.format);
        fprintf(stderr, "%d: spec.samples = %d\n", __LINE__, spec.samples);
        fprintf(stderr, "%d: spec.channels = %d\n", __LINE__, spec.channels);
        fprintf(stderr, "%d: spec.freq = %d\n", __LINE__, spec.freq);
        
        is->audio_src_fmt = is->audio_tgt_fmt = AV_SAMPLE_FMT_S16;
        is->audio_src_freq = is->audio_tgt_freq = spec.freq;
        is->audio_src_channel_layout = is->audio_tgt_channel_layout =
        wanted_channel_layout;
        is->audio_src_channels = is->audio_tgt_channels = spec.channels;
    }
    
    
    codec = avcodec_find_decoder(codecCtx->codec_id);
    if (!codec || (avcodec_open2(codecCtx, codec, NULL) < 0)) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1;
    }
    
    ic->streams[stream_index]->discard = AVDISCARD_DEFAULT;
    switch (codecCtx->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
            is->audioStream = stream_index;
            is->audio_st = ic->streams[stream_index];
            is->audio_buf_size = 0;
            is->audio_buf_index = 0;
            
            // Averaging filter for audio sync.
            is->audio_diff_avg_coef = exp(log(0.01 / AUDIO_DIFF_AVG_NB));
            is->audio_diff_avg_count = 0;
            // Correct audio only if larger error than this.
            is->audio_diff_threshold = 2.0 * SDL_AUDIO_BUFFER_SIZE / codecCtx->sample_rate;
            
            
            memset(&is->audio_pkt, 0, sizeof(is->audio_pkt));
            packet_queue_init(&is->audioq);
            SDL_PauseAudio(0);
            break;
        case AVMEDIA_TYPE_VIDEO:
            is->videoStream = stream_index;
            is->video_st = ic->streams[stream_index];
            
            is->frame_timer = (double)av_gettime() / 1000000.0;
            is->frame_last_delay = 40e-3;
            is->video_current_pts_time = av_gettime();
            
            packet_queue_init(&is->videoq);
            const char * name = "video_thread";
            is->video_tid = SDL_CreateThread(video_thread,name, is);
            codecCtx->get_buffer2 = our_get_buffer;
            // codecCtx->release_buffer = our_release_buffer;
            break;
        default:
            break;
    }
    return 0;
}


// These are called whenever we allocate a frame buffer. We use this to store the global_pts in a frame at the time it is allocated.
int our_get_buffer(struct AVCodecContext *c, AVFrame *pic, int flags) {
    int ret = avcodec_default_get_buffer2(c, pic, 0);
    uint64_t *pts = av_malloc(sizeof(uint64_t));
    *pts = global_video_pkt_pts;
    pic->opaque = pts;
    return ret;
}

int video_thread(void *arg) {
    VideoState *is = (VideoState *)arg;
    AVPacket pkt1, *packet = &pkt1;
    int frameFinished;
    AVFrame *pFrame;
    double pts;
    
    pFrame = av_frame_alloc();
    if (is->paused) {
        return -1;
    }
    
    for (;;) {
        if (stopFlag == 1) {
            av_packet_unref(packet);
            av_freep(packet);
            av_frame_free(&pFrame);
            return -1;
        }
        if (packet_queue_get(&is->videoq, packet, 1) < 0) {
            // Means we quit getting packets.
            break;
        }
        if (packet->data == flush_pkt.data) {
            avcodec_flush_buffers(is->video_st->codec);
            continue;
        }
        pts = 0;
        
        // Save global pts to be stored in pFrame in first call.
        global_video_pkt_pts = packet->pts;
        // Decode video frame.
        avcodec_decode_video2(is->video_st->codec, pFrame, &frameFinished, packet);
        if (packet->dts == AV_NOPTS_VALUE && pFrame->opaque && *(uint64_t*)pFrame->opaque != AV_NOPTS_VALUE) {
            pts = *(uint64_t *)pFrame->opaque;
        } else if (packet->dts != AV_NOPTS_VALUE) {
            pts = packet->dts;
        } else {
            pts = 0;
        }
        pts *= av_q2d(is->video_st->time_base);
//        NSLog(@"-----video------ %f", pts);
        if (frameFinished) {
            pts = synchronize_video(is, pFrame, pts);
            if (queue_picture(is, pFrame, pts) < 0) {
                break;
            }
        }
        
        av_packet_unref(packet);
        av_freep(packet);
    }
    av_frame_free(&pFrame);
    return 0;
}

int queue_picture(VideoState *is, AVFrame *pFrame, double pts) {
    VideoPicture *vp;
    
    SDL_LockMutex(is->pictq_mutex);
    while (is->pictq_size >= VIDEO_PICTURE_QUEUE_SIZE && !is->quit) {
        SDL_CondWait(is->pictq_cond, is->pictq_mutex);
    }
    SDL_UnlockMutex(is->pictq_mutex);
    
    if (is->quit) {
        return -1;
    }
    
    // windex is set to 0 initially.
    vp = &is->pictq[is->pictq_windex];
    
    // Allocate or resize the buffer!.
    if (vp->width != is->video_st->codec->width || vp->height != is->video_st->codec->height) {
        SDL_Event event;
        
        vp->allocated = 0;
        // We have to do it in the main thread.
        event.type = FF_ALLOC_EVENT;
        event.user.data1 = is;
        SDL_PushEvent(&event);
        
        // wait until we have a picture allocated.
        SDL_LockMutex(is->pictq_mutex);
        while (!vp->allocated && !is->quit) {
            SDL_CondWait(is->pictq_cond, is->pictq_mutex);
        }
        SDL_UnlockMutex(is->pictq_mutex);
        if (is->quit) {
            return -1;
        }
    }
    // We have a place to put our picture on the queue.
    // If we are skipping a frame, do we set this to null but still return vp->allocated = 1?
    if (vp) {
        
        unsigned int lumaLength= (is->video_st->codec->height)*(MIN(pFrame->linesize[0], is->video_st->codec->width));
        unsigned int chromBLength=((is->video_st->codec->height)/2)*(MIN(pFrame->linesize[1], (is->video_st->codec->width)/2));
        unsigned int chromRLength=((is->video_st->codec->height)/2)*(MIN(pFrame->linesize[2], (is->video_st->codec->width)/2));
        
        
        vp->yuvFrame.luma.length = lumaLength;
        vp->yuvFrame.chromaB.length = chromBLength;
        vp->yuvFrame.chromaR.length =chromRLength;
        
        vp->yuvFrame.luma.dataBuffer=(unsigned char*)malloc(lumaLength);
        vp->yuvFrame.chromaB.dataBuffer=(unsigned char*)malloc(chromBLength);
        vp->yuvFrame.chromaR.dataBuffer=(unsigned char*)malloc(chromRLength);
        
        copyDecodedFrame(pFrame->data[0],vp->yuvFrame.luma.dataBuffer,pFrame->linesize[0],
                         is->video_st->codec->width,is->video_st->codec->height);
        copyDecodedFrame(pFrame->data[1], vp->yuvFrame.chromaB.dataBuffer,pFrame->linesize[1],
                         is->video_st->codec->width / 2,is->video_st->codec->height / 2);
        copyDecodedFrame(pFrame->data[2], vp->yuvFrame.chromaR.dataBuffer,pFrame->linesize[2],
                         is->video_st->codec->width / 2,is->video_st->codec->height / 2);
        
        vp->yuvFrame.width=is->video_st->codec->width;
        vp->yuvFrame.height=is->video_st->codec->height;
        
    
        vp->pts = pts;
        
        // Now we inform our display thread that we have a pic ready.
        if (++is->pictq_windex == VIDEO_PICTURE_QUEUE_SIZE) {
            is->pictq_windex = 0;
        }
        SDL_LockMutex(is->pictq_mutex);
        is->pictq_size++;
        SDL_UnlockMutex(is->pictq_mutex);
    }
    return 0;
}

static void packet_queue_flush(PacketQueue *q) {
    AVPacketList *pkt, *pkt1;
    
    SDL_LockMutex(q->mutex);
    for (pkt = q->first_pkt; pkt != NULL; pkt = pkt1) {
        pkt1 = pkt->next;
        av_packet_unref(&pkt->pkt);
        av_freep(&pkt);
    }
    q->last_pkt = NULL;
    q->first_pkt = NULL;
    q->nb_packets = 0;
    q->size = 0;
    SDL_UnlockMutex(q->mutex);
}

void copyDecodedFrame(unsigned char *src, unsigned char *dist,int linesize, int width, int height){
    
    width = MIN(linesize, width);
    
    for (NSUInteger i = 0; i < height; ++i) {
        memcpy(dist, src, width);
        dist += width;
        src += linesize;
    }
    
}
- (void)updateYUVFrameOnMainThread:(H264YUV_Frame*)yuvFrame{
    if(yuvFrame!=NULL){
        if([self.updateDelegate respondsToSelector:@selector(updateDecodedH264FrameData: )]){
            [self.updateDelegate updateDecodedH264FrameData:yuvFrame];
        }
    }
}

-(double)duration {
    return (double)global_video_state->ic->duration / AV_TIME_BASE;
}
- (double)currentTime {
//    AVRational timeBase = global_video_state->ic->streams[videoIndex]->time_base;
    return current_pkt.pts ;
}

@end
