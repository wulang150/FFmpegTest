//
//  MuxVideoViewController.m
//  FFmpegTest
//
//  Created by Anker on 2019/3/15.
//  Copyright © 2019 Anker. All rights reserved.
//

#import "MuxVideoViewController.h"
#include <libavutil/avassert.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libavutil/mathematics.h>
#include <libavutil/timestamp.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

#define STREAM_DURATION   10.0
#define STREAM_FRAME_RATE 15 /* 25 images/s */
#define STREAM_PIX_FMT    AV_PIX_FMT_YUV420P /* default pix_fmt */
#define SCALE_FLAGS SWS_BICUBIC
#define Base_TB (AVRational){1, 15}

static void log_packet(AVRational *time_base, const AVPacket *pkt, const char *tag)
{
//    AVRational *time_base = &fmt_ctx->streams[pkt->stream_index]->time_base;
    printf("%s: pts:%s pts_time:%s dts:%s dts_time:%s duration:%s duration_time:%s stream_index:%d\n",
           tag,
           av_ts2str(pkt->pts), av_ts2timestr(pkt->pts, time_base),
           av_ts2str(pkt->dts), av_ts2timestr(pkt->dts, time_base),
           av_ts2str(pkt->duration), av_ts2timestr(pkt->duration, time_base),
           pkt->stream_index);
}

static void log_packet1(AVRational *time_base, const AVFrame *pkt, const char *tag)
{
    printf("%s: pts:%s pts_time:%s dts:%s dts_time:%s duration:%s duration_time:%s\n",
           tag,
           av_ts2str(pkt->pts), av_ts2timestr(pkt->pts, time_base),
           av_ts2str(pkt->pkt_dts), av_ts2timestr(pkt->pkt_dts, time_base),
           av_ts2str(pkt->pkt_duration), av_ts2timestr(pkt->pkt_duration, time_base));
   
}

@interface MuxVideoViewController ()
{
    NSInteger nPkt1, nPkt2, pkt1_size, pkt2_size;
    FILE *f;
    //解封装
    AVFormatContext *ifmt_ctx;       //输入格式上下文
    int in_stream_video;        //输入格式的视频流序号
    int in_stream_audio;
    //解码的
    AVCodec *de_Codec;
    AVCodecContext *de_CodecCtx;
    AVFrame *de_frame;
    //编码
    AVCodec *en_Codec;
    AVCodecContext *en_CodecCtx;
    AVPacket *en_pkt;
    //封装
    AVFormatContext *ofmt_ctx;
    AVStream *videoStream;
    AVCodecContext *muxEnCodecCtx;
    
    int width,height;
    
}
@end

@implementation MuxVideoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"MuxVideoViewController";
    in_stream_video = -1;
    in_stream_audio = -1;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [self mainFunc];
}

- (int)mainFunc{
    av_register_all();
    avcodec_register_all();
    //解封装mp4->H264
    [self demuxVideo:^(AVPacket pkt) {
        [self decodeVide:&pkt callBack:nil];
    }];
    NSLog(@"执行下面的，解码最后剩下的帧");
    if(in_stream_video>=0){
       [self decodeVide:NULL callBack:nil];
    }
    
    if(ofmt_ctx){
        av_write_trailer(ofmt_ctx);
    }
    [self destroy];
    
    NSLog(@"pkt1=%zi size1=%zi pkt2=%zi size2=%zi",nPkt1,pkt1_size,nPkt2,pkt2_size);
    return 1;
}

- (void)destroy{
    if(f){
        fclose(f);
    }
    if(ifmt_ctx){
        avformat_close_input(&ifmt_ctx);
    }
    if(de_CodecCtx){
        avcodec_free_context(&de_CodecCtx);
    }
    if(de_frame){
        av_frame_free(&de_frame);
    }
    if(en_CodecCtx){
        avcodec_free_context(&en_CodecCtx);
    }
    if(en_pkt){
        av_packet_free(&en_pkt);
    }
    if(muxEnCodecCtx){
        avcodec_free_context(&muxEnCodecCtx);
    }
    if(ofmt_ctx){
        if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE))
        /* Close the output file. */
            avio_closep(&ofmt_ctx->pb);
        avformat_free_context(ofmt_ctx);
    }
    
}
//解封装，返回视频流的packet 解封装mp4->H264
- (int)demuxVideo:(void(^)(AVPacket pkt))callBack{
    int ret, i;
    NSString *filePath = [CommonFunc getDocumentWithFile:@"movie.mp4"];
    const char *in_filename = [filePath cStringUsingEncoding:NSASCIIStringEncoding];
    if ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0) {
        fprintf(stderr, "Could not open input file '%s'", in_filename);
        return 0;
    }
    if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
        fprintf(stderr, "Failed to retrieve input stream information");
        return 0;
    }
    av_dump_format(ifmt_ctx, 0, in_filename, 0);
    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVCodecParameters *in_codecpar = in_stream->codecpar;
        if(in_codecpar->codec_type==AVMEDIA_TYPE_VIDEO){
            in_stream_video = i;
        }
        if(in_codecpar->codec_type==AVMEDIA_TYPE_AUDIO){
            in_stream_audio = 1;
        }
    }
    //读取每个packet
    AVPacket pkt;
    while (1) {
        ret = av_read_frame(ifmt_ctx, &pkt);
        if (ret < 0)
            break;
        nPkt1 ++;
        pkt1_size += pkt.size;
        if(callBack){
            callBack(pkt);
        }
//        AVStream *in_stream  = ifmt_ctx->streams[pkt.stream_index];
//        log_packet(&in_stream->time_base, &pkt, "in_pkt");
        //如果一开始就改变
        
        av_packet_unref(&pkt);
    }
    return 1;
}

//解码H264->YUV
- (int)decodeVide:(AVPacket *)pkt callBack:(void(^)(AVFrame frame))callBack{
    if(!de_Codec){
        de_Codec = avcodec_find_decoder(AV_CODEC_ID_H264);
        if (!de_Codec) {
            fprintf(stderr, "deCodec not found\n");
            return 0;
        }
    }
    if(!de_CodecCtx){
        de_CodecCtx = avcodec_alloc_context3(de_Codec);
        if (!de_CodecCtx) {
            fprintf(stderr, "Could not allocate video decodec context\n");
            return 0;
        }
        //这里是解AVCC格式的H264，不是Annex-B格式的，需要知道的参数比较多，比如extradata，要不，根本解不出每个nal
        AVStream *in_stream = ifmt_ctx->streams[in_stream_video];
        de_CodecCtx->pix_fmt = STREAM_PIX_FMT;
        //这个extradata才是最重要的，从这里才可以拿到解码相关的信息，其实就是怎么拿到每一个nal
        de_CodecCtx->extradata_size = in_stream->codecpar->extradata_size;
//        de_CodecCtx->extradata = in_stream->codecpar->extradata;
        de_CodecCtx->extradata = malloc(de_CodecCtx->extradata_size);
        memcpy(de_CodecCtx->extradata, in_stream->codecpar->extradata, de_CodecCtx->extradata_size);
        //也可以用下面的方法
//         Copy codec parameters from input stream to output codec context
//        if (avcodec_parameters_to_context(de_CodecCtx, in_stream->codecpar) < 0) {
//            fprintf(stderr, "Failed to copy codec parameters to decoder context\n");
//            return 0;
//        }
        if (avcodec_open2(de_CodecCtx, de_Codec, NULL) < 0) {
            fprintf(stderr, "Could not open codec\n");
            return 0;
        }
        //不能使用局部变量，avcodec_receive_frame函数可以的多次访问他
        //AVFrame frame;
        if(!de_frame){
            de_frame = av_frame_alloc();
            if (!de_frame) {
                fprintf(stderr, "Could not allocate video frame\n");
                return 0;
            }
        }
    }
    int ret = -1;
    //开始解码，没配置宽高，执行完avcodec_send_packet这个后也可以获得
    ret = avcodec_send_packet(de_CodecCtx, pkt);
    if (ret < 0) {
        fprintf(stderr, "Error sending a packet for decoding\n");
        return 0;
    }
    while (ret >= 0) {
        ret = avcodec_receive_frame(de_CodecCtx, de_frame);
        //解码成功，但是还没够frame返回，需要继续添加pkt
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF){
            if(ret==AVERROR_EOF){
                NSLog(@"所有都解码完成，返回空告诉外界");
                [self decodeSucc:NULL];
            }
            return 1;
        }
        else if (ret < 0) {
            fprintf(stderr, "Error during decoding\n");
            return 0;
        }
        
        //修改解码后的参数，转换为我们常见的pts是0 1 2
        de_frame->pts = av_rescale_q(de_frame->pts, ifmt_ctx->streams[in_stream_video]->time_base, Base_TB);
        de_frame->pkt_duration = av_rescale_q(de_frame->pkt_duration, ifmt_ctx->streams[in_stream_video]->time_base, Base_TB);
        de_frame->pkt_dts = av_rescale_q(de_frame->pkt_dts, ifmt_ctx->streams[in_stream_video]->time_base, Base_TB);
        
        //这里解码后的AVFrame
        log_packet1(&(Base_TB), de_frame, "decode");
        [self decodeSucc:de_frame];
    }
    return 1;
}

//编码YUV->H264
- (void)encodeVideo:(AVFrame *)frame{
    int ret = -1;
    if(!en_Codec){
        en_Codec = avcodec_find_encoder(AV_CODEC_ID_H264);
        if (!en_Codec) {
            fprintf(stderr, "enCodec not found\n");
            return;
        }
    }
    if(!en_CodecCtx){
        en_CodecCtx = avcodec_alloc_context3(en_Codec);
        if(!en_CodecCtx){
            fprintf(stderr, "en_CodecCtx not found\n");
            return;
        }
        //编码后的大小，跟bit_rate与time_base有关
        AVStream *in_stream = ifmt_ctx->streams[in_stream_video];
        /* put sample parameters */
        en_CodecCtx->bit_rate = in_stream->codecpar->bit_rate;
        /* resolution must be a multiple of two */
        width = frame->width;
        height = frame->height;
        en_CodecCtx->width = width;
        en_CodecCtx->height = height;
        /* frames per second */
        en_CodecCtx->time_base = Base_TB;

//        en_CodecCtx->gop_size = 30;
//        en_CodecCtx->max_b_frames = 1;        //如果有B帧，编码需接收全部的AVFrame才会进行统一编码
        en_CodecCtx->pix_fmt = frame->format;
//        if (en_Codec->id == AV_CODEC_ID_H264)
//            av_opt_set(en_CodecCtx->priv_data, "preset", "slow", 0);
//        en_CodecCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
        /* open it */
        ret = avcodec_open2(en_CodecCtx, en_Codec, NULL);
        if (ret < 0) {
            fprintf(stderr, "Could not open codec: %s\n", av_err2str(ret));
            return;
        }
    }
    if(!en_pkt){
        en_pkt = av_packet_alloc();
        if(!en_pkt){
            return;
        }
    }
    
    //开始编码
    /* send the frame to the encoder */
    ret = avcodec_send_frame(en_CodecCtx, frame);
    if (ret < 0) {
        fprintf(stderr, "Error sending a frame for encoding\n");
        return;
    }
    
    while (ret >= 0) {
        ret = avcodec_receive_packet(en_CodecCtx, en_pkt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        else if (ret < 0) {
            fprintf(stderr, "Error during encoding\n");
            return;
        }
//        printf("Write packet %3"PRId64" (size=%5d)\n", en_pkt->pts, en_pkt->size);
        [self encodeSucc:en_pkt];
        av_packet_unref(en_pkt);
    }
}

- (AVCodecContext *)getMuxEnCodecContext:(enum AVCodecID)codec_id{
    if(!muxEnCodecCtx){
        AVCodec *codec = avcodec_find_encoder(codec_id);
        if (!codec) {
            fprintf(stderr, "enCodec not found\n");
            return NULL;
        }
        muxEnCodecCtx = avcodec_alloc_context3(codec);
        if(!muxEnCodecCtx){
            fprintf(stderr, "en_CodecCtx not found\n");
            return NULL;
        }
//        AVStream *in_stream = ifmt_ctx->streams[in_stream_video];
        /* put sample parameters */
//        muxEnCodecCtx->bit_rate = in_stream->codecpar->bit_rate;
        /* resolution must be a multiple of two */
        muxEnCodecCtx->width = 960;
        muxEnCodecCtx->height = 540;
        if(width>0){
            muxEnCodecCtx->width = width;
        }
        if(height>0){
            muxEnCodecCtx->height = height;
        }
        //在这里配置好像没用，只有在封装中，才可以改变帧率
        muxEnCodecCtx->time_base = (AVRational){1, 15};
        //2倍的速度播放
//        muxEnCodecCtx->time_base = (AVRational){1, 30};

        muxEnCodecCtx->pix_fmt = STREAM_PIX_FMT;        //这个必须添加，要不然会导致avcodec_open2失败
//        muxEnCodecCtx->gop_size = 12;
        //mp4一定要配这个，并且得在avcodec_open2前添加，要不然，就只有黑屏
        /* Some formats want stream headers to be separate. */
        if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
            muxEnCodecCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
//        if (codec->id == AV_CODEC_ID_H264)
//            av_opt_set(en_CodecCtx->priv_data, "preset", "slow", 0);
        /* open it */
        int ret = -1;
        ret = avcodec_open2(muxEnCodecCtx, codec, NULL);
        if (ret < 0) {
            fprintf(stderr, "Could not open codec: %s\n", av_err2str(ret));
            return NULL;
        }
    }
    return muxEnCodecCtx;
}
//封装H264->mp4
- (void)muxVideo:(AVPacket *)pkt{
    const char *filename;
    int ret = -1;
    if(!ofmt_ctx){
        NSString *filePath = [CommonFunc getDefaultPath:@"movieOut.mp4"];
        filename = [filePath cStringUsingEncoding:NSASCIIStringEncoding];
        avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, filename);
        if(!ofmt_ctx){
            printf("Could not ofmt_ctx output format\n");
            exit(0);
        }
        if(ofmt_ctx->oformat->video_codec==AV_CODEC_ID_NONE){
            exit(0);
        }
    }
    //创建流
    if(!videoStream){
        //配置编码ctx
//        AVCodecContext *codecCtx = [self getMuxEnCodecContext:ofmt_ctx->oformat->video_codec];
//        AVCodecContext *codecCtx = ifmt_ctx->streams[in_stream_video]->codec;
        AVCodecContext *codecCtx = [self getMuxEnCodecContext:AV_CODEC_ID_H264];
//        AVCodecContext *codecCtx = en_CodecCtx;
        
        if(codecCtx==NULL){
            return;
        }
        videoStream = avformat_new_stream(ofmt_ctx, NULL);
        if(!videoStream){
            fprintf(stderr, "Could not allocate stream\n");
            exit(0);
        }
        /* copy the stream parameters to the muxer */
    //这样关联的话，释放的时候，如果先释放en_CodecCtx，再释放ofmt_ctx就会出错，估计释放ofmt_ctx时候会同时释放en_CodecCtx，所以被弃用也是有原因的
//        videoStream->codec = en_CodecCtx;
//        videoStream->time_base = ifmt_ctx->streams[in_stream_video]->time_base;
        //增大timeBase，那么每个pts转为时间，都会缩小，其实控制视频总时间，不是通过改变帧率的，因为每个pts，dts都有了对应的值，都可以根据timeBase转为对应的时间，所以通过改变timebase，才可以操作pts最后的值
//        videoStream->time_base = (AVRational){1, videoStream->time_base.den*2};
        videoStream->time_base = codecCtx->time_base;
        ret = avcodec_parameters_from_context(videoStream->codecpar, codecCtx);
//        ret = avcodec_parameters_copy(videoStream->codecpar, ifmt_ctx->streams[in_stream_video]->codecpar);
        if (ret < 0) {
            fprintf(stderr, "Could not copy the stream parameters\n");
            return;
        }
        //打开输出的文件
        av_dump_format(ofmt_ctx, 0, filename, 1);
        /* open the output file, if needed */
        if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
            ret = avio_open(&ofmt_ctx->pb, filename, AVIO_FLAG_WRITE);
            if (ret < 0) {
                fprintf(stderr, "Could not open '%s': %s\n", filename,
                        av_err2str(ret));
                return;
            }
        }
        /* Write the stream header, if any. */
        //执行这个之后，videoStream->time_base会自动修改为正常的值，小于15360，都会改为15360
        ret = avformat_write_header(ofmt_ctx, NULL);
        if (ret < 0) {
            fprintf(stderr, "Error occurred when opening output file: %s\n",
                    av_err2str(ret));
            return;
        }
    }
    
    //转换时间
//    av_packet_rescale_ts(pkt, ifmt_ctx->streams[in_stream_video]->time_base, videoStream->time_base);
    //写入之前进行一次转换，codecCtx的timeBase转为stream的timeBase
    av_packet_rescale_ts(pkt, muxEnCodecCtx->time_base, videoStream->time_base);
    log_packet(&videoStream->time_base, pkt, "mux");
    av_interleaved_write_frame(ofmt_ctx, pkt);
    
}

#pragma -mark callback
//解码成功的返回
- (void)decodeSucc:(AVFrame *)frame{
    //进行编码
    [self encodeVideo:frame];
}
//编码成功后的返回
- (void)encodeSucc:(AVPacket *)pkt{
    nPkt2++;
    pkt2_size += pkt->size;
    //这里的time_base还是继承了AVFrame的time_base，如果只是裸流倒是无所谓，如果要合成视频，就得参考ctx->time_base了
//    log_packet(&(ifmt_ctx->streams[in_stream_video]->time_base), pkt, "encode");
    //写到文件
//    if(f==NULL){
//        NSString *filePath = [CommonFunc getDefaultPath:@"movie.h264"];
//        const char *filename = [filePath cStringUsingEncoding:NSASCIIStringEncoding];
//        f = fopen(filename, "wb");
//    }
    //    fwrite(pkt->data, 1, pkt->size, f);
    
    //这里，我改变pkt.pts等值，转出正常的1,2,3等值，最后在封装的时候，还得转回来，因为流的timebase至少在(AVRational){1, 15360}以上
//    AVRational time_base = (AVRational){1, 15};
//    av_packet_rescale_ts(pkt, (ifmt_ctx->streams[in_stream_video]->time_base), time_base);
    //这里测试下不连接帧的现象，就是5秒后的全增加一秒。现象是，视频总长度多了1秒，5秒后停了1秒，再继续播放
//    if(pkt->pts>15*5){
//        pkt->pts = pkt->pts + 15;
//        pkt->dts = pkt->pts;
//    }
    log_packet(&(Base_TB), pkt, "encode");
////    //进行封装成mp4
    [self muxVideo:pkt];
}

@end
