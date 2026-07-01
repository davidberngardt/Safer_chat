// call_screen.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:safer_chat/generated/app_localizations.dart';
import 'package:safer_chat/theme.dart';
import 'package:safer_chat/providers/font_scale_provider.dart';
import 'dart:async';
import '../utils/platform_utils.dart'; // Добавлен импорт

enum CallType { audio, video }
enum CallDirection { incoming, outgoing }
enum CallState { ringing, connected, ended }

class CallScreen extends StatefulWidget {
  final int myUserId;
  final int otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final CallType callType;
  final CallDirection callDirection;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onEnd;
  final ValueChanged<bool> onToggleMute;
  final ValueChanged<bool>? onToggleVideo;

  const CallScreen({
    Key? key,
    required this.myUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.callType,
    required this.callDirection,
    required this.onAccept,
    required this.onReject,
    required this.onEnd,
    required this.onToggleMute,
    this.onToggleVideo,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _gradientAnimationController;
  late Animation<Color?> _colorAnimation1;
  late Animation<Color?> _colorAnimation2;
  late Animation<Color?> _colorAnimation3;
  
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;
  Timer? _ringtoneTimer;
  int _callDuration = 0;
  Timer? _durationTimer;
  CallState _callState = CallState.ringing;

  // Для демонстрации видео (заглушка)
  bool _showLocalVideo = false;
  bool _showRemoteVideo = false;

  final List<Color> _gradientColors = [
    const Color(0xFFFFA000),
    const Color(0xFFFF5722),
    const Color(0xFFE91E63),
    const Color(0xFF9C27B0),
    const Color(0xFF673AB7),
  ];

  @override
  void initState() {
    super.initState();
    
    _gradientAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _colorAnimation1 = ColorTween(
      begin: _gradientColors[0],
      end: _gradientColors[2],
    ).animate(CurvedAnimation(
      parent: _gradientAnimationController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
    ));

    _colorAnimation2 = ColorTween(
      begin: _gradientColors[1],
      end: _gradientColors[3],
    ).animate(CurvedAnimation(
      parent: _gradientAnimationController,
      curve: const Interval(0.2, 0.7, curve: Curves.easeInOut),
    ));

    _colorAnimation3 = ColorTween(
      begin: _gradientColors[2],
      end: _gradientColors[4],
    ).animate(CurvedAnimation(
      parent: _gradientAnimationController,
      curve: const Interval(0.4, 0.9, curve: Curves.easeInOut),
    ));

    if (widget.callDirection == CallDirection.outgoing) {
      _callState = CallState.connected;
      _startCallDuration();
      if (widget.callType == CallType.video) {
        _showLocalVideo = true;
        _showRemoteVideo = true;
      }
    }

    if (widget.callDirection == CallDirection.incoming && _callState == CallState.ringing) {
      _startRingtoneSimulation();
    }
  }

  void _startRingtoneSimulation() {
    _ringtoneTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && _callState == CallState.ringing) {
        print('🔔 Ringtone...');
      }
    });
  }

  void _startCallDuration() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _callState == CallState.connected) {
        setState(() {
          _callDuration++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }

  void _handleAccept() {
    setState(() {
      _callState = CallState.connected;
      if (widget.callType == CallType.video) {
        _showLocalVideo = true;
        _showRemoteVideo = true;
      }
    });
    _ringtoneTimer?.cancel();
    _startCallDuration();
    widget.onAccept();
  }

  void _handleReject() {
    _ringtoneTimer?.cancel();
    _durationTimer?.cancel();
    widget.onReject();
  }

  void _handleEnd() {
    _durationTimer?.cancel();
    widget.onEnd();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    widget.onToggleMute(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
  }

  void _toggleVideo() {
    if (widget.onToggleVideo != null) {
      setState(() {
        _isVideoEnabled = !_isVideoEnabled;
        _showLocalVideo = _isVideoEnabled;
        _showRemoteVideo = _isVideoEnabled;
      });
      widget.onToggleVideo!(_isVideoEnabled);
    }
  }

  void _switchCamera() {
    print('Switching camera');
    // TODO: Реализовать переключение камеры
  }

  @override
  void dispose() {
    _gradientAnimationController.dispose();
    _ringtoneTimer?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 600;
    final fontSizeScale = Provider.of<FontScaleProvider>(context).fontSizeScale;

    if (isWeb) {
      return _buildWebModal(fontSizeScale);
    } else {
      return _buildMobileScreen(fontSizeScale);
    }
  }

  Widget _buildWebModal(double fontSizeScale) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: AnimatedBuilder(
        animation: _gradientAnimationController,
        builder: (context, child) {
          return Container(
            width: widget.callType == CallType.video ? 800 : 400,
            height: widget.callType == CallType.video ? 600 : 600,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _colorAnimation1.value ?? _gradientColors[0],
                  _colorAnimation2.value ?? _gradientColors[1],
                  _colorAnimation3.value ?? _gradientColors[2],
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: _buildCallContent(fontSizeScale),
          );
        },
      ),
    );
  }

  Widget _buildMobileScreen(double fontSizeScale) {
    return AnimatedBuilder(
      animation: _gradientAnimationController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _colorAnimation1.value ?? _gradientColors[0],
                _colorAnimation2.value ?? _gradientColors[1],
                _colorAnimation3.value ?? _gradientColors[2],
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: _buildCallContent(fontSizeScale),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCallContent(double fontSizeScale) {
    final isIncoming = widget.callDirection == CallDirection.incoming;
    final isRinging = _callState == CallState.ringing;
    final isConnected = _callState == CallState.connected;
    final isVideoCall = widget.callType == CallType.video;

    if (isVideoCall && isConnected) {
      return _buildVideoCallLayout(fontSizeScale);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: EdgeInsets.all(24 * fontSizeScale),
          child: Column(
            children: [
              SizedBox(height: 20 * fontSizeScale),
              
              Container(
                width: 120 * fontSizeScale,
                height: 120 * fontSizeScale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 4 * fontSizeScale,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 60 * fontSizeScale,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  backgroundImage: widget.otherUserAvatar != null
                      ? NetworkImage(widget.otherUserAvatar!)
                      : null,
                  child: widget.otherUserAvatar == null
                      ? Text(
                          widget.otherUserName[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 48 * fontSizeScale,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              ),
              
              SizedBox(height: 24 * fontSizeScale),
              
              Text(
                widget.otherUserName,
                style: TextStyle(
                  fontSize: 28 * fontSizeScale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 8 * fontSizeScale),
              
              if (isConnected)
                Text(
                  _formatDuration(_callDuration),
                  style: TextStyle(
                    fontSize: 18 * fontSizeScale,
                    color: Colors.white.withOpacity(0.9),
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        Padding(
          padding: EdgeInsets.all(24 * fontSizeScale),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(12 * fontSizeScale),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.callType == CallType.video
                      ? Icons.videocam
                      : Icons.phone,
                  color: Colors.white,
                  size: 20 * fontSizeScale,
                ),
              ),
              
              SizedBox(height: 30 * fontSizeScale),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _buildCallButtons(isIncoming, isRinging, fontSizeScale),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoCallLayout(double fontSizeScale) {
    return Stack(
      children: [
        if (_showRemoteVideo)
          Container(
            color: Colors.black,
            child: Center(
              child: Text(
                '🎥 Remote Video',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 24 * fontSizeScale,
                ),
              ),
            ),
          )
        else
          Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120 * fontSizeScale,
                    height: 120 * fontSizeScale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    child: widget.otherUserAvatar == null
                        ? Text(
                            widget.otherUserName[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 48 * fontSizeScale,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(60 * fontSizeScale),
                            child: Image.network(
                              widget.otherUserAvatar!,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                  SizedBox(height: 16 * fontSizeScale),
                  Text(
                    widget.otherUserName,
                    style: TextStyle(
                      fontSize: 24 * fontSizeScale,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8 * fontSizeScale),
                  Text(
                    _formatDuration(_callDuration),
                    style: TextStyle(
                      fontSize: 18 * fontSizeScale,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (_showLocalVideo)
          Positioned(
            bottom: 100 * fontSizeScale,
            right: 20 * fontSizeScale,
            child: Container(
              width: 120 * fontSizeScale,
              height: 160 * fontSizeScale,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(10 * fontSizeScale),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  '🎥 You',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),

        Positioned(
          top: 20 * fontSizeScale,
          left: 20 * fontSizeScale,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * fontSizeScale,
              vertical: 8 * fontSizeScale,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20 * fontSizeScale),
            ),
            child: Text(
              _formatDuration(_callDuration),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16 * fontSizeScale,
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 30 * fontSizeScale,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  width: 50 * fontSizeScale,
                  height: 50 * fontSizeScale,
                  decoration: BoxDecoration(
                    color: _isMuted ? Colors.orange.withOpacity(0.2) : Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isMuted ? Colors.orange : Colors.white,
                      width: 2 * fontSizeScale,
                    ),
                  ),
                  child: Icon(
                    _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted ? Colors.orange : Colors.white,
                    size: 24 * fontSizeScale,
                  ),
                ),
              ),

              GestureDetector(
                onTap: _toggleVideo,
                child: Container(
                  width: 50 * fontSizeScale,
                  height: 50 * fontSizeScale,
                  decoration: BoxDecoration(
                    color: _isVideoEnabled ? Colors.white.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isVideoEnabled ? Colors.white : Colors.orange,
                      width: 2 * fontSizeScale,
                    ),
                  ),
                  child: Icon(
                    _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                    color: _isVideoEnabled ? Colors.white : Colors.orange,
                    size: 24 * fontSizeScale,
                  ),
                ),
              ),

              GestureDetector(
                onTap: _switchCamera,
                child: Container(
                  width: 50 * fontSizeScale,
                  height: 50 * fontSizeScale,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2 * fontSizeScale,
                    ),
                  ),
                  child: Icon(
                    Icons.flip_camera_ios,
                    color: Colors.white,
                    size: 24 * fontSizeScale,
                  ),
                ),
              ),

              GestureDetector(
                onTap: _handleEnd,
                child: Container(
                  width: 60 * fontSizeScale,
                  height: 60 * fontSizeScale,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.red,
                      width: 2 * fontSizeScale,
                    ),
                  ),
                  child: Icon(
                    Icons.call_end,
                    color: Colors.red,
                    size: 28 * fontSizeScale,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCallButtons(
    bool isIncoming,
    bool isRinging,
    double fontSizeScale,
  ) {
    final List<Widget> buttons = [];

    if (isIncoming && isRinging) {
      buttons.addAll([
        _buildCallButton(
          icon: Icons.call,
          color: Colors.green,
          onTap: _handleAccept,
          fontSizeScale: fontSizeScale,
        ),
        _buildCallButton(
          icon: Icons.call_end,
          color: Colors.red,
          onTap: _handleReject,
          fontSizeScale: fontSizeScale,
        ),
      ]);
    } else {
      buttons.addAll([
        _buildCallButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          color: _isMuted ? Colors.orange : Colors.white,
          onTap: _toggleMute,
          fontSizeScale: fontSizeScale,
        ),
        _buildCallButton(
          icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
          color: _isSpeakerOn ? Colors.blue : Colors.white,
          onTap: _toggleSpeaker,
          fontSizeScale: fontSizeScale,
        ),
        if (widget.callType == CallType.video)
          _buildCallButton(
            icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
            color: _isVideoEnabled ? Colors.blue : Colors.orange,
            onTap: _toggleVideo,
            fontSizeScale: fontSizeScale,
          ),
        _buildCallButton(
          icon: Icons.call_end,
          color: Colors.red,
          onTap: _handleEnd,
          fontSizeScale: fontSizeScale,
        ),
      ]);
    }

    return buttons;
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required double fontSizeScale,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60 * fontSizeScale,
        height: 60 * fontSizeScale,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(
            color: color,
            width: 2 * fontSizeScale,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: color,
          size: 28 * fontSizeScale,
        ),
      ),
    );
  }
}