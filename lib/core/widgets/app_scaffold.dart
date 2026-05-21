import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';

class AppScaffold extends StatelessWidget {
  final Widget body;
  final String title;
  final SystemUiOverlayStyle systemUiOverlayStyle;
  final List<Widget>? actions;
  final Color appBarColor;
  final Color drawerHeaderColor;

  const AppScaffold({
    super.key,
    required this.body,
    required this.title,
    required this.systemUiOverlayStyle,
    this.actions,
    this.appBarColor = Colors.indigo,
    this.drawerHeaderColor = Colors.indigo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(headerColor: drawerHeaderColor),
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        systemOverlayStyle: systemUiOverlayStyle,
        actions: actions,
      ),
      body: body,
    );
  }
}
