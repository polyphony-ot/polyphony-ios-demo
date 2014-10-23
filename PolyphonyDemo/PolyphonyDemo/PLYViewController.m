#import "PLYViewController.h"
#import "SRWebSocket.h"
#import "client.h"

@interface PLYViewController () <SRWebSocketDelegate, NSTextStorageDelegate, UITextViewDelegate>

@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

@implementation PLYViewController

// The libot client that will handle sending and receiving operations to and from the server.
static ot_client *client;

// The text view that is being used as our editor.
static UITextView *staticTextView;

// The WebSocket that's used to communicate with the server.
static SRWebSocket *websocket;

// This function is invoked by the OT client whenever an event happens that the editor needs to know about. For the
// purposes of this demo app, we only care about the OT_OP_APPLIED event, which is fired when someone else has changed
// the document.
static int client_event(ot_event_type t, ot_op* op) {
    // Ignore all other events except for OT_OP_APPLIED.
    if (t != OT_OP_APPLIED) {
        return 0;
    }

    // Temporarily remove the text storage's delegate so that we don't receive text change notifications while we update
    // the editor.
    id temp = staticTextView.textStorage.delegate;
    staticTextView.textStorage.delegate = nil;

    // pos will track our current index position within the editor's text as we update it with the new changes.
    size_t pos = 0;

    // Iterate over each component within the operation and update the editor as we go.
    ot_comp* comps = op->comps.data;
    for (size_t i = 0; i < op->comps.len; ++i) {
        ot_comp* comp = comps + i;
        switch (comp->type) {
            case OT_SKIP:
            {
                // We're skipping characters, so don't do anything and just move the position forward.
                pos += comp->value.skip.count;
                break;
            }
            case OT_INSERT:
            {
                // Insert the component's text at the current position.
                ot_comp_insert insert = comp->value.insert;
                NSString* utf8String = [[NSString alloc] initWithUTF8String:insert.text];
                NSAttributedString *insertString = [[NSAttributedString alloc] initWithString:utf8String];
                [staticTextView.textStorage insertAttributedString:insertString atIndex:pos];

                // Move the position forward over the text we just inserted.
                pos += utf8String.length;
                break;
            }
            case OT_DELETE:
            {
                // Delete characters at the current position. We don't need to update the position since text was only
                // deleted.
                ot_comp_delete delete = comp->value.delete;;
                NSRange range = NSMakeRange(pos, delete.count);
                [staticTextView.textStorage deleteCharactersInRange:range];
                break;
            }
            default:
                // Don't do anything with other component types since they aren't implemented yet.
                break;
        }
    }

    // Reassign the text storage's delegate so we receive text change notifications again.
    staticTextView.textStorage.delegate = temp;
    return 0;
}

// This function is invoked by the OT client whenever an operation needs to be sent to the server. All it needs to do is
// forward the operation string to our WebSocket.
static int client_send(const char* op) {
    NSString *string = [[NSString alloc] initWithUTF8String:op];
    [websocket send:string];
    return 0;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Create our WebSocket and connect it to the Polyphony demo server.
    NSURL *url = [[NSURL alloc] initWithString:@"ws://staging.polyphony-ot.com:51015"];
    websocket = [[SRWebSocket alloc] initWithURL:url];
    websocket.delegate = self;
    [websocket open];

    // Assign the text storage a delegate so we get notifed when the user changes the text.
    staticTextView = self.textView;
    staticTextView.delegate = self;
    staticTextView.textStorage.delegate = self;

    // Create our libot client and give it our send and event functions.
    client = ot_new_client(client_send, client_event);
}

// The WebSocket callback that is invoked whenever a message is received from the server.
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    // If our client doesn't have an ID yet, then we expect the first message from the server to contain an ID and the
    // initial document contents. This is a protocol decided upon by the Polyphony demo, and isn't a part of libot
    // itself. Your own app and server can decide on how to handle new clients in whatever way they see fit.
    if (client->client_id == 0) {
        // Deserialize the JSON.
        NSData *jsonData = [message dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                    options:NSJSONReadingMutableContainers error:nil];

        // Assign the client its ID.
        client->client_id = [[dict valueForKey:@"clientId"] intValue];

        // Forward the initial document contents to the client.
        NSString *lastOp = [dict valueForKey:@"lastOp"];
        if (lastOp != nil) {
            ot_client_receive(client, [lastOp UTF8String]);
        }

        return;
    }

    // Forward the received operation to the client.
    ot_client_receive(client, [message UTF8String]);
}

// This callback is invoked when the NSTextStorage is about to process the users changes. We use this opportunity to
// ensure that the document ends with a newline. A trailing newline is required by the Quill editor used by the web app,
// and isn't a required by libot.
- (void)textStorage:(NSTextStorage *)textStorage willProcessEditing:(NSTextStorageEditActions)editedMask
              range:(NSRange)editedRange changeInLength:(NSInteger)delta {

    if (![textStorage.string hasSuffix:@"\n"]) {
        NSAttributedString *newline = [[NSAttributedString alloc] initWithString:@"\n"];
        [textStorage appendAttributedString:newline];
    }
}

// This callback is invoked when the NSTextStorage has finished processing user changes. At this point, we can build an
// operation that represents the user's changes and give it to our OT client.
- (void)textStorage:(NSTextStorage *)textStorage didProcessEditing:(NSTextStorageEditActions)editedMask
              range:(NSRange)editedRange changeInLength:(NSInteger)delta {

    // Ignore changes where the user didn't modify any characters.
    if ((editedMask & NSTextStorageEditedCharacters) == 0) {
        return;
    }

    ot_op* op = ot_new_op();

    // Skip all the characters before the user's change.
    uint32_t beforeLength = (uint32_t)editedRange.location;
    if (beforeLength > 0) {
        ot_skip(op, beforeLength);
    }

    // Delete any characters that were removed by the user's change. This is equal to the total delta of the changes,
    // minus the length of the text that the user inserted.
    uint32_t deletedLength = (uint32_t) ((delta - editedRange.length) * -1);
    if (deletedLength > 0) {
        ot_delete(op, deletedLength);
    }

    // Insert any text that the user added. This is simply the substring of the edited range.
    if (editedRange.length > 0) {
        const char* inserted = [[textStorage.string substringWithRange:editedRange] UTF8String];
        ot_insert(op, inserted);
    }

    // Skip the remaining characters after the user's change.
    uint32_t afterLength = (uint32_t)(textStorage.string.length - beforeLength - editedRange.length);
    if (afterLength > 0) {
        ot_skip(op, afterLength);
    }

    // Finally, apply our operation.
    ot_client_apply(client, &op);
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    NSUInteger newLength = [textView.text length] + [text length] - range.length;
    return (newLength < 1024);
}

@end
