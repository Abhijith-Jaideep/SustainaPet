// lib/widgets/eco_pet.dart
import 'package:flutter/material.dart';
import '../api/pawprint_api.dart' show PetMood; // import the enum

class EcoPet extends StatelessWidget {
  final PetMood mood;

  const EcoPet({super.key, required this.mood});

  String _assetForMood() {
    switch (mood) {
      case PetMood.happy:
        return 'assets/images/eco_pet/eco_pet_happy.png';
      case PetMood.sad:
        return 'assets/images/eco_pet/eco_pet_sad.png';
      case PetMood.neutral:
      default:
        return 'assets/images/eco_pet/eco_pet_neutral.png';
    }
  }

  String _messageForMood() {
    switch (mood) {
      case PetMood.happy:
        return "I'm feeling great about your eco-choices!";
      case PetMood.sad:
        return "I'm worried about your eco-choices...";
      case PetMood.neutral:
      default:
        return "Let's keep making eco-friendly choices!";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Full-size pet image (expands to parent constraints)
        Expanded(
          child: Image.asset(
            _assetForMood(),
            fit: BoxFit.contain, // scale without cropping
            width: double.infinity,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _messageForMood(),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: Colors.green),
        ),
      ],
    );
  }
}
