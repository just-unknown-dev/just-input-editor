import 'package:flutter/material.dart';
import 'package:just_editor_core/kit.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:meta/meta.dart';

import '../../session/session.dart';
import '../look/input_editor_theme.dart';
import '../look/input_text_field.dart';
import 'property_rows.dart';

/// The players — how many, how they join — and the asset's settings that
/// interactions and dead zones fall back on.
@internal
class SettingsProperties extends StatelessWidget {
  /// The players and settings of [session]'s asset.
  const SettingsProperties({super.key, required this.session});

  /// The session it edits.
  final InputEditorSession session;

  /// The most players the editor offers: what the templates' games have
  /// room for, and what the README promises.
  static const int maxPlayers = 4;

  /// Why [n] cannot be the setting [p] of [settings], or null when it can:
  /// out of its range ([InputSettingsDef.params] — a press point of 0
  /// would leave every button pressed at rest), or a dead zone's min not
  /// below its max ([InputSettingsDef.ranges]) — what `validateAsset`
  /// would call an error, and the input system could not run.
  static String? problem(InputSettingsDef settings, ParamInfo p, num n) {
    if (!p.accepts(n)) {
      final (min, max) = (p.min, p.max);
      return max == null
          ? '${p.label} is a number of seconds, ${plainNumber(min ?? 0)} or '
                'more.'
          : '${p.label} is a number from ${plainNumber(min ?? 0)} to '
                '${plainNumber(max)}.';
    }
    String label(String key) =>
        InputSettingsDef.params.firstWhere((x) => x.name == key).label;
    for (final (low, high) in InputSettingsDef.ranges) {
      if (p.name == low && n >= settings.valueOf(high)!) {
        return '${p.label} has to be below ${label(high)} '
            '(${plainNumber(settings.valueOf(high)!)}).';
      }
      if (p.name == high && n <= settings.valueOf(low)!) {
        return '${p.label} has to be above ${label(low)} '
            '(${plainNumber(settings.valueOf(low)!)}).';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final players = s.asset.players;
    void setPlayers(String label, PlayerSettingsDef next) =>
        s.edit(label, (a) => a.copyWith(players: next));
    final actionPaths = [for (final ref in s.asset.actions) ref.path];
    final own = [
      for (final i in s.issues)
        if (i.mapId == null && i.actionId == null) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PLAYERS', style: InputEditorTheme.heading),
        const SizedBox(height: 6),
        PropertyField(
          'At most',
          Row(
            children: [
              EditorIconButton(
                icon: Icons.remove,
                tooltip: 'Fewer',
                onTap: players.maxPlayers <= 1
                    ? null
                    : () => setPlayers(
                        'Players',
                        players.copyWith(maxPlayers: players.maxPlayers - 1),
                      ),
              ),
              SizedBox(
                width: 30,
                child: Center(
                  child: Text(
                    '${players.maxPlayers}',
                    style: InputEditorTheme.body,
                  ),
                ),
              ),
              EditorIconButton(
                icon: Icons.add,
                tooltip: 'More',
                onTap: players.maxPlayers >= maxPlayers
                    ? null
                    : () => setPlayers(
                        'Players',
                        players.copyWith(maxPlayers: players.maxPlayers + 1),
                      ),
              ),
            ],
          ),
        ),
        PropertyToggle(
          'Players join by an action',
          players.joining == JoinBehavior.onJoinAction,
          (v) => setPlayers(
            'Joining',
            players.copyWith(
              joining: v ? JoinBehavior.onJoinAction : JoinBehavior.disabled,
            ),
          ),
          hint:
              'A device nobody uses joins as the next player when a join '
              'action is performed on it.',
        ),
        PropertyToggle(
          'Player 1 is whoever plays first',
          players.autoJoinFirst,
          (v) => setPlayers('Join first', players.copyWith(autoJoinFirst: v)),
        ),
        PropertyToggle(
          'Alone, switch devices on use',
          players.autoSwitch,
          (v) => setPlayers('Auto-switch', players.copyWith(autoSwitch: v)),
          hint:
              'With one player, a device nobody uses takes over the moment it '
              'is used — scheme and all.',
        ),
        if (players.joining == JoinBehavior.onJoinAction) ...[
          const SizedBox(height: 6),
          Text('JOIN ACTIONS', style: InputEditorTheme.heading),
          Text(
            'Give one a Hold, and a quick press on a free pad switches '
            'instead of joining.',
            style: InputEditorTheme.label,
          ),
          const SizedBox(height: 4),
          for (final path in actionPaths)
            PropertyToggle(path, players.joinActions.contains(path), (on) {
              final list = [
                for (final p in players.joinActions)
                  if (p != path) p,
                if (on) path,
              ];
              setPlayers('Join actions', players.copyWith(joinActions: list));
            }),
        ],
        const PropertyGap(),
        Text('SETTINGS', style: InputEditorTheme.heading),
        Text(
          'What interactions and dead zones fall back on.',
          style: InputEditorTheme.label,
        ),
        const SizedBox(height: 6),
        for (final p in InputSettingsDef.params) ...[
          PropertyField(
            p.label,
            InputTextField(
              value: plainNumber(s.asset.settings.valueOf(p.name)!),
              onCommit: (text) {
                // NaN and Infinity parse, and no file can hold them.
                final n = double.tryParse(text.trim());
                final settings = s.asset.settings;
                final why = n == null || !n.isFinite
                    ? problem(settings, p, double.nan)
                    : problem(settings, p, n);
                if (why != null) return s.say(why);
                s.edit(
                  p.label,
                  (a) => a.copyWith(
                    settings: InputSettingsDef.fromJson({
                      ...a.settings.toJson(),
                      p.name: n,
                    }),
                  ),
                );
              },
            ),
          ),
          for (final i in own)
            if (i.param == p.name)
              Padding(
                padding: const EdgeInsets.only(left: 96),
                child: IssueLine(i),
              ),
        ],
        const PropertyGap(),
        PropertyProblems(own),
      ],
    );
  }
}
