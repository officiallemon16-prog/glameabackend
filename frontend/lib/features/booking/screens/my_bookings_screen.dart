import 'package:flutter/material.dart';

import '../../../shared/widgets/app_bar.dart';
import 'my_bookings_tab.dart';

/// Full-screen booking list (opened from the Profile tab).
class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: GlameaAppBar(title: 'My bookings'),
      body: MyBookingsTab(showTitle: false),
    );
  }
}
