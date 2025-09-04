// lib/widgets/eco_pet.dart
import 'package:flutter/material.dart';

enum PetMood { neutral, happy, sad }

class EcoPet extends StatelessWidget {
  final PetMood mood;

  const EcoPet({super.key, required this.mood});

  String _assetForMood() {
    switch (mood) {
      case PetMood.happy:
        return 'assets/images/eco_pet/eco_pet_happy.jpg';
      case PetMood.sad:
        return 'assets/images/eco_pet/eco_pet_sad.jpg';
      case PetMood.neutral:
      default:
        return 'assets/images/eco_pet/eco_pet_neutral.jpg';
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              _assetForMood(),
              height: 120,
              fit: BoxFit.contain,
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
        ),
      ),
    );
  }
}
