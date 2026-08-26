import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// One pose row in the private progress-photo capture flow.
/// Camera and gallery actions are real capture entry points.
class PosePhotoRow extends StatelessWidget {
  const PosePhotoRow({
    required this.pose,
    required this.label,
    required this.guidance,
    required this.isCaptured,
    required this.onCamera,
    required this.onGallery,
    super.key,
  });

  final String pose;
  final String label;
  final String guidance;
  final bool isCaptured;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(
          isCaptured
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.circle,
          color: isCaptured
              ? context.tracendColors.stateStable
              : context.tracendColors.textSecondary,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              Text(guidance, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onCamera,
          child: const Icon(CupertinoIcons.camera, size: 24),
        ),
        const SizedBox(width: 4),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onGallery,
          child: const Icon(CupertinoIcons.photo, size: 24),
        ),
      ],
    ),
  );
}

/// A stored private photo set with real view/delete actions.
class PhotoSetCard extends StatelessWidget {
  const PhotoSetCard({
    required this.set,
    required this.onView,
    required this.onDelete,
    super.key,
  });

  final ProgressPhotoSet set;
  final VoidCallback onView, onDelete;

  @override
  Widget build(BuildContext context) => TracendCard(
    child: Row(
      children: [
        const Icon(CupertinoIcons.lock_shield_fill),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${set.date.day}/${set.date.month}/${set.date.year}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${set.objectKeys.length} private photos · ${set.status}'),
            ],
          ),
        ),
        TextButton(onPressed: onView, child: const Text('View')),
        IconButton(
          onPressed: onDelete,
          tooltip: 'Delete photo set',
          icon: const Icon(CupertinoIcons.delete),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Private photo set',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text('Short-lived access · links expire after 60 seconds'),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
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
