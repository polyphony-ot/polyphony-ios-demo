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

@interface PLYViewController () <SRWebSocketDelegate, NSTextStorageDelegate>

@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

@implementation PLYViewController

static ot_client *client;
static UITextView *staticTextView;
static SRWebSocket *websocket;

static int client_event(ot_event_type t, ot_op* op) {
    if (t != OT_OP_APPLIED) {
        return 0;
    }

    id temp = staticTextView.textStorage.delegate;
    staticTextView.textStorage.delegate = nil;
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
                pos += utf8String.length;
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

    staticTextView.textStorage.delegate = temp;
    return 0;
}

static int client_send(const char* op) {
    NSString *string = [[NSString alloc] initWithUTF8String:op];
    [websocket send:string];
    return 0;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSURL *url = [[NSURL alloc] initWithString:@"ws://staging.polyphony-ot.com:51015"];
    websocket = [[SRWebSocket alloc] initWithURL:url];
    websocket.delegate = self;
    [websocket open];

    staticTextView = self.textView;
    staticTextView.textStorage.delegate = self;
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

- (void)textStorage:(NSTextStorage *)textStorage willProcessEditing:(NSTextStorageEditActions)editedMask range:(NSRange)editedRange changeInLength:(NSInteger)delta {
    if (delta > 0) {
        char parent[20] = { 0 };
        ot_op* op = ot_new_op(0, parent);

        uint32_t beforeLength = (uint32_t)editedRange.location;
        if (beforeLength > 0) {
            ot_skip(op, beforeLength);
        }

        const char* inserted = [[textStorage.string substringWithRange:editedRange] UTF8String];
        ot_insert(op, inserted);

        uint32_t afterLength = (uint32_t)(textStorage.string.length - (beforeLength + delta));
        if (afterLength > 0) {
            ot_skip(op, afterLength);
        }

        ot_client_apply(client, &op);
    } else if (delta < 0) {
        char parent[20] = { 0 };
        ot_op* op = ot_new_op(0, parent);

        uint32_t beforeLength = (uint32_t)editedRange.location;
        if (beforeLength > 0) {
            ot_skip(op, beforeLength);
        }

        uint32_t deletedLength = (uint32_t)(delta * -1);
        ot_delete(op, deletedLength);

        uint32_t afterLength = (uint32_t)(textStorage.string.length - beforeLength);
        if (afterLength > 0) {
            ot_skip(op, afterLength);
        }

        ot_client_apply(client, &op);
    } else {

    }
}

@end
