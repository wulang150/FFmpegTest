//
//  DecoderViewController.m
//  FFmpegTest
//
//  Created by Anker on 2019/3/11.
//  Copyright © 2019 Anker. All rights reserved.
//

#import "DecoderViewController.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>

#define INBUF_SIZE 4096

static AVFrame *pFrameYUV;
static struct SwsContext *img_convert_ctx;

@interface DecoderViewController ()

@end

@implementation DecoderViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"解码";
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [self mainFunc];
}

static AVFrame *alloc_picture(enum AVPixelFormat pix_fmt, int width, int height)
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

static void pgm_save(AVFrame *frame, FILE *f)
{
    //进行转码操作，转成yuv420
    if(frame->format!=AV_PIX_FMT_YUV420P){
        if(!pFrameYUV){
            pFrameYUV = alloc_picture(AV_PIX_FMT_YUV420P, frame->width, frame->height);
        }
        if(!img_convert_ctx){
            //转码器
            img_convert_ctx = sws_getContext(frame->width, frame->height,
                                             frame->format,
                                             pFrameYUV->width, pFrameYUV->height,
                                             AV_PIX_FMT_YUV420P,
                                             SWS_BICUBIC, NULL, NULL, NULL);
        }
        sws_scale(img_convert_ctx, (const uint8_t* const*)frame->data, frame->linesize, 0, frame->height,
                                    pFrameYUV->data, pFrameYUV->linesize);
        frame = pFrameYUV;
    }
    printf("fmx=%d size=%dx%d\n",frame->format,frame->width,frame->height);
    int i;
    //Y
    int width = MIN(frame->linesize[0], frame->width);
    for(i=0;i<frame->height;i++)
    {
        fwrite(frame->data[0]+i*frame->linesize[0], 1, width, f);
    }
    //u
    width = MIN(frame->linesize[1], frame->width/2);
    for(i=0;i<frame->height/2;i++)
    {
        fwrite(frame->data[1]+i*frame->linesize[1], 1, width, f);
    }
    //v
    width = MIN(frame->linesize[2], frame->width/2);
    for(i=0;i<frame->height/2;i++)
    {
        fwrite(frame->data[2]+i*frame->linesize[2], 1, width, f);
    }
}

static void decode(AVCodecContext *dec_ctx, AVFrame *frame, AVPacket *pkt,
                   FILE *f)
{
//    char buf[1024];
    int ret;
    ret = avcodec_send_packet(dec_ctx, pkt);
    if (ret < 0) {
        fprintf(stderr, "Error sending a packet for decoding\n");
        exit(1);
    }
    while (ret >= 0) {
        ret = avcodec_receive_frame(dec_ctx, frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        else if (ret < 0) {
            fprintf(stderr, "Error during decoding\n");
            exit(1);
        }
        fflush(stdout);
        printf("saving frame %3d ",dec_ctx->frame_number);
        pgm_save(frame, f);
    }
}

- (int)mainFunc{
    av_register_all();
    avcodec_register_all();
    
    const char *filename, *outfilename;
    const AVCodec *codec;
    AVCodecParserContext *parser;
    AVCodecContext *c= NULL;
    FILE *f, *outF;
    AVFrame *frame;
    uint8_t inbuf[INBUF_SIZE + AV_INPUT_BUFFER_PADDING_SIZE];
    uint8_t *data;
    size_t   data_size;
    int ret;
    AVPacket *pkt;
    
    //input
    NSString *filePath = [CommonFunc getDocumentWithFile:@"movieH264.ts"];
    filename = [filePath cStringUsingEncoding:NSASCIIStringEncoding];
    //output
    filePath = [CommonFunc getDefaultPath:@"movie.yuv"];
    outfilename = [filePath cStringUsingEncoding:NSASCIIStringEncoding];
    
    pkt = av_packet_alloc();
    if (!pkt)
        exit(1);
    /* set end of buffer to 0 (this ensures that no overreading happens for damaged MPEG streams) */
    memset(inbuf + INBUF_SIZE, 0, AV_INPUT_BUFFER_PADDING_SIZE);
    /* find video decoder */
    codec = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!codec) {
        fprintf(stderr, "Codec not found\n");
        exit(1);
    }
    parser = av_parser_init(codec->id);
    if (!parser) {
        fprintf(stderr, "parser not found\n");
        exit(1);
    }
    c = avcodec_alloc_context3(codec);
    if (!c) {
        fprintf(stderr, "Could not allocate video codec context\n");
        exit(1);
    }
//    c->pix_fmt = AV_PIX_FMT_YUV420P;
    /* For some codecs, such as msmpeg4 and mpeg4, width and height
     MUST be initialized there because this information is not
     available in the bitstream. */
    /* open it */
    if (avcodec_open2(c, codec, NULL) < 0) {
        fprintf(stderr, "Could not open codec\n");
        exit(1);
    }
    f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "Could not open %s\n", filename);
        exit(1);
    }
    outF = fopen(outfilename, "wb");
    if (!outF) {
        fprintf(stderr, "Could not open %s\n", outfilename);
        exit(1);
    }
    frame = av_frame_alloc();
    if (!frame) {
        fprintf(stderr, "Could not allocate video frame\n");
        exit(1);
    }
    while (!feof(f)) {
        /* read raw data from the input file */
        data_size = fread(inbuf, 1, INBUF_SIZE, f);
        if (!data_size)
            break;
        /* use the parser to split the data into frames */
        data = inbuf;
        while (data_size > 0) {
            //相当于在annex-b格式的流中拆出每一个nal，可能得多次操作才有一个完整的pkt出来
            ret = av_parser_parse2(parser, c, &pkt->data, &pkt->size,
                                   data, (int)data_size, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
            if (ret < 0) {
                fprintf(stderr, "Error while parsing\n");
                exit(1);
            }
            data      += ret;
            data_size -= ret;
            if (pkt->size)
                decode(c, frame, pkt, outF);
        }
    }
    /* flush the decoder */
    decode(c, frame, NULL, outF);
    fclose(f);
    fclose(outF);
    sws_freeContext(img_convert_ctx);
    av_parser_close(parser);
    avcodec_free_context(&c);
    av_frame_free(&frame);
    av_frame_free(&pFrameYUV);
    av_packet_free(&pkt);
    return 0;
}

@end
