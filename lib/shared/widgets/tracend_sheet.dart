import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';

/// Opens a Tracend bottom sheet (DESIGN_SYSTEM.md §5.1, sheet) and completes
/// with the value the sheet pops, or null when it is dismissed.
///
/// The sheet rises over a blurred scrim, shows the drag handle and closes on
/// a swipe down, a tap on the scrim or the round close button. With a
/// [title] it gets the standard header (title, optional [subtitle], close).
/// It stays clear of the home indicator and moves up with the keyboard; the
/// builder sees no keyboard inset, so it never pads for it twice.
///
/// By default the body scrolls when it is taller than the screen. Pass
/// [scrollable] false when the builder brings its own scroll view or sizes
/// itself. Pass [detents] (ascending fractions of the available height, such
/// as `[0.5, 0.92]`) for a sheet that opens at the first size and snaps
/// between them when dragged; its body always scrolls.
///
/// A sheet that takes input wraps its body in [TracendSheetUnsavedGuard].
/// While the guard reports unsaved input, a swipe down, a tap on the scrim and
/// the close button ask "Discard changes?" instead of closing; a saving
/// action that pops the route itself is never asked. A guarded sheet with
/// [detents] stays at its smallest size on a swipe rather than closing.
Future<T?> showTracendSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  bool showCloseButton = true,
  List<double>? detents,
  bool scrollable = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: TracendSpacing.gutter,
  ),
}) {
  assert(
    detents == null ||
        (detents.isNotEmpty &&
            detents.first > 0 &&
            detents.last <= 1 &&
            [
              for (var i = 1; i < detents.length; i++)
                detents[i] > detents[i - 1],
            ].every((ascending) => ascending)),
    'detents must be ascending fractions in (0, 1]',
  );
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  final media = MediaQuery.of(context);
  return navigator.push(
    _TracendSheetRoute<T>(
      builder: (sheetContext) => _TracendSheetFrame(
        title: title,
        subtitle: subtitle,
        showCloseButton: showCloseButton,
        detents: detents,
        scrollable: scrollable,
        padding: padding,
        hasDragHandle: enableDrag,
        builder: builder,
      ),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      useSafeArea: true,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      // The frame draws its own handle; the theme's is off app-wide.
      showDragHandle: false,
      constraints: BoxConstraints(
        maxWidth: 640,
        maxHeight: media.size.height - media.padding.top - TracendSpacing.xs,
      ),
    ),
  );
}

/// A modal bottom sheet route whose scrim also blurs what is behind it.
class _TracendSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _TracendSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.isScrollControlled,
    required super.useSafeArea,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.modalBarrierColor,
    required super.isDismissible,
    required super.enableDrag,
    required super.showDragHandle,
    required super.constraints,
  });

  static const scrimBlur = 6.0;

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    final animation = this.animation;
    if (animation == null) return barrier;
    return AnimatedBuilder(
      animation: animation,
      child: barrier,
      builder: (context, child) {
        final sigma = scrimBlur * animation.value.clamp(0.0, 1.0);
        return BackdropFilter(
          enabled: sigma > 0,
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        );
      },
    );
  }
}

class _TracendSheetFrame extends StatefulWidget {
  const _TracendSheetFrame({
    required this.title,
    required this.subtitle,
    required this.showCloseButton,
    required this.detents,
    required this.scrollable,
    required this.padding,
    required this.hasDragHandle,
    required this.builder,
  });

  final String? title;
  final String? subtitle;
  final bool showCloseButton;
  final List<double>? detents;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final bool hasDragHandle;
  final WidgetBuilder builder;

  @override
  State<_TracendSheetFrame> createState() => _TracendSheetFrameState();
}

class _TracendSheetFrameState extends State<_TracendSheetFrame> {
  /// A downward drag this far, or this fast, is a swipe to close.
  static const _swipeDistance = 80.0;
  static const _swipeVelocity = 700.0;

  final _unsaved = _UnsavedInput();
  var _swiped = 0.0;
  var _asking = false;

  @override
  void dispose() {
    _unsaved.close();
    super.dispose();
  }

  Future<void> _askToDiscard() async {
    if (_asking) return;
    _asking = true;
    final discard = await showTracendConfirm(
      context,
      title: 'Discard changes?',
      message: 'What you entered has not been saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    _asking = false;
    if (discard && mounted) Navigator.of(context).pop();
  }

  void _swipeEnded(DragEndDetails details) {
    final swiped =
        _swiped >= _swipeDistance ||
        details.velocity.pixelsPerSecond.dy >= _swipeVelocity;
    _swiped = 0;
    if (swiped) unawaited(_askToDiscard());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final bodyPadding = widget.padding.add(
      EdgeInsets.only(
        bottom: (keyboard > 0 ? 0 : media.padding.bottom) + TracendSpacing.lg,
      ),
    );
    final title = widget.title;
    final header = title == null
        ? null
        : TracendSheetHeader(
            title: title,
            subtitle: widget.subtitle,
            showCloseButton: widget.showCloseButton,
            topPadding: widget.hasDragHandle ? 0 : TracendSpacing.lg,
          );
    Widget body(BuildContext context) => MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: Builder(builder: widget.builder),
    );

    final detents = widget.detents;
    final Widget sheet;
    if (detents != null) {
      sheet = ValueListenableBuilder<bool>(
        valueListenable: _unsaved,
        builder: (context, unsaved, _) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: detents.first,
          minChildSize: detents.first,
          maxChildSize: detents.last,
          shouldCloseOnMinExtent: !unsaved,
          snap: detents.length > 1,
          snapSizes: detents.length > 2
              ? detents.sublist(1, detents.length - 1)
              : null,
          builder: (context, controller) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.hasDragHandle) const TracendSheetHandle(),
              ?header,
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: bodyPadding,
                  child: body(context),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      sheet = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.hasDragHandle) const TracendSheetHandle(),
          ?header,
          Flexible(
            child: widget.scrollable
                ? SingleChildScrollView(
                    padding: bodyPadding,
                    child: body(context),
                  )
                : Padding(padding: bodyPadding, child: body(context)),
          ),
        ],
      );
    }
    // While input is unsaved the close button and the scrim go through
    // `maybePop`, which the PopScope turns into the question. The route's own
    // swipe pops without asking, so a drag recognizer closer to the touch
    // wins it instead; it exists only while unsaved, so a clean sheet keeps
    // the interactive swipe.
    return _UnsavedInputScope(
      input: _unsaved,
      child: ValueListenableBuilder<bool>(
        valueListenable: _unsaved,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: sheet,
        ),
        builder: (context, unsaved, child) => PopScope(
          canPop: !unsaved,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_askToDiscard());
          },
          child: GestureDetector(
            // The swipe is for touch; its scroll actions would merge the
            // whole sheet into one screen reader element.
            excludeFromSemantics: true,
            onVerticalDragStart: unsaved ? (_) => _swiped = 0 : null,
            onVerticalDragUpdate: unsaved
                ? (details) => _swiped += details.delta.dy
                : null,
            onVerticalDragEnd: unsaved ? _swipeEnded : null,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Whether the sheet holds unsaved input. A change that arrives after the
/// sheet is gone (a guard disposed with it) is ignored.
class _UnsavedInput extends ValueNotifier<bool> {
  _UnsavedInput() : super(false);

  var _open = true;

  void close() {
    _open = false;
    dispose();
  }

  void set(bool dirty) {
    if (_open && value != dirty) value = dirty;
  }
}

class _UnsavedInputScope extends InheritedWidget {
  const _UnsavedInputScope({required this.input, required super.child});

  final _UnsavedInput input;

  @override
  bool updateShouldNotify(_UnsavedInputScope oldWidget) =>
      input != oldWidget.input;
}

/// Tells the sheet around it whether the athlete has typed or chosen
/// something that closing would lose. Wrap the body of any sheet that takes
/// input; see [showTracendSheet] for what an unsaved sheet does on a swipe,
/// a scrim tap or the close button.
///
/// [isDirty] is read when the guard is built and whenever [listenable]
/// notifies, so a sheet that rebuilds on every change (`setState`) needs no
/// listenable, and one with text controllers passes
/// `Listenable.merge([...])`. Outside a sheet the guard does nothing.
class TracendSheetUnsavedGuard extends StatefulWidget {
  const TracendSheetUnsavedGuard({
    required this.isDirty,
    required this.child,
    this.listenable,
    super.key,
  });

  final bool Function() isDirty;
  final Listenable? listenable;
  final Widget child;

  @override
  State<TracendSheetUnsavedGuard> createState() =>
      _TracendSheetUnsavedGuardState();
}

class _TracendSheetUnsavedGuardState extends State<TracendSheetUnsavedGuard> {
  _UnsavedInput? _input;

  @override
  void initState() {
    super.initState();
    widget.listenable?.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _input = context
        .dependOnInheritedWidgetOfExactType<_UnsavedInputScope>()
        ?.input;
    _sync();
  }

  @override
  void didUpdateWidget(TracendSheetUnsavedGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable?.removeListener(_sync);
      widget.listenable?.addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_sync);
    _publish(_input, false);
    super.dispose();
  }

  void _sync() => _publish(_input, widget.isDirty());

  /// Changes made while a frame is building wait for its end, so the sheet
  /// is never marked dirty in the middle of building itself.
  static void _publish(_UnsavedInput? input, bool dirty) {
    if (input == null) return;
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      input.set(dirty);
      return;
    }
    binding
      ..addPostFrameCallback((_) => input.set(dirty))
      ..scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The sheet's drag handle: a 36×5 pill, 8pt below the top edge. It is a
/// visual cue only; the whole sheet takes the swipe.
class TracendSheetHandle extends StatelessWidget {
  const TracendSheetHandle({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.only(top: TracendSpacing.xs, bottom: 6),
      child: Center(
        child: Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: context.tracendColors.borderSubtle,
            borderRadius: BorderRadius.circular(TracendRadii.pill),
          ),
        ),
      ),
    ),
  );
}

/// The standard sheet header: a 24pt Archivo title, an optional subtitle and
/// a round close button. [showTracendSheet] adds it when given a title; use
/// it directly only in a sheet that builds its own layout.
class TracendSheetHeader extends StatelessWidget {
  const TracendSheetHeader({
    required this.title,
    this.subtitle,
    this.showCloseButton = true,
    this.topPadding = 0,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool showCloseButton;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        topPadding,
        TracendSpacing.sm,
        TracendSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: TracendSpacing.xxs),
                    Text(subtitle!, style: textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
          if (showCloseButton) ...[
            const SizedBox(width: TracendSpacing.xs),
            const TracendSheetCloseButton(),
          ],
        ],
      ),
    );
  }
}

/// The round close button of a sheet: a 32pt circle in a 44pt target.
class TracendSheetCloseButton extends StatelessWidget {
  const TracendSheetCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Pressable(
      onTap: () => Navigator.of(context).maybePop(),
      semanticLabel: MaterialLocalizations.of(context).closeButtonTooltip,
      borderRadius: BorderRadius.circular(TracendRadii.pill),
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 32,
              child: Icon(
                CupertinoIcons.xmark,
                size: 15,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
