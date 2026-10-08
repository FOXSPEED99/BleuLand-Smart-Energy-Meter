// Design tokens: every colour, size and radius the app uses lives here.
// Dark theme only (brand decision). Colours come from the SEM-1 front label
// (teal accent on charcoal) and were checked with the data-viz palette
// validator against the card surface.
import 'package:flutter/material.dart';

abstract final class C {
  // surfaces, darkest to lightest
  static const bg = Color(0xFF0E1114);
  static const surface = Color(0xFF171B20); // cards; chart surface
  static const surface2 = Color(0xFF1E242A); // raised: inputs, chips, sheets
  static const outline = Color(0xFF2A3139);
  static const grid = Color(0xFF252C33); // hairline gridlines

  // text
  static const text = Color(0xFFEEF2F4);
  static const text2 = Color(0xFFA3AFB7);
  static const text3 = Color(0xFF6E7A83);

  // brand
  static const brand = Color(0xFF1FC8A0); // label teal: buttons, highlights
  static const onBrand = Color(0xFF06231C);
  static const series = Color(0xFF139C7C); // chart marks (passes dark-band checks)
  static const seriesWash = Color(0x1A139C7C); // 10 % area fill

  // status (fixed; always shown with an icon + label, never colour alone)
  static const good = Color(0xFF0CA30C);
  static const goodText = Color(0xFF4CC94C);
  static const warning = Color(0xFFFAB219);
  static const serious = Color(0xFFEC835A);
  static const critical = Color(0xFFD03B3B);
  static const criticalText = Color(0xFFF07070);
}

abstract final class R {
  static const xl = 28.0; // hero card
  static const lg = 20.0; // cards
  static const md = 14.0; // inputs, buttons
  static const sm = 10.0; // chips
}

abstract final class S {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const page = 20.0; // side gutter
}
