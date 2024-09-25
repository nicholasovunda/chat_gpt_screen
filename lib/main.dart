import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:flutter_chat_bubble/clippers/chat_bubble_clipper_8.dart';
import 'package:html_unescape/html_unescape.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "ChatGPT App",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChatApp(),
    );
  }
}

class ChatApp extends StatefulWidget {
  const ChatApp({Key? key}) : super(key: key);

  @override
  _ChatAppState createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final FlutterTts flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final HtmlUnescape _htmlUnescape = HtmlUnescape();

  bool _isLoading = false;
  bool _isListening = false;
  bool _isSpeechAvailable = false;
  bool _isTtsEnabled = true;

  String _currentLanguage = 'en-US';
  final List<Map<String, String>> _languages = [
    {'code': 'en-US', 'name': 'English'},
    {'code': 'es-ES', 'name': 'Español'},
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage(_currentLanguage);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
    flutterTts.setSharedInstance(true);
    flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker
        ],
        IosTextToSpeechAudioMode.defaultMode);
  }

  Future<void> _initSpeech() async {
    _isSpeechAvailable = await _speech.initialize();
    setState(() {});
  }

  Future<void> _changeLanguage(String languageCode) async {
    await flutterTts.setLanguage(languageCode);
    setState(() {
      _currentLanguage = languageCode;
    });
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _messages.add(ChatMessage(text: message, isMe: true));
      _controller.clear();
    });

    if (_isListening) {
      await _stopListening();
    }
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['OPENAI_API_KEY']}',
        },
        body: jsonEncode({
          "model": "gpt-3.5-turbo",
          "messages": [
            {
              "role": "system",
              "content":
                  "Respond in ${_currentLanguage == 'en-US' ? 'English' : 'Spanish'}. Use UTF-8 encoding for special characters."
            },
            {"role": "user", "content": message}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final chatGptReply = data['choices'][0]['message']['content'];
        String unescapedReply = _htmlUnescape.convert(chatGptReply);
        setState(() {
          _messages.add(ChatMessage(text: unescapedReply, isMe: false));
        });
        _scrollToBottom();

        if (_isTtsEnabled) {
          await _speak(unescapedReply);
        }
      } else {
        setState(() {
          _messages.add(ChatMessage(
              text: "Error: ${response.statusCode}: ${response.reasonPhrase}",
              isMe: false));
        });
      }
    } catch (error) {
      setState(() {
        _messages
            .add(ChatMessage(text: "Error: ${error.toString()}", isMe: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    String unescapedText = _htmlUnescape.convert(text);
    await flutterTts.speak(unescapedText);
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _startListening() async {
    if (_isSpeechAvailable && !_isListening) {
      setState(() {
        _controller.clear();
        _isListening = true;
      });
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _controller.text = result.recognizedWords;
          });
        },
      );
    }
  }

  Future<void> _stopListening() async {
    if (_isListening) {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _toggleTts() {
    setState(() {
      _isTtsEnabled = !_isTtsEnabled;
    });
  }

  Widget _buildLanguageToggle() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.language, color: Colors.white),
      onSelected: _changeLanguage,
      itemBuilder: (BuildContext context) {
        return _languages.map((language) {
          return PopupMenuItem<String>(
            value: language['code'],
            child: Text(language['name']!),
          );
        }).toList();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'ChatGPT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          _buildLanguageToggle(),
          IconButton(
            icon: Icon(
              _isTtsEnabled ? Icons.volume_up : Icons.volume_off,
              color: Colors.white,
            ),
            onPressed: _toggleTts,
            tooltip: 'Toggle Text-to-Speech',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ChatBubble(
                  clipper: ChatBubbleClipper8(
                    type: message.isMe
                        ? BubbleType.sendBubble
                        : BubbleType.receiverBubble,
                  ),
                  alignment:
                      message.isMe ? Alignment.topRight : Alignment.topLeft,
                  margin: const EdgeInsets.only(top: 10),
                  backGroundColor:
                      message.isMe ? Colors.grey[800] : Colors.grey[600],
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    child: Text(
                      _htmlUnescape.convert(message.text),
                      style: TextStyle(
                        color: message.isMe ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                      filled: true,
                      fillColor: Colors.grey[800],
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                  ),
                  onPressed: _isListening ? _stopListening : _startListening,
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    if (_controller.text.isNotEmpty) {
                      _sendMessage(_controller.text);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    flutterTts.stop();
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isMe;

  ChatMessage({required this.text, required this.isMe});
}
