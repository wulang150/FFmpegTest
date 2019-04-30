//
//  CommonFunc.m
//  FFmpegTest
//
//  Created by Anker on 2019/3/6.
//  Copyright © 2019 Anker. All rights reserved.
//

#import "CommonFunc.h"

@implementation CommonFunc

+ (NSString *)getDocumentWithFile:(NSString *)filename{
    NSString *documentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    char ss = [documentsDirectory characterAtIndex:0];
    if(ss=='/')
    {
        documentsDirectory = [documentsDirectory substringFromIndex:1];
    }
    
    return [NSString stringWithFormat:@"%@/%@",documentsDirectory,filename];
}

+ (NSString *)getDefaultPath:(NSString *)defaultPath
{
    NSString *documentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    char ss = [documentsDirectory characterAtIndex:0];
    if(ss=='/')
    {
        documentsDirectory = [documentsDirectory substringFromIndex:1];
    }
    
    if(defaultPath.length<=0)
        return documentsDirectory;
    NSDate *date = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH_mm_ss"];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]];
    NSString *dateString = [formatter stringFromDate:date];
    defaultPath = [NSString stringWithFormat:@"%@_%@",dateString,defaultPath];
    return [NSString stringWithFormat:@"%@/%@",documentsDirectory,defaultPath];
}

+ (void)createFile:(NSString *)filePath{
    [self createFolderByFilePath:filePath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if([fileManager fileExistsAtPath:filePath]){
        return;
    }
    
    [fileManager createFileAtPath:filePath contents:nil attributes:nil];
}

+ (void)createFolderByFilePath:(NSString *)filePath{
    if(filePath==nil||filePath.length==0)
        return;
    
    char ss = [filePath characterAtIndex:filePath.length-1];
    if(ss=='/')
    {
        filePath = [filePath substringToIndex:filePath.length-1];
    }
    //取出文件路径
    NSRange range = [filePath rangeOfString:@"/" options:NSBackwardsSearch];
    if(range.length<=0)
        return;
    NSString *folderPath = [filePath substringToIndex:range.location];
    
    if(folderPath==nil||folderPath.length==0)
        return;
    //文件夹不存在，就创建文件夹
    if (![[NSFileManager defaultManager] fileExistsAtPath:folderPath]) {
        NSLog(@"folderPath = %@",folderPath);
        BOOL ret = [[NSFileManager defaultManager] createDirectoryAtPath:folderPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
}
@end
