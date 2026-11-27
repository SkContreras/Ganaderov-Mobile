import 'package:material_ui/material_ui.dart';

import '../../../../core/widgets/ranch_illustration.dart';

class RanchScene extends StatelessWidget {
  const RanchScene({super.key, required this.hideEyes});

  final bool hideEyes;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final light = hour < 6 || hour >= 19 ? 'night' : 'day';
    final expression = hideEyes ? '-closed' : '';
    return RanchIllustration(
      'ranch-login-$light$expression',
      aspectRatio: 2.2,
      maxWidth: 440,
    );
  }
}
