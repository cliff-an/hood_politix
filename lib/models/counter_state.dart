import 'package:flutter/material.dart';

class CounterState extends ChangeNotifier {
  int _count = 0;

  int get count => _count;

  void increment() {
    _count++;
    notifyListeners(); // Benachrichtige Widgets, die diesen Zustand abhören.
  }
}
