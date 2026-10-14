// PromptGuard AI — Flutter client
//
// Single-screen app: type a prompt, tap "Check Prompt", see the traffic-light
// risk result plus suggestions for improving the prompt before it's sent to
// an LLM.
//
// Before running: set backendBaseUrl below to your deployed backend's URL
// (e.g. your Hugging Face Space's URL, ending in no trailing slash).
//
// Setup:
//   1. flutter create promptguard_app
//   2. Replace lib/main.dart with this file
//   3. Add the http package: flutter pub add http
//   4. flutter run

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String backendBaseUrl =
    "https://rajwardhankadam-promptguard-ai-space.hf.space";

/// Overlay window entry point executed in a separate Flutter engine instance
/// by flutter_overlay_window.
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FloatingBubbleOverlay(),
    ),
  );
}

/// Floating draggable circular bubble overlay displayed over other apps.
class FloatingBubbleOverlay extends StatefulWidget {
  const FloatingBubbleOverlay({super.key});

  @override
  State<FloatingBubbleOverlay> createState() => _FloatingBubbleOverlayState();
}

class _FloatingBubbleOverlayState extends State<FloatingBubbleOverlay> {
  bool _isExpanded = false;
  bool _loading = false;
  String? _error;
  PromptGuardResult? _result;
  final TextEditingController _textController = TextEditingController();

  Future<void> _expandAndCheckClipboard() async {
    setState(() {
      _isExpanded = true;
      _loading = true;
      _error = null;
      _result = null;
    });

    // Expand overlay window size to show the quick-check popup card
    await FlutterOverlayWindow.resizeOverlay(360, 520, false);

    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final clipText = clipboardData?.text?.trim();

      if (clipText != null && clipText.isNotEmpty) {
        _textController.text = clipText;
        await _runCheck(clipText);
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _runCheck(String promptText) async {
    final prompt = promptText.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final data = await checkPrompt(prompt);
      if (mounted) {
        setState(() {
          _result = PromptGuardResult.fromJson(data);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e.toString().contains('TimeoutException')) {
            _error =
                'The server is taking longer than usual to respond — it '
                'may be waking up from being idle. Please try again.';
          } else {
            _error = 'Could not reach PromptGuard server ($e)';
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _collapseOverlay() async {
    setState(() {
      _isExpanded = false;
      _loading = false;
      _error = null;
      _result = null;
      _textController.clear();
    });

    // Shrink overlay back to a small circular draggable bubble
    await FlutterOverlayWindow.resizeOverlay(120, 120, true);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isExpanded) {
      return Material(
        color: Colors.transparent,
        child: Center(
          child: GestureDetector(
            onTap: _expandAndCheckClipboard,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E74B5), Color(0xFF1B4975)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 8,
                    spreadRadius: 2,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withAlpha(200),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 340,
          constraints: const BoxConstraints(maxHeight: 500),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 16,
                spreadRadius: 4,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFF2E74B5), width: 1.5),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.shield,
                      color: Color(0xFF2E74B5),
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'PromptGuard AI',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF2E74B5),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _collapseOverlay,
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const Divider(height: 16),
                if (_loading) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 14),
                  const Text(
                    'Analyzing prompt...\n(Note: First request after inactivity may take longer as the backend wakes up)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  if (_result == null) ...[
                    TextField(
                      controller: _textController,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Clipboard empty. Type or paste a prompt...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => _runCheck(_textController.text),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Check Prompt'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_result != null) ...[
                    PromptGuardResultCard(
                      result: _result!,
                      onUseTemplate: _result!.rewriteTemplate != null
                          ? () {
                              Clipboard.setData(
                                ClipboardData(text: _result!.rewriteTemplate!),
                              );
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _result = null;
                        });
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                        'Check Another Prompt',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable result card displaying traffic light status, overall risk percentage,
/// risk breakdown probabilities, explanation bullets, suggestion tips, and template actions.
class PromptGuardResultCard extends StatelessWidget {
  final PromptGuardResult result;
  final VoidCallback? onUseTemplate;

  const PromptGuardResultCard({
    super.key,
    required this.result,
    this.onUseTemplate,
  });

  Color _trafficLightColor(String light) {
    switch (light) {
      case "red":
        return Colors.red;
      case "yellow":
        return Colors.amber;
      case "green":
      default:
        return Colors.green;
    }
  }

  IconData _trafficLightIcon(String light) {
    switch (light) {
      case "red":
        return Icons.block;
      case "yellow":
        return Icons.warning_amber_rounded;
      case "green":
      default:
        return Icons.check_circle;
    }
  }

  Widget _buildScoreRow(String label, double value) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(
          '${(value * 100).toStringAsFixed(0)}%',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _trafficLightColor(result.trafficLight);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  _trafficLightIcon(result.trafficLight),
                  color: color,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  result.trafficLight.toUpperCase(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  'Risk: ${(result.overallRisk * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Recommended action: ${result.recommendedAction}',
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
            ),
            const Divider(height: 20),
            _buildScoreRow(
              'Injection risk (Track A)',
              result.injectionProbability,
            ),
            const SizedBox(height: 4),
            _buildScoreRow(
              'Quality/ambiguity risk (Track B)',
              result.qualityRiskProbability,
            ),
            if (result.domainSensitive) ...[
              const SizedBox(height: 8),
              Chip(
                label: const Text(
                  'Sensitive topic — extra caution advised',
                  style: TextStyle(fontSize: 11),
                ),
                backgroundColor: Colors.orange.shade100,
                visualDensity: VisualDensity.compact,
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Why:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            ...result.explanation.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $e', style: const TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Suggestions:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            ...result.suggestionTips.map(
              (tip) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $tip', style: const TextStyle(fontSize: 13)),
              ),
            ),
            if (result.rewriteTemplate != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  result.rewriteTemplate!,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ),
              if (onUseTemplate != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onUseTemplate,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text(
                    'Use this template',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Calls the Gradio Space's /score endpoint using Gradio's modern two-step
/// queue-based API: POST to queue the request and get an event_id, then GET
/// (as a stream) to receive the result as Server-Sent Events. This is what
/// gradio_client does internally — Flutter has to replicate it manually since
/// there's no Dart client for Gradio's API.
Future<Map<String, dynamic>> checkPrompt(String prompt) async {
  // Step 1: queue the request.
  final postResponse = await http
      .post(
        Uri.parse('$backendBaseUrl/gradio_api/call/score'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': [prompt],
        }),
      )
      .timeout(const Duration(seconds: 30));

  if (postResponse.statusCode != 200) {
    throw Exception('Failed to queue request (${postResponse.statusCode})');
  }

  final eventId =
      (jsonDecode(postResponse.body) as Map<String, dynamic>)['event_id']
          as String?;
  if (eventId == null) {
    throw Exception('No event_id returned from server');
  }

  // Step 2: fetch the streamed result. Timeout is generous (90s) since the
  // Space can have a slow "cold start" — Track B trains lazily on the first
  // request after any restart/sleep, and free-tier Spaces sleep after
  // inactivity. Subsequent requests are much faster.
  final request = http.Request(
    'GET',
    Uri.parse('$backendBaseUrl/gradio_api/call/score/$eventId'),
  );
  final client = http.Client();
  String fullText;
  try {
    final streamedResponse = await client
        .send(request)
        .timeout(const Duration(seconds: 90));

    if (streamedResponse.statusCode != 200) {
      throw Exception(
        'Failed to fetch result (${streamedResponse.statusCode})',
      );
    }

    fullText = await streamedResponse.stream.transform(utf8.decoder).join();
  } finally {
    client.close();
  }

  // Parse the SSE-formatted text. Scan every line rather than assuming a
  // fixed structure, and keep the LAST event/data pair seen — robust against
  // any extra heartbeat/comment lines the server might send first.
  String? lastEvent;
  String? lastData;
  for (final rawLine in fullText.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('event:')) {
      lastEvent = line.substring('event:'.length).trim();
    } else if (line.startsWith('data:')) {
      lastData = line.substring('data:'.length).trim();
    }
  }

  if (lastData == null) {
    throw Exception('No data received in server response');
  }

  final decoded = jsonDecode(lastData);

  if (lastEvent == 'error') {
    throw Exception('Server error: $decoded');
  }

  // Gradio wraps outputs in a list — one element per output component in the
  // interface. Our Space has exactly one output (the JSON result box).
  if (decoded is List && decoded.isNotEmpty) {
    return decoded[0] as Map<String, dynamic>;
  }
  throw Exception('Unexpected response format: $decoded');
}

void main() {
  runApp(const PromptGuardApp());
}

class PromptGuardApp extends StatelessWidget {
  const PromptGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PromptGuard AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E74B5),
        useMaterial3: true,
      ),
      home: const PromptGuardHomePage(),
    );
  }
}

class PromptGuardResult {
  final String prompt;
  final double overallRisk;
  final String trafficLight;
  final String recommendedAction;
  final double injectionProbability;
  final double qualityRiskProbability;
  final bool domainSensitive;
  final List<String> explanation;
  final List<String> suggestionTips;
  final String? rewriteTemplate;

  PromptGuardResult({
    required this.prompt,
    required this.overallRisk,
    required this.trafficLight,
    required this.recommendedAction,
    required this.injectionProbability,
    required this.qualityRiskProbability,
    required this.domainSensitive,
    required this.explanation,
    required this.suggestionTips,
    required this.rewriteTemplate,
  });

  factory PromptGuardResult.fromJson(Map<String, dynamic> json) {
    return PromptGuardResult(
      prompt: json['prompt'] as String,
      overallRisk: (json['overall_risk'] as num).toDouble(),
      trafficLight: json['traffic_light'] as String,
      recommendedAction: json['recommended_action'] as String,
      injectionProbability: (json['injection_probability'] as num).toDouble(),
      qualityRiskProbability: (json['quality_risk_probability'] as num)
          .toDouble(),
      domainSensitive: json['domain_sensitive'] as bool,
      explanation: List<String>.from(json['explanation'] as List),
      suggestionTips: List<String>.from(json['suggestion_tips'] as List),
      rewriteTemplate: json['rewrite_template'] as String?,
    );
  }
}

class PromptGuardHomePage extends StatefulWidget {
  const PromptGuardHomePage({super.key});

  @override
  State<PromptGuardHomePage> createState() => _PromptGuardHomePageState();
}

class _PromptGuardHomePageState extends State<PromptGuardHomePage> {
  final TextEditingController _controller = TextEditingController();
  PromptGuardResult? _result;
  bool _loading = false;
  String? _error;
  bool _isBubbleEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    _checkInitialOverlayStatus();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    if (!hasSeenOnboarding && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.shield, size: 36, color: Color(0xFF2E74B5)),
            title: const Text('Welcome to PromptGuard AI'),
            content: const SingleChildScrollView(
              child: Text(
                'PromptGuard AI analyzes your LLM prompts before sending them to detect '
                'prompt injection security risks and evaluate prompt quality.\n\n'
                'You can also enable the floating bubble feature to keep PromptGuard accessible '
                'over other apps. Enabling the bubble will request the "Draw over other apps" permission.',
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  await prefs.setBool('has_seen_onboarding', true);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                  }
                },
                child: const Text('Get Started'),
              ),
            ],
          ),
        );
      });
    }
  }

  Future<void> _checkInitialOverlayStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEnabled = prefs.getBool('is_bubble_enabled') ?? false;
      final active = await FlutterOverlayWindow.isActive();

      if (savedEnabled && !active) {
        final isGranted = await FlutterOverlayWindow.isPermissionGranted();
        if (isGranted) {
          await FlutterOverlayWindow.showOverlay(
            enableDrag: true,
            overlayTitle: "PromptGuard AI Active",
            overlayContent: "PromptGuard is active — tap to disable",
            flag: OverlayFlag.defaultFlag,
            visibility: NotificationVisibility.visibilityPublic,
            positionGravity: PositionGravity.auto,
            height: 120,
            width: 120,
          );
        } else {
          await prefs.setBool('is_bubble_enabled', false);
        }
      }

      final updatedActive = await FlutterOverlayWindow.isActive();
      if (mounted) {
        setState(() {
          _isBubbleEnabled = updatedActive;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleBubble(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (enabled) {
      final isGranted = await FlutterOverlayWindow.isPermissionGranted();
      if (!isGranted) {
        if (!mounted) return;
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'PromptGuard needs the "Draw over other apps" (SYSTEM_ALERT_WINDOW) '
              'permission to display a floating bubble while you navigate other apps. '
              'Please grant this permission in System Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );

        if (shouldOpenSettings == true) {
          await FlutterOverlayWindow.requestPermission();
        }

        final recheckGranted = await FlutterOverlayWindow.isPermissionGranted();
        if (!recheckGranted) {
          await prefs.setBool('is_bubble_enabled', false);
          if (mounted) {
            setState(() {
              _isBubbleEnabled = false;
            });
          }
          return;
        }
      }

      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "PromptGuard AI Active",
        overlayContent: "PromptGuard is active — tap to disable",
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: 120,
        width: 120,
      );
      await prefs.setBool('is_bubble_enabled', true);
      if (mounted) {
        setState(() {
          _isBubbleEnabled = true;
        });
      }
    } else {
      await FlutterOverlayWindow.closeOverlay();
      await prefs.setBool('is_bubble_enabled', false);
      if (mounted) {
        setState(() {
          _isBubbleEnabled = false;
        });
      }
    }
  }

  Future<void> _checkPrompt() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final data = await checkPrompt(prompt);
      setState(() {
        _result = PromptGuardResult.fromJson(data);
      });
    } catch (e) {
      setState(() {
        // Distinguish a slow cold-start timeout from other failures, since
        // the Space can take much longer than usual on its first request
        // after being asleep — worth telling the user that specifically
        // rather than a generic "couldn't reach server" message.
        if (e.toString().contains('TimeoutException')) {
          _error =
              'The server is taking longer than usual to respond — it '
              'may be waking up from being idle. Please try again in a '
              'moment.';
        } else {
          _error =
              'Could not reach PromptGuard server. Check your internet '
              'connection and try again. ($e)';
        }
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _useTemplate() {
    if (_result?.rewriteTemplate != null) {
      _controller.text = _result!.rewriteTemplate!;
      setState(() {
        _result = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PromptGuard AI'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => SettingsScreen(
                    isBubbleEnabled: _isBubbleEnabled,
                    onToggleBubble: _toggleBubble,
                  ),
                ),
              );
              _checkInitialOverlayStatus();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Check your prompt before sending it to an AI model.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: SwitchListTile(
                  secondary: Icon(
                    Icons.bubble_chart,
                    color: _isBubbleEnabled
                        ? const Color(0xFF2E74B5)
                        : Colors.grey,
                  ),
                  title: const Text(
                    'Enable Floating Bubble',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Keep PromptGuard accessible over other apps',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _isBubbleEnabled,
                  onChanged: _toggleBubble,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type your prompt here...',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loading ? null : _checkPrompt,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_loading ? 'Checking...' : 'Check Prompt'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ),
                ),
              if (_result != null)
                PromptGuardResultCard(
                  result: _result!,
                  onUseTemplate: _useTemplate,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings screen for managing floating overlay bubble controls, permissions,
/// and viewing details about Track A and Track B prompt evaluation.
class SettingsScreen extends StatefulWidget {
  final bool isBubbleEnabled;
  final Future<void> Function(bool) onToggleBubble;

  const SettingsScreen({
    super.key,
    required this.isBubbleEnabled,
    required this.onToggleBubble,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _bubbleEnabled;

  @override
  void initState() {
    super.initState();
    _bubbleEnabled = widget.isBubbleEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Floating Overlay Controls',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.bubble_chart,
                    color: _bubbleEnabled
                        ? const Color(0xFF2E74B5)
                        : Colors.grey,
                  ),
                  title: const Text(
                    'Enable Floating Bubble',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Keep PromptGuard accessible over other apps',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _bubbleEnabled,
                  onChanged: (value) async {
                    await widget.onToggleBubble(value);
                    final active = await FlutterOverlayWindow.isActive();
                    if (mounted) {
                      setState(() {
                        _bubbleEnabled = active;
                      });
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: Color(0xFF2E74B5),
                  ),
                  title: const Text(
                    'System Permission Settings',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Manage "Draw over other apps" (SYSTEM_ALERT_WINDOW) in Android Settings',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await FlutterOverlayWindow.requestPermission();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'About PromptGuard AI',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track A — Injection & Jailbreak Detection',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF2E74B5),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Evaluates input prompts for security risks, command-injection attacks, '
                    'system prompt overrides, and adversarial jailbreak patterns designed to bypass LLM guardrails.',
                    style: TextStyle(fontSize: 13),
                  ),
                  Divider(height: 24),
                  Text(
                    'Track B — Prompt Quality & Ambiguity Scoring',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF2E74B5),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Analyzes prompt structure, clarity, and specificity. Identifies vague context or ambiguous '
                    'instructions and provides actionable suggestions to ensure optimal model output quality.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
