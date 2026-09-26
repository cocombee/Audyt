import 'package:flutter/material.dart';

/// Named colors from the supplied chart swatches. The large bars contribute
/// one shade each; their matching small swatches are not duplicate entries.
final class AccountingColorLibrary {
  AccountingColorLibrary._();

  static const primaryGreen = Color(0xFF23AF83);
  static const grapefruit = Color(0xFFED5565);
  static const grapefruitDeep = Color(0xFFDA4453);
  static const bittersweet = Color(0xFFFC6E51);
  static const bittersweetDeep = Color(0xFFE9573F);
  static const sunflower = Color(0xFFFFCE54);
  static const sunflowerDeep = Color(0xFFF6BB42);
  static const mint = Color(0xFF48CFAD);
  static const mintDeep = Color(0xFF37BC9B);
  static const aqua = Color(0xFF4FC1E9);
  static const aquaDeep = Color(0xFF3BAFDA);
  static const blueJeans = Color(0xFF5D9CEC);
  static const blueJeansDeep = Color(0xFF4A89DC);
  static const lavender = Color(0xFFAC92EC);
  static const lavenderDeep = Color(0xFF967ADC);
  static const pinkRose = Color(0xFFEC87C0);
  static const pinkRoseDeep = Color(0xFFD770AD);

  /// Reminder colours belong to the visible card group, in deadline order.
  static const reminderCycle = [
    grapefruit,
    blueJeansDeep,
    sunflowerDeep,
    primaryGreen,
  ];
  static Color reminderColor(int index, int count) =>
      reminderCycle[index % (count >= 4 ? 4 : 3)];

  /// Charts sort by value: the largest item uses the shared green. Continue
  /// with the five large-bar colors, then the unused swatches. Related shades
  /// are separated by other families, including at wraparound.
  static const chartSeries = <Color>[
    primaryGreen,
    grapefruit,
    aquaDeep,
    lavender,
    sunflowerDeep,
    pinkRose,
    mint,
    blueJeansDeep,
    bittersweet,
    lavenderDeep,
    sunflower,
    pinkRoseDeep,
    mintDeep,
    grapefruitDeep,
    blueJeans,
    bittersweetDeep,
    aqua,
  ];
}
