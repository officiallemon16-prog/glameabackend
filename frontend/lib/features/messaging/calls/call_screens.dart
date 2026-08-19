import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../models/message.dart';
import '../../../shared/widgets/app_image.dart';
import 'call_controller.dart';

/// Full-screen call UI mounted above the app shell whenever a call is in
/// progress. Renders nothing when idle.
class CallOverlay extends ConsumerWidget {
  const CallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callControllerProvider);
    if (state.phase == CallPhase.idle) return const SizedBox.shrink();

    final controller = ref.read(callControllerProvider.notifier);
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: switch (state.phase) {
          CallPhase.incoming => _IncomingCall(state: state, controller: controller),
          CallPhase.active => _ActiveCall(state: state, controller: controller),
          CallPhase.outgoing || CallPhase.connecting => _OutgoingCall(
              state: state,
              controller: controller,
              connecting: state.phase == CallPhase.connecting,
            ),
          CallPhase.failed => _FailedCall(state: state),
          CallPhase.idle => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _HeaderInfo extends StatelessWidget {
  const _HeaderInfo({required this.name, required this.status});

  final String name;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name.isEmpty ? 'Unknown' : name,
          style: AppTextStyles.headline2.copyWith(color: AppColors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          status,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.white.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _IncomingCall extends StatelessWidget {
  const _IncomingCall({required this.state, required this.controller});

  final CallState state;
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        _HeaderInfo(
          name: state.otherName,
          status: 'Incoming ${state.kind == CallKind.video ? 'video' : 'voice'} call',
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundButton(
              icon: Icons.call_end_rounded,
              label: 'Decline',
              color: AppColors.error,
              onTap: controller.rejectCall,
            ),
            const SizedBox(width: AppSpacing.xxl),
            _RoundButton(
              icon: Icons.call_rounded,
              label: 'Accept',
              color: AppColors.success,
              onTap: controller.acceptCall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.huge),
      ],
    );
  }
}

class _OutgoingCall extends StatelessWidget {
  const _OutgoingCall({
    required this.state,
    required this.controller,
    required this.connecting,
  });

  final CallState state;
  final CallController controller;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        _HeaderInfo(
          name: state.otherName,
          status: connecting
              ? 'Connecting…'
              : 'Ringing ${state.kind == CallKind.video ? 'video' : 'voice'} call…',
        ),
        if (connecting) ...[
          const SizedBox(height: AppSpacing.lg),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.white,
            ),
          ),
        ],
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundButton(
              icon: state.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: 'Mute',
              onTap: controller.toggleMute,
            ),
            const SizedBox(width: AppSpacing.xxl),
            _RoundButton(
              icon: Icons.call_end_rounded,
              label: 'End',
              color: AppColors.error,
              onTap: controller.endCall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.huge),
      ],
    );
  }
}

class _ActiveCall extends StatelessWidget {
  const _ActiveCall({required this.state, required this.controller});

  final CallState state;
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    final isVideo = state.kind == CallKind.video;
    if (isVideo) return _VideoCall(state: state, controller: controller);
    return _VoiceCall(state: state, controller: controller);
  }
}

class _VoiceCall extends StatelessWidget {
  const _VoiceCall({required this.state, required this.controller});

  final CallState state;
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        AppAvatar(name: state.otherName, radius: 48),
        const SizedBox(height: AppSpacing.lg),
        _HeaderInfo(
          name: state.otherName,
          status: _formatDuration(state.durationSeconds),
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundButton(
              icon: state.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: 'Mute',
              active: state.isMuted,
              onTap: controller.toggleMute,
            ),
            const SizedBox(width: AppSpacing.xxl),
            _RoundButton(
              icon: Icons.call_end_rounded,
              label: 'End',
              color: AppColors.error,
              onTap: controller.endCall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.huge),
      ],
    );
  }
}

class _VideoCall extends StatelessWidget {
  const _VideoCall({required this.state, required this.controller});

  final CallState state;
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RTCVideoView(
          controller.remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
        Positioned(
          top: AppSpacing.md,
          left: 0,
          right: 0,
          child: _HeaderInfo(
            name: state.otherName,
            status: _formatDuration(state.durationSeconds),
          ),
        ),
        Positioned(
          top: AppSpacing.lg,
          right: AppSpacing.md,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            child: SizedBox(
              width: 108,
              height: 150,
              child: RTCVideoView(
                controller.localRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.huge,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundButton(
                icon: state.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: 'Mute',
                active: state.isMuted,
                onTap: controller.toggleMute,
              ),
              const SizedBox(width: AppSpacing.lg),
              _RoundButton(
                icon: Icons.cameraswitch_rounded,
                label: 'Flip',
                onTap: controller.switchCamera,
              ),
              const SizedBox(width: AppSpacing.lg),
              _RoundButton(
                icon: Icons.call_end_rounded,
                label: 'End',
                color: AppColors.error,
                onTap: controller.endCall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FailedCall extends StatelessWidget {
  const _FailedCall({required this.state});

  final CallState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.call_end_rounded, color: AppColors.error, size: 40),
        ),
        const SizedBox(height: AppSpacing.lg),
        _HeaderInfo(
          name: state.otherName,
          status: state.error ?? 'Call failed',
        ),
        const Spacer(),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.white.withValues(alpha: 0.15);
    final fg = color == null
        ? (active ? AppColors.error : AppColors.white)
        : AppColors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: Border.all(
                color: AppColors.white.withValues(alpha: active ? 0 : 0.4),
              ),
            ),
            child: Icon(icon, color: fg, size: 28),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

String _formatDuration(int totalSeconds) {
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
