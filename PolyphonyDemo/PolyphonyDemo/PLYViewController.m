//
//  PLYViewController.m
//  PolyphonyDemo
//
//  Created by Greg Curtis on 7/26/14.
//  Copyright (c) 2014 Polyphony. All rights reserved.
//

#import "PLYViewController.h"
#import "SRWebSocket.h"
#import "client.h"

@interface PLYViewController () <SRWebSocketDelegate>

@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

@implementation PLYViewController

static ot_client *client;
static UITextView *staticTextView;

static int client_event(ot_event_type t, ot_op* op) {
    if (t != OT_OP_APPLIED) {
        return 0;
    }
    
    size_t pos = 0;
    ot_comp* comps = op->comps.data;
    for (size_t i = 0; i < op->comps.len; ++i) {
        ot_comp* comp = comps + i;
        switch (comp->type) {
            case OT_SKIP:
                pos += comp->value.skip.count;
                break;
            case OT_INSERT:
            {
                ot_comp_insert insert = comp->value.insert;
                NSString* utf8String = [[NSString alloc] initWithUTF8String:insert.text];
                NSAttributedString *insertString = [[NSAttributedString alloc] initWithString:utf8String];
                [staticTextView.textStorage insertAttributedString:insertString atIndex:pos];
                pos += comp->value.skip.count;
                break;
            }
            case OT_DELETE:
            {
                ot_comp_delete delete = comp->value.delete;;
                NSRange range = NSMakeRange(pos, delete.count);
                [staticTextView.textStorage deleteCharactersInRange:range];
                break;
            }
            default:
                break;
        }
    }
    return 0;
}

static int client_send(const char* op) {
    return 0;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSURL *url = [[NSURL alloc] initWithString:@"ws://staging.polyphony-ot.com:8080"];
    SRWebSocket* socket = [[SRWebSocket alloc] initWithURL:url];
    socket.delegate = self;
    [socket open];

    staticTextView = self.textView;
    client = ot_new_client(client_send, client_event, 0);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    NSLog(@"Received \"%@\"", message);

    if (client->client_id == 0) {
        NSData *jsonData = [message dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:nil];
        client->client_id = [[dict valueForKey:@"clientId"] intValue];

        NSString *lastOp = [dict valueForKey:@"lastOp"];
        if (lastOp != nil) {
            ot_client_receive(client, [lastOp UTF8String]);
        }

        return;
    }

    ot_client_receive(client, [message UTF8String]);
}

@end
