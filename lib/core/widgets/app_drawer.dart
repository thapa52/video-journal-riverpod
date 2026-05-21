import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/user_provider.dart';
import '../utils/system_ui_helper.dart';

class AppDrawer extends ConsumerWidget {
  final Color headerColor;
  const AppDrawer({super.key, required this.headerColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final fullName = user?.fullName ?? 'User';
    final email = user?.email ?? '';
    return Drawer(
      width: MediaQuery.of(context).size.width,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUIHelper.custom(statusBarColor: headerColor),
        child: SafeArea(
          child: ListView(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: headerColor),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 40,
                      child: Icon(Icons.person, size: 30, color: Colors.black),
                    ),
                    Text(fullName),
                    Text(email),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
