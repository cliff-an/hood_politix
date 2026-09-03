import 'package:flutter/material.dart';
import 'package:hp_card_game/models/counter_state.dart';
import 'package:provider/provider.dart';
class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Counter Example'),
      ),
      body: Center(
        child: Consumer<CounterState>(
          builder: (context, counterState, child) => Text(
            'Count: ${counterState.count}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Zugriff auf den Zustand über den Provider und führe eine Aktion aus
          Provider.of<CounterState>(context, listen: false).increment();
        },
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
