import 'package:flutter/material.dart';

import '../../shared/widgets/app_back_handler.dart';
import 'screens/pro_account_tab.dart';
import 'screens/pro_availability_tab.dart';
import 'screens/pro_bookings_tab.dart';
import 'screens/pro_dashboard_tab.dart';
import 'screens/pro_services_tab.dart';

/// Professional shell: Dashboard, Bookings, Services, Availability, Account.
class ProShell extends StatefulWidget {
  const ProShell({super.key});

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return AppBackHandler(
      child: Scaffold(
        body: IndexedStack(
        index: _index,
        children: const [
          ProDashboardTab(),
          ProBookingsTab(),
          ProServicesTab(),
          ProAvailabilityTab(),
          ProAccountTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0x3DC98F86),
        surfaceTintColor: Colors.transparent,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.content_cut_outlined), selectedIcon: Icon(Icons.content_cut), label: 'Services'),
          NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Availability'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Account'),
        ],
      ),
    ),
  );
  }
}
