import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'database_helper.dart';

// ─── Общото съдържание на настройките ────────────────────────────────────
class SettingsContent extends StatefulWidget {
  final VoidCallback? onChanged;  // ← ново
  const SettingsContent({super.key, this.onChanged});

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  bool _isOldStyle = AppSettings.isOldStyle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text(
            'КАЛЕНДАР',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Center(
          child: SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.backgroundCard,
              foregroundColor: AppColors.textMuted,
              selectedForegroundColor: AppColors.textPrimary,
              selectedBackgroundColor: AppColors.appBarWeekday,
            ),
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Стар стил'),
                icon: Icon(Icons.history, size: 16),
              ),
              ButtonSegment(
                value: false,
                label: Text('Нов стил'),
                icon: Icon(Icons.today, size: 16),
              ),
            ],
            selected: {_isOldStyle},
						onSelectionChanged: (value) async {
						  setState(() {
							_isOldStyle = value.first;
							AppSettings.isOldStyle = value.first;
						  });
						  await DatabaseHelper.resetDatabase();
						  await DatabaseHelper.database;
						  widget.onChanged?.call();  // ← ново
						},
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.backgroundCard,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _isOldStyle
                ? 'Юлиански (стар) стил. В горната лента ще се показва справочно и датата по Григориански (нов) стил.'
                : 'Григориански (нов) стил. Показва се само датата по нов стил.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Пълен екран (от менюто) ─────────────────────────────────────────────
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, 
          color: AppColors.textPrimary, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Настройки',
          style: TextStyle(
            color: AppColors.textPrimary, fontSize: 20),
        ),
      ),
      backgroundColor: AppColors.background,
      body: const SettingsContent(),
    );
  }
}

// ─── Десен Drawer (от toolbar) ───────────────────────────────────────────
class SettingsDrawer extends StatelessWidget {
  final VoidCallback? onChanged;
  const SettingsDrawer({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          // Хедър с title и бутон за затваряне вдясно
          Container(
            color: AppColors.toolbar,
            height: 40 + MediaQuery.of(context).padding.top,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text(
                      'Настройки',
                      style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 20),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, 
                  color: AppColors.textPrimary, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Съдържанието
          //const Expanded(child: SettingsContent()),
          Expanded(child: SettingsContent(onChanged: onChanged)),

        ],
      ),
    );
  }
}
