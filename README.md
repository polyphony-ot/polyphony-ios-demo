Polyphony iOS Demo
==================

A Polyphony demo running on iOS that performs real-time text editing with
<http://polyphony-ot.com>. It shows how to build a completely native real-time
editor without using any WebViews.

Running
-------

Since this app is only a demo, it cannot be published to the AppStore. In order
to install and run it, you must have Xcode 6 installed. Once you have Xcode
installed, simply open PolyphonyDemo.xcworkspace and run the app with Cmd+R.

![Polyphony running on iOS](http://i.imgur.com/Ury1X2V.png)

Walkthrough
-----------

All of the code for the demo can be found in [PolyphonyDemo/PolyphonyDemo/PLYViewController.m](PolyphonyDemo/PolyphonyDemo/PLYViewController.m).
It demonstrates how to create a real-time text editor using a UITextView and a
Polyphony client.
