import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import './custom_icon_widget.dart';
import '../theme/app_theme.dart';
import '../services/locale_provider.dart';
import '../services/theme_provider.dart';
import '../services/app_strings.dart';

class AppNavigation extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppNavigation({required this.navigationShell, super.key});

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation> {
  int _selectedVisualIndex = 0;

  static const List<_TabSpec> _tabs = [
    _TabSpec(icon: 'home_outlined', selectedIcon: 'home', branchIndex: 0),
    _TabSpec(
      icon: 'back_hand_outlined',
      selectedIcon: 'back_hand',
      branchIndex: 1,
    ),
    _TabSpec(
      icon: 'auto_awesome_outlined',
      selectedIcon: 'auto_awesome',
      branchIndex: 2,
    ),
    _TabSpec(icon: 'favorite_border', selectedIcon: 'favorite', branchIndex: 3),
    _TabSpec(icon: 'person_outline', selectedIcon: 'person', branchIndex: 4),
  ];

  void _onTabTap(int visualIndex) {
    final tab = _tabs[visualIndex];
    setState(() => _selectedVisualIndex = visualIndex);
    widget.navigationShell.goBranch(
      tab.branchIndex,
      initialLocation: tab.branchIndex == widget.navigationShell.currentIndex,
    );
  }

  @override
  void didUpdateWidget(AppNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentBranch = widget.navigationShell.currentIndex;
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].branchIndex == currentBranch) {
        _selectedVisualIndex = i;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final s = AppStrings.of(localeProvider.languageCode);
    final isDark = themeProvider.isDark;

    final navBg = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final navBorder = isDark ? AppTheme.outlineDark : AppTheme.outlineLight;
    final activeGradient = isDark
        ? AppTheme.goldGradient
        : AppTheme.purpleGradientLight;
    final activeTextColor = isDark ? const Color(0xFF0A0A0F) : Colors.white;
    final inactiveIconColor = isDark
        ? AppTheme.textMuted
        : AppTheme.textMutedLight;

    final tabLabels = [s.home, s.scan, s.readings, s.couple, s.profile];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: navBg,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: navBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 100 : 30),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_tabs.length, (index) {
              final tab = _tabs[index];
              final isActive = _selectedVisualIndex == index;

              return Expanded(
                child: GestureDetector(
                  onTap: () => _onTabTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: isActive ? activeGradient : null,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CustomIconWidget(
                          iconName: isActive ? tab.selectedIcon : tab.icon,
                          color: isActive ? activeTextColor : inactiveIconColor,
                          size: 20,
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 2),
                          Text(
                            tabLabels[index],
                            style: TextStyle(
                              color: activeTextColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  final String icon;
  final String selectedIcon;
  final int branchIndex;

  const _TabSpec({
    required this.icon,
    required this.selectedIcon,
    required this.branchIndex,
  });
}
