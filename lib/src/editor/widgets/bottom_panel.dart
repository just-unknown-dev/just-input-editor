import 'package:flutter/material.dart';

import 'package:just_inputs/just_inputs.dart';
import '../core/input_editor_session.dart';
import 'editor_harness.dart';
import 'editor_theme.dart';
import 'gamepad_view.dart';
import 'keyboard_view.dart';
import 'live_test_view.dart';
import 'touch_layout_view.dart';

/// The views along the bottom: a keyboard, a gamepad and a phone to see the
/// bindings on, and a place to try them.
class BottomPanel extends StatefulWidget {
  const BottomPanel({super.key, required this.session, required this.harness});

  final InputEditorSession session;
  final EditorHarness harness;

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

enum BottomTab {
  keyboard('Keyboard', Icons.keyboard_outlined),
  gamepad('Gamepad', Icons.sports_esports_outlined),
  touch('Touch layout', Icons.phone_iphone),
  live('Live test', Icons.play_circle_outline);

  const BottomTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _BottomPanelState extends State<BottomPanel> {
  BottomTab _tab = BottomTab.keyboard;

  /// The scheme chip last followed: picking Gamepad in the top bar shows
  /// the pad, Touch the phone, Keyboard & Mouse the keyboard. All leaves the
  /// tab as it is.
  String? _followed;

  BottomTab? _tabFor(String? group) {
    if (group == null) return null;
    final layouts =
        widget.session.asset.schemeWithGroup(group)?.layouts.toSet() ??
        const <String>{};
    if (layouts.contains(InputLayouts.gamepad)) return BottomTab.gamepad;
    if (layouts.contains(InputLayouts.onScreen) ||
        layouts.contains(InputLayouts.touchscreen)) {
      return BottomTab.touch;
    }
    if (layouts.contains(InputLayouts.keyboard) ||
        layouts.contains(InputLayouts.mouse)) {
      return BottomTab.keyboard;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.session.schemeFilter;
    if (filter != _followed) {
      _followed = filter;
      _tab = _tabFor(filter) ?? _tab;
    }
    return _panel();
  }

  Widget _panel() => Container(
    color: InputEditorTheme.workArea,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 32,
          color: InputEditorTheme.panel,
          child: Row(
            children: [
              for (final tab in BottomTab.values)
                InkWell(
                  key: ValueKey('tab:${tab.name}'),
                  onTap: () => setState(() => _tab = tab),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: tab == _tab
                              ? InputEditorTheme.accent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tab.icon,
                          size: 15,
                          color: tab == _tab
                              ? InputEditorTheme.accent
                              : InputEditorTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tab.label,
                          style: TextStyle(
                            color: tab == _tab
                                ? InputEditorTheme.text
                                : InputEditorTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            BottomTab.keyboard => KeyboardView(
              session: widget.session,
              harness: widget.harness,
            ),
            BottomTab.gamepad => GamepadView(session: widget.session),
            BottomTab.touch => TouchLayoutView(session: widget.session),
            // Built only while shown: its ticker runs only then.
            BottomTab.live => LiveTestView(
              session: widget.session,
              harness: widget.harness,
            ),
          },
        ),
      ],
    ),
  );
}
