import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/widgets/physique_check_widgets.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// The poses of one progress photo set, in capture order.
const progressPhotoPoses = <({String pose, String label, String guidance})>[
  (
    pose: 'front',
    label: 'Front photo',
    guidance: 'Face the camera with your full body visible',
  ),
  (
    pose: 'side',
    label: 'Side photo',
    guidance: 'Turn 90 degrees, arm away from your body',
  ),
  (
    pose: 'back',
    label: 'Back photo',
    guidance: 'Face away from the camera, natural stance',
  ),
  (
    pose: 'lower',
    label: 'Lower body',
    guidance: 'Full lower body from the waist down',
  ),
];

/// Uploads one pose. `captured` is false when the user cancelled or the
/// upload failed; `error` is set only for a failure worth showing.
typedef PoseCapture =
    Future<({bool captured, String? error})> Function(
      String pose,
      ImageSource source,
    );

/// Progress photos on the main screen: one card with the latest set, the
/// capture action, and the way into past sets. Photos never render here.
/// Accounts with physique checks also get the check action and its latest
/// result.
class PhotoProgressCard extends StatelessWidget {
  const PhotoProgressCard({
    required this.photoSets,
    required this.inProgress,
    required this.onCapture,
    required this.onOpenSets,
    this.photoCheckProvider,
    this.onPhysiqueCheck,
    this.latestPhysique,
    this.onOpenPhysique,
    this.now,
    super.key,
  });

  /// Stored sets, newest first.
  final List<ProgressPhotoSet> photoSets;

  /// True while a set has some poses but is not finished.
  final bool inProgress;
  final VoidCallback onCapture;
  final VoidCallback onOpenSets;

  /// Who photos go to when this account starts a physique check, as the
  /// server names it; null when it may not. The privacy line then says when
  /// they leave the app; with a stored check it never says "never".
  final String? photoCheckProvider;

  /// Starts a check on the newest set; null hides the action.
  final VoidCallback? onPhysiqueCheck;
  final PhysiqueAnalysis? latestPhysique;
  final ValueChanged<PhysiqueAnalysis>? onOpenPhysique;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final latest = photoSets.isEmpty ? null : photoSets.first;
    final provider = photoCheckProvider;
    final physique = latestPhysique;
    return PremiumGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TracendRowIcon(
                icon: CupertinoIcons.lock_shield_fill,
                color: colors.stateStable,
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      latest == null
                          ? 'Start your photo timeline'
                          : 'Last set · ${friendlyDate(latest.date, now: now)}',
                      style: theme.titleMedium,
                    ),
                    Text(
                      provider != null
                          ? 'Only you can see these. Sent to $provider only '
                                'when you start a physique check.'
                          : physique != null
                          ? 'Only you can see these. A set was sent to AI '
                                'only for a physique check you started.'
                          : 'Only you can see these. Never sent to AI.',
                      style: theme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onCapture,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.camera_fill, size: 18),
                  const SizedBox(width: TracendSpacing.xs),
                  Flexible(
                    child: Text(
                      inProgress
                          ? 'Continue photo set'
                          : 'Take progress photos',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (provider != null && onPhysiqueCheck != null) ...[
            const SizedBox(height: TracendSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onPhysiqueCheck,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.sparkles, size: 18),
                    SizedBox(width: TracendSpacing.xs),
                    Flexible(
                      child: Text(
                        'Physique check',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (physique != null && onOpenPhysique != null) ...[
            const SizedBox(height: TracendSpacing.xs),
            PhysiqueSummaryRow(
              analysis: physique,
              onOpen: () => onOpenPhysique!(physique),
              now: now,
            ),
          ],
          if (photoSets.isNotEmpty)
            Center(
              child: TextButton(
                onPressed: onOpenSets,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(
                  photoSets.length == 1
                      ? 'View past set'
                      : 'View past sets (${photoSets.length})',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Guided capture: front, side, back, lower body. Each pose uploads as soon
/// as it is chosen; errors stay inline because snackbars sit behind sheets.
class PhotoCaptureSheet extends StatefulWidget {
  const PhotoCaptureSheet({
    required this.captured,
    required this.onCapture,
    super.key,
  });

  /// Poses already uploaded to the open set.
  final Set<String> captured;
  final PoseCapture onCapture;

  @override
  State<PhotoCaptureSheet> createState() => _PhotoCaptureSheetState();
}

class _PhotoCaptureSheetState extends State<PhotoCaptureSheet> {
  late final Set<String> _captured = {...widget.captured};
  String? _busyPose;
  String? _error;

  bool get _complete => _captured.length == progressPhotoPoses.length;

  Future<void> _capture(String pose, ImageSource source) async {
    setState(() {
      _busyPose = pose;
      _error = null;
    });
    final result = await widget.onCapture(pose, source);
    if (!mounted) return;
    setState(() {
      _busyPose = null;
      _error = result.error;
      if (result.captured) _captured.add(pose);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          TracendSpacing.gutter,
          0,
          TracendSpacing.gutter,
          TracendSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress photos', style: theme.headlineSmall),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              'Same spot, same light, same time of day makes changes easy to '
              'see. ${_captured.length} of ${progressPhotoPoses.length} done.',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: TracendSpacing.md),
            TracendGroupedList(
              children: [
                for (final item in progressPhotoPoses)
                  PosePhotoRow(
                    label: item.label,
                    guidance: item.guidance,
                    isCaptured: _captured.contains(item.pose),
                    isBusy: _busyPose == item.pose,
                    onCamera: _busyPose == null
                        ? () => _capture(item.pose, ImageSource.camera)
                        : null,
                    onGallery: _busyPose == null
                        ? () => _capture(item.pose, ImageSource.gallery)
                        : null,
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: TracendSpacing.sm),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 18,
                    color: colors.stateAttention,
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(child: Text(_error!, style: theme.bodyMedium)),
                ],
              ),
            ],
            const SizedBox(height: TracendSpacing.md),
            SizedBox(
              width: double.infinity,
              child: _complete
                  ? FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    )
                  : OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Finish later'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One pose in the capture sheet, with camera and library actions.
class PosePhotoRow extends StatelessWidget {
  const PosePhotoRow({
    required this.label,
    required this.guidance,
    required this.isCaptured,
    required this.onCamera,
    required this.onGallery,
    this.isBusy = false,
    super.key,
  });

  final String label;
  final String guidance;
  final bool isCaptured;
  final bool isBusy;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return TracendListRow(
      title: label,
      subtitle: guidance,
      leading: isBusy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isCaptured
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 22,
              color: isCaptured ? colors.stateStable : colors.textSecondary,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onCamera,
            tooltip: 'Take $label',
            icon: const Icon(CupertinoIcons.camera),
          ),
          IconButton(
            onPressed: onGallery,
            tooltip: 'Choose $label from library',
            icon: const Icon(CupertinoIcons.photo),
          ),
        ],
      ),
    );
  }
}

/// Stored sets, newest first, each with view and delete.
class PhotoSetsSheet extends StatelessWidget {
  const PhotoSetsSheet({
    required this.photoSets,
    required this.onView,
    required this.onDelete,
    this.now,
    super.key,
  });

  final List<ProgressPhotoSet> photoSets;
  final ValueChanged<ProgressPhotoSet> onView;
  final ValueChanged<ProgressPhotoSet> onDelete;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        0,
        TracendSpacing.gutter,
        TracendSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Past photo sets',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: TracendSpacing.md),
          TracendGroupedList(
            children: [
              for (final set in photoSets)
                TracendListRow(
                  title: friendlyDate(set.date, now: now),
                  subtitle: set.status == 'complete'
                      ? '${set.objectKeys.length} photos'
                      : '${set.objectKeys.length} of '
                            '${progressPhotoPoses.length} photos · unfinished',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: set.objectKeys.isEmpty
                            ? null
                            : () => onView(set),
                        child: const Text('View'),
                      ),
                      IconButton(
                        onPressed: () => onDelete(set),
                        tooltip: 'Delete photo set',
                        icon: const Icon(CupertinoIcons.delete),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Private viewer with short-lived signed URLs (60-second expiry).
class PrivatePhotoViewer extends StatelessWidget {
  const PrivatePhotoViewer({required this.urls, super.key});

  final List<String> urls;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        0,
        TracendSpacing.gutter,
        TracendSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Private photo set',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: TracendSpacing.xxs),
          const Text('Only you can open these. The link expires in a minute.'),
          const SizedBox(height: TracendSpacing.md),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: TracendSpacing.sm),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Image.network(
                    urls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Text('Photo unavailable')),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
