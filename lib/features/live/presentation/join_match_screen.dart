
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';



import '../../../core/widgets/glass.dart';

import '../../../core/widgets/glass_scaffold.dart';



class JoinMatchScreen extends ConsumerStatefulWidget {

  const JoinMatchScreen({super.key});



  @override

  ConsumerState<JoinMatchScreen> createState() => _JoinMatchScreenState();

}



class _JoinMatchScreenState extends ConsumerState<JoinMatchScreen> {

  final _matchIdCtrl = TextEditingController();

  final _homeCtrl = TextEditingController();

  final _awayCtrl = TextEditingController();



  String? _error;



  @override

  void dispose() {

    _matchIdCtrl.dispose();

    _homeCtrl.dispose();

    _awayCtrl.dispose();

    super.dispose();

  }



  void _pushLiveView({

    required bool isHost,

    String? side, // 'home' | 'away' | 'unknown'

  }) {

    final matchId = _matchIdCtrl.text.trim();

    final homeName = _homeCtrl.text.trim();

    final awayName = _awayCtrl.text.trim();



    if (matchId.isEmpty) {

      setState(() => _error = 'Match ID is required');

      return;

    }



    setState(() => _error = null);



    context.push(

      '/live/view/$matchId',

      extra: <String, dynamic>{

        'isHost': isHost,

        if (homeName.isNotEmpty) 'homeName': homeName,

        if (awayName.isNotEmpty) 'awayName': awayName,

        if (side != null && side.trim().isNotEmpty) 'side': side.trim(),

      },

    );

  }



  @override

  Widget build(BuildContext context) {

    final isWide = MediaQuery.of(context).size.width > 600;



    return GlassScaffold(

      appBar: AppBar(

        title: const Text('Join Live Match (Online)'),

        backgroundColor: Colors.transparent,

        elevation: 0,

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

                  Glass(

                    borderRadius: 24,

                    padding: const EdgeInsets.all(16),

                    child: Row(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Container(

                          width: 44,

                          height: 44,

                          decoration: BoxDecoration(

                            shape: BoxShape.circle,

                            color: Colors.cyanAccent.withOpacity(0.18),

                          ),

                          child: const Icon(

                            Icons.public,

                            color: Colors.cyanAccent,

                          ),

                        ),

                        const SizedBox(width: 12),

                        const Expanded(

                          child: Column(

                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [

                              Text(

                                'Online Live Video',

                                style: TextStyle(

                                  color: Colors.white,

                                  fontSize: 16,

                                  fontWeight: FontWeight.w800,

                                ),

                              ),

                              SizedBox(height: 4),

                              Text(

                                'Join using Match ID. This is ONLINE (no Wi‑Fi discovery / no IP / no port).',

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

                  Glass(

                    borderRadius: 20,

                    padding: const EdgeInsets.all(12),

                    child: Column(

                      children: [

                        TextField(

                          controller: _matchIdCtrl,

                          decoration: const InputDecoration(

                            labelText: 'Match ID',

                            hintText: 'e.g. 9f2c1a',

                          ),

                        ),

                        const SizedBox(height: 10),

                        Row(

                          children: [

                            Expanded(

                              child: TextField(

                                controller: _homeCtrl,

                                decoration: const InputDecoration(

                                  labelText: 'Home name (optional)',

                                ),

                              ),

                            ),

                            const SizedBox(width: 10),

                            Expanded(

                              child: TextField(

                                controller: _awayCtrl,

                                decoration: const InputDecoration(

                                  labelText: 'Away name (optional)',

                                ),

                              ),

                            ),

                          ],

                        ),

                        if (_error != null) ...[

                          const SizedBox(height: 10),

                          Align(

                            alignment: Alignment.centerLeft,

                            child: Text(

                              _error!,

                              style: const TextStyle(

                                color: Colors.redAccent,

                                fontSize: 12,

                              ),

                            ),

                          ),

                        ],

                        const SizedBox(height: 14),

                        Row(

                          children: [

                            Expanded(

                              child: FilledButton.icon(

                                onPressed: () => _pushLiveView(

                                  isHost: false,

                                  side: 'unknown',

                                ),

                                icon: const Icon(Icons.play_arrow),

                                label: const Text('Join as Viewer'),

                              ),

                            ),

                          ],

                        ),

                        const SizedBox(height: 10),

                        Row(

                          children: [

                            Expanded(

                              child: OutlinedButton.icon(

                                onPressed: () => _pushLiveView(

                                  isHost: true,

                                  side: 'home',

                                ),

                                icon: const Icon(Icons.sports_esports),

                                label: const Text('Host as HOME'),

                              ),

                            ),

                            const SizedBox(width: 10),

                            Expanded(

                              child: OutlinedButton.icon(

                                onPressed: () => _pushLiveView(

                                  isHost: true,

                                  side: 'away',

                                ),

                                icon: const Icon(Icons.sports_esports),

                                label: const Text('Host as AWAY'),

                              ),

                            ),

                          ],

                        ),

                        const SizedBox(height: 8),

                        const Text(

                          'Tip: for a match with two streamers, one hosts as HOME and the other hosts as AWAY using the same Match ID.',

                          textAlign: TextAlign.center,

                          style: TextStyle(

                            color: Colors.white38,

                            fontSize: 11,

                            height: 1.4,

                          ),

                        ),

                      ],

                    ),

                  ),

                  const Spacer(),

                ],

              ),

            ),

          ),

        ),

      ),

    );

  }

}

