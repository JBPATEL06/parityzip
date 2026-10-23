import 'package:flutter/material.dart';

class AppNavigationController extends ChangeNotifier {
  int _currentTabIndex = 0;
  int get currentTabIndex => _currentTabIndex;

  String? _preselectedRepairFile;
  String? get preselectedRepairFile => _preselectedRepairFile;

  TabController? _tabController;

  void attachTabController(TabController controller) {
    _tabController = controller;
  }

  void switchTab(int index) {
    _currentTabIndex = index;
    if (_tabController != null && _tabController!.index != index) {
      _tabController!.animateTo(index);
    }
    notifyListeners();
  }

  void goToRepair(String par2FilePath) {
    _preselectedRepairFile = par2FilePath;
    switchTab(2); // Index 2 is Repair tab
  }

  void clearPreselectedRepairFile() {
    _preselectedRepairFile = null;
  }
}
