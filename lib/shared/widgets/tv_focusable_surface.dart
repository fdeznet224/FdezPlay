import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color kTvFocusNeonColor = Color(0xFFFFFFFF);
const Color kTvFocusGlowColor = Color(0xCC6F8CFF);
const Color kTvFocusFillColor = Color(0x33263B75);

/// Superficie reutilizable para que tarjetas táctiles también puedan manejarse
/// con flechas y botón OK/Enter en Android TV y Google TV.
class TvFocusableSurface extends StatefulWidget {
  const TvFocusableSurface({
    required this.enabled,
    required this.onPressed,
    required this.builder,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.onKeyEvent,
    this.showNeonWhenFocused = true,
    super.key,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final Widget Function(BuildContext context, bool focused) builder;
  final bool autofocus;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;
  final FocusOnKeyEventCallback? onKeyEvent;
  final bool showNeonWhenFocused;

  @override
  State<TvFocusableSurface> createState() => _TvFocusableSurfaceState();
}

class _TvFocusableSurfaceState extends State<TvFocusableSurface> {
  bool _focused = false;

  void _setFocused(bool focused) {
    if (_focused == focused || !mounted) {
      return;
    }

    setState(() {
      _focused = focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(context, _focused);

    if (!widget.enabled) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: widget.borderRadius,
          child: content,
        ),
      );
    }

    final decoratedContent = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      foregroundDecoration: widget.showNeonWhenFocused && _focused
          ? tvNeonOutlineDecoration(borderRadius: widget.borderRadius)
          : null,
      child: content,
    );

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _setFocused,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        final customResult = widget.onKeyEvent?.call(node, event);
        if (customResult == KeyEventResult.handled) {
          return KeyEventResult.handled;
        }

        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space) {
          widget.onPressed();
          return KeyEventResult.handled;
        }

        return customResult ?? KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _focused ? 1.055 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: widget.onPressed,
            borderRadius: widget.borderRadius,
            child: decoratedContent,
          ),
        ),
      ),
    );
  }
}

/// Envoltura genérica para botones, iconos, campos o acciones que no usan
/// [TvFocusableSurface], pero que también deben mostrar el marco neón en TV.
class TvNeonFocus extends StatefulWidget {
  const TvNeonFocus({
    required this.child,
    this.enabled = true,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding = EdgeInsets.zero,
    this.scale = 1.035,
    this.onPressed,
    this.onKeyEvent,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final FocusNode? focusNode;
  final bool autofocus;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double scale;
  final VoidCallback? onPressed;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<TvNeonFocus> createState() => _TvNeonFocusState();
}

class _TvNeonFocusState extends State<TvNeonFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (_focused != focused && mounted) {
          setState(() {
            _focused = focused;
          });
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        final customResult = widget.onKeyEvent?.call(node, event);
        if (customResult == KeyEventResult.handled) {
          return KeyEventResult.handled;
        }

        final key = event.logicalKey;
        if (widget.onPressed != null &&
            (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter ||
                key == LogicalKeyboardKey.space)) {
          widget.onPressed!();
          return KeyEventResult.handled;
        }

        return customResult ?? KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _focused ? widget.scale : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          padding: widget.padding,
          foregroundDecoration: _focused
              ? tvNeonOutlineDecoration(borderRadius: widget.borderRadius)
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Decoración de foco neón reutilizable en todo Android TV / Google TV.
Decoration tvNeonOutlineDecoration({
  required BorderRadius borderRadius,
  Color color = kTvFocusNeonColor,
  Color glowColor = kTvFocusGlowColor,
  double borderWidth = 3.4,
  double blurRadius = 24,
  double spreadRadius = 2.5,
}) {
  return BoxDecoration(
    borderRadius: borderRadius,
    border: Border.all(color: color, width: borderWidth),
    boxShadow: [
      BoxShadow(
        color: glowColor,
        blurRadius: blurRadius,
        spreadRadius: spreadRadius,
      ),
    ],
  );
}

/// Borde uniforme para indicar claramente el elemento enfocado en televisión.
BoxDecoration tvFocusedDecoration({
  required bool focused,
  required Color backgroundColor,
  required BorderRadius borderRadius,
  Color normalBorderColor = const Color(0xFF242A36),
}) {
  return BoxDecoration(
    color: focused ? Color.alphaBlend(kTvFocusFillColor, backgroundColor) : backgroundColor,
    borderRadius: borderRadius,
    border: Border.all(
      color: focused ? kTvFocusNeonColor : normalBorderColor,
      width: focused ? 3.4 : 1,
    ),
    boxShadow: focused
        ? const [
            BoxShadow(
              color: kTvFocusGlowColor,
              blurRadius: 24,
              spreadRadius: 2.5,
            ),
          ]
        : null,
  );
}
