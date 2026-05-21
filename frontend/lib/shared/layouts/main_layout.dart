import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({
    super.key,
    required this.currentRoute,
    required this.child,
    this.title,
  });

  final String currentRoute;
  final Widget child;
  final String? title;

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  static bool _sidebarCollapsed = false;

  static const double _expandedWidth = 220;
  static const double _collapsedWidth = 76;

  String get _activeRoute {
    final route = widget.currentRoute;
    if (route.startsWith('/dashboard')) return '/dashboard';
    if (route.startsWith('/predictions')) return '/predictions';
    if (route.startsWith('/results')) return '/results';
    if (route.startsWith('/history')) return '/history';
    if (route.startsWith('/analytics')) return '/analytics';
    if (route.startsWith('/alerts')) return '/alerts';
    if (route.startsWith('/admin/users')) return '/admin/users';
    if (route.startsWith('/settings')) return '/settings';
    return route;
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarCollapsed = !_sidebarCollapsed;
    });
  }

  void _navigate(String route) {
    if (_activeRoute == route) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = _sidebarCollapsed;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            width: collapsed ? _collapsedWidth : _expandedWidth,
            color: const Color(0xFF0F172A),
            clipBehavior: Clip.hardEdge,
            child: SafeArea(
              bottom: false,
              child: _Sidebar(
                collapsed: collapsed,
                activeRoute: _activeRoute,
                onToggle: _toggleSidebar,
                onNavigate: _navigate,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                // Route transitions are already handled in main.dart.
                // Keeping the page child direct avoids a nested AnimatedSwitcher
                // being disposed while sidebar hover overlays are active.
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.collapsed,
    required this.activeRoute,
    required this.onToggle,
    required this.onNavigate,
  });

  final bool collapsed;
  final String activeRoute;
  final VoidCallback onToggle;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final isAdminUser =
        (_AccountSessionStore.readUsernameSync() ?? '').trim().toLowerCase() == 'admin';

    return Column(
      children: [
        _SidebarHeader(collapsed: collapsed, onToggle: onToggle),
        const Divider(height: 1, thickness: 1, color: Color(0x1AFFFFFF)),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              collapsed ? 10 : 10,
              18,
              collapsed ? 10 : 10,
              18,
            ),
            children: [
              _SectionLabel(label: 'MAIN', collapsed: collapsed),
              const SizedBox(height: 8),
              _NavItem(
                icon: Icons.dashboard_outlined,
                label: 'Dashboard',
                route: '/dashboard',
                collapsed: collapsed,
                selected: activeRoute == '/dashboard',
                onTap: onNavigate,
              ),
              _NavItem(
                icon: Icons.bolt_outlined,
                label: 'Predictions',
                route: '/predictions',
                collapsed: collapsed,
                selected: activeRoute == '/predictions',
                onTap: onNavigate,
              ),
              _NavItem(
                icon: Icons.description_outlined,
                label: 'Results',
                route: '/results',
                collapsed: collapsed,
                selected: activeRoute == '/results',
                onTap: onNavigate,
              ),
              _NavItem(
                icon: Icons.history_rounded,
                label: 'History',
                route: '/history',
                collapsed: collapsed,
                selected: activeRoute == '/history',
                onTap: onNavigate,
              ),
              _NavItem(
                icon: Icons.bar_chart_rounded,
                label: 'Analytics',
                route: '/analytics',
                collapsed: collapsed,
                selected: activeRoute == '/analytics',
                onTap: onNavigate,
              ),
              _NavItem(
                icon: Icons.notifications_none_rounded,
                label: 'Alerts',
                route: '/alerts',
                collapsed: collapsed,
                selected: activeRoute == '/alerts',
                onTap: onNavigate,
              ),
              const SizedBox(height: 18),
              _SectionLabel(label: 'USER', collapsed: collapsed),
              const SizedBox(height: 8),
              _NavItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                route: '/settings',
                collapsed: collapsed,
                selected: activeRoute == '/settings',
                onTap: onNavigate,
              ),
              if (isAdminUser)
                _NavItem(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Admin Users',
                  route: '/admin/users',
                  collapsed: collapsed,
                  selected: activeRoute == '/admin/users',
                  onTap: onNavigate,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.collapsed,
    required this.onToggle,
  });

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // Keep the header height fixed while the sidebar width animates.
    // The previous version changed both the child layout and the height at
    // the same time, so Flutter could briefly give the collapsed header only
    // 56px of inner height while it still contained a logo + button column.
    // That caused the RenderFlex bottom overflow.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      height: 96,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // During expand/collapse, use the compact layout until there is
          // enough width for the title row. This prevents the temporary
          // right overflow that happened while the width was still animating.
          final useCollapsedLayout = collapsed || constraints.maxWidth < 150;

          if (useCollapsedLayout) {
            return _CollapsedHeader(onToggle: onToggle);
          }

          return _ExpandedHeader(onToggle: onToggle);
        },
      ),
    );
  }
}

class _ExpandedHeader extends StatelessWidget {
  const _ExpandedHeader({required this.onToggle});

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _LogoMark(size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRect(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Engine Health',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Monitor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        _CollapseButton(collapsed: false, onTap: onToggle),
      ],
    );
  }
}

class _CollapsedHeader extends StatelessWidget {
  const _CollapsedHeader({required this.onToggle});

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _LogoMark(size: 34),
        const SizedBox(height: 6),
        _CollapseButton(collapsed: true, onTap: onToggle),
      ],
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF2563EB),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.flight_takeoff_rounded,
        color: Colors.white,
        size: size * 0.56,
      ),
    );
  }
}

class _CollapseButton extends StatelessWidget {
  const _CollapseButton({
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: AnimatedRotation(
            turns: collapsed ? 0.5 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            child: const Icon(
              Icons.chevron_left_rounded,
              color: Color(0xFFCBD5E1),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.collapsed});

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      height: collapsed ? 8 : 18,
      alignment: Alignment.centerLeft,
      child: ClipRect(
        child: AnimatedOpacity(
          opacity: collapsed ? 0 : 1,
          duration: const Duration(milliseconds: 160),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: GoogleFonts.inter(
              color: const Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.collapsed,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String route;
  final bool collapsed;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? Colors.white : const Color(0xFFA7B0BE);
    final iconColor = selected ? Colors.white : const Color(0xFF9CA3AF);

    // Do not use Flutter Tooltip here. On Windows desktop, the tooltip
    // overlay can remain attached while a route is replaced from the sidebar,
    // which may trigger framework assertion `_dependents.isEmpty`.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: collapsed ? 6 : 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = collapsed ? 40.0 : constraints.maxWidth;
          final itemHeight = collapsed ? 36.0 : 36.0;
          final borderRadius = BorderRadius.circular(collapsed ? 9 : 8);

          return Align(
            alignment: Alignment.center,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: () => onTap(route),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: itemWidth,
                  height: itemHeight,
                  padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF2563EB) : Colors.transparent,
                    borderRadius: borderRadius,
                  ),
                  child: Row(
                    mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      Icon(icon, color: iconColor, size: collapsed ? 17 : 18),
                      if (!collapsed) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatefulWidget {
  const _TopBar();

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  String _username = 'User';

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final username = await _AccountSessionStore.readUsername();
    if (!mounted) return;
    setState(() {
      _username = username?.trim().isNotEmpty == true ? username!.trim() : 'User';
    });
  }

  Future<void> _signOut() async {
    await _AccountSessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _openSettings() {
    Navigator.of(context).pushReplacementNamed('/settings');
  }

  String get _initials {
    final parts = _username
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      final cleaned = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (cleaned.isEmpty) return 'U';
      return cleaned.substring(0, cleaned.length >= 2 ? 2 : 1).toUpperCase();
    }

    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          _AccountDropdown(
            username: _username,
            initials: _initials,
            onSettings: _openSettings,
            onSignOut: _signOut,
          ),
        ],
      ),
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.username,
    required this.initials,
    required this.onSettings,
    required this.onSignOut,
  });

  final String username;
  final String initials;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_AccountAction>(
      tooltip: '',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      onSelected: (action) {
        switch (action) {
          case _AccountAction.account:
            break;
          case _AccountAction.settings:
            onSettings();
            break;
          case _AccountAction.signOut:
            onSignOut();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_AccountAction>(
          value: _AccountAction.account,
          enabled: false,
          height: 34,
          child: Text(
            'My Account',
            style: GoogleFonts.inter(
              color: const Color(0xFF111827),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<_AccountAction>(
          value: _AccountAction.settings,
          height: 38,
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 12),
              Text(
                'Settings',
                style: GoogleFonts.inter(
                  color: const Color(0xFF111827),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_AccountAction>(
          value: _AccountAction.signOut,
          height: 38,
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 12),
              Text(
                'Sign Out',
                style: GoogleFonts.inter(
                  color: const Color(0xFFDC2626),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF2563EB),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 9),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: const Color(0xFF111827),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
        ],
      ),
    );
  }
}

enum _AccountAction { account, settings, signOut }

class _AccountSessionStore {
  static String? _cachedUsername;
  static Future<File> _sessionFile() async {
    final appData = Platform.environment['APPDATA'];
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final basePath = appData != null && appData.trim().isNotEmpty
        ? appData
        : '${home ?? '.'}${Platform.pathSeparator}.config';

    final directory = Directory(
      '$basePath${Platform.pathSeparator}EngineHealthMonitor',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return File('${directory.path}${Platform.pathSeparator}current_user.json');
  }

  static File _sessionFileSync() {
    final appData = Platform.environment['APPDATA'];
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final basePath = appData != null && appData.trim().isNotEmpty
        ? appData
        : '${home ?? '.'}${Platform.pathSeparator}.config';

    final directoryPath = '$basePath${Platform.pathSeparator}EngineHealthMonitor';
    return File('$directoryPath${Platform.pathSeparator}current_user.json');
  }

  static String? readUsernameSync() {
    try {
      final file = _sessionFileSync();
      if (!file.existsSync()) {
        _cachedUsername = null;
        return null;
      }

      final data = jsonDecode(file.readAsStringSync());
      if (data is Map<String, dynamic>) {
        final username = '${data['username'] ?? ''}'.trim();
        _cachedUsername = username.isNotEmpty ? username : null;
        return _cachedUsername;
      }
    } catch (_) {
      _cachedUsername = null;
      return null;
    }

    _cachedUsername = null;
    return null;
  }

  static Future<String?> readUsername() async {
    try {
      final file = await _sessionFile();
      if (!await file.exists()) {
        _cachedUsername = null;
        return null;
      }

      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) {
        final username = '${data['username'] ?? ''}'.trim();
        _cachedUsername = username.isNotEmpty ? username : null;
        return _cachedUsername;
      }
    } catch (_) {
      _cachedUsername = null;
      return null;
    }

    _cachedUsername = null;
    return null;
  }

  static Future<void> clear() async {
    _cachedUsername = null;
    try {
      final file = await _sessionFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore sign-out cleanup failures so navigation can continue.
    }
  }
}
