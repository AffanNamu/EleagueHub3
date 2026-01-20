import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/local_discovery.dart';

class JoinMatchScreen extends ConsumerStatefulWidget {
  const JoinMatchScreen({super.key});

  @override
  ConsumerState<JoinMatchScreen> createState() =>
      _JoinMatchScreenState();
}

class _JoinMatchScreenState
    extends ConsumerState<JoinMatchScreen> {
  final _discovery = LocalLiveDiscoveryListener();

  @override
  void initState() {
    super.initState();
    _discovery.start();
  }

  @override
  void dispose() {
    _discovery.stop();
    super.dispose();
  }

  void _joinHost(DiscoveredHost h) {
    context.push(
      '/live/view/${h.matchId}',
      extra: {
        'isHost': false,
        'host': h.hostIp,
        'port': h.port,

        // pass names so LiveView shows team names even without league context
        'homeName': h.homeName,
        'awayName': h.awayName,

        // pass side so viewer can map host to left/right
        'side': liveHostSideToWire(h.side),
      },
    );
  }

  Future<void> _openManual() async {
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '8765');
    final matchIdCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Glass(
                borderRadius: 24,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Join by IP / Code',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ask the host to share their IP, port and match ID.\n'
                      'Use this if auto‑discovery does not find the match.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Host IP (e.g. 192.168.1.25)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port (default 8765)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: matchIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Match ID',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.pop(ctx, true),
                            child: const Text('Join'),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (ok != true) return;

    final host = hostCtrl.text.trim();
    final port =
        int.tryParse(portCtrl.text.trim()) ?? 8765;
    final matchId = matchIdCtrl.text.trim();
    if (host.isEmpty || matchId.isEmpty) return;

    if (!mounted) return;
    context.push(
      '/live/view/$matchId',
      extra: {
        'isHost': false,
        'host': host,
        'port': port,
        'side': 'unknown',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.of(context).size.width > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Join Live Match'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _openManual,
            icon: const Icon(
              Icons.vpn_key,
              size: 18,
            ),
            label: const Text('By Code'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 720 : 540,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Hero / description card
                  Glass(
                    borderRadius: 24,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.cyanAccent
                                .withOpacity(0.18),
                          ),
                          child: const Icon(
                            Icons.cast_connected,
                            color: Colors.cyanAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Find a Live Match',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight:
                                      FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Make sure you are on the same Wi‑Fi or hotspot as the host. '
                                'Nearby matches will show up below automatically.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Header row + refresh hint
                  Row(
                    children: const [
                      Text(
                        'Nearby on this network',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.wifi_tethering,
                        color: Colors.cyanAccent,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Glass(
                      borderRadius: 20,
                      padding: const EdgeInsets.all(10),
                      child:
                          ValueListenableBuilder<
                              List<DiscoveredHost>>(
                        valueListenable:
                            _discovery.hosts,
                        builder: (_, hosts, __) {
                          if (hosts.isEmpty) {
                            return Column(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .center,
                              children: [
                                const SizedBox(
                                  height: 32,
                                  width: 32,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color:
                                        Colors.cyanAccent,
                                  ),
                                ),
                                const SizedBox(
                                    height: 12),
                                const Text(
                                  'Searching for live matches…',
                                  style: TextStyle(
                                    color:
                                        Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(
                                    height: 6),
                                const Text(
                                  'If nothing appears, ask the host to start live\n'
                                  'or tap the “By Code” option to join manually.',
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                    color:
                                        Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            );
                          }

                          return ListView.separated(
                            itemCount: hosts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(
                                    height: 10),
                            itemBuilder:
                                (context, i) {
                              final h = hosts[i];
                              final title = (h.homeName !=
                                          null &&
                                      h.awayName !=
                                          null)
                                  ? '${h.homeName} vs ${h.awayName}'
                                  : 'Match ${h.matchId}';

                              final sideLabel =
                                  liveHostSideToWire(
                                          h.side)
                                      .toUpperCase();

                              final endpoint =
                                  '${h.hostIp}:${h.port}';

                              return InkWell(
                                onTap: () =>
                                    _joinHost(h),
                                child: Glass(
                                  borderRadius: 18,
                                  padding:
                                      const EdgeInsets
                                          .all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration:
                                            BoxDecoration(
                                          shape: BoxShape
                                              .circle,
                                          color: Colors
                                              .cyanAccent
                                              .withOpacity(
                                                  0.16),
                                        ),
                                        child:
                                            const Icon(
                                          Icons
                                              .sports_esports,
                                          color: Colors
                                              .cyanAccent,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(
                                          width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            Text(
                                              title,
                                              style:
                                                  const TextStyle(
                                                color: Colors
                                                    .white,
                                                fontWeight:
                                                    FontWeight
                                                        .w800,
                                              ),
                                              maxLines:
                                                  1,
                                              overflow:
                                                  TextOverflow
                                                      .ellipsis,
                                            ),
                                            const SizedBox(
                                                height:
                                                    4),
                                            Text(
                                              endpoint,
                                              style:
                                                  const TextStyle(
                                                color: Colors
                                                    .white60,
                                                fontSize:
                                                    11,
                                              ),
                                              maxLines:
                                                  1,
                                              overflow:
                                                  TextOverflow
                                                      .ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(
                                          width: 8),
                                      Container(
                                        padding:
                                            const EdgeInsets
                                                .symmetric(
                                          horizontal:
                                              8,
                                          vertical: 4,
                                        ),
                                        decoration:
                                            BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  999),
                                          color: Colors
                                              .black
                                              .withOpacity(
                                                  0.3),
                                          border: Border.all(
                                              color: Colors
                                                  .white24),
                                        ),
                                        child: Text(
                                          sideLabel,
                                          style:
                                              const TextStyle(
                                            color: Colors
                                                .white70,
                                            fontSize:
                                                10,
                                            fontWeight:
                                                FontWeight
                                                    .w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                          width: 4),
                                      const Icon(
                                        Icons
                                            .arrow_forward_ios,
                                        size: 14,
                                        color: Colors
                                            .white54,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Bottom manual connect hint button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _openManual,
                      icon: const Icon(
                        Icons.vpn_key,
                        size: 16,
                      ),
                      label: const Text(
                        'Join with IP / Match ID',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
