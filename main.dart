import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyHomePage(title: "Test"),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _offer = false;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  final sdpController = TextEditingController();

  @override
  dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    sdpController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    initRenderer();
    _createPeerConnecion().then((pc) {
      _peerConnection = pc;
      setState(() {});
    });

    // Connect to the server

    // _getUserMedia();
    super.initState();
  }

  initRenderer() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _createPeerConnecion() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    _localStream = await _getUserMedia();

    RTCPeerConnection pc =
        await createPeerConnection(configuration, offerSdpConstraints);

    _localStream!.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onIceCandidate = (e) {
      if (e.candidate != null) {
        print(json.encode({
          'candidate': e.candidate.toString(),
          'sdpMid': e.sdpMid.toString(),
          'sdpMlineIndex': e.sdpMLineIndex.toString(),
        }));
      }
    };

    pc.onIceConnectionState = (e) {
      print(e);
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
      }
    };

    return pc;
  }

  _getUserMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      },
    };

    try {
      MediaStream stream =
          await navigator.mediaDevices.getUserMedia(constraints);
      _localRenderer.srcObject = stream;
      // _localRenderer.mirror = true;
      return stream;
    } catch (e) {
      print('Error accessing media devices: $e');
      // Handle the error (e.g., show a user-friendly message)
      return null;
    }
  }

  void _createOffer() async {
    RTCSessionDescription description =
        await _peerConnection!.createOffer({'offerToReceiveVideo': 1});
    var session = parse(description.sdp.toString());
    if (kIsWeb) {
      print(json.encode(session));
    } else {
      log(json.encode(session));
    }

    _offer = true;

    // print(json.encode({
    //       'sdp': description.sdp.toString(),
    //       'type': description.type.toString(),
    //     }));

    _peerConnection!.setLocalDescription(description);
  }

  void _createAnswer() async {
    RTCSessionDescription description =
        await _peerConnection!.createAnswer({'offerToReceiveVideo': 1});

    var session = parse(description.sdp.toString());
    if (kIsWeb) {
      print(json.encode(session));
    } else {
      log(json.encode(session));
    }
    // print(json.encode({
    //       'sdp': description.sdp.toString(),
    //       'type': description.type.toString(),
    //     }));

    _peerConnection!.setLocalDescription(description);
  }

  void _setRemoteDescription() async {
    String jsonString = sdpController.text;
    dynamic session = await jsonDecode(jsonString);

    String sdp = write(session, null);

    // RTCSessionDescription description =
    //     new RTCSessionDescription(session['sdp'], session['type']);
    RTCSessionDescription description =
        RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
    print(description.toMap());

    await _peerConnection!.setRemoteDescription(description);
    setState(() {});
  }

  void _switchCamera() async {
    try {
      // Find the video track in the local stream
      MediaStreamTrack videoTrack = _localStream!.getVideoTracks()[0];

      // Get the current facing mode
      String currentFacingMode =
          videoTrack.getSettings()['facingMode'] ?? 'user';

      // Set the new facing mode (switch between 'user' and 'environment')
      String newFacingMode =
          currentFacingMode == 'user' ? 'environment' : 'user';

      // Stop the current stream
      await _localStream!.dispose();

      // Get a new stream with the updated facing mode
      MediaStream newStream = await navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': newFacingMode}
      });

      // Update the local stream and renderer
      setState(() {
        _localStream = newStream;
        _localRenderer.srcObject = _localStream;
      });
    } catch (e) {
      print('Error switching camera: $e');
    }
  }

  void _addCandidate() async {
    String jsonString = sdpController.text;
    dynamic session = await jsonDecode(jsonString);
    print(session['candidate']);
    dynamic candidate = RTCIceCandidate(session['candidate'], session['sdpMid'],
        int.parse(session['sdpMlineIndex']));
    await _peerConnection!.addCandidate(candidate);
  }

  SizedBox videoRenderers() => SizedBox(
      height: 210,
      child: Row(children: [
        Flexible(
          child: Container(
              key: const Key("local"),
              margin: const EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: const BoxDecoration(color: Colors.black),
              child: RTCVideoView(_localRenderer)),
        ),
        Flexible(
          child: Container(
              key: const Key("remote"),
              margin: const EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: const BoxDecoration(color: Colors.black),
              child: RTCVideoView(
                _remoteRenderer,
                mirror: false,
              )),
        )
      ]));

  Row offerAndAnswerButtons() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        ElevatedButton(
          // onPressed: () {
          //   return showDialog(
          //       context: context,
          //       builder: (context) {
          //         return AlertDialog(
          //           content: Text(sdpController.text),
          //         );
          //       });
          // },
          onPressed: _createOffer,
          child: const Text('Call'),
          // color: Colors.amber,
        ),
        ElevatedButton(
          onPressed: _createAnswer,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          child: const Text('Answer'),
        ),
        ElevatedButton(
          onPressed: _switchCamera,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          child: const Text('camera'),
        ),
      ]);

  Row sdpCandidateButtons() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
        ElevatedButton(
          onPressed: _setRemoteDescription,
          child: const Text('Set Remote Desc'),
          // color: Colors.amber,
        ),
        ElevatedButton(
          onPressed: _addCandidate,
          child: const Text('Add Candidate'),
          // color: Colors.amber,
        )
      ]);
  Row disconnectButton() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ElevatedButton(
            onPressed: _disconnect,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      );
  void _disconnect() async {
    // Close the peer connection
    await _peerConnection?.close();

    // Dispose of the local and remote renderers
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    // Set the state to trigger a rebuild
    setState(() {
      _peerConnection = null;
      _localStream = null;
      _offer = false;
    });
  }

  Padding sdpCandidatesTF() => Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: sdpController,
          keyboardType: TextInputType.multiline,
          maxLines: 4,
          maxLength: TextField.noMaxLength,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: Container(
            child: Container(
                child: Column(
          children: [
            videoRenderers(),
            offerAndAnswerButtons(),
            sdpCandidatesTF(),
            sdpCandidateButtons(),
            disconnectButton(), // Add the disconnect button
          ],
        ))
            // new Stack(
            //   children: [
            //     new Positioned(
            //       top: 0.0,
            //       right: 0.0,
            //       left: 0.0,
            //       bottom: 0.0,
            //       child: new Container(
            //         child: new RTCVideoView(_localRenderer)
            //       )
            //     )
            //   ],
            // ),
            ));
  }
}
