import 'package:material_ui/material_ui.dart';

/// A decorative image bundled from the corresponding Ganaderov web screen.
class RanchIllustration extends StatelessWidget {
  const RanchIllustration(
    this.name, {
    super.key,
    this.aspectRatio = 2.45,
    this.maxWidth = 420,
  });

  final String name;
  final double aspectRatio;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/$name.webp',
              fit: BoxFit.cover,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}
