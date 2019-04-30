//
//  CommonFunc.h
//  FFmpegTest
//
//  Created by Anker on 2019/3/6.
//  Copyright © 2019 Anker. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CommonFunc : NSObject

+ (NSString *)getDocumentWithFile:(NSString *)filename;

+ (NSString *)getDefaultPath:(NSString *)defaultPath;

+ (void)createFile:(NSString *)filePath;
@end

NS_ASSUME_NONNULL_END
