import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../shared/layouts/main_layout.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedTab = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  OverlayEntry? _toastEntry;

  late AppSettingsData _settings;

  final TextEditingController _recipientController = TextEditingController();

  static const List<_SettingsTabItem> _tabs = [
    _SettingsTabItem(label: 'General', icon: Icons.tune_rounded),
    _SettingsTabItem(label: 'Notifications', icon: Icons.notifications_none_rounded),
    _SettingsTabItem(label: 'Display', icon: Icons.monitor_rounded),
    _SettingsTabItem(label: 'Maintenance Mail', icon: Icons.mail_outline_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _settings = AppSettingsData.defaults();
    _loadSettings();
  }

  @override
  void dispose() {
    _toastEntry?.remove();
    _toastEntry = null;
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final loaded = await AppSettingsStorage.load();
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await AppSettingsStorage.save(_settings);
      if (!mounted) return;
      _showMessage('Settings saved successfully.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Failed to save settings: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _resetSettings() async {
    setState(() {
      _settings = AppSettingsData.defaults();
    });
    await _saveSettings();
  }

  void _addRecipient() {
    final email = _recipientController.text.trim();

    if (email.isEmpty) return;

    if (!_isValidEmail(email)) {
      _showMessage('Enter a valid email address.', isError: true);
      return;
    }

    final alreadyExists = _settings.maintenanceRecipients
        .any((item) => item.toLowerCase() == email.toLowerCase());

    if (alreadyExists) {
      _showMessage('This email is already in the recipient list.', isError: true);
      return;
    }

    setState(() {
      _settings = _settings.copyWith(
        maintenanceRecipients: [
          ..._settings.maintenanceRecipients,
          email,
        ],
      );
      _recipientController.clear();
    });
  }

  void _removeRecipient(String email) {
    setState(() {
      _settings = _settings.copyWith(
        maintenanceRecipients: _settings.maintenanceRecipients
            .where((item) => item != email)
            .toList(),
      );
    });
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  void _showMessage(String message, {bool isError = false}) {
    _showTemplatePopup(
      title: isError ? 'Settings error' : 'Settings saved',
      message: message,
      isError: isError,
    );
  }

  void _showTemplatePopup({
    required String title,
    required String message,
    bool isError = false,
  }) {
    _toastEntry?.remove();
    _toastEntry = null;

    final overlay = Overlay.of(context);
    final accentColor = isError ? SettingsPalette.critical : const Color(0xFF22C55E);
    final backgroundColor = isError ? const Color(0xFFFFF1F2) : const Color(0xFFEFFBF4);
    final borderColor = isError ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0);
    final icon = isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          right: 24,
          bottom: 24,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset((1 - value) * 16, 0),
                    child: child,
                  ),
                );
              },
              child: Container(
                width: 350,
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                decoration: BoxDecoration(
                  color: SettingsPalette.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: accentColor, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: SettingsPalette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SettingsPalette.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        entry.remove();
                        if (identical(_toastEntry, entry)) _toastEntry = null;
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: SettingsPalette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    _toastEntry = entry;
    overlay.insert(entry);

    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (identical(_toastEntry, entry)) {
        entry.remove();
        _toastEntry = null;
      }
    });
  }

  Future<void> _signOut() async {
    await AppSettingsStorage.clearCurrentUser();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      currentRoute: '/settings',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Container(
      color: SettingsPalette.pageBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 42),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Application Settings',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: SettingsPalette.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Configure feasible frontend preferences and maintenance email recipients',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: SettingsPalette.textMuted,
                  ),
                ),
                const SizedBox(height: 22),
                _SettingsTabs(
                  tabs: _tabs,
                  selectedIndex: _selectedTab >= _tabs.length ? _tabs.length - 1 : _selectedTab,
                  onSelected: (index) {
                    setState(() => _selectedTab = index);
                  },
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _isLoading
                      ? const _LoadingCard(key: ValueKey('loading'))
                      : _buildSelectedTabContent(),
                ),
                const SizedBox(height: 20),
                _SettingsActions(
                  isSaving: _isSaving,
                  onSave: _saveSettings,
                  onReset: _resetSettings,
                  onSignOut: _signOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedTab) {
      case 0:
        return _GeneralSettingsCard(
          key: const ValueKey('general'),
          settings: _settings,
          onChanged: (updated) => setState(() => _settings = updated),
        );
      case 1:
        return _NotificationSettingsCard(
          key: const ValueKey('notifications'),
          settings: _settings,
          onChanged: (updated) => setState(() => _settings = updated),
        );
      case 2:
        return _DisplaySettingsCard(
          key: const ValueKey('display'),
          settings: _settings,
          onChanged: (updated) => setState(() => _settings = updated),
        );
      case 3:
        return _MaintenanceEmailCard(
          key: const ValueKey('maintenance-mail'),
          recipients: _settings.maintenanceRecipients,
          controller: _recipientController,
          onAddRecipient: _addRecipient,
          onRemoveRecipient: _removeRecipient,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_SettingsTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SettingsPalette.segmentBackground,
        borderRadius: BorderRadius.circular(18),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int index = 0; index < tabs.length; index++)
              _SettingsTabButton(
                item: tabs[index],
                selected: index == selectedIndex,
                onTap: () => onSelected(index),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTabButton extends StatelessWidget {
  const _SettingsTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _SettingsTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x0A101828),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 15,
                color: selected ? SettingsPalette.textPrimary : SettingsPalette.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? SettingsPalette.textPrimary : SettingsPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeneralSettingsCard extends StatelessWidget {
  const _GeneralSettingsCard({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final AppSettingsData settings;
  final ValueChanged<AppSettingsData> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Regional Settings',
      subtitle: 'These settings are frontend-only and can be used later for formatting dates and times.',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DropdownSetting(
                  label: 'Language',
                  value: settings.language,
                  options: const ['English'],
                  onChanged: (value) => onChanged(settings.copyWith(language: value)),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _DropdownSetting(
                  label: 'Timezone',
                  value: settings.timezone,
                  options: const ['UTC', 'Local Time'],
                  onChanged: (value) => onChanged(settings.copyWith(timezone: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DropdownSetting(
                  label: 'Date Format',
                  value: settings.dateFormat,
                  options: const ['YYYY-MM-DD HH:mm', 'DD/MM/YYYY HH:mm', 'MM/DD/YYYY HH:mm'],
                  onChanged: (value) => onChanged(settings.copyWith(dateFormat: value)),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _DropdownSetting(
                  label: 'Time Format',
                  value: settings.timeFormat,
                  options: const ['24-hour', '12-hour'],
                  onChanged: (value) => onChanged(settings.copyWith(timeFormat: value)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationSettingsCard extends StatelessWidget {
  const _NotificationSettingsCard({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final AppSettingsData settings;
  final ValueChanged<AppSettingsData> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Notification Preferences',
      subtitle: 'These options are frontend preferences. Alert creation still comes from the backend prediction flow.',
      child: Column(
        children: [
          _SwitchSetting(
            title: 'Show Critical Alerts',
            subtitle: 'Display critical engine alerts in the alerts queue.',
            value: settings.showCriticalAlerts,
            onChanged: (value) => onChanged(settings.copyWith(showCriticalAlerts: value)),
          ),
          const Divider(height: 28, color: SettingsPalette.border),
          _SwitchSetting(
            title: 'Show Watch Alerts',
            subtitle: 'Display watch-level engine alerts in the alerts queue.',
            value: settings.showWatchAlerts,
            onChanged: (value) => onChanged(settings.copyWith(showWatchAlerts: value)),
          ),
        ],
      ),
    );
  }
}

class _DisplaySettingsCard extends StatelessWidget {
  const _DisplaySettingsCard({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final AppSettingsData settings;
  final ValueChanged<AppSettingsData> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Dashboard Preferences',
      subtitle: 'Choose the first page opened after signing in.',
      child: _DropdownSetting(
        label: 'Default Landing Page',
        value: settings.defaultLandingPage,
        options: const ['Dashboard', 'Predictions', 'Results', 'History', 'Analytics', 'Alerts'],
        onChanged: (value) => onChanged(settings.copyWith(defaultLandingPage: value)),
      ),
    );
  }
}

class _MaintenanceEmailCard extends StatelessWidget {
  const _MaintenanceEmailCard({
    super.key,
    required this.recipients,
    required this.controller,
    required this.onAddRecipient,
    required this.onRemoveRecipient,
  });

  final List<String> recipients;
  final TextEditingController controller;
  final VoidCallback onAddRecipient;
  final ValueChanged<String> onRemoveRecipient;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Email Recipients',
      subtitle: 'Only the maintenance recipient list is kept here. Automated reports and report content preferences were removed.',
      leadingIcon: Icons.mail_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recipient Email Addresses',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: SettingsPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'These addresses can later be used as the default maintenance recipients when sending reports.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: SettingsPalette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAddRecipient(),
                  decoration: _InputStyles.inputDecoration(
                    hintText: 'email@example.com',
                    prefixIcon: Icons.alternate_email_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: onAddRecipient,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: SettingsPalette.navDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (recipients.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: SettingsPalette.inputBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SettingsPalette.border),
              ),
              child: const Text(
                'No recipients added yet.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SettingsPalette.textMuted,
                ),
              ),
            )
          else
            Column(
              children: [
                for (final email in recipients)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RecipientTile(
                      email: email,
                      onRemove: () => onRemoveRecipient(email),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.email,
    required this.onRemove,
  });

  final String email;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: SettingsPalette.inputBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SettingsPalette.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.mail_outline_rounded,
            size: 17,
            color: SettingsPalette.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              email,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SettingsPalette.textPrimary,
              ),
            ),
          ),
          IconButton(
            splashRadius: 18,
            onPressed: onRemove,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: SettingsPalette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.leadingIcon,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: SettingsPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leadingIcon != null) ...[
                Icon(
                  leadingIcon,
                  size: 19,
                  color: SettingsPalette.textPrimary,
                ),
                const SizedBox(width: 9),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SettingsPalette.textPrimary,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 7),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: SettingsPalette.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 26),
          child,
        ],
      ),
    );
  }
}

class _DropdownSetting extends StatelessWidget {
  const _DropdownSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: SettingsPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: options.contains(value) ? value : options.first,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, size: 20),
          decoration: _InputStyles.inputDecoration(hintText: ''),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: options
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SettingsPalette.textPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ],
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: SettingsPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: SettingsPalette.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeColor: Colors.white,
          activeTrackColor: SettingsPalette.navDark,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: SettingsPalette.border,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SettingsActions extends StatelessWidget {
  const _SettingsActions({
    required this.isSaving,
    required this.onSave,
    required this.onReset,
    required this.onSignOut,
  });

  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          height: 38,
          child: ElevatedButton.icon(
            onPressed: isSaving ? null : onSave,
            icon: isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 17),
            label: Text(isSaving ? 'Saving...' : 'Save Changes'),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: SettingsPalette.navDark,
              disabledBackgroundColor: SettingsPalette.navDark.withOpacity(0.7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        SizedBox(
          height: 38,
          child: OutlinedButton(
            onPressed: isSaving ? null : onReset,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: SettingsPalette.border),
              foregroundColor: SettingsPalette.textPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: const Text('Reset to Defaults'),
          ),
        ),
        SizedBox(
          height: 38,
          child: OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded, size: 17),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: SettingsPalette.border),
              foregroundColor: SettingsPalette.textPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsCard(
      title: 'Loading Settings',
      child: SizedBox(
        height: 160,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

class _SettingsTabItem {
  const _SettingsTabItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _InputStyles {
  static InputDecoration inputDecoration({
    required String hintText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 17, color: SettingsPalette.textMuted),
      hintStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: SettingsPalette.placeholder,
      ),
      filled: true,
      fillColor: SettingsPalette.inputBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SettingsPalette.blue, width: 1.1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SettingsPalette.critical, width: 1.1),
      ),
    );
  }
}

class AppSettingsData {
  const AppSettingsData({
    required this.language,
    required this.timezone,
    required this.dateFormat,
    required this.timeFormat,
    required this.showCriticalAlerts,
    required this.showWatchAlerts,
    required this.defaultLandingPage,
    required this.maintenanceRecipients,
  });

  final String language;
  final String timezone;
  final String dateFormat;
  final String timeFormat;
  final bool showCriticalAlerts;
  final bool showWatchAlerts;
  final String defaultLandingPage;
  final List<String> maintenanceRecipients;

  static AppSettingsData defaults() {
    return const AppSettingsData(
      language: 'English',
      timezone: 'UTC',
      dateFormat: 'YYYY-MM-DD HH:mm',
      timeFormat: '24-hour',
      showCriticalAlerts: true,
      showWatchAlerts: true,
      defaultLandingPage: 'Dashboard',
      maintenanceRecipients: [
        'grad.maintenance.team@gmail.com',
      ],
    );
  }

  AppSettingsData copyWith({
    String? language,
    String? timezone,
    String? dateFormat,
    String? timeFormat,
    bool? showCriticalAlerts,
    bool? showWatchAlerts,
    String? defaultLandingPage,
    List<String>? maintenanceRecipients,
  }) {
    return AppSettingsData(
      language: language ?? this.language,
      timezone: timezone ?? this.timezone,
      dateFormat: dateFormat ?? this.dateFormat,
      timeFormat: timeFormat ?? this.timeFormat,
      showCriticalAlerts: showCriticalAlerts ?? this.showCriticalAlerts,
      showWatchAlerts: showWatchAlerts ?? this.showWatchAlerts,
      defaultLandingPage: defaultLandingPage ?? this.defaultLandingPage,
      maintenanceRecipients: maintenanceRecipients ?? this.maintenanceRecipients,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'language': language,
      'timezone': timezone,
      'dateFormat': dateFormat,
      'timeFormat': timeFormat,
      'showCriticalAlerts': showCriticalAlerts,
      'showWatchAlerts': showWatchAlerts,
      'defaultLandingPage': defaultLandingPage,
      'maintenanceRecipients': maintenanceRecipients,
    };
  }

  factory AppSettingsData.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettingsData.defaults();

    return AppSettingsData(
      language: json['language'] as String? ?? defaults.language,
      timezone: json['timezone'] as String? ?? defaults.timezone,
      dateFormat: json['dateFormat'] as String? ?? defaults.dateFormat,
      timeFormat: json['timeFormat'] as String? ?? defaults.timeFormat,
      showCriticalAlerts: json['showCriticalAlerts'] as bool? ?? defaults.showCriticalAlerts,
      showWatchAlerts: json['showWatchAlerts'] as bool? ?? defaults.showWatchAlerts,
      defaultLandingPage: json['defaultLandingPage'] as String? ?? defaults.defaultLandingPage,
      maintenanceRecipients: (json['maintenanceRecipients'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          defaults.maintenanceRecipients,
    );
  }
}

class AppSettingsStorage {
  const AppSettingsStorage._();

  static Future<AppSettingsData> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        return AppSettingsData.defaults();
      }
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return AppSettingsData.fromJson(decoded);
      }
      return AppSettingsData.defaults();
    } catch (_) {
      return AppSettingsData.defaults();
    }
  }

  static Future<void> save(AppSettingsData settings) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(settings.toJson()));
  }

  static Future<List<String>> loadMaintenanceRecipients() async {
    final settings = await load();
    return settings.maintenanceRecipients;
  }

  static Future<void> clearCurrentUser() async {
    final file = await _currentUserFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<File> _currentUserFile() async {
    final baseDir = await _appDataDir();
    return File('${baseDir.path}${Platform.pathSeparator}current_user.json');
  }

  static Future<File> _settingsFile() async {
    final baseDir = await _appDataDir();
    return File('${baseDir.path}${Platform.pathSeparator}settings.json');
  }

  static Future<Directory> _appDataDir() async {
    final env = Platform.environment;
    final String basePath;

    if (Platform.isWindows && (env['APPDATA'] ?? '').isNotEmpty) {
      basePath = env['APPDATA']!;
    } else if ((env['HOME'] ?? '').isNotEmpty) {
      basePath = env['HOME']!;
    } else {
      basePath = Directory.current.path;
    }

    return Directory('$basePath${Platform.pathSeparator}EngineHealthMonitor');
  }
}

class SettingsPalette {
  static const pageBackground = Color(0xFFF5F7FB);
  static const cardBackground = Colors.white;
  static const navDark = Color(0xFF030521);
  static const blue = Color(0xFF2563EB);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF667085);
  static const placeholder = Color(0xFF98A2B3);
  static const border = Color(0xFFE4E7EC);
  static const inputBackground = Color(0xFFF3F4F6);
  static const segmentBackground = Color(0xFFEDEFF4);
  static const critical = Color(0xFFEF4444);
}
