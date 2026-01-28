import 'package:flutter/material.dart';

import '../../../../core/widgets/glass.dart';

class LiveFloatingQuickMessage extends StatefulWidget {
  const LiveFloatingQuickMessage({
    super.key,
    required this.enabled,
    required this.messages,
    required this.onSend,
    this.initialOffset,
    this.icon = Icons.flash_on_rounded,
  });

  final bool enabled;
  final List<String> messages;
  final void Function(String message) onSend;
  final Offset? initialOffset;
  final IconData icon;

  @override
  State<LiveFloatingQuickMessage> createState() =>
      _LiveFloatingQuickMessageState();
}

class _LiveFloatingQuickMessageState extends State<LiveFloatingQuickMessage> {
  Offset _pos = const Offset(18, 140);
  bool _open = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialOffset != null) {
      _pos = widget.initialOffset!;
    }
  }

  void _toggleOpen() {
    if (!widget.enabled) return;
    setState(() => _open = !_open);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
  }

  void _send(String msg) {
    final m = msg.trim();
    if (m.isEmpty) return;
    widget.onSend(m);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;

        const btn = 56.0;

        double clampX(double x) {
          final v = x.clamp(0.0, (maxW - btn).clamp(0.0, maxW));
          return v.toDouble();
        }

        double clampY(double y) {
          final v = y.clamp(0.0, (maxH - btn).clamp(0.0, maxH));
          return v.toDouble();
        }

        _pos = Offset(clampX(_pos.dx), clampY(_pos.dy));

        const panelW = 220.0;
        const panelMaxH = 260.0;

        final panelLeft = (_pos.dx + btn + 10 + panelW <= maxW)
            ? (_pos.dx + btn + 10)
            : (_pos.dx - panelW - 10);

        final panelTop = (_pos.dy - 10)
            .clamp(8.0, (maxH - panelMaxH - 8).clamp(8.0, maxH));

        return Stack(
          children: [
            if (_open)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _close,
                  child: const SizedBox.expand(),
                ),
              ),
            if (_open)
              Positioned(
                left: panelLeft.toDouble(),
                top: panelTop.toDouble(),
                width: panelW,
                child: Glass(
                  borderRadius: 18,
                  padding: const EdgeInsets.all(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: panelMaxH),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (c, i) {
                        final msg = widget.messages[i];
                        return InkWell(
                          onTap: () => _send(msg),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.10)),
                            ),
                            child: Text(
                              msg,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            Positioned(
              left: _pos.dx,
              top: _pos.dy,
              child: GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    _pos = Offset(
                      clampX(_pos.dx + d.delta.dx),
                      clampY(_pos.dy + d.delta.dy),
                    );
                  });
                },
                child: Glass(
                  borderRadius: 999,
                  padding: const EdgeInsets.all(6),
                  child: SizedBox(
                    width: btn,
                    height: btn,
                    child: IconButton(
                      onPressed: _toggleOpen,
                      icon: Icon(widget.icon, color: Colors.cyanAccent),
                      tooltip: 'Quick message',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
