//
//  ViewController.m
//  FFmpeg_Test
//
//  Created by mac on 17/10/21.
//  Copyright © 2016年 Gwl. All rights reserved.
//

#import "PlayViewController.h"
#import "XYQMovieObject.h"
#import "OpenGLFrameView.h"
#import "MonitorButton.h"
#import <MediaPlayer/MediaPlayer.h>
#import <Photos/PHAssetChangeRequest.h>
#import "PlaylistCell.h"
#import "WXApi.h"
#import "AppDelegate.h"

#define URL_APPID @"wx44c887c7214f0d94"
#define URL_SECRET @"b18c7b76371bab8e62f54bf24518fb60"

#define LERP(A,B,C) ((A)*(1.0-C)+(B)*C)
#define SCREEN_W    [[UIScreen mainScreen] bounds].size.width
#define SCREEN_H    [[UIScreen mainScreen] bounds].size.height
#define BANNER_H    40

typedef NS_ENUM(NSUInteger, Direction) {
    DirectionLeftOrRight,
    DirectionUpOrDown,
    DirectionNone
};

@interface PlayViewController ()<updateDecodedH264FrameDelegate, MonitorButtonDelegate, UIGestureRecognizerDelegate, UITableViewDelegate, UITableViewDataSource, WXDelegate>

@property (nonatomic, strong) XYQMovieObject *video;
@property (strong, nonatomic) UILabel *TimerLabel;
@property (nonatomic, strong) OpenGLFrameView *openView;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, assign) double sliderFlag;
@property (nonatomic, assign) NSTimer *timer;
@property (nonatomic, strong) UIImageView *bannerView;
@property (nonatomic, strong) UIButton *changeViewSize;
@property (nonatomic, strong) UIButton *nextBtn;
@property (nonatomic, strong) UIButton *toggle_pauseBtn;
@property (nonatomic, assign) BOOL isHalfScreen;
@property (nonatomic, strong) MonitorButton *monitorBtn;
@property (assign, nonatomic) Direction direction;
@property (assign, nonatomic) CGPoint startPoint;
@property (assign, nonatomic) CGFloat startVB;
@property (assign, nonatomic) CGFloat startVideoRate;
@property (strong, nonatomic) MPVolumeView *volumeView;
@property (strong, nonatomic) UISlider* volumeViewSlider;
@property (strong, nonatomic) UIActivityIndicatorView *activityIndicatorView;
@property (strong, nonatomic) UIButton *lockBtn;
@property (strong, nonatomic) UIButton *cutBtn;
@property (strong, nonatomic) UIButton *listBtn;
@property (strong, nonatomic) UIGestureRecognizer *tap;
@property (strong, nonatomic) UIImageView *imageView;
@property (strong, nonatomic) UIButton *titleBtn;
@property (strong, nonatomic) UIView *pictureView;
@property (strong, nonatomic) UIButton *cancleBtn;
@property (strong, nonatomic) UIButton *questionsBtn;
@property (strong, nonatomic) UIButton *wxfShareBtn;
@property (strong, nonatomic) UIButton *wxShareBtn;
@property (strong, nonatomic) UIButton *selectionsBtn;
@property (strong, nonatomic) UIView *selectionsView;
@property (strong, nonatomic) UILabel *currentTimeLable;
@property (strong, nonatomic) UIImageView *topView;
@property (strong, nonatomic) UIButton *backBtn;
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) UILabel *tableTitleLabel;
@property (strong, nonatomic) NSMutableArray *dataSourceArr;
@property (strong, nonatomic) NSString *currentVideoName;
@property (assign, nonatomic) AppDelegate *appdelegate;
@end


extern NSString *fileP;

@implementation PlayViewController

@synthesize video;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setLayoutView];
}
#pragma mark     ------------------------ 界面布局 --------------------------
- (void) setLayoutView {
    //初始化数据
    self.dataSourceArr = [@[@"1.wmv", @"3.wmv", @"4.wmv", @"3.wmv", @"4.wmv"] mutableCopy];
    
    self.currentVideoName = @"3.wmv";
    NSString *str = [[NSBundle mainBundle]pathForResource:@"3.wmv" ofType:NULL];
    //NSString *str = [NSString stringWithFormat:@"aaaymj://%@", fileP];
    //NSLog(@"lujing %@", str);
    //self.video = [[XYQMovieObject alloc] initWithVideo:_rPath];
    self.video = [[XYQMovieObject alloc] initWithVideo:str];
    
    self.video.updateDelegate = self;
    
    //播放器
    self.openView = [[OpenGLFrameView alloc]initWithFrame:CGRectMake(0, 0, SCREEN_W, SCREEN_H)];
    self.tap =[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapAction:)];
    [self.openView addGestureRecognizer:self.tap];
    self.tap.delegate = self;
    [self.view addSubview:self.openView];
    
    //banner 控制条背景
    self.bannerView =[[UIImageView alloc] init];
    [self.bannerView setImage:[UIImage imageNamed:@"bottom_shadow"]];
    [self.openView addSubview:self.bannerView];
    
    //播放
    self.toggle_pauseBtn = [[UIButton alloc] initWithFrame:CGRectMake(10, 0, BANNER_H, BANNER_H)];
    [self.toggle_pauseBtn setBackgroundImage:[UIImage imageNamed:@"icon_play.png"] forState:UIControlStateNormal];
    self.toggle_pauseBtn.tag = 100;
    [self.toggle_pauseBtn addTarget:self action:@selector(togglePauseAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.toggle_pauseBtn];
    
    //下一个
    self.nextBtn = [[UIButton alloc]init];
    [self.nextBtn setBackgroundImage:[UIImage imageNamed:@"next_button.png"] forState:UIControlStateNormal];
    [self.nextBtn addTarget:self action:@selector(nextBtnAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextBtn];
    
    //时间1
    self.currentTimeLable = [[UILabel alloc]init];
    [self.currentTimeLable setTextColor:[UIColor whiteColor]];
    self.currentTimeLable.text = [NSString stringWithFormat:@"%@",[self dealTime:0]];
    self.currentTimeLable.font = [UIFont systemFontOfSize:10];
    [self.view addSubview:self.currentTimeLable];
    
    //点击隐藏,显示
    self.monitorBtn = [[MonitorButton alloc]init];
    [self.monitorBtn addTarget:self action:@selector(changeDisplay:) forControlEvents:UIControlEventTouchUpInside];
    self.monitorBtn.touchDelegate = self;
    [self.view addSubview:self.monitorBtn];
    
    //滑竿进度
    self.slider = [[UISlider alloc]init];
    self.slider.minimumValue = 0;
    //    self.slider.maximumValue = video.duration;
    self.slider.minimumTrackTintColor = [UIColor colorWithRed:232/255.0 green:56/255.0 blue:47/255.0 alpha:1];
    self.slider.continuous = NO;
    [self.slider addTarget:self action:@selector(seekTimeAction:) forControlEvents:UIControlEventValueChanged];
    [self.slider setThumbImage:[UIImage imageNamed:@"progress_point"] forState:UIControlStateNormal];
    self.sliderFlag = YES;
    [self.slider addTarget:self action:@selector(seekTimeStart:) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:self.slider];
    
    //时间
    self.TimerLabel = [[UILabel alloc]init];
    [self.TimerLabel setTextColor:[UIColor whiteColor]];
    self.TimerLabel.text = [NSString stringWithFormat:@"%@", [self dealTime:0]];
    self.TimerLabel.font = [UIFont systemFontOfSize:10];
    [self.view addSubview:self.TimerLabel];
    
    //处理选集
    self.selectionsBtn = [[UIButton alloc] init];
    [self.selectionsBtn setTitle:@"相关" forState:UIControlStateNormal];
    [self.selectionsBtn addTarget:self action:@selector(selectionsAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.selectionsBtn];
    
    //锁屏
    self.lockBtn = [[UIButton alloc]initWithFrame:CGRectMake(20, SCREEN_W / 2 - 22, 44, 44)];
    self.lockBtn.layer.cornerRadius = 22;
    [self.lockBtn setImage:[UIImage imageNamed:@"unlock_normal"] forState:UIControlStateNormal];
    [self.lockBtn setImage:[UIImage imageNamed:@"locking_down"] forState:UIControlStateSelected];
    [self.lockBtn addTarget:self action:@selector(lockBtnAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.lockBtn];
    
    //截屏
    self.cutBtn = [[UIButton alloc]initWithFrame:CGRectMake(SCREEN_H - 60, SCREEN_W / 2 - 22, 44, 44)];
    self.cutBtn.layer.cornerRadius = 22;
    [self.cutBtn setImage:[UIImage imageNamed:@"photo_normal"] forState:UIControlStateNormal];
    [self.cutBtn addTarget:self action:@selector(cutBtnAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cutBtn];
    
    //选集视图
    self.selectionsView = [[UIView alloc]init];
    self.selectionsView.backgroundColor = [UIColor blackColor];
    self.selectionsView.alpha = 0.9;
    [self.view addSubview:self.selectionsView];
    
    //topView
    self.topView = [[UIImageView alloc]init];
    [self.topView setImage:[UIImage imageNamed:@"top_shadow"]];
    [self.view addSubview:self.topView];
    
    //返回按钮
    self.backBtn = [[UIButton alloc]init];
    [self.backBtn setTitle:@"中高考视频教程" forState:UIControlStateNormal];
    [self.backBtn setImage:[UIImage imageNamed:@"back"] forState:UIControlStateNormal];
    [self.backBtn addTarget:self action:@selector(backAction:) forControlEvents:UIControlEventTouchUpInside];
    //    [self.backBtn.titleLabel setFont:[UIFont systemFontOfSize:22]];
    [self.view addSubview:self.backBtn];
    
    //选集界面
    self.imageView = [[UIImageView alloc]init];
    self.pictureView = [[UIView alloc]init];
    self.cancleBtn = [[UIButton alloc]init];
    self.titleBtn = [[UIButton alloc]init];
    self.questionsBtn = [[UIButton alloc] init];
    self.wxfShareBtn = [[UIButton alloc]init];
    self.wxShareBtn = [[UIButton alloc] init];
    [self.cancleBtn setTitle:@"取消" forState:UIControlStateNormal];
    self.cancleBtn.layer.cornerRadius = 19;
    [self.cancleBtn setBackgroundColor:[UIColor colorWithRed:47/255.0 green:49/255.0 blue:50/255.0 alpha:1]];
    
    [self.titleBtn setTitle:@"已保存到系统相册,可以分享给好友啦" forState:UIControlStateNormal];
    [self.titleBtn setImage:[UIImage imageNamed:@"icon_right"] forState:UIControlStateNormal];
    [self.titleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.titleBtn.titleLabel setFont:[UIFont systemFontOfSize:15]];
    [self.titleBtn setImageEdgeInsets:UIEdgeInsetsMake(0.0, -20, 0.0, 0.0)];
    
    [self.questionsBtn setTitle:@"提问" forState:UIControlStateNormal];
    [self.questionsBtn setImage:[UIImage imageNamed:@"questions.png"] forState:UIControlStateNormal];
    [self.questionsBtn setImageEdgeInsets:UIEdgeInsetsMake(0, 20, 40, 20)];
    [self.questionsBtn setTitleEdgeInsets:UIEdgeInsetsMake(44, -104, 0, 0)];
    [self.questionsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.questionsBtn.titleLabel setFont:[UIFont systemFontOfSize:15]];
    
    [self.wxfShareBtn setTitle:@"微信好友" forState:UIControlStateNormal];
    [self.wxfShareBtn setImage:[UIImage imageNamed:@"wechat.png"] forState:UIControlStateNormal];
    [self.wxfShareBtn setImageEdgeInsets:UIEdgeInsetsMake(0, 20, 40, 20)];
    [self.wxfShareBtn setTitleEdgeInsets:UIEdgeInsetsMake(44, -104, 0, 0)];
    [self.wxfShareBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.wxfShareBtn.titleLabel setFont:[UIFont systemFontOfSize:15]];
    [self.wxfShareBtn addTarget: self action:@selector(wxfShareBtnAction:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.wxShareBtn setTitle:@"微信朋友圈" forState:UIControlStateNormal];
    [self.wxShareBtn setImage:[UIImage imageNamed:@"circle_of_friends.png"] forState:UIControlStateNormal];
    [self.wxShareBtn setImageEdgeInsets:UIEdgeInsetsMake(0, 20, 40, 20)];
    [self.wxShareBtn setTitleEdgeInsets:UIEdgeInsetsMake(44, -104, 0, 0)];
    [self.wxShareBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.wxShareBtn.titleLabel setFont:[UIFont systemFontOfSize:15]];
    [self.wxShareBtn addTarget: self action:@selector(wxShareBtnAction:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.pictureView];
    [self.view addSubview:self.imageView];
    [self.view addSubview:self.cancleBtn];
    [self.view addSubview:self.questionsBtn];
    [self.view addSubview:self.titleBtn];
    [self.view addSubview:self.wxfShareBtn];
    [self.view addSubview:self.wxShareBtn];
    
    // tableView
    self.tableView = [[UITableView alloc]init];
    self.tableView.backgroundColor = [UIColor colorWithRed:43/255.0 green:43/255.0 blue:43/255.0 alpha:1];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.selectionsView addSubview:self.tableView];
    [self.tableView registerClass:[PlaylistCell class] forCellReuseIdentifier:@"playlistcell"];
    self.tableView.rowHeight = 80;
    self.tableTitleLabel = [[UILabel alloc]init];
    self.tableTitleLabel.text = @"  相关";
    self.tableTitleLabel.frame = CGRectMake(10, 10, 100, 44);
    [self.tableTitleLabel setTextColor:[UIColor whiteColor]];
    self.tableView.tableHeaderView = self.tableTitleLabel;
    self.tableView.tableFooterView = [[UIView alloc]init];
    
    //播放
    [self startPlay];
    
    //横屏处理
    [[UIDevice currentDevice]setValue:[NSNumber numberWithInteger:UIDeviceOrientationPortrait]  forKey:@"orientation"];//这句话是防止手动先把设备置为横屏,导致下面的语句失效.
    [[UIDevice currentDevice] setValue:[NSNumber numberWithInteger:UIDeviceOrientationLandscapeLeft] forKey:@"orientation"];
    
    self.openView.frame=CGRectMake(0, 0, SCREEN_W, SCREEN_H);
    self.bannerView.frame = CGRectMake(0, SCREEN_H - BANNER_H - 73, SCREEN_W, BANNER_H + 73);
    self.toggle_pauseBtn.frame = CGRectMake(20, SCREEN_H - BANNER_H - 10, BANNER_H, BANNER_H);
    self.nextBtn.frame = CGRectMake(BANNER_H + 20 +10, SCREEN_H - BANNER_H - 10, BANNER_H, BANNER_H);
    self.currentTimeLable.frame = CGRectMake(2  * BANNER_H + 20 +20, SCREEN_H - BANNER_H - 10, 50, BANNER_H);
    self.slider.frame = CGRectMake(3  * BANNER_H + 20 +20 + 10, SCREEN_H - BANNER_H - 10, SCREEN_W - 5 *BANNER_H - 100, BANNER_H);
    self.TimerLabel.frame = CGRectMake(SCREEN_W - BANNER_H * 2 - 40, SCREEN_H - BANNER_H - 10, 50, BANNER_H);
    self.selectionsBtn.frame = CGRectMake(SCREEN_W - BANNER_H - 20, SCREEN_H - BANNER_H - 10, BANNER_H, BANNER_H);
    self.monitorBtn.frame = CGRectMake(0, 0, SCREEN_W, SCREEN_H - BANNER_H);
    self.volumeView.frame = CGRectMake(0, 0, SCREEN_W, SCREEN_W * 9.0 / 16.0);
    self.topView.frame = CGRectMake(0, 0, SCREEN_W, BANNER_H + 73);
    self.backBtn.frame = CGRectMake(20, 25, 100, 30);
    [self.backBtn sizeToFit];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(EnterBackgroundAction:) name:@"EnterBackground" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(EnterForegroundAction:) name:@"EnterForeground" object:nil];
}

#pragma mark     ------------------------ 前台后台 --------------------------
- (void)EnterBackgroundAction:(NSNotification *) notice {
    if (self.toggle_pauseBtn.tag == 100) {
        [UIView animateWithDuration:0 animations:^{
            [video playAndPauseAction:100];
            self.toggle_pauseBtn.transform = CGAffineTransformRotate(self.toggle_pauseBtn.transform, M_PI);
            self.toggle_pauseBtn.tag = 200;
            
        } completion:^(BOOL finished) {
            [self.toggle_pauseBtn setBackgroundImage:[UIImage imageNamed:@"icon_suspend.png"] forState:UIControlStateNormal];
        }];
        
        
    }
}
- (void)EnterForegroundAction:(NSNotification *) notice {
    [video backgroundAction];
}

#pragma mark     ------------------------ 播放操作 --------------------------
- (void)startPlay{
    self.sliderFlag = YES;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        //通知主线程刷新
        dispatch_async(dispatch_get_main_queue(), ^{
            self.timer = [NSTimer scheduledTimerWithTimeInterval: 1 target:self selector:@selector(displayNextFrame:) userInfo:nil repeats:YES];
        });
        // 处理耗时操作
        [video play];
    });
}
- (void)togglePauseAction:(UIButton *)sender {
    
    if (sender.tag == 100) {
        [UIView animateWithDuration:0.4 animations:^{
            [video playAndPauseAction:100];
            sender.transform = CGAffineTransformRotate(sender.transform, M_PI);
            sender.tag = 200;
            
        } completion:^(BOOL finished) {
            [sender setBackgroundImage:[UIImage imageNamed:@"icon_suspend.png"] forState:UIControlStateNormal];
        }];
    }else {
        [UIView animateWithDuration:0.4 animations:^{
            [video playAndPauseAction:200];
            sender.transform = CGAffineTransformRotate(sender.transform, M_PI);
            sender.tag = 100;
            
        } completion:^(BOOL finished) {
            [sender setBackgroundImage:[UIImage imageNamed:@"icon_play.png"] forState:UIControlStateNormal];
        }];
    }
}
- (void)nextBtnAction:(UIButton *)sender {
    self.sliderFlag = YES;
    if (self.timer != nil) {
        [self.timer invalidate];
        self.timer = nil;
    }
    
    int index = -1;
    for (int i = 0; i < self.dataSourceArr.count; i++) {
        if ([self.dataSourceArr[i] isEqualToString: self.currentVideoName]) {
            index = i;
        }
    }
    if (index < self.dataSourceArr.count - 1 && index != -1) {
        self.currentVideoName = self.dataSourceArr[index + 1];
    }else {
        return;
    }
    
    if (self.toggle_pauseBtn.tag == 200) {
        [UIView animateWithDuration:0.4 animations:^{
            self.toggle_pauseBtn.transform = CGAffineTransformRotate(self.toggle_pauseBtn.transform, M_PI);
            self.toggle_pauseBtn.tag = 100;
        } completion:^(BOOL finished) {
            [self.toggle_pauseBtn setBackgroundImage:[UIImage imageNamed:@"icon_play.png"] forState:UIControlStateNormal];
        }];
    }
    NSString *str = [[NSBundle mainBundle]pathForResource:self.currentVideoName ofType:NULL];
    
    //    self.video = nil;
    self.video = [[XYQMovieObject alloc] initWithVideo:str];
    self.video.updateDelegate = self;
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        //通知主线程刷新
        dispatch_async(dispatch_get_main_queue(), ^{
            self.timer = [NSTimer scheduledTimerWithTimeInterval: 1 target:self selector:@selector(displayNextFrame:) userInfo:nil repeats:YES];
        });
        // 处理耗时操作
        [video playNext];
    });
}
- (void)seekTimeAction:(UISlider *)sender {
    
    if (self.sliderFlag == NO) {
        return;
    }
    double second = sender.value - video.currentTime;
    [video seekTime:second];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.timer = [NSTimer scheduledTimerWithTimeInterval: 1 target:self selector:@selector(displayNextFrame:) userInfo:nil repeats:YES];
    });
}
- (void)seekTimeStart:(UISlider*) sender{
    if (self.timer != nil) {
        [self.timer invalidate];
        self.timer = nil;
    }
}
- (void)displayNextFrame:(NSTimer *)timer {
    self.currentTimeLable.text = [NSString stringWithFormat:@"%@",[self dealTime:video.currentTime]];
    self.slider.value = video.currentTime;
    self.slider.maximumValue = video.duration;
    self.TimerLabel.text = [NSString stringWithFormat:@"%@",[self dealTime:video.duration]];
}
- (NSString *)dealTime:(double)time {
    int tns, thh, tmm, tss;
    tns = time;
    thh = tns / 3600;
    tmm = (tns % 3600) / 60;
    tss = tns % 60;
    return [NSString stringWithFormat:@"%02d:%02d:%02d",thh,tmm,tss];
}
- (void)updateDecodedH264FrameData:(H264YUV_Frame *)yuvFrame {
    [self.openView render:yuvFrame];
}

- (void)changeDisplay:(UIButton *)sender {
    self.lockBtn.hidden = !self.lockBtn.hidden;
    self.cutBtn.hidden = !self.cutBtn.hidden;
    self.selectionsView.frame = CGRectZero;
    self.tableView.frame = CGRectZero;
    self.bannerView.hidden = !self.bannerView.hidden;
    self.toggle_pauseBtn.hidden = !self.toggle_pauseBtn.hidden;
    self.nextBtn.hidden = !self.nextBtn.hidden;
    self.currentTimeLable.hidden = !self.currentTimeLable.hidden;
    self.slider.hidden = !self.slider.hidden;
    self.TimerLabel.hidden = !self.TimerLabel.hidden;
    self.selectionsBtn.hidden = !self.selectionsBtn.hidden;
    self.topView.hidden = !self.topView.hidden;
    self.backBtn.hidden = !self.backBtn.hidden;
}
- (void)backAction:(UIButton *)sender {
    if (self.timer != nil) {
        [self.timer invalidate];
        self.timer = nil;
    }
    
    [video stopPlay];

    [self dismissViewControllerAnimated:NO completion:nil];
}
- (void)lockBtnAction:(UIButton *) sender {
    self.lockBtn.selected = !self.lockBtn.selected;
    if(self.lockBtn.selected == YES) {
        [self.monitorBtn setHidden:YES];
        self.bannerView.hidden = YES;
        self.toggle_pauseBtn.hidden = YES;
        self.nextBtn.hidden = YES;
        self.currentTimeLable.hidden = YES;
        self.slider.hidden = YES;
        self.TimerLabel.hidden = YES;
        self.selectionsBtn.hidden = YES;
        [self.cutBtn setHidden:YES];
        [self.selectionsView setHidden:YES];
        self.topView.hidden = YES;
        self.backBtn.hidden = YES;
    }else {
        [self.monitorBtn setHidden:NO];
        self.bannerView.hidden = NO;
        self.toggle_pauseBtn.hidden = NO;
        self.nextBtn.hidden = NO;
        self.currentTimeLable.hidden = NO;
        self.slider.hidden = NO;
        self.TimerLabel.hidden = NO;
        self.selectionsBtn.hidden = NO;
        [self.cutBtn setHidden:NO];
        [self.selectionsView setHidden:NO];
        self.topView.hidden = NO;
        self.backBtn.hidden = NO;
    }
    
}
- (void)cutBtnAction:(UIButton *) sender {
    
    if (sender.hidden == NO) {
        [self changeDisplay:self.monitorBtn];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.pictureView.frame = CGRectMake(0, 0, SCREEN_W, SCREEN_H);
        self.pictureView.backgroundColor = [UIColor blackColor];
        self.pictureView.alpha = 0.9;
        
        UIView * captureView = self.view;
        if (self.tabBarController.view) {
            captureView = self.tabBarController.view;
        }
        
        CGSize size = captureView.frame.size;
        
        UIGraphicsBeginImageContextWithOptions(size, NO, 2);
        
        CGRect rec = CGRectMake(0, 0, captureView.frame.size.width, captureView.frame.size.height);
        
        [captureView drawViewHierarchyInRect:rec afterScreenUpdates:NO];
        
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        NSString *filePath = [doc stringByAppendingPathComponent:[NSString stringWithFormat:@"cutImage.png"]];// 保存文件的名称
        [UIImagePNGRepresentation(image) writeToFile: filePath atomically:YES];
        
        [self.imageView setImage:image];
        self.imageView.frame = CGRectMake(200, 50, SCREEN_W - 400, SCREEN_H - 220);
        self.cancleBtn.frame = CGRectMake(20, 20, 70, 38);
        self.titleBtn.frame = CGRectMake(SCREEN_W / 2 - 150, SCREEN_H - 160, 300, 30);
        
        self.questionsBtn.frame = CGRectMake(SCREEN_W / 2 - 42 - 10 - 84, SCREEN_H - 120, 84, 84);
        self.wxfShareBtn.frame = CGRectMake(SCREEN_W / 2 - 42, SCREEN_H - 120, 84, 84);
        self.wxShareBtn.frame = CGRectMake(SCREEN_W / 2 + 42 + 10, SCREEN_H - 120 , 84, 84);
        [self.cancleBtn addTarget:self action:@selector(cancleBtnAction:) forControlEvents:UIControlEventTouchUpInside];
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            NSLog(@"success = %d, error = %@", success, error);
        }];

    });
    
}
- (void)cancleBtnAction:(UIButton *)sender {
    self.cancleBtn.frame = CGRectZero;
    self.pictureView.frame = CGRectZero;
    self.imageView.frame = CGRectZero;
    self.questionsBtn.frame = CGRectZero;
    self.wxfShareBtn.frame = CGRectZero;
    self.wxShareBtn.frame = CGRectZero;
    self.titleBtn.frame = CGRectZero;
}
- (void)selectionsAction:(UIButton *)sender {
    //创建tableView
    self.selectionsView.frame = CGRectMake(SCREEN_W - 250, 0, 250, SCREEN_H);
    self.tableView.frame = self.selectionsView.bounds;
    self.lockBtn.hidden = !self.lockBtn.hidden;
    self.cutBtn.hidden = !self.cutBtn.hidden;
    self.bannerView.hidden = !self.bannerView.hidden;
    self.toggle_pauseBtn.hidden = !self.toggle_pauseBtn.hidden;
    self.nextBtn.hidden = !self.nextBtn.hidden;
    self.currentTimeLable.hidden = !self.currentTimeLable.hidden;
    self.slider.hidden = !self.slider.hidden;
    self.TimerLabel.hidden = !self.TimerLabel.hidden;
    self.selectionsBtn.hidden = !self.selectionsBtn.hidden;
    self.topView.hidden = !self.topView.hidden;
    self.backBtn.hidden = !self.backBtn.hidden;
    
}
- (void)updateActivityView :(double)diff {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.activityIndicatorView=[[UIActivityIndicatorView alloc]initWithFrame:CGRectMake(0, 0, 100, 100)];
        self.activityIndicatorView.center=self.openView.center;
        [self.activityIndicatorView setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleGray];
        [self.activityIndicatorView setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
        [self.activityIndicatorView setBackgroundColor:[UIColor lightGrayColor]];
        [self.monitorBtn addSubview:self.activityIndicatorView];
        [self.activityIndicatorView startAnimating];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(diff * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.activityIndicatorView removeFromSuperview];
        });
    });
}

#pragma mark     ------------------------ 手势操作 --------------------------
- (void)tapAction:(UITapGestureRecognizer *)tap {
    self.lockBtn.hidden = !self.lockBtn.hidden;
}
- (MPVolumeView *)volumeView {
    if (_volumeView == nil) {
        _volumeView  = [[MPVolumeView alloc] init];
        [_volumeView sizeToFit];
        for (UIView *view in [_volumeView subviews]){
            if ([view.class.description isEqualToString:@"MPVolumeSlider"]){
                self.volumeViewSlider = (UISlider*)view;
                break;
            }
        }
    }
    return _volumeView;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer{
    if([gestureRecognizer locationInView:gestureRecognizer.view].y >= self.bannerView.frame.origin.y && !self.toggle_pauseBtn.hidden)
        return NO;
    return YES;
}
- (void)touchesBeganWithPoint:(CGPoint)point {
    //记录首次触摸坐标
    self.startPoint = point;
    self.direction = DirectionNone;
    //检测用户是触摸屏幕的左边还是右边，以此判断用户是要调节音量还是亮度，左边是亮度，右边是音量
    if (self.startPoint.x <= self.monitorBtn.frame.size.width / 2.0) {
        //亮度
        self.startVB = [UIScreen mainScreen].brightness;
    } else {
        //音量
        self.startVB = self.volumeViewSlider.value;
    }
    
}
- (void)touchesMoveWithPoint:(CGPoint)point {
    //得出手指在Button上移动的距离
    CGPoint panPoint = CGPointMake(point.x - self.startPoint.x, point.y - self.startPoint.y);
    
    if (self.direction == DirectionNone) {
        if (panPoint.x >= 30 || panPoint.x <= -30) {
            //进度
            self.direction = DirectionLeftOrRight;
        } else if (panPoint.y >= 30 || panPoint.y <= -30) {
            //音量和亮度
            self.direction = DirectionUpOrDown;
        }
    }
    
    if (self.direction == DirectionNone) {
        return;
    } else if (self.direction == DirectionUpOrDown) {
        //音量和亮度
        if (self.startPoint.x <= self.monitorBtn.frame.size.width / 2.0) {
            //调节亮度
            if (panPoint.y < 0) {
                //增加亮度
                [[UIScreen mainScreen] setBrightness:self.startVB + (-panPoint.y / 30.0 / 10)];
            } else {
                //减少亮度
                [[UIScreen mainScreen] setBrightness:self.startVB - (panPoint.y / 30.0 / 10)];
            }
            
        } else {
            //音量
            if (panPoint.y < 0) {
                //增大音量
                [self.volumeViewSlider setValue:self.startVB + (-panPoint.y / 30.0 / 10) animated:YES];
                if (self.startVB + (-panPoint.y / 30 / 10) - self.volumeViewSlider.value >= 0.1) {
                    [self.volumeViewSlider setValue:0.1 animated:NO];
                    [self.volumeViewSlider setValue:self.startVB + (-panPoint.y / 30.0 / 10) animated:YES];
                }
                
            } else {
                //减少音量
                [self.volumeViewSlider setValue:self.startVB - (panPoint.y / 30.0 / 10) animated:YES];
            }
        }
    } else if (self.direction == DirectionLeftOrRight ) {
    
    }
    
}
- (void)touchesEndWithPoint:(CGPoint)point {
    CGPoint panPoint = CGPointMake(point.x - self.startPoint.x, point.y - self.startPoint.y);
    
    if (self.direction == DirectionLeftOrRight) {
        if (panPoint.x > 30) {
            self.currentTimeLable.text = [NSString stringWithFormat:@"%@",[self dealTime:video.currentTime]];
            self.slider.value = video.currentTime;
            [video seekTime:panPoint.x / 10];
        }if (panPoint.x < -30) {
            self.currentTimeLable.text = [NSString stringWithFormat:@"%@",[self dealTime:video.currentTime]];
            self.slider.value = video.currentTime;
            [video seekTime:panPoint.x / 10];
        }
    }
}


#pragma mark     ------------------------ 横屏代理 --------------------------
- (BOOL)shouldAutorotate{
    return YES;
}
-(UIInterfaceOrientationMask)supportedInterfaceOrientations{
    return UIInterfaceOrientationMaskLandscape;
}

#pragma mark     ------------------------ 微信分享 --------------------------
- (void)wxfShareBtnAction:(UIButton *)sender {
    [self isShareToPengyouquan:NO];
}
- (void)wxShareBtnAction:(UIButton *)sender {
    [self isShareToPengyouquan:YES];
}
-(void)loginSuccessByCode:(NSString *)code{
    NSLog(@"code %@",code);
    __weak typeof(*&self) weakSelf = self;
    
    NSURL *url = [NSURL URLWithString: [NSString stringWithFormat:@"https://api.weixin.qq.com/sns/oauth2/access_token?appid=%@&secret=%@&code=%@&grant_type=authorization_code",URL_APPID,URL_SECRET,code]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        NSLog(@"dic %@",dic);
        
        NSString* accessToken=[dic valueForKey:@"access_token"];
        NSString* openID=[dic valueForKey:@"openid"];
        [weakSelf requestUserInfoByToken:accessToken andOpenid:openID];
    }];
    [dataTask resume];
}
-(void)requestUserInfoByToken:(NSString *)token andOpenid:(NSString *)openID{
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.weixin.qq.com/sns/userinfo?access_token=%@&openid=%@",token,openID]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *dic = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        //开发人员拿到相关微信用户信息后， 需要与后台对接，进行登录
        NSLog(@"login success dic  ==== %@",dic);
    }];
    [dataTask resume];
}
-(void)isShareToPengyouquan:(BOOL)isPengyouquan{
    
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *filePath = [doc stringByAppendingPathComponent:[NSString stringWithFormat:@"cutImage.png"]];// 保存文件的名称
    
    UIImage *image = [UIImage imageWithContentsOfFile:filePath];
    WXMediaMessage *message = [WXMediaMessage message];
    message.title = @"分享内容";
    message.description = @"详细信息";
    //png图片压缩成data的方法，如果是jpg就要用 UIImageJPEGRepresentation
    message.thumbData = UIImagePNGRepresentation(image);
    [message setThumbImage:image];
    
    
    WXImageObject *img = [WXImageObject object];
    img.imageData = [NSData dataWithContentsOfFile:filePath];
    message.mediaObject = img;
    
    SendMessageToWXReq *sentMsg = [[SendMessageToWXReq alloc]init];
    sentMsg.message = message;
    sentMsg.bText = NO;
    //选择发送到会话(WXSceneSession)或者朋友圈(WXSceneTimeline)
    if (isPengyouquan) {
        sentMsg.scene = WXSceneTimeline;  //分享到朋友圈
    }else{
        sentMsg.scene =  WXSceneSession;  //分享到会话。
    }
    
    //如果我们想要监听是否成功分享，我们就要去appdelegate里面 找到他的回调方法
    // -(void) onResp:(BaseResp*)resp .我们可以自定义一个代理方法，然后把分享的结果返回回来。
    _appdelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    _appdelegate.wxDelegate = self;
    [WXApi sendReq:sentMsg];
    
}
-(void)shareSuccessByCode:(int)code{
    UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"分享成功" message:nil delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"确定",nil];
    [alert show];
}

#pragma mark     ------------------------ tableView --------------------------
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataSourceArr.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    static NSString *identifier = @"playlistcell";
    PlaylistCell *cell = [tableView dequeueReusableCellWithIdentifier:@"playlistcell" forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    if (cell == nil) {
        cell = [[PlaylistCell alloc]initWithStyle:UITableViewCellStyleDefault   reuseIdentifier:identifier];
    }
    [cell.iconView setImage:[UIImage imageNamed:@"example_11"]];
    [cell.nameLabel setText:self.dataSourceArr[indexPath.row]];
    [cell.typeLabel setText:@"中断语文"];
    
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    self.sliderFlag = YES;
    if (self.timer != nil) {
        [self.timer invalidate];
        self.timer = nil;
    }
    self.selectionsView.frame = CGRectZero;
    self.tableView.frame = CGRectZero;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.toggle_pauseBtn.tag == 200) {
        [UIView animateWithDuration:0.4 animations:^{
            self.toggle_pauseBtn.transform = CGAffineTransformRotate(self.toggle_pauseBtn.transform, M_PI);
            self.toggle_pauseBtn.tag = 100;
        } completion:^(BOOL finished) {
            [self.toggle_pauseBtn setBackgroundImage:[UIImage imageNamed:@"icon_play.png"] forState:UIControlStateNormal];
        }];
    }
    self.currentVideoName = self.dataSourceArr[indexPath.row];
    NSString *str = [[NSBundle mainBundle]pathForResource:self.currentVideoName ofType:NULL];
    self.video = [[XYQMovieObject alloc] initWithVideo:str];
    self.video.updateDelegate = self;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        //通知主线程刷新
        dispatch_async(dispatch_get_main_queue(), ^{
            self.timer = [NSTimer scheduledTimerWithTimeInterval: 1 target:self selector:@selector(displayNextFrame:) userInfo:nil repeats:YES];
        });
        // 处理耗时操作
        [video playNext];
    });
}

@end
