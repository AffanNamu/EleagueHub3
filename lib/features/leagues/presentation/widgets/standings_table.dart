import 'package:flutter/material.dart';

import '../../../../core/widgets/glass.dart';
import '../../domain/standings/standings.dart';

/// A sortable, scrollable standings table rendered using the [StandingsRow] model.
///
/// - Horizontally scrollable for narrow screens.
/// - Vertically scrollable when there are many teams.
/// - Sortable by tapping column headers (can be disabled via [allowSorting]).
/// - Allows optional custom row coloring via [rowColorBuilder].
class StandingsTable extends StatefulWidget {
  const StandingsTable({
    super.key,
    required this.rows,
    this.rowColorBuilder,
    this.allowSorting = true,
  });

  /// Raw, unsorted list of standing rows.
  final List<StandingsRow> rows;

  /// Optional custom row color function.
  ///
  /// Parameters:
  /// - [context]: BuildContext
  /// - [index]: 0-based index in the sorted table
  /// - [row]: the actual [StandingsRow] for that index
  /// - [total]: total number of rows
  ///
  /// Return a [Color] to tint the row, or null for no background.
  final Color? Function(
    BuildContext context,
    int index,
    StandingsRow row,
    int total,
  )? rowColorBuilder;

  /// When false, preserves the incoming [rows] order and disables header sorting.
  final bool allowSorting;

  @override
  State<StandingsTable> createState() => _StandingsTableState();
}

class _StandingsTableState extends State<StandingsTable> {
  /// Index of the currently sorted column in the DataTable.
  /// 0 = Team, 1 = P, 2 = W, 3 = D, 4 = L, 5 = GD, 6 = GF, 7 = Pts
  int _sortCol = 7; // default sort by points

  /// Whether the sort is ascending or descending.
  bool _asc = false;

  /// Returns a sorted copy of the incoming rows based on the current sort state.
  List<StandingsRow> get _sorted {
    final rows = List<StandingsRow>.from(widget.rows);

    if (!widget.allowSorting) return rows;

    rows.sort((a, b) {
      int v;
      switch (_sortCol) {
        case 0: // Team
          v = a.teamName.compareTo(b.teamName);
          break;
        case 1: // Played
          v = a.mp.compareTo(b.mp);
          break;
        case 2: // Wins
          v = a.w.compareTo(b.w);
          break;
        case 3: // Draws
          v = a.d.compareTo(b.d);
          break;
        case 4: // Losses
          v = a.l.compareTo(b.l);
          break;
        case 5: // Goal difference
          v = a.gd.compareTo(b.gd);
          break;
        case 6: // Goals for
          v = a.gf.compareTo(b.gf);
          break;
        case 7: // Points
        default:
          v = a.pts.compareTo(b.pts);
      }
      return _asc ? v : -v;
    });

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final screenHeight = MediaQuery.of(context).size.height;
    final maxTableHeight = screenHeight * 0.6;

    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      color: cs.onSurface.withOpacity(0.82),
      fontWeight: FontWeight.w900,
    );

    final cellStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withOpacity(0.78),
      fontWeight: FontWeight.w700,
      height: 1.15,
    );

    final primaryCellStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withOpacity(0.92),
      fontWeight: FontWeight.w800,
      height: 1.15,
    );

    final pointsStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withOpacity(0.95),
      fontWeight: FontWeight.w900,
    );

    return Glass(
      borderRadius: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              maxHeight: maxTableHeight,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  sortAscending: widget.allowSorting ? _asc : true,
                  sortColumnIndex: widget.allowSorting ? _sortCol : null,
                  columnSpacing: 18,
                  headingTextStyle: headerStyle,
                  dataTextStyle: cellStyle,
                  dividerThickness: 0.6,
                  columns: [
                    _col('Team', 0),
                    _col('P', 1, numeric: true),
                    _col('W', 2, numeric: true),
                    _col('D', 3, numeric: true),
                    _col('L', 4, numeric: true),
                    _col('GD', 5, numeric: true),
                    _col('GF', 6, numeric: true),
                    _col('Pts', 7, numeric: true),
                  ],
                  rows: [
                    for (int i = 0; i < rows.length; i++)
                      _row(
                        context,
                        i,
                        rows.length,
                        rows[i],
                        primaryCellStyle: primaryCellStyle,
                        pointsStyle: pointsStyle,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  DataColumn _col(String label, int index, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(label),
      onSort: widget.allowSorting
          ? (colIndex, ascending) {
              setState(() {
                _sortCol = colIndex;
                _asc = ascending;
              });
            }
          : null,
    );
  }

  DataRow _row(
    BuildContext context,
    int i,
    int total,
    StandingsRow r, {
    required TextStyle? primaryCellStyle,
    required TextStyle? pointsStyle,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color? zoneColor;

    if (widget.rowColorBuilder != null) {
      zoneColor = widget.rowColorBuilder!(context, i, r, total);
    } else {
      // Default zones: keep consistent across themes and keep it premium-light friendly.
      final topZone = const Color(0xFF22C55E).withOpacity(0.12);
      final midZone = cs.primary.withOpacity(0.10);
      zoneColor = i < 2
          ? topZone
          : i < 4
              ? midZone
              : Colors.transparent;
    }

    return DataRow(
      color: zoneColor != null ? WidgetStatePropertyAll(zoneColor) : null,
      cells: [
        DataCell(
          Text(
            '${i + 1}. ${r.teamName}',
            style: primaryCellStyle,
          ),
        ),
        DataCell(Text('${r.mp}')),
        DataCell(Text('${r.w}')),
        DataCell(Text('${r.d}')),
        DataCell(Text('${r.l}')),
        DataCell(Text('${r.gd}')),
        DataCell(Text('${r.gf}')),
        DataCell(
          Text(
            '${r.pts}',
            style: pointsStyle,
          ),
        ),
      ],
    );
  }
}
