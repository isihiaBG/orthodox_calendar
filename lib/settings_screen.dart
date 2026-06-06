import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_settings.dart';
import 'database_helper.dart';

// ─── Общото съдържание на настройките ────────────────────────────────────
class SettingsContent extends StatefulWidget {
  final Function(bool styleChanged)? onChanged;
  const SettingsContent({super.key, this.onChanged});

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  bool _isOldStyle = AppSettings.isOldStyle;
  bool _oldStyleFirst = AppSettings.oldStyleFirst;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ─── Стар/Нов стил ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text('КАЛЕНДАР',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.5)),
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
              final newIsOldStyle = value.first;
              setState(() {
                _isOldStyle = newIsOldStyle;
                AppSettings.isOldStyle = newIsOldStyle;
              });
              await DatabaseHelper.resetDatabase();
              await DatabaseHelper.database;
              widget.onChanged?.call(true);
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
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ),

        // ─── Водеща дата — плавно разширяване/свиване ────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: SizedBox(
            width: double.infinity,
            child: _isOldStyle
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('ВОДЕЩА ДАТА',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            letterSpacing: 1.5,
                          )),
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
                          selected: {!_oldStyleFirst},
                          onSelectionChanged: (value) {
                            setState(() {
                              _oldStyleFirst = !value.first;
                              AppSettings.oldStyleFirst = !value.first;
                            });
                            widget.onChanged?.call(false);
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
                          _oldStyleFirst
                              ? 'Гражданската дата (нов стил) е на преден план вляво.'
                              : 'Църковната дата (стар стил) е на преден план вляво.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

// ─── Пълен екран (от менюто) ─────────────────────────────────────────────
class SettingsScreen extends StatelessWidget {
  final Function(bool styleChanged)? onChanged;
  const SettingsScreen({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        toolbarHeight: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Настройки',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 20)),
      ),
      backgroundColor: AppColors.background,
      body: SettingsContent(onChanged: onChanged),
    );
  }
}

// ─── Десен Drawer (от toolbar) ───────────────────────────────────────────
class SettingsDrawer extends StatelessWidget {
  final Function(bool styleChanged)? onChanged;
  const SettingsDrawer({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          Container(
            color: AppColors.toolbar,
            height: 40 + MediaQuery.of(context).padding.top,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text('Настройки',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 20)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, color: AppColors.textPrimary, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(child: SettingsContent(onChanged: onChanged)),
        ],
      ),
    );
  }
}
