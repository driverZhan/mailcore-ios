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
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [[self.session fetchMessagesOperationWithFolder:@"INBOX" requestKind:MCOIMAPMessagesRequestKindStructure uids:[MCOIndexSet indexSetWithRange:MCORangeMake(1, UINT64_MAX)]] start:^(NSError * _Nullable error, NSArray<MCOIMAPMessage *> * _Nullable messages, MCOIndexSet * _Nullable vanishedMessages) {
            
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
