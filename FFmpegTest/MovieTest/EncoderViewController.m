//
//  EncoderViewController.m
//  FFmpegTest
//
//  Created by Anker on 2019/3/8.
//  Copyright © 2019 Anker. All rights reserved.
//

#import "EncoderViewController.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>

@interface EncoderViewController ()
{
    AVPacket *pkt;
    AVFrame *frame;
    AVCodecContext *codecCtx;
//    AVCodec *codec;
    NSInteger allSize;
}
@end

@implementation EncoderViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"编码";

}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [self mainFunc];
}

- (void)mainFunc{
    av_register_all();
    avcodec_register_all();
    
    FILE *f;
//    uint8_t endcode[] = { 0, 0, 1, 0xb7 };
    NSString *filePath = [CommonFunc getDefaultPath:@"movie.h264"];
    const char *filename = [filePath cStringUsingEncoding:NSASCIIStringEncoding];
    //保存的文件
    f = fopen(filename, "wb");
    if (!f) {
        fprintf(stderr, "Could not open %s\n", filename);
        exit(1);
    }
    //分辨率
    int width = 1600, height = 1200;
    pkt = av_packet_alloc();
    if(!pkt){
        return;
    }
    frame = alloc_picture(AV_PIX_FMT_YUV420P, width, height);
    if(frame==NULL){
        return;
    }
    //创建编码上下文
    codecCtx = [self findEncoder:frame];
    if(codecCtx==NULL){
        return;
    }
    
    [self readYUV:width height:height callback:^(AVFrame *tframe) {
        [self yuv420ToH264:tframe codeCtx:self->codecCtx callBack:^(AVPacket *pkt) {
            fwrite(pkt->data, 1, pkt->size, f);
        }];
    }];
    
    NSLog(@">>>>>begin!!!!!");
    [self yuv420ToH264:NULL codeCtx:codecCtx callBack:^(AVPacket *pkt) {
        fwrite(pkt->data, 1, pkt->size, f);
    }];
    NSLog(@">>>>>end allSize=%.2fKB",allSize/1024.0);
    
    //结尾处理
    /* add sequence end code to have a real MPEG file */
//    fwrite(endcode, 1, sizeof(endcode), f);
    fclose(f);
    avcodec_free_context(&codecCtx);
    av_frame_free(&frame);
    av_packet_free(&pkt);
}

- (void)readYUV:(int)width height:(int)height callback:(void(^)(AVFrame *tframe))callBack{
    //读取yuv数据
    NSString *yuvPath = [CommonFunc getDocumentWithFile:@"11_23_07_movie.yuv"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:yuvPath]){
        NSLog(@"file error!");
        return;
    }
    FILE *fp=fopen([yuvPath UTF8String],"rb+");
    unsigned char *pic=(unsigned char *)malloc(width*height*3/2);
    int i = 0;
    while (true)
    {
        unsigned long ret = fread(pic,1,width*height*3/2,fp);
        if(ret<width*height*3/2){
            break;
        }
        memcpy(frame->data[0], pic, width*height);
        //        frame->linesize[0] = width;
        memcpy(frame->data[1], pic+width*height, width*height/4);
        //        frame->linesize[1] = width/2;
        memcpy(frame->data[2], pic+width*height*5/4, width*height/4);
        //        frame->linesize[2] = width/2;
        frame->pts = i++;
        
        if(callBack){
            callBack(frame);
        }
    }
    
    free(pic);
    fclose(fp);
}

AVFrame *alloc_picture(enum AVPixelFormat pix_fmt, int width, int height)
{
    AVFrame *picture;
    int ret;
    picture = av_frame_alloc();
    if (!picture)
        return NULL;
    picture->format = pix_fmt;
    picture->width  = width;
    picture->height = height;
    /* allocate the buffers for the frame data */
    ret = av_frame_get_buffer(picture, 32);
    if (ret < 0) {
        fprintf(stderr, "Could not allocate frame data.\n");
        return NULL;
    }
    return picture;
}
//找到生产对应的编码器
- (AVCodecContext *)findEncoder:(AVFrame *)frame{
    AVCodecContext *c= NULL;
    int ret = -1;
    AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_H264);
    if (!codec) {
        fprintf(stderr, "Codec not found\n");
        return c;
    }
    c = avcodec_alloc_context3(codec);
    if (!c) {
        fprintf(stderr, "Could not allocate video codec context\n");
        return c;
    }
    /* put sample parameters */
    c->bit_rate = 900000;
    /* resolution must be a multiple of two */
    c->width = frame->width;
    c->height = frame->height;
    /* frames per second */
    c->time_base = (AVRational){1, 15};
//    c->framerate = (AVRational){15, 1};
    /* emit one intra frame every ten frames
     * check frame pict_type before passing frame
     * to encoder, if frame->pict_type is AV_PICTURE_TYPE_I
     * then gop_size is ignored and the output of encoder
     * will always be I frame irrespective to gop_size
     */
    c->gop_size = 30;
    c->max_b_frames = 0;
    c->pix_fmt = frame->format;
//    if (codec->id == AV_CODEC_ID_H264)
//        av_opt_set(c->priv_data, "preset", "slow", 0);
    /* open it */
    ret = avcodec_open2(c, codec, NULL);
    if (ret < 0) {
        fprintf(stderr, "Could not open codec: %s\n", av_err2str(ret));
        return NULL;
    }
    return c;
}

- (void)yuv420ToH264:(AVFrame *)frame codeCtx:(AVCodecContext *)codecCtx callBack:(void(^)(AVPacket *enPkt))callBack{
    if(codecCtx==NULL){
        return;
    }
    int ret;
    /* send the frame to the encoder */
    ret = avcodec_send_frame(codecCtx, frame);
    if (ret < 0) {
        fprintf(stderr, "Error sending a frame for encoding\n");
        return;
    }
    if (frame)
        printf("Send frame %3"PRId64"\n", frame->pts);
    
    while (ret >= 0) {
        ret = avcodec_receive_packet(codecCtx, pkt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        else if (ret < 0) {
            fprintf(stderr, "Error during encoding\n");
            return;
        }
//        pkt->pts = pkt->dts = pkt->pts * (codecCtx->time_base.den) /codecCtx->time_base.num / 15;
        printf("Write packet pts=%lld dts=%lld (size=%5d)\n", pkt->pts, pkt->dts, pkt->size);
        allSize += pkt->size;
        if(callBack){
            callBack(pkt);
        }
        av_packet_unref(pkt);
    }
}


@end
