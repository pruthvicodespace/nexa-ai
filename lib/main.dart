import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexaApp());
}

class NexaApp extends StatelessWidget {
  const NexaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080B12),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const NexaHomePage(),
    );
  }
}

class NexaHomePage extends StatefulWidget {
  const NexaHomePage({super.key});

  @override
  State<NexaHomePage> createState() => _NexaHomePageState();
}

class _NexaHomePageState extends State<NexaHomePage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isLoading = false;
  bool _isSpeaking = false;

  String _selectedLanguage = 'en-IN';

  String _userName = '';

  final List<Map<String, String>> _messages = [];

  // ==========================================================
  // IMPORTANT:
  // This is your laptop's Wi-Fi IPv4 address.
  //
  // Laptop: 10.86.68.123
  // Backend: port 5000
  //
  // Your phone and laptop must be on the same Wi-Fi.
  // ==========================================================

  static const String backendUrl =
      'http://10.86.68.123:5000/chat';

  @override
  void initState() {
    super.initState();

    _initializeTts();
    _initializeSpeech();
    _loadMemory();
  }

  // ==========================================================
  // TTS
  // ==========================================================

  Future<void> _initializeTts() async {
    try {
      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      _tts.setStartHandler(() {
        if (mounted) {
          setState(() {
            _isSpeaking = true;
          });
        }
      });

      _tts.setCompletionHandler(() {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
          });
        }
      });

      _tts.setCancelHandler(() {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
          });
        }
      });

      _tts.setErrorHandler((message) {
        debugPrint('NEXA TTS error: $message');

        if (mounted) {
          setState(() {
            _isSpeaking = false;
          });
        }
      });
    } catch (e) {
      debugPrint('TTS initialization error: $e');
    }
  }

  // ==========================================================
  // SPEECH INITIALIZATION
  // ==========================================================

  Future<void> _initializeSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          debugPrint('NEXA speech status: $status');

          if (mounted) {
            setState(() {
              _isListening = status == 'listening';
            });
          }
        },
        onError: (error) {
          debugPrint('NEXA speech error: $error');

          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
        },
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Speech initialization error: $e');
    }
  }

  // ==========================================================
  // START LISTENING
  // ==========================================================

  Future<void> _startListening() async {
    FocusScope.of(context).unfocus();

    if (!_speechAvailable) {
      await _initializeSpeech();
    }

    if (!_speechAvailable) {
      _showMessage(
        'Speech recognition is not available on this phone.',
      );
      return;
    }

    if (_isListening) {
      await _stopListening();
      return;
    }

    try {
      await _tts.stop();

      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isListening = true;
          _controller.clear();
        });
      }

      await _speech.listen(
        onResult: (dynamic result) {
          try {
            final String recognizedText =
                result.recognizedWords?.toString() ?? '';

            if (recognizedText.isNotEmpty && mounted) {
              setState(() {
                _controller.text = recognizedText;
                _controller.selection = TextSelection.fromPosition(
                  TextPosition(
                    offset: _controller.text.length,
                  ),
                );
              });
            }

            final bool isFinal =
                result.finalResult == true;

            if (isFinal && recognizedText.trim().isNotEmpty) {
              _stopListening();

              Future.delayed(
                const Duration(milliseconds: 300),
                () {
                  if (mounted &&
                      _controller.text.trim().isNotEmpty) {
                    _sendMessage();
                  }
                },
              );
            }
          } catch (e) {
            debugPrint('Speech result error: $e');
          }
        },
        localeId: _selectedLanguage,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('Start listening error: $e');

      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  // ==========================================================
  // STOP LISTENING
  // ==========================================================

  Future<void> _stopListening() async {
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('Stop listening error: $e');
    }

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  // ==========================================================
  // SEND MESSAGE
  // ==========================================================

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();

    if (message.isEmpty || _isLoading) {
      return;
    }

    await _stopListening();
    await _tts.stop();

    setState(() {
      _messages.add({
        'role': 'user',
        'text': message,
      });

      _controller.clear();
      _isLoading = true;
    });

    _scrollToBottom();

    // --------------------------------------------------------
    // LOCAL COMMANDS
    // --------------------------------------------------------

    final lower = message.toLowerCase();

    if (_handleLocalCommand(lower, message)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      return;
    }

    // --------------------------------------------------------
    // BACKEND
    // --------------------------------------------------------

    try {
      debugPrint('NEXA sending to: $backendUrl');

      final response = await http
          .post(
            Uri.parse(backendUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'message': message,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
          );

      debugPrint(
        'NEXA server status: ${response.statusCode}',
      );

      debugPrint(
        'NEXA server response: ${response.body}',
      );

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final decoded =
            jsonDecode(response.body);

        final answer =
            decoded['response']?.toString() ??
                'I received your message, but no response was returned.';

        if (mounted) {
          setState(() {
            _messages.add({
              'role': 'assistant',
              'text': answer,
            });

            _isLoading = false;
          });
        }

        _scrollToBottom();

        await _speak(answer);
      } else {
        String serverMessage =
            'AI server returned an error.';

        try {
          final decoded =
              jsonDecode(response.body);

          if (decoded['response'] != null) {
            serverMessage =
                decoded['response'].toString();
          }
        } catch (_) {}

        _addAssistantMessage(
          serverMessage,
        );
      }
    } on SocketException catch (e) {
      debugPrint('NEXA SocketException: $e');

      _addAssistantMessage(
        'I could not connect to the AI server. '
        'Make sure backend/app.py is running and '
        'your phone and laptop are connected to the same Wi-Fi.',
      );
    } on TimeoutException catch (e) {
      debugPrint('NEXA timeout: $e');

      _addAssistantMessage(
        'The AI server took too long to respond. '
        'Please check that backend/app.py is running.',
      );
    } catch (e) {
      debugPrint('NEXA connection error: $e');

      _addAssistantMessage(
        'I could not connect to the AI server. '
        'Please check your backend and Wi-Fi connection.',
      );
    }
  }

  // ==========================================================
  // LOCAL COMMAND HANDLER
  // ==========================================================

  bool _handleLocalCommand(
    String lower,
    String original,
  ) {
    // OPEN YOUTUBE

    if (lower.contains('open youtube') ||
        lower == 'youtube' ||
        lower.contains('open youtube in kannada')) {
      _openUrl(
        'https://www.youtube.com',
        spokenText: 'Opening YouTube.',
      );

      return true;
    }

    // OPEN GOOGLE

    if (lower.contains('open google')) {
      _openUrl(
        'https://www.google.com',
        spokenText: 'Opening Google.',
      );

      return true;
    }

    // OPEN INSTAGRAM

    if (lower.contains('open instagram')) {
      _openUrl(
        'https://www.instagram.com',
        spokenText: 'Opening Instagram.',
      );

      return true;
    }

    // OPEN MAPS

    if (lower.contains('open maps') ||
        lower.contains('open google maps')) {
      _openUrl(
        'https://maps.google.com',
        spokenText: 'Opening Google Maps.',
      );

      return true;
    }

    // STOP SPEAKING

    if (lower.contains('stop speaking') ||
        lower.contains('stop talking') ||
        lower == 'stop') {
      _tts.stop();

      _addAssistantMessage(
        'Okay, I stopped speaking.',
      );

      return true;
    }

    return false;
  }

  // ==========================================================
  // OPEN URL
  // ==========================================================

  Future<void> _openUrl(
    String url, {
    String spokenText = '',
  }) async {
    try {
      final uri = Uri.parse(url);

      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        _addAssistantMessage(
          'I could not open that application.',
        );

        return;
      }

      if (spokenText.isNotEmpty) {
        await _speak(spokenText);
      }
    } catch (e) {
      debugPrint('URL error: $e');

      _addAssistantMessage(
        'I could not open that link.',
      );
    }
  }

  // ==========================================================
  // SPEAK
  // ==========================================================

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    try {
      await _tts.stop();

      String language = 'en-IN';

      if (_selectedLanguage == 'kn-IN') {
        language = 'kn-IN';
      } else if (_selectedLanguage == 'hi-IN') {
        language = 'hi-IN';
      }

      await _tts.setLanguage(language);
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);

      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  // ==========================================================
  // MEMORY
  // ==========================================================

  Future<void> _loadMemory() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      final savedName =
          prefs.getString('user_name');

      if (savedName != null &&
          savedName.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _userName = savedName;
          });
        }
      }
    } catch (e) {
      debugPrint('Memory load error: $e');
    }
  }

  Future<void> _saveName(String name) async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setString(
        'user_name',
        name,
      );

      if (mounted) {
        setState(() {
          _userName = name;
        });
      }
    } catch (e) {
      debugPrint('Memory save error: $e');
    }
  }

  // ==========================================================
  // ADD ASSISTANT MESSAGE
  // ==========================================================

  void _addAssistantMessage(String text) {
    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add({
        'role': 'assistant',
        'text': text,
      });

      _isLoading = false;
    });

    _scrollToBottom();

    _speak(text);
  }

  // ==========================================================
  // SCROLL
  // ==========================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(
          milliseconds: 300,
        ),
        curve: Curves.easeOut,
      );
    });
  }

  // ==========================================================
  // LANGUAGE
  // ==========================================================

  Future<void> _changeLanguage(
    String language,
  ) async {
    setState(() {
      _selectedLanguage = language;
    });

    String ttsLanguage = 'en-IN';

    if (language == 'kn-IN') {
      ttsLanguage = 'kn-IN';
    } else if (language == 'hi-IN') {
      ttsLanguage = 'hi-IN';
    }

    try {
      await _tts.setLanguage(ttsLanguage);
    } catch (e) {
      debugPrint(
        'Language change error: $e',
      );
    }
  }

  // ==========================================================
  // WELCOME MESSAGE
  // ==========================================================

  String get _welcomeMessage {
    if (_userName.isNotEmpty) {
      return 'Hello $_userName! I am NEXA. How can I help you?';
    }

    return 'Hello! I am NEXA. How can I help you?';
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Colors.blueAccent,
                    Colors.purpleAccent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent
                        .withOpacity(0.3),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'NEXA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                Text(
                  'AI Assistant',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.language,
            ),
            onSelected: _changeLanguage,
            itemBuilder: (context) {
              return const [
                PopupMenuItem(
                  value: 'en-IN',
                  child: Text(
                    'English',
                  ),
                ),
                PopupMenuItem(
                  value: 'kn-IN',
                  child: Text(
                    'ಕನ್ನಡ',
                  ),
                ),
                PopupMenuItem(
                  value: 'hi-IN',
                  child: Text(
                    'हिन्दी',
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildWelcome()
                : _buildMessages(),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(
                bottom: 8,
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'NEXA is thinking...',
                  ),
                ],
              ),
            ),

          _buildInputArea(),
        ],
      ),
    );
  }

  // ==========================================================
  // WELCOME
  // ==========================================================

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Colors.blueAccent,
                    Colors.purpleAccent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent
                        .withOpacity(0.35),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 52,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'NEXA',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _welcomeMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),

            const SizedBox(height: 35),

            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment:
                  WrapAlignment.center,
              children: [
                _suggestion(
                  'What is AI?',
                ),
                _suggestion(
                  'What is the time?',
                ),
                _suggestion(
                  'Open YouTube',
                ),
                _suggestion(
                  'Tell me a joke',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestion(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () {
        _controller.text = text;
        _sendMessage();
      },
    );
  }

  // ==========================================================
  // MESSAGES
  // ==========================================================

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message =
            _messages[index];

        final isUser =
            message['role'] == 'user';

        return Align(
          alignment: isUser
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Container(
            constraints:
                const BoxConstraints(
              maxWidth: 330,
            ),
            margin:
                const EdgeInsets.only(
              bottom: 12,
            ),
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              gradient: isUser
                  ? const LinearGradient(
                      colors: [
                        Colors.blueAccent,
                        Colors.indigo,
                      ],
                    )
                  : null,
              color: isUser
                  ? null
                  : const Color(
                      0xFF151A24,
                    ),
              borderRadius:
                  BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white
                    .withOpacity(0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  isUser
                      ? 'You'
                      : 'NEXA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        FontWeight.bold,
                    color: isUser
                        ? Colors.white70
                        : Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message['text'] ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // INPUT AREA
  // ==========================================================

  Widget _buildInputArea() {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration:
                    BoxDecoration(
                  color:
                      const Color(0xFF151A24),
                  borderRadius:
                      BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white
                        .withOpacity(0.08),
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction:
                      TextInputAction.newline,
                  decoration:
                      const InputDecoration(
                    hintText:
                        'Ask NEXA anything...',
                    border:
                        InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                  ),
                  onSubmitted: (_) {
                    _sendMessage();
                  },
                ),
              ),
            ),

            const SizedBox(width: 8),

            GestureDetector(
              onTap: _startListening,
              child: AnimatedContainer(
                duration:
                    const Duration(
                  milliseconds: 200,
                ),
                width: 52,
                height: 52,
                decoration:
                    BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening
                      ? Colors.redAccent
                      : Colors.blueAccent,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_isListening
                                  ? Colors.redAccent
                                  : Colors.blueAccent)
                              .withOpacity(
                        0.35,
                      ),
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening
                      ? Icons.stop
                      : Icons.mic,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(width: 8),

            GestureDetector(
              onTap: _isLoading
                  ? null
                  : _sendMessage,
              child: Container(
                width: 52,
                height: 52,
                decoration:
                    BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLoading
                      ? Colors.grey
                      : Colors.purpleAccent,
                ),
                child: const Icon(
                  Icons.send,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SNACKBAR
  // ==========================================================

  void _showMessage(String text) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(text),
        duration:
            const Duration(seconds: 3),
      ),
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    _tts.stop();

    super.dispose();
  }
}