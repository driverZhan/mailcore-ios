//
//  ViewController.m
//  MDemo
//
//  Created by .77 on 2024/7/17.
//

#import "ViewController.h"
#import <MailCore/MailCore.h>

@interface ViewController ()

@property (nonatomic, strong) MCOIMAPSession *session;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
//    NSString *value = @"%E8%B6%85%E9%95%BF%E5%90%8D%E5%AD%97%E7%9A%84%E6%96%87%E6%A1%A3%E6%B5%8B%E8%AF%95%E6%B5%8B%E8%AF%95%E8%B6%85%E9%95%BF%E5%90%8D%E5%AD%97%E7%9A%84%E6%96%87%E6%A1%A3%E6%B5%8B%E8%AF%95%E6%B5%8B%E8%AF%95%E8%B6%85%E9%95%BF%E5%90%8D%E5%AD%97%E7%9A%84%E6%96%87%E6%A1%A3%E6%B5%8B%E8%AF%95%E6%B5%8B%E8%AF%95%E8%B6%85%E9%95%BF%E5%90%8D%E5%AD%97%E7%9A%84%E6%96%87%E6%A1%A3%E6%B5%8B%E8%AF%95%E6%B5%8B%E8%AF%95%E8%B6%85%E9%95%BF%E5%90%8D%E5%AD%97%E7%9A%84%E6%96%87%E6%A1%A3%E6%B5%8B%E8%AF%95%E6%B5%8B%E8%AF%95%E8%B6%85%E9%95%BF%E5%90%8D%E5%AD%97%E7%9A%84%E6%96%87%E6%A1%A3%E6%B5%8B%E8%AF%95%E6%B5%8B%E8%AF%95%E8%B6%85%E9%95%BF%E5%90%8D%E5%AD%97%E7%9A%84%E6%96%87%E6%A1%A3%E6%B5%8B%E8%AF%95%E6%B5%8B%E8%AF%95%E8%B6%85%E9%95%BF%E5%90%8D%E5%AD%97%E7%9A%84%E6%96%87%E6%A1%A3%E6%B5%8B%E8%AF%95%E6%B5%8B%E8%AF%95";
//    NSLog(@"%@",[self stringByURLDecode:value]);
    
}

- (NSString *)stringByURLDecode:(NSString *)value {
    if ([self respondsToSelector:@selector(stringByRemovingPercentEncoding)]) {
        return [value stringByRemovingPercentEncoding];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CFStringEncoding en = CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding);
        NSString *decoded = [value stringByReplacingOccurrencesOfString:@"+"
                                                            withString:@" "];
        decoded = (__bridge_transfer NSString *)
        CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
                                                                NULL,
                                                                (__bridge CFStringRef)decoded,
                                                                CFSTR(""),
                                                                en);
        return decoded;
#pragma clang diagnostic pop
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    MCOIndexSet *uid = [MCOIndexSet indexSet];
    [uid addIndex:76];
    [[self.session fetchMessagesOperationWithFolder:@"INBOX" requestKind:MCOIMAPMessagesRequestKindStructure uids:uid] start:^(NSError * _Nullable error, NSArray<MCOIMAPMessage *> * _Nullable messages, MCOIndexSet * _Nullable vanishedMessages) {
        if (error) {
            NSLog(@"%@",error);
            return;
        }
        
        for (MCOIMAPMessage *msg in messages) {
            
            [msg.attachments enumerateObjectsUsingBlock:^(MCOAbstractPart * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSLog(@"filename = %@",obj.filename);
            }];
//            [[self.session htmlBodyRenderingOperationWithMessage:msg folder:@"INBOX"] start:^(NSString * _Nullable htmlString, NSError * _Nullable error) {
//                if (error) {
//                    NSLog(@"%@",error);
//                    return;
//                }
//                NSLog(@"%@",htmlString);
//            }];
        }
        
    }];
//    [[self.session fetchAllFoldersOperation] start:^(NSError * _Nullable error, NSArray<MCOIMAPFolder *> * _Nullable folders) {
//
//    }];
}


- (MCOIMAPSession *)session {
    if (!_session) {
        _session = [[MCOIMAPSession alloc] init];
        _session.port = 993;
        _session.username = @"zz1@mail.starfronts.com";
        _session.password = @"qq123456.";
        _session.hostname = @"mail.starfronts.com";
        _session.voIPEnabled = NO;
        _session.checkCertificateEnabled = NO;
        _session.connectionType = MCOConnectionTypeTLS;
        _session.capabilityIdEnabled = NO;
        _session.connectionLogger = ^(void *connectionID, MCOConnectionLogType type, NSData *data) {
            NSLog(@"event logged:%p type:%ld withData: %@", connectionID, type, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        };
    }
    return _session;
}


@end
