import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../session/session.dart';
import 'gamepad_view.dart';
import 'keyboard_view.dart';
import 'live_test_view.dart';
import 'touch_layout_view.dart';

/// The views along the bottom: a keyboard, a gamepad and a phone to see the
/// bindings on, and a place to try them.
@internal
class BottomPanel extends StatefulWidget {
  /// The views of [session], trying it on [harness].
  const BottomPanel({super.key, required this.session, required this.harness});

  /// The session they show.
  final InputEditorSession session;

  /// What the live test runs on.
  final InputEditorHarness harness;

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

/// The tabs along the bottom.
@internal
enum BottomTab {
  /// The keyboard and the mouse.
  keyboard('Keyboard', Icons.keyboard_outlined),

  /// A gamepad.
  gamepad('Gamepad', Icons.sports_esports_outlined),

  /// The on-screen controls on a phone.
  touch('Touch layout', Icons.phone_iphone),

  /// The asset running, to try.
  live('Live test', Icons.play_circle_outline);

  const BottomTab(this.label, this.icon);

  /// The tab's words.
  final String label;

  /// The tab's icon.
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
    color: EditorTheme.panelBg,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 32,
          color: EditorTheme.menuBg,
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
                              ? EditorTheme.primaryBright
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
                              ? EditorTheme.primaryBright
                              : EditorTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tab.label,
                          style: TextStyle(
                            color: tab == _tab
                                ? EditorTheme.textPrimary
                                : EditorTheme.textMuted,
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
